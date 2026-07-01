import SwiftUI
import MetalKit

struct NowPlayingBackground: NSViewRepresentable {
    let coverData: Data?
    let nightMode: Bool

    // Loads the default album art asset as PNG data for use as Metal renderer input.
    static let defaultArtData: Data? = {
        NSImage(named: "DefaultAlbumArt").flatMap { $0.tiffRepresentation }
    }()

    private var effectiveCoverData: Data? {
        coverData ?? Self.defaultArtData
    }

    func makeCoordinator() -> NowPlayingBackgroundRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return NowPlayingBackgroundRenderer(device: device)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        if let renderer = context.coordinator {
            view.delegate = renderer
            renderer.updateCoverData(effectiveCoverData)
            renderer.highlightCap = nightMode ? (100.0 / 255.0) : 0.85
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator?.updateCoverData(effectiveCoverData)
        context.coordinator?.highlightCap = nightMode ? (100.0 / 255.0) : 0.85
    }
}
