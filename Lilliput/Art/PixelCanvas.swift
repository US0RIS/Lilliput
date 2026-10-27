import Foundation
import CoreGraphics
import AppKit

struct RGBA: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ hex: UInt32, alpha: UInt8 = 255) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
        a = alpha
    }

    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    func scaled(_ f: Double) -> RGBA {
        func c(_ v: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(v) * f).rounded()))) }
        return RGBA(r: c(r), g: c(g), b: c(b), a: a)
    }

    func mixed(with o: RGBA, _ t: Double) -> RGBA {
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(x) * (1 - t) + Double(y) * t).rounded()))) }
        return RGBA(r: m(r, o.r), g: m(g, o.g), b: m(b, o.b), a: a)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

/// A tiny RGBA bitmap used to author all of Lilliput's pixel art in code.
/// Coordinates are (x, y) with y = 0 at the top row.
struct PixelCanvas {
    let width: Int
    let height: Int
    private(set) var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    func color(_ x: Int, _ y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        let i = (y * width + x) * 4
        return RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    func isOpaque(_ x: Int, _ y: Int) -> Bool { color(x, y).a > 0 }

    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height, c.a > 0 else { return }
        let i = (y * width + x) * 4
        bytes[i] = c.r
        bytes[i + 1] = c.g
        bytes[i + 2] = c.b
        bytes[i + 3] = c.a
    }

    mutating func clearPixel(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0
    }

    mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) {
            for xx in x..<(x + w) { set(xx, yy, c) }
        }
    }

    mutating func hline(_ x0: Int, _ x1: Int, _ y: Int, _ c: RGBA) {
        guard x1 >= x0 else { return }
        for x in x0...x1 { set(x, y, c) }
    }

    mutating func vline(_ x: Int, _ y0: Int, _ y1: Int, _ c: RGBA) {
        guard y1 >= y0 else { return }
        for y in y0...y1 { set(x, y, c) }
    }

    /// Draws a pattern where each character maps to a color via `palette`.
    /// Unknown characters (and '.') are left transparent.
    mutating func stamp(_ rows: [String], at ox: Int = 0, _ oy: Int = 0, palette: [Character: RGBA]) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                if let c = palette[ch] { set(ox + x, oy + y, c) }
            }
        }
    }

    /// Nearest-neighbour integer upscale.
    func scaled(by k: Int) -> PixelCanvas {
        guard k > 1 else { return self }
        var out = PixelCanvas(width: width * k, height: height * k)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x, y)
                if c.a > 0 { out.fill(x * k, y * k, k, k, c) }
            }
        }
        return out
    }

    func makeImage() -> CGImage? {
        // Premultiply for CoreGraphics.
        var premul = bytes
        var i = 0
        while i < premul.count {
            let a = UInt16(premul[i + 3])
            if a < 255 {
                premul[i] = UInt8(UInt16(premul[i]) * a / 255)
                premul[i + 1] = UInt8(UInt16(premul[i + 1]) * a / 255)
                premul[i + 2] = UInt8(UInt16(premul[i + 2]) * a / 255)
            }
            i += 4
        }
        let data = Data(premul) as CFData
        guard let provider = CGDataProvider(data: data),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
