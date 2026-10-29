import SwiftUI
import AppKit

/// Arc-style command bar: ⌘T opens it, type to fuzzy-match songs, albums, artists,
/// genres and commands, arrow keys to move, Return to run, Esc to close.
struct CommandPalette: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var selectedID: String?
    @State private var scope: PaletteScope = .all
    /// Set when Tab drills into an artist or genre: results become its albums.
    @State private var drill: PaletteDrill?
    @FocusState private var isFieldFocused: Bool
    @State private var deleteMonitor: Any?

    private let maxResults = 40

    var body: some View {
        let items = results
        VStack(spacing: 0) {
            searchField(items: items)

            if !items.isEmpty {
                Divider().opacity(0.5)
                resultList(items: items)
            }
        }
        .frame(width: 620)
        .glassEffect(.regular.tint(.black.opacity(0.45)), in: .rect(cornerRadius: 22))
        .background {
            // Esc closes the bar even when the field doesn't have focus.
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .onAppear {
            query = ""
            scope = .all
            drill = nil
            selectedID = items.first?.id
            // Focusing during the first layout pass is often dropped; retry next runloop.
            isFieldFocused = true
            DispatchQueue.main.async { isFieldFocused = true }
            // The text field swallows Backspace, so watch for it at the app level.
            deleteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 51, stepBack() else { return event }
                return nil
            }
        }
        .onDisappear {
            if let deleteMonitor { NSEvent.removeMonitor(deleteMonitor) }
            deleteMonitor = nil
        }
        .onChange(of: query) { _, _ in
            selectedID = results.first?.id
        }
        .onChange(of: scope) { _, _ in
            selectedID = results.first?.id
        }
        .onChange(of: drill) { _, _ in
            selectedID = results.first?.id
        }
    }

    // MARK: - Field

    private func searchField(items: [PaletteItem]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            if let chipTitle {
                Text(chipTitle)
                    .lineLimit(1)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Self.chipColor))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            TextField(chipTitle.map { "Search \($0)…" } ?? "Search…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .medium))
                .focused($isFieldFocused)
                .onSubmit { run(selected(in: items), alternate: false) }
                .onKeyPress(.downArrow) { moveSelection(by: 1, in: items); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1, in: items); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                .onKeyPress(keys: [.tab]) { press in
                    handleTab(backwards: press.modifiers.contains(.shift), items: items)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    run(selected(in: items), alternate: true)
                    return .handled
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: chipTitle)
    }

    /// Backspace in an empty field steps back out: drill first, then filter.
    /// Returns whether it did anything.
    private func stepBack() -> Bool {
        guard query.isEmpty else { return false }
        if drill != nil {
            drill = nil
        } else if scope != .all {
            scope = .all
        } else {
            return false
        }
        return true
    }

    private var chipTitle: String? {
        if let drill { return drill.name }
        return scope == .all ? nil : scope.title
    }

    /// The app's purple accent (matches the sidebar).
    private static let chipColor = Color(red: 0.608, green: 0.455, blue: 0.729)

    // MARK: - Scope

    /// Tab, in priority order: a lone scope letter sets that filter ("a" Tab →
    /// Albums); a highlighted artist or genre drills into its albums; otherwise Tab
    /// and ⇧Tab cycle through the filters, keeping the query.
    private func handleTab(backwards: Bool, items: [PaletteItem]) {
        if !backwards, drill == nil, let letterScope = PaletteScope.forLetter(query) {
            scope = letterScope
            query = ""
            return
        }
        if !backwards, let item = selected(in: items) {
            switch item.kind {
            case .artist(let artist):
                drill = .artist(artist)
                query = ""
                return
            case .genre(let genre):
                drill = .genre(genre)
                query = ""
                return
            default:
                break
            }
        }
        guard drill == nil else { return }
        let all = PaletteScope.allCases
        let index = all.firstIndex(of: scope) ?? 0
        scope = all[(index + (backwards ? all.count - 1 : 1)) % all.count]
    }

    // MARK: - Results

    private func resultList(items: [PaletteItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if query.isEmpty, scope == .all, drill == nil, items.contains(where: { if case .album = $0.kind { true } else { false } }) {
                        sectionLabel("Recently Played")
                    }
                    ForEach(items) { item in
                        PaletteRow(item: item, isSelected: item.id == selectedID)
                            .id(item.id)
                            .onTapGesture { run(item, alternate: false) }
                            .onHover { if $0 { selectedID = item.id } }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private func selected(in items: [PaletteItem]) -> PaletteItem? {
        items.first { $0.id == selectedID } ?? items.first
    }

    private func moveSelection(by offset: Int, in items: [PaletteItem]) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
    }

    // MARK: - Matching

    private var results: [PaletteItem] {
        if let drill {
            let albums = switch drill {
            case .artist(let artist): viewModel.albumsForArtist(artist)
            case .genre(let genre): viewModel.albumsForGenre(genre)
            }
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return albums.map { PaletteItem(kind: .album($0)) }
            }
            return albums
                .compactMap { album in FuzzyMatcher.score(query, album.title).map { (album, $0) } }
                .sorted { $0.1 > $1.1 }
                .map { PaletteItem(kind: .album($0.0)) }
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(browseItems.prefix(maxResults))
        }

        var scored: [(item: PaletteItem, score: Int)] = []

        for command in commands where scope == .all {
            if let score = FuzzyMatcher.score(query, command.title) {
                scored.append((PaletteItem(kind: .command(command)), score + 20))
            }
        }
        for album in viewModel.library where scope.includes(.albums) {
            let best = [
                FuzzyMatcher.score(query, album.title),
                FuzzyMatcher.score(query, "\(album.title) \(album.artist)").map { $0 - 5 },
            ].compactMap { $0 }.max()
            if let best { scored.append((PaletteItem(kind: .album(album)), best + 10)) }
        }
        for artist in viewModel.artists where scope.includes(.artists) {
            if let score = FuzzyMatcher.score(query, artist) {
                scored.append((PaletteItem(kind: .artist(artist)), score + 10))
            }
        }
        for genre in viewModel.allGenres() where scope.includes(.genres) {
            if let score = FuzzyMatcher.score(query, genre) {
                scored.append((PaletteItem(kind: .genre(genre)), score))
            }
        }
        for album in viewModel.library where scope.includes(.songs) {
            for (index, track) in album.tracks.enumerated() {
                let best = [
                    FuzzyMatcher.score(query, track.title),
                    FuzzyMatcher.score(query, "\(track.title) \(track.artist)").map { $0 - 5 },
                ].compactMap { $0 }.max()
                if let best { scored.append((PaletteItem(kind: .song(track, album, index)), best)) }
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(maxResults)
            .map(\.item)
    }

    /// What an empty field shows: recently played, or everything in the filter.
    private var browseItems: [PaletteItem] {
        switch scope {
        case .all:
            return viewModel.recentAlbums.map { PaletteItem(kind: .album($0)) }
        case .albums:
            return viewModel.filteredAlbums().map { PaletteItem(kind: .album($0)) }
        case .artists:
            return viewModel.artists.map { PaletteItem(kind: .artist($0)) }
        case .genres:
            return viewModel.allGenres().map { PaletteItem(kind: .genre($0)) }
        case .songs:
            return viewModel.allTracks().prefix(maxResults).compactMap { pair in
                guard let index = pair.album.tracks.firstIndex(where: { $0.id == pair.track.id }) else { return nil }
                return PaletteItem(kind: .song(pair.track, pair.album, index))
            }
        }
    }

    // MARK: - Commands

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = []
        if viewModel.currentAlbum != nil {
            list.append(PaletteCommand(
                title: playback.isPlaying ? "Pause" : "Play",
                icon: playback.isPlaying ? "pause.fill" : "play.fill"
            ) { viewModel.togglePlayback() })
            list.append(PaletteCommand(title: "Next Track", icon: "forward.fill") {
                viewModel.playNext()
            })
            list.append(PaletteCommand(title: "Previous Track", icon: "backward.fill") {
                viewModel.playPrevious()
            })
            list.append(PaletteCommand(title: "Show Now Playing", icon: "play.rectangle") {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    viewModel.isNowPlayingExpanded = true
                }
            })
        }
        list += [
            PaletteCommand(title: "Go to Home", icon: "house") { go(to: .home) },
            PaletteCommand(title: "Go to Albums", icon: "square.stack") { go(to: .albums) },
            PaletteCommand(title: "Go to Artists", icon: "music.mic") { go(to: .artists) },
            PaletteCommand(title: "Go to Songs", icon: "music.note") { go(to: .songs) },
            PaletteCommand(title: "Go to Genres", icon: "guitars") { go(to: .genres) },
            PaletteCommand(title: "Settings", icon: "gearshape") { openSettings() },
        ]
        return list
    }

    private func go(to section: LibrarySection) {
        leaveNowPlaying()
        viewModel.selectSection(section)
    }

    private func leaveNowPlaying() {
        guard viewModel.isNowPlayingExpanded else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            viewModel.isNowPlayingExpanded = false
        }
    }

    // MARK: - Actions

    /// Return plays songs and albums and opens artists and genres. ⌘Return opens an
    /// album's page instead of playing it.
    private func run(_ item: PaletteItem?, alternate: Bool) {
        guard let item else { return }
        close()
        switch item.kind {
        case .command(let command):
            command.action()
        case .album(let album):
            if alternate {
                leaveNowPlaying()
                viewModel.selectBrowsingAlbum(album)
            } else {
                viewModel.play(album: album)
            }
        case .song(_, let album, let index):
            viewModel.play(album: album, trackIndex: index)
        case .artist(let artist):
            leaveNowPlaying()
            viewModel.navigateToArtist(artist)
        case .genre(let genre):
            go(to: .genres)
            viewModel.selectedGenre = genre
        }
    }

    private func close() {
        viewModel.isCommandPaletteVisible = false
    }
}

