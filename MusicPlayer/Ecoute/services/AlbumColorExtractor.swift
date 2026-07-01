import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct AlbumColorExtractor {

    private let ciContext = CIContext()

    // MARK: - Public API

    /// k-means accent colors, one optimised per colour scheme.
    func accentColors(from data: Data?, k: Int = 4) -> (dark: Color, light: Color) {
        let gray = Color(red: 0.5, green: 0.5, blue: 0.5)
        if data == nil {
            return (dark: Color(red: 0.608, green: 0.455, blue: 0.729),   // #9B74BA
                    light: Color(red: 0.482, green: 0.353, blue: 0.639))  // #7B5AA3
        }
        guard let pixels = downsample(data, size: 60), !pixels.isEmpty else {
            return (gray, gray)
        }
        let centroids = kMeans(pixels: pixels, k: k)

        let minContrast = 3.0
        let darkBgLum   = 0.020  // #262728
        let lightBgLum  = 1.0    // #FFFFFF

        func best(bgLum: Double) -> Color {
            let scored = centroids.map { p in (score: vibrancyIfContrast(p, bgLum: bgLum, minRatio: minContrast), pixel: p) }
            if let pick = scored.max(by: { $0.score < $1.score }), pick.score >= 0 {
                return Color(red: pick.pixel.r, green: pick.pixel.g, blue: pick.pixel.b)
            }
            return gray
        }

        return (dark: best(bgLum: darkBgLum), light: best(bgLum: lightBgLum))
    }

    /// Most visually interesting colour from the album art — no contrast requirement,
    /// suitable as a backing colour where legibility comes from overlay elements.
    func vibrantColor(from data: Data?, k: Int = 6) -> Color {
        let noDataFallback = Color(red: 0.482, green: 0.353, blue: 0.639) // #7B5AA3
        let noColorFallback = Color(red: 0.12, green: 0.12, blue: 0.14)
        guard data != nil else { return noDataFallback }
        guard let pixels = downsample(data, size: 60), !pixels.isEmpty else { return noColorFallback }
        let centroids = kMeans(pixels: pixels, k: k)
        let best = centroids.max { vibrancy($0) < vibrancy($1) }
        guard let best else { return noColorFallback }
        return Color(red: best.r, green: best.g, blue: best.b)
    }

    /// Simple average colour — used as the now-playing background base.
    func dominantColor(from data: Data?) -> Color {
        guard let data, let ciImage = CIImage(data: data) else {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        }
        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent
        guard let output = filter.outputImage else {
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &bitmap, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return Color(red: Double(bitmap[0]) / 255,
                     green: Double(bitmap[1]) / 255,
                     blue:  Double(bitmap[2]) / 255)
    }

    /// White for dark backgrounds, near-black for very bright ones.
    func preferredTextColor(for background: Color) -> Color {
        let ns = NSColor(background)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return .white }
        let lum = 0.2126 * Self.linearized(rgb.redComponent)
                + 0.7152 * Self.linearized(rgb.greenComponent)
                + 0.0722 * Self.linearized(rgb.blueComponent)
        return lum < 0.9 ? .white : Color(red: 0.08, green: 0.08, blue: 0.1)
    }

    // MARK: - WCAG helpers

    static func linearized(_ value: CGFloat) -> Double {
        let v = Double(value)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    // MARK: - Private

    private typealias Pixel = (r: Double, g: Double, b: Double)

    private func downsample(_ data: Data?, size: Int) -> [Pixel]? {
        guard let data, let ciImage = CIImage(data: data) else { return nil }
        let scale = CGAffineTransform(scaleX: CGFloat(size) / ciImage.extent.width,
                                      y: CGFloat(size) / ciImage.extent.height)
        let scaled = ciImage.transformed(by: scale)
        var bitmap = [UInt8](repeating: 0, count: size * size * 4)
        ciContext.render(scaled, toBitmap: &bitmap, rowBytes: size * 4,
                         bounds: CGRect(x: 0, y: 0, width: size, height: size),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var pixels: [Pixel] = []
        pixels.reserveCapacity(size * size)
        for i in stride(from: 0, to: size * size * 4, by: 4) {
            pixels.append((Double(bitmap[i]) / 255, Double(bitmap[i+1]) / 255, Double(bitmap[i+2]) / 255))
        }
        return pixels
    }

    private func kMeans(pixels: [Pixel], k: Int) -> [Pixel] {
        // Deterministic seeding: brightest first, then furthest from existing centroids
        let first = pixels.max(by: { ($0.r + $0.g + $0.b) < ($1.r + $1.g + $1.b) }) ?? pixels[0]
        var centroids: [Pixel] = [first]
        while centroids.count < k {
            var maxDist = -1.0
            var farthest = pixels[0]
            for p in pixels {
                var minDist = Double.infinity
                for c in centroids {
                    let d = (p.r-c.r)*(p.r-c.r) + (p.g-c.g)*(p.g-c.g) + (p.b-c.b)*(p.b-c.b)
                    if d < minDist { minDist = d }
                }
                if minDist > maxDist { maxDist = minDist; farthest = p }
            }
            centroids.append(farthest)
        }

        var assignments = [Int](repeating: 0, count: pixels.count)
        for _ in 0..<20 {
            var changed = false
            for i in 0..<pixels.count {
                let p = pixels[i]
                var best = 0
                var bestDist = Double.infinity
                for j in 0..<k {
                    let c = centroids[j]
                    let d = (p.r-c.r)*(p.r-c.r) + (p.g-c.g)*(p.g-c.g) + (p.b-c.b)*(p.b-c.b)
                    if d < bestDist { bestDist = d; best = j }
                }
                if assignments[i] != best { assignments[i] = best; changed = true }
            }
            if !changed { break }
            var sums = [(r: Double, g: Double, b: Double, n: Int)](repeating: (0,0,0,0), count: k)
            for i in 0..<pixels.count {
                let j = assignments[i]
                sums[j].r += pixels[i].r; sums[j].g += pixels[i].g; sums[j].b += pixels[i].b; sums[j].n += 1
            }
            for j in 0..<k where sums[j].n > 0 {
                centroids[j] = (sums[j].r / Double(sums[j].n),
                                sums[j].g / Double(sums[j].n),
                                sums[j].b / Double(sums[j].n))
            }
        }
        return centroids
    }

    private func luminance(_ p: Pixel) -> Double {
        0.2126 * Self.linearized(CGFloat(p.r))
        + 0.7152 * Self.linearized(CGFloat(p.g))
        + 0.0722 * Self.linearized(CGFloat(p.b))
    }

    private func vibrancy(_ p: Pixel) -> Double {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(red: CGFloat(p.r), green: CGFloat(p.g), blue: CGFloat(p.b), alpha: 1)
            .usingColorSpace(.deviceRGB)?
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(s) * Double(b)
    }

    private func vibrancyIfContrast(_ p: Pixel, bgLum: Double, minRatio: Double) -> Double {
        let lum = luminance(p)
        let hi = Swift.max(lum, bgLum), lo = Swift.min(lum, bgLum)
        let ratio = (hi + 0.05) / (lo + 0.05)
        guard ratio >= minRatio else { return -1 }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(red: p.r, green: p.g, blue: p.b, alpha: 1)
            .usingColorSpace(.deviceRGB)?
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(s) * Double(b)
    }
}
