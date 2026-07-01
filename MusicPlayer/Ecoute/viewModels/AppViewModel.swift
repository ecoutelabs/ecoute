import Foundation
import Combine
import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class PlaybackState: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 0.8
    @Published var isQueueVisible: Bool = true
}

enum LibrarySection: Equatable {
    case albums, artists, songs, genres, search
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var library: [Album] = []
    @Published var currentAlbum: Album?
    @Published var currentTrackIndex: Int = 0
    @Published var backgroundColor: Color = Color(red: 0.12, green: 0.12, blue: 0.14)
    @Published var foregroundColor: Color = .white
    @Published var artists: [String] = []
    @Published var libraryPath: String?
    @Published var selectedSection: LibrarySection = .albums
    @Published var browsingAlbum: Album?
    @Published var browsingAlbumAccentColorDark: Color?
    @Published var browsingAlbumAccentColorLight: Color?
    @Published var selectedArtist: String?
    @Published var selectedGenre: String?
    @Published var isNowPlayingExpanded: Bool = false
    @Published var isNightMode: Bool = UserDefaults.standard.bool(forKey: "isNightMode") {
        didSet { UserDefaults.standard.set(isNightMode, forKey: "isNightMode") }
    }
    @Published var nowPlayingIdleTimeout: Int = (UserDefaults.standard.object(forKey: "nowPlayingIdleTimeout") as? Int) ?? 30 {
        didSet { UserDefaults.standard.set(nowPlayingIdleTimeout, forKey: "nowPlayingIdleTimeout") }
    }
    let playback = PlaybackState()
    private var listenTracker = ListenTracker()
    private var nowProvider: () -> Date = { Date() }
    private let lastFMSessionController: LastFMSessionController
    private var hasScrobbledCurrentTrack = false

    private let player = PlayerController()
    private let nowPlaying = NowPlayingController()
    private let lastFMClient: LastFMClient
    private let scrobbleService: ScrobbleService
    private var cancellables: Set<AnyCancellable> = []
    private var progressTimer: AnyCancellable?
    private let bookmarkKey = "musicplayer.libraryBookmark"
    private let colorExtractor = AlbumColorExtractor()
    @Published var lastFMUsername: String?
    @Published var lastFMStatus: String = "Not linked"
    @Published var lastFMAuthPending: Bool = false

    private var currentTrackStartDate: Date?

    init(lastFMClient: LastFMClient, scrobbleService: ScrobbleService? = nil) {
        self.lastFMClient = lastFMClient
        self.scrobbleService = scrobbleService ?? ScrobbleService(client: lastFMClient)
        self.lastFMSessionController = LastFMSessionController(client: lastFMClient)
        foregroundColor = colorExtractor.preferredTextColor(for: backgroundColor)
        Task { await loadPersistedLibrary() }
        bindLastFM()
        lastFMSessionController.loadSession()
        player.onTrackEnd = { [weak self] in
            Task { @MainActor in
                self?.handleTrackFinished()
            }
        }
        player.onExternalPause = { [weak self] in
            Task { @MainActor in
                self?.handleExternalPause()
            }
        }
        nowPlaying.configureRemoteCommands(
            play: { [weak self] in
                Task { @MainActor in self?.handleRemotePlay() }
            },
            pause: { [weak self] in
                Task { @MainActor in self?.handleRemotePause() }
            },
            toggle: { [weak self] in
                Task { @MainActor in self?.handleRemoteToggle() }
            },
            next: { [weak self] in
                Task { @MainActor in self?.playNext() }
            },
            previous: { [weak self] in
                Task { @MainActor in self?.playPrevious() }
            },
            seek: { [weak self] newTime in
                Task { @MainActor in self?.handleRemoteSeek(to: newTime) }
            }
        )
    }

    convenience init() {
        self.init(lastFMClient: LastFMClient(), scrobbleService: nil)
    }