// MARK: - Items

enum PaletteDrill: Equatable {
    case artist(String)
    case genre(String)

    var name: String {
        switch self {
        case .artist(let name), .genre(let name): name
        }
    }
}

enum PaletteScope: CaseIterable {
    case all, songs, albums, artists, genres

    var title: String {
        switch self {
        case .all: "All"
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .genres: "Genres"
        }
    }

    /// The letter that, followed by Tab, jumps to this filter.
    static func forLetter(_ text: String) -> PaletteScope? {
        switch text.lowercased() {
        case "s": .songs
        case "a": .albums
        case "r": .artists
        case "g": .genres
        default: nil
        }
    }

    func includes(_ other: PaletteScope) -> Bool {
        self == .all || self == other
    }
}

struct PaletteCommand {
    let title: String
    let icon: String
    let action: () -> Void
}

struct PaletteItem: Identifiable {
    enum Kind {
        case command(PaletteCommand)
        case album(Album)
        case artist(String)
        case genre(String)
        case song(Track, Album, Int)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .command(let command): "command:\(command.title)"
        case .album(let album): "album:\(album.id)"
        case .artist(let artist): "artist:\(artist)"
        case .genre(let genre): "genre:\(genre)"
        case .song(let track, _, _): "song:\(track.id)"
        }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artwork: some View {
        switch item.kind {
        case .album(let album), .song(_, let album, _):
            album.coverImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .command(let command):
            symbol(command.icon)
        case .artist:
            symbol("music.mic")
        case .genre:
            symbol("guitars")
        }
    }

