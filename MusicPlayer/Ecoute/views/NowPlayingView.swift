import SwiftUI
import Combine

struct NowPlayingView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState
    let album: Album
    @ObservedObject var idleManager: IdleManager

    private var currentTrack: Track? {
        album.tracks[safe: viewModel.currentTrackIndex]
    }

    var body: some View {
        fullControlsLayer
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Full controls layer

    private var fullControlsLayer: some View {
        let primary = viewModel.foregroundColor
        let secondary = primary.opacity(0.72)

        return VStack(spacing: 32) {
            Spacer(minLength: 32)

            ZStack {
                // Measures this cover's center in the viewport coordinate space
                // so ContentView can position the idle overlay cover correctly,
                // including when the user has scrolled.
                Color.clear
                    .frame(width: 420, height: 420)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CoverCenterKey.self,
                                value: CGPoint(
                                    x: geo.frame(in: .named("nowPlayingViewport")).midX,
                                    y: geo.frame(in: .named("nowPlayingViewport")).midY
                                )
                            )
                        }
                    )
                // Visible cover — scrolls with layout, disappears instantly on idle
                // so the viewport-level overlay cover can take over seamlessly.
                AlbumCoverView(image: album.coverImage)
                    .frame(width: 420, height: 420)
                    .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 18)
                    .opacity(idleManager.isIdle ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: idleManager.isIdle)
            }
            .frame(width: 420, height: 420)

            VStack(spacing: 32) {
                metadataSection.frame(maxWidth: 420)

                VStack(spacing: 28) {
                    ScrubberView(
                        position: $playback.position,
                        duration: playback.duration,
                        onSeek: { time in viewModel.seek(to: time) },
                        tint: primary,
                        secondary: secondary
                    )
                    .frame(maxWidth: 420)

                    TransportControlsView(
                        isPlaying: playback.isPlaying,
                        volume: playback.volume,
                        isQueueVisible: playback.isQueueVisible,
                        tint: primary,
                        secondary: secondary,
                        onPlayPause: { viewModel.togglePlayback() },
                        onNext: { viewModel.playNext() },
                        onPrevious: { viewModel.playPrevious() },
                        onVolumeChange: { viewModel.setVolume($0) },
                        onToggleQueue: { viewModel.toggleQueueVisibility() }
                    )
                    .frame(maxWidth: 420)
                }

                if playback.isQueueVisible {
                    UpcomingListView(
                        album: album,
                        currentIndex: viewModel.currentTrackIndex,
                        primary: primary,
                        secondary: secondary
                    ) { index in
                        viewModel.play(album: album, trackIndex: index)
                    }
                    .frame(maxWidth: 420)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .opacity(idleManager.isControlsHidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: idleManager.isControlsHidden)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 80)
        .foregroundColor(primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let track = currentTrack {
                Text(track.title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(2)
            }
            if let track = currentTrack {
                Text(
                    album.year.isEmpty
                    ? "\(track.artist) – \(album.title)"
                    : "\(track.artist) – \(album.title) (\(album.year))"
                )
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(viewModel.foregroundColor.opacity(0.75))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

// MARK: - Cover center preference key

struct CoverCenterKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

// MARK: - Idle Manager

@MainActor
final class IdleManager: ObservableObject {
    // Phase 1: controls fade out
    @Published var isControlsHidden = false
    // Phase 2: cover moves to idle position
    @Published var isIdle = false
    // Phase 3: idle text fades in
    @Published var showIdleText = false

    private var workItem: DispatchWorkItem?
    private var phaseItems: [DispatchWorkItem] = []
    private var eventMonitor: Any?

    func start(timeout: TimeInterval) {
        stop()
        guard timeout > 0 else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            self?.activity(timeout: timeout)
            return event
        }
        scheduleIdle(after: timeout)
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        workItem?.cancel()
        workItem = nil
        cancelPhases()
        isControlsHidden = false
        isIdle = false
        showIdleText = false
    }

    private func activity(timeout: TimeInterval) {
        workItem?.cancel()
        if isIdle { wakeUp() }
        scheduleIdle(after: timeout)
    }

    private func scheduleIdle(after timeout: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.goIdle() }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    // MARK: - Staged animation

    private func goIdle() {
        cancelPhases()

        // Phase 1 — fade controls out (0.25s)
        withAnimation(.easeOut(duration: 0.25)) { isControlsHidden = true }

        // Phase 2 — cover moves to idle position (MGE spring)
        let phase2 = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { self?.isIdle = true }
        }
        phaseItems.append(phase2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: phase2)

        // Phase 3 — idle text fades in after cover has settled
        let phase3 = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) { self?.showIdleText = true }
        }
        phaseItems.append(phase3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: phase3)
    }

    private func wakeUp() {
        cancelPhases()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            showIdleText = false
            isIdle = false
            isControlsHidden = false
        }
    }

    private func cancelPhases() {
        phaseItems.forEach { $0.cancel() }
        phaseItems.removeAll()
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        workItem?.cancel()
        phaseItems.forEach { $0.cancel() }
    }
}