    func togglePlayback() {
        guard let album = currentAlbum else { return }
        if playback.isPlaying {
            player.pause()
            playback.isPlaying = false
            listenTracker.stop()
            nowPlaying.updatePlaybackState(isPlaying: false, elapsed: playback.position, duration: playback.duration)
        } else {
            if player.hasCurrentItem {
                player.resume()
                playback.isPlaying = true
                listenTracker.start(at: playback.position)
                startProgressTimer()
                nowPlaying.updatePlaybackState(isPlaying: true, elapsed: playback.position, duration: playback.duration)
            } else {
                play(album: album, trackIndex: currentTrackIndex)
            }
        }
    }

    private func handleRemotePlay() {
        guard !playback.isPlaying else { return }
        togglePlayback()
    }

    private func handleRemotePause() {
        guard playback.isPlaying else { return }
        togglePlayback()
    }

    private func handleRemoteToggle() {
        togglePlayback()
    }

    private func handleRemoteSeek(to time: TimeInterval) {
        seek(to: time)
    }

    func play(album: Album, trackIndex: Int = 0, scrobbleCurrent: Bool = true) {
        if scrobbleCurrent {
            scrobbleIfNeeded()
        }
        currentAlbum = album
        currentTrackIndex = trackIndex
        playback.position = 0
        guard let track = album.tracks[safe: trackIndex] else { return }
        playback.duration = track.duration
        playback.isPlaying = true
        listenTracker.reset()
        listenTracker.start(at: playback.position)
        hasScrobbledCurrentTrack = false
        updatePalette(from: album)
        currentTrackStartDate = Date()
        sendLastFMNowPlaying(track: track, album: album)
        player.play(track: track, volume: playback.volume)
        nowPlaying.updateMetadata(track: track, album: album, elapsed: playback.position, duration: playback.duration, isPlaying: true)
        refreshDurationFromPlayer()
        startProgressTimer()
    }

    func playNext(autoAdvance: Bool = false) {
        guard let album = currentAlbum else { return }
        if autoAdvance {
            let nextRawIndex = currentTrackIndex + 1
            // Stop at end of album on auto-advance instead of looping.
            guard nextRawIndex < album.tracks.count else {
                playback.isPlaying = false
                progressTimer?.cancel()
                currentTrackStartDate = nil
                player.pause()
                nowPlaying.updatePlaybackState(isPlaying: false, elapsed: playback.position, duration: playback.duration)
                listenTracker.stop()
                return
            }
            hasScrobbledCurrentTrack = false
            play(album: album, trackIndex: nextRawIndex, scrobbleCurrent: false)
            return
        }
        if !autoAdvance {
            scrobbleIfNeeded()
        }
        let nextIndex = (currentTrackIndex + 1) % album.tracks.count
        hasScrobbledCurrentTrack = false
        play(album: album, trackIndex: nextIndex, scrobbleCurrent: false)
    }

    func playPrevious() {
        guard let album = currentAlbum else { return }
        scrobbleIfNeeded()
        let previousIndex = max(currentTrackIndex - 1, 0)
        hasScrobbledCurrentTrack = false
        play(album: album, trackIndex: previousIndex, scrobbleCurrent: false)
    }

    func seek(to time: TimeInterval) {
        // Update UI immediately for responsive scrubbing.
        playback.position = time
        listenTracker.seek(to: time, isPlaying: playback.isPlaying)
        nowPlaying.updatePlaybackState(isPlaying: playback.isPlaying, elapsed: time, duration: playback.duration)

        player.seek(to: time) { [weak self] actual in
            guard let self else { return }
            playback.position = actual
            listenTracker.seek(to: actual, isPlaying: playback.isPlaying)
            nowPlaying.updatePlaybackState(isPlaying: playback.isPlaying, elapsed: actual, duration: playback.duration)
            refreshDurationFromPlayer()
        }
    }

    func setVolume(_ newVolume: Double) {
        playback.volume = newVolume
        player.setVolume(newVolume)
    }

    func rescanLibrary() {
        guard let path = libraryPath else { return }
        Task {
            await loadLibrary(from: URL(fileURLWithPath: path))
        }
    }

    func rescanLibraryClearingCache() {
        guard let path = libraryPath else { return }
        Task {
            do {
                try LibraryScanner.clearCache()
            } catch {
                print("Failed to clear cache: \(error)")
            }
            await loadLibrary(from: URL(fileURLWithPath: path))
        }
    }

