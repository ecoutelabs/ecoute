import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var playback: PlaybackState
    @State private var windowDelegate = FullscreenHidingWindowDelegate()
    @State private var keyShortcuts: SingleKeyShortcuts?
    @State private var searchQuery = ""
    @StateObject private var idleManager = IdleManager()
    @State private var fullCoverCenter: CGPoint = .zero
    @State private var filterText: String = ""

    // Whether the per-section filter toolbar is relevant
    private var showFilterBar: Bool {
        showsTitle && viewModel.selectedSection != .home
    }

    private var showsTitle: Bool {
        !viewModel.isNowPlayingExpanded
            && viewModel.browsingAlbum == nil
            && viewModel.selectedSection != .search
    }

    private var showSearchBar: Bool {
        !viewModel.isNowPlayingExpanded
            && viewModel.browsingAlbum == nil
            && viewModel.selectedSection == .search
    }

    private var sectionTitle: String {
        switch viewModel.selectedSection {
        case .home:    "Home"
        case .albums:  "Albums"
        case .artists: "Artists"
        case .songs:   "Songs"
        case .genres:  "Genres"
        case .search:  "Search"
        }
    }

    private var filterPrompt: String {
        switch viewModel.selectedSection {
        case .home:    ""
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

    private func toggleNowPlaying() {
        guard viewModel.currentAlbum != nil else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            viewModel.isNowPlayingExpanded.toggle()
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                LibrarySidebar()
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A real window title is what makes macOS 27 draw the solid
                    // strip under the toolbar when content scrolls beneath it.
                    .navigationTitle(showsTitle ? sectionTitle : "")
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

            if viewModel.isCommandPaletteVisible {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.isCommandPaletteVisible = false }
                    .transition(.opacity)
                    .zIndex(2)
                CommandPalette()
                    .padding(.top, 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    .zIndex(3)
            }
        }
        .animation(.easeOut(duration: 0.14), value: viewModel.isCommandPaletteVisible)
        .frame(minWidth: 820, idealWidth: 1020, minHeight: 450, idealHeight: 760)
        // No title-bar strip over now playing.
        .toolbarBackgroundVisibility(
            viewModel.isNowPlayingExpanded ? .hidden : .automatic,
            for: .windowToolbar
        )
        .background(WindowAccessor { window in
            windowDelegate.install(on: window)
        })
        .toolbar {
            if viewModel.isNowPlayingExpanded {
                // Invisible placeholder: an empty toolbar disappears, which shifts the
                // traffic lights. The back button is drawn in the overlay instead.
                ToolbarItem(placement: .navigation) {
                    Color.clear.frame(width: 1, height: 1)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if showSearchBar {
                ToolbarItem(placement: .principal) {
                    ViewFilterField(text: $searchQuery, prompt: "Search library", focusOnAppear: true)
                        .frame(width: 360)
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
            keyShortcuts = SingleKeyShortcuts(actions: [
                " ": { viewModel.togglePlayback() },
                "f": toggleNowPlaying,
            ])
            keyShortcuts?.start()
        }
        .onDisappear {
            keyShortcuts?.stop()
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
            case .home:
                HomeView()
            case .albums:
                AlbumGridView(filterText: filterText)
            case .artists:
                ArtistListView(filterText: filterText)
            case .songs:
                SongListView(filterText: filterText)
            case .genres:
                GenreBrowserView(filterText: filterText)
            case .search:
                SearchView(query: searchQuery)
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
                .scrollEdgeEffectHidden(true, for: .top)
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

            // Back button in the top-left corner, beside the window controls, over
            // where the sidebar sits underneath.
            Button(action: collapse) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .circle)
            // Esc belongs to the command palette while it's open.
            .keyboardShortcut(viewModel.isCommandPaletteVisible ? nil : .cancelAction)
            .padding(.leading, 100)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
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

/// Wraps SwiftUI's own window delegate instead of replacing it — SwiftUI relies on
/// its delegate for window sizing and frame restoration.
private final class FullscreenHidingWindowDelegate: NSObject, NSWindowDelegate {
    private var original: NSWindowDelegate?

    func install(on window: NSWindow?) {
        guard let window, window.delegate !== self else { return }
        original = window.delegate
        window.delegate = self
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if original?.responds(to: aSelector) == true { return original }
        return super.forwardingTarget(for: aSelector)
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        [.autoHideToolbar, .autoHideMenuBar, .fullScreen]
    }
}

/// Bare-key shortcuts (Space, F), ignored while typing in a text field.
private final class SingleKeyShortcuts {
    private var monitor: Any?
    private let actions: [String: () -> Void]

    init(actions: [String: () -> Void]) {
        self.actions = actions
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let disallowed = event.modifierFlags.intersection([.command, .option, .control])
            guard disallowed.isEmpty else { return event }
            guard let key = event.charactersIgnoringModifiers,
                  let action = self.actions[key] else { return event }
            if let responder = NSApp.keyWindow?.firstResponder {
                if responder is NSTextView || responder is NSTextField {
                    return event
                }
            }
            action()
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