// MARK: - Artwork

struct AlbumCoverView: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Scrubber

struct ScrubberView: View {
    @Binding var position: TimeInterval
    let duration: TimeInterval
    var onSeek: (TimeInterval) -> Void
    let tint: Color
    let secondary: Color

    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { position },
                    set: { newValue in
                        position = newValue
                        onSeek(newValue)
                    }
                ),
                in: 0...max(duration, 1)
            )
            .tint(tint)
            .sliderThumbVisibility(.hidden)

            HStack {
                Text(timeString(position))
                Spacer()
                Text(timeString(duration))
            }
            .font(.caption)
            .foregroundColor(secondary)
        }
    }
}

// MARK: - Transport / volume / queue

struct TransportControlsView: View {
    let isPlaying: Bool
    let volume: Double
    let isQueueVisible: Bool
    let tint: Color
    let secondary: Color

    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onVolumeChange: (Double) -> Void
    var onToggleQueue: () -> Void

    var body: some View {
        let primary = tint

        VStack(spacing: 28) {
            // Main playback controls
            HStack(spacing: 64) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            // Volume slider (long, bottom-aligned) + queue button on the right
            HStack(spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                    Slider(
                        value: Binding(
                            get: { volume },
                            set: { newValue in onVolumeChange(newValue) }
                        ),
                        in: 0...1
                    )
                    .tint(primary)
                    Image(systemName: "speaker.wave.3.fill")
                }

                Button(action: onToggleQueue) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text(isQueueVisible ? "Hide Queue" : "Show Queue")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(primary.opacity(isQueueVisible ? 0.2 : 0.12))
                    .clipShape(Capsule())
                    .glassEffect()
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundColor(secondary)
        }
        .foregroundColor(primary)
    }
}

// MARK: - Queue

struct UpcomingListView: View {
    let album: Album
    let currentIndex: Int
    let primary: Color
    let secondary: Color
    var onSelect: (Int) -> Void

    var body: some View {
        let hasMultipleDiscs = Set(album.tracks.map { $0.discNumber ?? 1 }).count > 1

        VStack(alignment: .leading, spacing: 10) {
            Text("Up Next")
                .font(.headline)

            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                let disc = (track.discNumber ?? 1)
                let previousDisc = index > 0 ? (album.tracks[index - 1].discNumber ?? 1) : disc

                VStack(alignment: .leading, spacing: 6) {
                    if hasMultipleDiscs && (index == 0 || disc != previousDisc) {
                        Text("Disc \(disc)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(secondary)
                            .padding(.top, index == 0 ? 2 : 8)
                    }

                    Button {
                        onSelect(index)
                    } label: {
                        HStack(spacing: 12) {
                            Text(formattedTrackNumber(track, fallbackIndex: index))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)

                            VStack(alignment:.leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            if index == currentIndex {
                                Image(systemName: "waveform")
                                    .foregroundColor(primary)
                            } else {
                                Text(formattedDuration(track.duration))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(index == currentIndex ? Color.clear : secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .glassEffect(index == currentIndex ? .regular : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formattedTrackNumber(_ track: Track, fallbackIndex: Int) -> String {
        let number = track.trackNumber > 0 ? track.trackNumber : (fallbackIndex + 1)
        return String(format: "%02d", number)
    }
}