    func toggleQueueVisibility() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            playback.isQueueVisible.toggle()
        }
    }

    // MARK: - Last.fm

    func startLastFMAuth() {
        lastFMSessionController.startAuth()
    }

    func completeLastFMAuth() {
        lastFMSessionController.completeAuth()
    }

    func unlinkLastFM() {
        lastFMSessionController.unlink()
    }

    func pickAlbumFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Library"
        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
            Task { await loadLibrary(from: url) }
        }
    }

    private func loadLibrary(from url: URL) async {
        do {
            let albums = try await LibraryScanner().scan(url: url)
            await MainActor.run {
                self.library = albums
                let artistEntries: [(name: String, sortKey: String)] = albums.map { album in
                    let display = album.artist.isEmpty ? "Unknown Artist" : album.artist
                    let sort = album.artistSort ?? display
                    return (display, sort)
                }
                var artistSortMap: [String: String] = [:]
                for entry in artistEntries {
                    artistSortMap[entry.name] = entry.sortKey
                }
                self.artists = artistSortMap.keys.sorted {
                    let lhs = artistSortMap[$0] ?? $0
                    let rhs = artistSortMap[$1] ?? $1
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                self.selectedArtist = nil
                self.selectedGenre = nil
                self.selectedSection = .albums
                self.browsingAlbum = nil
                self.browsingAlbumAccentColorDark = nil
                self.browsingAlbumAccentColorLight = nil
                self.currentAlbum = nil
                self.playback.isPlaying = false
                self.playback.position = 0
                self.playback.duration = 0
                self.nowPlaying.clear()
                self.libraryPath = url.path
            }
            enrichWithGenres(albums)
        } catch {
            print("Failed to load album: \(error)")
        }
    }

    private func loadPersistedLibrary() async {
        guard let url = restoreBookmark() else { return }
        await loadLibrary(from: url)
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    private func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                saveBookmark(for: url)
            }
            if url.startAccessingSecurityScopedResource() {
                libraryPath = url.path
                return url
            }
        } catch {
            print("Failed to restore bookmark: \(error)")
        }
        return nil
    }

    private func startProgressTimer() {
        progressTimer?.cancel()
        progressTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.playback.isPlaying else { return }
                self.playback.position = self.player.currentTime()
                self.playback.duration = max(self.playback.duration, self.player.currentDuration())
                self.nowPlaying.updateProgress(elapsed: self.playback.position,
                                               duration: self.playback.duration,
                                               isPlaying: self.playback.isPlaying)
            }
    }

    func scrobbleIfNeeded() {
        guard let album = currentAlbum,
              let track = album.tracks[safe: currentTrackIndex],
              let startDate = currentTrackStartDate else { return }
        guard !hasScrobbledCurrentTrack else { return }

        let listened = listenTracker.totalListeningTime(asOf: nowProvider())
        let threshold = min(track.duration * 0.5, 240)
        guard listened >= threshold else { return }

        let scrobbled = scrobbleService.scrobbleIfNeeded(sessionKey: lastFMSessionController.currentSessionKey(),
                                                         track: track,
                                                         album: album,
                                                         startDate: startDate,
                                                         elapsed: playback.position,
                                                         listenedTime: listened)
        if scrobbled {
            hasScrobbledCurrentTrack = true
        }
    }

    private func handleTrackFinished() {
        scrobbleIfNeeded()
        playNext(autoAdvance: true)
    }

    private func handleExternalPause() {
        playback.isPlaying = false
        player.pause()
        listenTracker.stop()
        nowPlaying.updatePlaybackState(isPlaying: false, elapsed: playback.position, duration: playback.duration)
    }

    private func sendLastFMNowPlaying(track: Track, album: Album) {
        guard let sessionKey = lastFMSessionController.currentSessionKey() else { return }
        Task {
            await lastFMClient.updateNowPlaying(sessionKey: sessionKey, track: track, album: album)
        }
    }

    private func refreshDurationFromPlayer() {
        Task { @MainActor in
            let duration = await player.loadCurrentDuration()
            if duration > 0 {
                playback.duration = max(playback.duration, duration)
                nowPlaying.updatePlaybackState(isPlaying: playback.isPlaying, elapsed: playback.position, duration: playback.duration)
            }
        }
    }

    private func updatePalette(from album: Album) {
        let bg = colorExtractor.vibrantColor(from: album.coverData)
        backgroundColor = bg
        foregroundColor = colorExtractor.preferredTextColor(for: bg)
    }

    func selectSection(_ section: LibrarySection) {
        selectedSection = section
        selectedArtist = nil
        selectedGenre = nil
        browsingAlbum = nil
        browsingAlbumAccentColorDark = nil
        browsingAlbumAccentColorLight = nil
    }

    func selectBrowsingAlbum(_ album: Album) {
        browsingAlbum = album
        let colors = colorExtractor.accentColors(from: album.coverData)
        browsingAlbumAccentColorDark = colors.dark
        browsingAlbumAccentColorLight = colors.light
    }

    func clearBrowsingAlbum() {
        browsingAlbum = nil
        browsingAlbumAccentColorDark = nil
        browsingAlbumAccentColorLight = nil
    }

    func navigateToArtist(_ artist: String) {
        clearBrowsingAlbum()
        selectedSection = .artists
        selectedArtist = artist
    }

    func allTracks(query: String = "") -> [(track: Track, album: Album)] {
        let q = query.lowercased()
        var pairs: [(track: Track, album: Album)] = []

        for album in library {
            for track in album.tracks {
                if q.isEmpty
                    || track.title.lowercased().contains(q)
                    || track.artist.lowercased().contains(q)
                    || album.title.lowercased().contains(q) {
                    pairs.append((track, album))
                }
            }
        }

        return pairs.sorted {
            let a0 = $0.track.artist.lowercased()
            let a1 = $1.track.artist.lowercased()
            if a0 != a1 { return a0 < a1 }

            let y0 = Int($0.album.year) ?? Int.max
            let y1 = Int($1.album.year) ?? Int.max
            if y0 != y1 { return y0 < y1 }

            let d0 = $0.track.discNumber ?? 0
            let d1 = $1.track.discNumber ?? 0
            if d0 != d1 { return d0 < d1 }

            return $0.track.trackNumber < $1.track.trackNumber
        }
    }

    private func enrichWithGenres(_ albums: [Album]) {
        Task {
            print("[GenreFetcher] enrichWithGenres starting for \(albums.count) albums")
            let fetcher = GenreFetcher(lastFMAPIKey: LastFMClient.defaultAPIKey)
            let genreMap = await fetcher.fetchGenres(for: albums)
            await MainActor.run {
                self.library = self.library.map { album in
                    let genres = (genreMap[album.id] ?? []).map { Self.formatGenre($0) }
                    return genres.isEmpty ? album : album.with(genres: genres)
                }
                let populated = self.library.filter { !$0.genres.isEmpty }.count
                print("[GenreFetcher] Library updated: \(populated)/\(self.library.count) albums have genres")
            }
        }
    }

    func allGenres(query: String = "") -> [String] {
        var counts: [String: Int] = [:]
        for genre in library.flatMap({ $0.genres }) {
            counts[genre, default: 0] += 1
        }
        let qualified = counts.filter { $0.value >= 2 }.keys
        if query.isEmpty { return qualified.sorted() }
        let q = query.lowercased()
        return qualified.filter { $0.lowercased().contains(q) }.sorted()
    }

    func albumsForGenre(_ genre: String) -> [Album] {
        library
            .filter { $0.genres.contains(genre) }
            .sorted {
                let lhsArtist = ($0.artistSort ?? $0.artist).lowercased()
                let rhsArtist = ($1.artistSort ?? $1.artist).lowercased()
                if lhsArtist != rhsArtist { return lhsArtist < rhsArtist }
                return (Int($0.year) ?? Int.max) < (Int($1.year) ?? Int.max)
            }
    }

    func filteredAlbums(query: String = "") -> [Album] {
        let q = query.lowercased()
        let base = library.filter { album in
            q.isEmpty
                || album.title.lowercased().contains(q)
                || album.artist.lowercased().contains(q)
        }
        return base.sorted {
            let lhsArtist = ($0.artistSort ?? $0.artist).lowercased()
            let rhsArtist = ($1.artistSort ?? $1.artist).lowercased()
            if lhsArtist != rhsArtist { return lhsArtist < rhsArtist }
            let lhsYear = Int($0.year) ?? Int.max
            let rhsYear = Int($1.year) ?? Int.max
            return lhsYear < rhsYear
        }
    }

    func filteredArtists(query: String = "") -> [String] {
        guard !query.isEmpty else { return artists }
        let q = query.lowercased()
        return artists.filter { $0.lowercased().contains(q) || albumsForArtist($0).contains(where: { $0.title.lowercased().contains(q) }) }
    }

    func albumsForArtist(_ artist: String) -> [Album] {
        library
            .filter { ($0.artist.isEmpty ? "Unknown Artist" : $0.artist) == artist }
            .sorted {
                let lhsKey = albumYearSortKey($0)
                let rhsKey = albumYearSortKey($1)
                if lhsKey.year != rhsKey.year {
                    return lhsKey.year < rhsKey.year
                }
                return lhsKey.title.localizedCaseInsensitiveCompare(rhsKey.title) == .orderedAscending
            }
    }

    // Known genre acronyms that .capitalized mangles (e.g. "idm" → "Idm" instead of "IDM").
    private static let genreAcronyms: [String: String] = [
        "Idm": "IDM",
        "Edm": "EDM",
        "Ebm": "EBM",
        "Dnb": "DnB",
        "Uk": "UK",
        "Us": "US",
        "Eu": "EU",
    ]

    private static func formatGenre(_ raw: String) -> String {
        let capitalized = raw.capitalized
        return genreAcronyms[capitalized] ?? capitalized
    }

    private func albumYearSortKey(_ album: Album) -> (year: Int, title: String) {
        let year = [
            album.originalYear,
            album.year
        ].compactMap { $0 }.compactMap(Int.init).first ?? Int.max

        let title = album.titleSort ?? album.title
        return (year: year, title: title)
    }

    // MARK: - Last.fm state binding

    private func bindLastFM() {
        lastFMSessionController.$username
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastFMUsername = $0 }
            .store(in: &cancellables)

        lastFMSessionController.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastFMStatus = $0 }
            .store(in: &cancellables)

        lastFMSessionController.$isPending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastFMAuthPending = $0 }
            .store(in: &cancellables)
    }
}

