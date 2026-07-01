import MetalKit
import AppKit

struct BackgroundUniforms {
    var time: Float
    var width: Float
    var height: Float
    var speed: Float
    var saturation: Float
    var displayScale: Float
    var samplePosMultiplier: Float
    var highlightCap: Float
}

final class NowPlayingBackgroundRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal state

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var compositePipeline: MTLRenderPipelineState?
    private var dualKawaseDownPipeline: MTLRenderPipelineState?
    private var dualKawaseUpPipeline: MTLRenderPipelineState?
    private var finalizePipeline: MTLRenderPipelineState?

    // Offscreen textures: full-res composite/output target + pyramid levels
    private var textureA: MTLTexture?       // full res — composite write & final upsample output
    private var pyramid: [MTLTexture] = []  // [1/2, 1/4, 1/8, …] — rebuilt on resize

    // Number of downsample levels per display type. HiDPI gets one extra to match
    // point-space blur radius. Increase either to widen the blur.
    private let baseLevels = 4
    private var hiDPILevels: Int { baseLevels + 1 }

    // Album art texture — rebuilt when coverData changes
    private var artTexture: MTLTexture?
    private var lastCoverData: Data?

    private let startTime: CFTimeInterval = CACurrentMediaTime()

    var speed: Float = 0.02
    var saturation: Float = 1.4
    var samplePosMultiplier: Float = 3.0
    var highlightCap: Float = 0.85

    // MARK: - Init

    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        super.init()
        buildPipelines()
    }

    // MARK: - Public

    func updateCoverData(_ data: Data?) {
        guard data != lastCoverData else { return }
        lastCoverData = data
        artTexture = data.flatMap { Self.makeTexture(from: $0, device: device) }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        textureA = makeOffscreenTexture(size: size)
        pyramid = (1...hiDPILevels).compactMap { level in
            makeOffscreenTexture(size: size, divisor: 1 << level)
        }
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let compositePipeline,
            let dualKawaseDownPipeline,
            let dualKawaseUpPipeline,
            let finalizePipeline,
            let textureA,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let size = view.drawableSize
        let scale = Float(view.window?.backingScaleFactor ?? 1.0)
        var uniforms = BackgroundUniforms(
            time: Float(CACurrentMediaTime() - startTime),
            width: Float(size.width),
            height: Float(size.height),
            speed: speed,
            saturation: saturation,
            displayScale: scale,
            samplePosMultiplier: samplePosMultiplier,
            highlightCap: highlightCap
        )
        let uniformsLength = MemoryLayout<BackgroundUniforms>.size

        let levels = scale >= 2 ? hiDPILevels : baseLevels
        guard pyramid.count >= levels else { return }

        // Pass 1 — composite sprites + twirl → textureA (full res)
        encode(commandBuffer: commandBuffer, pipeline: compositePipeline,
               inputTexture: artTexture, outputTexture: textureA,
               uniforms: &uniforms, uniformsLength: uniformsLength,
               clearColor: MTLClearColorMake(0, 0, 0, 1))

        // Downsample: textureA → pyramid[0] → pyramid[1] → … → pyramid[levels-1]
        let chain = [textureA] + pyramid.prefix(levels)
        for i in 0..<levels {
            encode(commandBuffer: commandBuffer, pipeline: dualKawaseDownPipeline,
                   inputTexture: chain[i], outputTexture: chain[i + 1],
                   uniforms: &uniforms, uniformsLength: uniformsLength)
        }

        // Upsample: pyramid[levels-1] → … → pyramid[0] → textureA
        for i in stride(from: levels - 1, through: 0, by: -1) {
            encode(commandBuffer: commandBuffer, pipeline: dualKawaseUpPipeline,
                   inputTexture: chain[i + 1], outputTexture: chain[i],
                   uniforms: &uniforms, uniformsLength: uniformsLength)
        }

        // Finalize (saturation + darken + grain) → drawable
        let finalDescriptor = MTLRenderPassDescriptor()
        finalDescriptor.colorAttachments[0].texture = drawable.texture
        finalDescriptor.colorAttachments[0].loadAction = .clear
        finalDescriptor.colorAttachments[0].storeAction = .store
        finalDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalDescriptor) {
            encoder.setRenderPipelineState(finalizePipeline)
            encoder.setFragmentTexture(textureA, index: 0)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Private helpers

    private func encode(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        inputTexture: MTLTexture?,
        outputTexture: MTLTexture,
        uniforms: inout BackgroundUniforms,
        uniformsLength: Int,
        clearColor: MTLClearColor = MTLClearColorMake(0, 0, 0, 0)
    ) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = outputTexture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = clearColor

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(inputTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func makeOffscreenTexture(size: CGSize, divisor: Int = 1) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:  max(1, Int(size.width)  / divisor),
            height: max(1, Int(size.height) / divisor),
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else { return }

        let vertex = library.makeFunction(name: "vertex_passthrough")

        func makePipeline(fragmentName: String) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertex
            desc.fragmentFunction = library.makeFunction(name: fragmentName)
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        compositePipeline      = makePipeline(fragmentName: "fragment_composite_twirl")
        dualKawaseDownPipeline = makePipeline(fragmentName: "fragment_dual_kawase_down")
        dualKawaseUpPipeline   = makePipeline(fragmentName: "fragment_dual_kawase_up")
        finalizePipeline       = makePipeline(fragmentName: "fragment_finalize")
    }

    private static func makeTexture(from data: Data, device: MTLDevice) -> MTLTexture? {
        guard
            let nsImage = NSImage(data: data),
            let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        // Downscale to 128×128 — the composite shader tiles, rotates, and blurs this heavily,
        // so full-resolution art just wastes GPU memory bandwidth.
        let maxDim = 128
        let scale  = min(1.0, Double(maxDim) / Double(max(cgImage.width, cgImage.height)))
        let width  = max(1, Int(Double(cgImage.width)  * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixels = ctx.data else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        return texture
    }
}