    private func symbol(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay(
                Image(systemName: name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var title: String {
        switch item.kind {
        case .command(let command): command.title
        case .album(let album): album.title
        case .artist(let artist): artist
        case .genre(let genre): genre
        case .song(let track, _, _): track.title
        }
    }

    private var subtitle: String? {
        switch item.kind {
        case .command: nil
        case .album(let album): "Album · \(album.artist)"
        case .artist: "Artist"
        case .genre: "Genre"
        case .song(let track, let album, _): "\(track.artist) — \(album.title)"
        }
    }
}

// MARK: - Fuzzy matching

enum FuzzyMatcher {
    /// Scores how well `query` matches `candidate`, or nil if it doesn't match.
    /// Ranks exact > prefix > every query word starting a word > every query word
    /// contained > a tight subsequence (e.g. "gbh" for Grand Budapest Hotel).
    static func score(_ query: String, _ candidate: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let c = candidate.lowercased()
        guard !q.isEmpty else { return nil }

        if c == q { return 1000 }
        if c.hasPrefix(q) { return 900 - c.count }

        let queryWords = q.split(separator: " ")
        let candidateWords = c.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if queryWords.allSatisfy({ word in candidateWords.contains { $0.hasPrefix(word) } }) {
            return 800 - c.count
        }
        if queryWords.allSatisfy({ c.contains($0) }) {
            return 600 - c.count
        }
        return subsequenceScore(q.replacingOccurrences(of: " ", with: ""), candidateWords)
    }

    /// Matches query characters against the starts of consecutive-ish words, so
    /// letters scattered through a long title don't count.
    private static func subsequenceScore(_ q: String, _ words: [Substring]) -> Int? {
        guard q.count >= 2 else { return nil }
        var remaining = Substring(q)
        var skippedWords = 0
        for word in words {
            guard let first = remaining.first else { break }
            if word.first == first {
                // Consume as many query characters as this word's prefix covers.
                let matched = zip(word, remaining).prefix { $0 == $1 }.count
                remaining = remaining.dropFirst(matched)
            } else {
                skippedWords += 1
            }
        }
        guard remaining.isEmpty, skippedWords <= 3 else { return nil }
        return 400 - skippedWords * 20
    }
}