/// Tracks real listening time for the current track based on play/pause/seek events.
private struct ListenTracker {
    private var accumulated: TimeInterval = 0
    private var currentStart: Date?

    mutating func reset() {
        accumulated = 0
        currentStart = nil
    }

    mutating func start(at _: TimeInterval, now: Date = Date()) {
        guard currentStart == nil else { return }
        currentStart = now
    }

    mutating func stop(now: Date = Date()) {
        guard let start = currentStart else { return }
        accumulated += now.timeIntervalSince(start)
        currentStart = nil
    }

    mutating func seek(to _: TimeInterval, isPlaying: Bool, now: Date = Date()) {
        if isPlaying {
            stop(now: now)
            start(at: 0, now: now)
        } else {
            stop(now: now)
        }
    }

    func totalListeningTime(asOf now: Date) -> TimeInterval {
        guard let start = currentStart else { return accumulated }
        return accumulated + now.timeIntervalSince(start)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

#if DEBUG
extension AppViewModel {
    func _testSetCurrentTrackStartDate(_ date: Date?) {
        currentTrackStartDate = date
    }

    func _testSetLastFMSessionKey(_ key: String?) {
        lastFMSessionController._testSetSessionKey(key)
    }

    func _testSetNowProvider(_ provider: @escaping () -> Date) {
        nowProvider = provider
    }

    func _testStartListening(now: Date) {
        listenTracker.start(at: playback.position, now: now)
    }

    func _testStopListening(now: Date) {
        listenTracker.stop(now: now)
    }

    func _testSeekListening(to time: TimeInterval, isPlaying: Bool, now: Date) {
        playback.position = time
        listenTracker.seek(to: time, isPlaying: isPlaying, now: now)
    }
}
#endif
