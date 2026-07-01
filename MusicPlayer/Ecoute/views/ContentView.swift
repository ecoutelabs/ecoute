import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowDelegate = FullscreenHidingWindowDelegate()
    @State private var spacebarHandler: SpacebarToggleManager?
    @StateObject private var idleManager = IdleManager()
    @State private var fullCoverCenter: CGPoint = .zero
    @State private var filterText: String = ""

    // Whether the per-section filter toolbar is relevant
    private var showFilterBar: Bool {
        !viewModel.isNowPlayingExpanded
            && viewModel.browsingAlbum == nil
            && viewModel.selectedSection != .search
    }

    private var sectionTitle: String {
        switch viewModel.selectedSection {
        case .albums:  "Albums"
        case .artists: "Artists"
        case .songs:   "Songs"
        case .genres:  "Genres"
        case .search:  "Search"
        }
    }

    private var filterPrompt: String {
        switch viewModel.selectedSection {
        case .albums:  "Find in Albums"
        case .artists: "Find in Artists"
        case .songs:   "Find in Songs"
        case .genres:  "Find in Genres"
        case .search:  ""
        }
    }


    private var collapse: () -> Void {
        {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                viewModel.isNowPlayingExpanded = false
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                LibrarySidebar()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                    .scrollEdgeEffectStyle(.soft, for: .top)
            } detail: {
                VStack(spacing: 0) {
                    if showFilterBar {
                        HStack {
                            Text(sectionTitle)
                                .font(.largeTitle.bold())
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    }
                    contentArea
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Floating pill mini player — always visible
            MiniPlayerBar(onExpand: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    viewModel.isNowPlayingExpanded = true
                }
            })
            .padding(.bottom, 20)

            // Full-screen now-playing overlay
            if viewModel.isNowPlayingExpanded, let album = viewModel.currentAlbum {
                nowPlayingOverlay(album: album)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .background(WindowAccessor { window in
            window?.delegate = windowDelegate
        })
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            if viewModel.isNowPlayingExpanded {
                ToolbarItem(placement: .navigation) {
                    Button(action: collapse) {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            if showFilterBar {
                ToolbarItemGroup(placement: .automatic) {
                    Spacer()
                    ViewFilterField(text: $filterText, prompt: filterPrompt)
                        .frame(width: 200)
                }
            }
        }
        .onChange(of: viewModel.selectedSection) { _, _ in filterText = "" }
        .onChange(of: viewModel.currentAlbum) { _, newValue in
            if newValue == nil {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    viewModel.isNowPlayingExpanded = false
                }
            }
        }
        .onAppear {
            spacebarHandler = SpacebarToggleManager { viewModel.togglePlayback() }
            spacebarHandler?.start()
        }
        .onDisappear {
            spacebarHandler?.stop()
        }
        .preferredColorScheme(viewModel.isNightMode ? .dark : nil)
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if let album = viewModel.browsingAlbum {
            AlbumDetailView(album: album)
        } else {
            switch viewModel.selectedSection {
            case .albums:
                AlbumGridView(filterText: filterText)
            case .artists:
                ArtistListView(filterText: filterText)
            case .songs:
                SongListView(filterText: filterText)
            case .genres:
                GenreBrowserView(filterText: filterText)
            case .search:
                SearchView()
            }
        }
    }

    // MARK: - Now playing overlay

    private func nowPlayingOverlay(album: Album) -> some View {
        let currentTrack = album.tracks[safe: viewModel.currentTrackIndex]
        let idlePad: CGFloat = 40
        let idleSize: CGFloat = 88

        return ZStack {
            NowPlayingBackground(coverData: album.coverData, nightMode: viewModel.isNightMode)
                .ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    VStack {
                        NowPlayingView(album: album, idleManager: idleManager)
                            .padding(.horizontal, 60)
                            .padding(.vertical, 40)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }

            // Idle-only cover. IdleCoverView initialises its internal @State position
            // from fullCoverCenter via State(initialValue:), so frame 1 is already at
            // the right spot — no onChange pre-snap needed.
            if idleManager.isIdle {
                GeometryReader { geo in
                    let startPos = fullCoverCenter != .zero
                        ? fullCoverCenter
                        : CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.35)
                    let target = CGPoint(
                        x: idlePad + idleSize / 2,
                        y: geo.size.height - idlePad - idleSize / 2
                    )
                    IdleCoverView(
                        image: album.coverImage,
                        startPosition: startPos,
                        targetPosition: target
                    )
                    .allowsHitTesting(false)
                }
            }

            // Idle text — appears after the cover settles
            VStack {
                Spacer()
                HStack(alignment: .center, spacing: 20) {
                    // Spacer that mirrors the idle cover width + padding so text
                    // starts just to the right of where the cover lands.
                    Color.clear.frame(width: idlePad + idleSize, height: idleSize)
                    if idleManager.isIdle, let track = currentTrack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                            Text(album.title)
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        .opacity(idleManager.showIdleText ? 1 : 0)
                        .animation(.easeIn(duration: 0.3), value: idleManager.showIdleText)
                    }
                    Spacer()
                }
                .padding(.bottom, 40) // center text vertically on the cover
            }
            .allowsHitTesting(false)
        }
        .coordinateSpace(name: "nowPlayingViewport")
        .onPreferenceChange(CoverCenterKey.self) { fullCoverCenter = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(.dark)
        .onExitCommand(perform: collapse)
        .onAppear { startIdleTimer() }
        .onDisappear { idleManager.stop() }
        .onChange(of: viewModel.nowPlayingIdleTimeout) { _, _ in startIdleTimer() }
    }

    private func startIdleTimer() {
        let t = viewModel.nowPlayingIdleTimeout
        idleManager.start(timeout: t == 0 ? 0 : TimeInterval(t))
    }
}

// MARK: - Idle cover

/// Animating cover shown only during idle mode. Uses State(initialValue:) so
/// position is correct on frame 1 — no onChange pre-snap required.
private struct IdleCoverView: View {
    let image: Image
    let targetPosition: CGPoint

    @State private var position: CGPoint
    @State private var size: CGFloat = 420

    init(image: Image, startPosition: CGPoint, targetPosition: CGPoint) {
        self.image = image
        self.targetPosition = targetPosition
        _position = State(initialValue: startPosition)
    }

    var body: some View {
        AlbumCoverView(image: image)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
            .position(position)
            .onAppear {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.88)) {
                    position = targetPosition
                    size = 88
                }
            }
    }
}

// MARK: - Window helpers

#Preview {
    let viewModel = AppViewModel()
    return ContentView()
        .environmentObject(viewModel)
        .environmentObject(viewModel.playback)
}

private struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }
}

private final class FullscreenHidingWindowDelegate: NSObject, NSWindowDelegate {
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        [.autoHideToolbar, .autoHideMenuBar, .fullScreen]
    }
}

private final class SpacebarToggleManager {
    private var monitor: Any?
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let disallowed = event.modifierFlags.intersection([.command, .option, .control])
            guard disallowed.isEmpty else { return event }
            guard event.charactersIgnoringModifiers == " " else { return event }
            if let responder = NSApp.keyWindow?.firstResponder {
                if responder is NSTextView || responder is NSTextField {
                    return event
                }
            }
            onToggle()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
