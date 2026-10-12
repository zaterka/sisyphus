import CoreGraphics
import Foundation

// MARK: - Pixel buffer

/// A tiny RGBA8 pixel buffer used to author the background and the sprites, then frozen into a
/// `CGImage`. Origin is top-left, y grows downward (same as the scene's logical coordinates).
struct PixelBuffer {
    let width: Int
    let height: Int
    private(set) var bytes: [UInt8]

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "PixelBuffer needs a positive size")
        self.width = width
        self.height = height
        self.bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Writes an opaque `0xRRGGBB` colour. Out-of-bounds writes are ignored.
    mutating func set(_ x: Int, _ y: Int, _ rgb: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = UInt8((rgb >> 16) & 0xFF)
        bytes[i + 1] = UInt8((rgb >> 8) & 0xFF)
        bytes[i + 2] = UInt8(rgb & 0xFF)
        bytes[i + 3] = 0xFF
    }

    /// Freezes the buffer into an sRGB `CGImage`. Pixels are either fully opaque or fully
    /// transparent (all zero), so straight and premultiplied alpha are identical.
    func makeImage() -> CGImage {
        let data = Data(bytes) as CFData
        guard
            let provider = CGDataProvider(data: data),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            preconditionFailure("Could not build a \(width)x\(height) CGImage")
        }
        return image
    }
}

// MARK: - Scene geometry

/// Logical geometry of the scene (160×90 logical px, origin top-left, y down).
enum SceneGeometry {
    static let width = 160
    static let height = 90
    /// Each logical pixel is drawn as a 2×2 point block.
    static let scale: Double = 2

    static let slopeStart = (x: 12.0, y: 78.0)
    static let slopeEnd = (x: 128.0, y: 24.0)

    /// Ground height at a logical x: flat at the bottom left of the slope, the slope itself, then
    /// the plateau up to the right edge.
    static func groundY(atX x: Double) -> Double {
        if x <= slopeStart.x { return slopeStart.y }
        if x >= slopeEnd.x { return slopeEnd.y }
        let t = (x - slopeStart.x) / (slopeEnd.x - slopeStart.x)
        return slopeStart.y + t * (slopeEnd.y - slopeStart.y)
    }

    /// Logical x of a progress value `p` (0 = foot of the hill, 1 = summit).
    static func slopeX(progress p: Double) -> Double {
        let p = p.isFinite ? min(max(p, 0), 1) : 0
        return slopeStart.x + p * (slopeEnd.x - slopeStart.x)
    }

    /// Point on the slope for progress `p`: `x = 12 + p*116`, `y = 78 - p*54`.
    static func slopePoint(progress p: Double) -> (x: Double, y: Double) {
        let x = slopeX(progress: p)
        return (x, groundY(atX: x))
    }
}

// MARK: - Background

/// The static backdrop: banded, dithered dusk sky, a setting sun, pixel clouds, two mountain
/// ridges, the hill with a grass rim and dithered earth, stones and a ruined column.
/// Built once into a 160×90 `CGImage`.
enum Background {
    /// The cached background image.
    static var image: CGImage { Cache.shared.image }

    private final class Cache: @unchecked Sendable {
        static let shared = Cache()
        let image: CGImage
        private init() { image = Background.render() }
    }

    // MARK: Palette (SNES-style dusk)

    private static let skyBands: [UInt32] = [
        0x23163F, 0x2E1D55, 0x3E2668, 0x553078,
        0x753A80, 0x9C4880, 0xC45A78, 0xE27668,
        0xF39A68, 0xFBC27A,
    ]
    private static let sunCore: UInt32 = 0xFFF2C0
    private static let sunRim: UInt32 = 0xFFD890
    private static let cloudLight: UInt32 = 0xFFD2B0
    private static let cloudMid: UInt32 = 0xE89A98
    private static let cloudDark: UInt32 = 0xA9637F
    private static let mountainFarRim: UInt32 = 0xB06A8C
    private static let mountainFar: UInt32 = 0x7A4880
    private static let mountainNearRim: UInt32 = 0x6E4276
    private static let mountainNear: UInt32 = 0x4C2E62
    private static let grassLight: UInt32 = 0xA8E070
    private static let grass: UInt32 = 0x58B048
    private static let grassDark: UInt32 = 0x2F7A3A
    private static let earth1: UInt32 = 0x9A6238
    private static let earth2: UInt32 = 0x7A4828
    private static let earth3: UInt32 = 0x58321E
    private static let earth4: UInt32 = 0x3C2016
    private static let stoneLight: UInt32 = 0xC8C0B8
    private static let stoneMid: UInt32 = 0x8C8288
    private static let stoneDark: UInt32 = 0x544A58
    private static let marbleLight: UInt32 = 0xF0E6D2
    private static let marbleMid: UInt32 = 0xC8B8A0
    private static let marbleDark: UInt32 = 0x8C7C70
    private static let outline: UInt32 = 0x2A1A2A

    /// 4×4 Bayer matrix, values 0...15.
    private static let bayer: [[Int]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]

    private static func threshold(_ x: Int, _ y: Int) -> Double {
        (Double(bayer[y & 3][x & 3]) + 0.5) / 16
    }

    /// Deterministic per-pixel hash in 0..<1 for sprinkling details.
    private static func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65_536
    }

    // MARK: Rendering

    static func render() -> CGImage {
        let w = SceneGeometry.width
        let h = SceneGeometry.height
        var buf = PixelBuffer(width: w, height: h)
        drawSky(&buf)
        drawSun(&buf, cx: 34, cy: 52, radius: 8)
        drawCloud(&buf, cx: 50, cy: 13, scale: 1.0)
        drawCloud(&buf, cx: 98, cy: 21, scale: 0.75)
        drawCloud(&buf, cx: 140, cy: 9, scale: 0.9)
        drawMountains(&buf)
        drawGround(&buf)
        drawStones(&buf)
        drawColumnRuin(&buf, x: 145)
        return buf.makeImage()
    }

    private static func drawSky(_ buf: inout PixelBuffer) {
        let horizon = 66.0
        let bands = Double(skyBands.count)
        for y in 0..<buf.height {
            for x in 0..<buf.width {
                let t = min(Double(y) / horizon, 0.999)
                let v = t * bands
                var band = Int(v)
                let f = v - Double(band)
                // Solid bands with a dithered seam in the last 40% of each band.
                if f > 0.6, threshold(x, y) < (f - 0.6) / 0.4 {
                    band += 1
                }
                buf.set(x, y, skyBands[min(band, skyBands.count - 1)])
            }
        }
    }

    private static func drawSun(_ buf: inout PixelBuffer, cx: Int, cy: Int, radius: Int) {
        let r = Double(radius)
        for y in (cy - radius - 1)...(cy + radius + 1) {
            for x in (cx - radius - 1)...(cx + radius + 1) {
                let d = (Double(x - cx) * Double(x - cx) + Double(y - cy) * Double(y - cy)).squareRoot()
                if d <= r - 1.5 {
                    // Horizontal heat stripes across the lower half, very SNES.
                    if y > cy + 1, (y - cy) % 3 == 0 {
                        buf.set(x, y, sunRim)
                    } else {
                        buf.set(x, y, sunCore)
                    }
                } else if d <= r {
                    buf.set(x, y, sunRim)
                }
            }
        }
    }

    private static func drawCloud(_ buf: inout PixelBuffer, cx: Int, cy: Int, scale: Double) {
        // A cloud is a union of flattened ellipses: (dx, dy, rx, ry).
        let puffs: [(Double, Double, Double, Double)] = [
            (0, 0, 9, 3), (-5, -1, 5, 3), (3, -2, 5, 3.2), (8, 0.5, 5, 2.2), (-9, 0.8, 4, 1.8),
        ]
        func inside(_ x: Int, _ y: Int) -> Bool {
            for (dx, dy, rx, ry) in puffs {
                let ex = (Double(x - cx) - dx * scale) / (rx * scale)
                let ey = (Double(y - cy) - dy * scale) / (ry * max(scale, 0.8))
                if ex * ex + ey * ey <= 1 { return true }
            }
            return false
        }
        let span = Int(16 * scale) + 2
        for y in (cy - 6)...(cy + 5) {
            for x in (cx - span)...(cx + span) where inside(x, y) {
                let color: UInt32
                if !inside(x, y + 1) {
                    color = cloudDark
                } else if !inside(x, y - 1) || !inside(x, y - 2) {
                    color = cloudLight
                } else if y >= cy + 1, threshold(x, y) < 0.5 {
                    color = cloudDark
                } else {
                    color = cloudMid
                }
                buf.set(x, y, color)
            }
        }
    }

    private static func drawMountains(_ buf: inout PixelBuffer) {
        for x in 0..<buf.width {
            let fx = Double(x)
            let far = 50 + 6 * sin(fx * 0.055 + 1.3) + 3 * sin(fx * 0.17 + 0.4) + 1.5 * sin(fx * 0.43)
            let near = 61 + 4 * sin(fx * 0.08 + 4.0) + 2.5 * sin(fx * 0.23 + 1.0) + 1 * sin(fx * 0.61)
            let farTop = Int(far.rounded())
            let nearTop = Int(near.rounded())
            for y in max(0, farTop)..<buf.height {
                buf.set(x, y, y == farTop ? mountainFarRim : mountainFar)
            }
            for y in max(0, nearTop)..<buf.height {
                let c: UInt32
                if y == nearTop {
                    c = mountainNearRim
                } else if y == nearTop + 1, threshold(x, y) < 0.5 {
                    c = mountainNearRim
                } else {
                    c = mountainNear
                }
                buf.set(x, y, c)
            }
        }
    }

    private static func drawGround(_ buf: inout PixelBuffer) {
        for x in 0..<buf.width {
            let top = Int(SceneGeometry.groundY(atX: Double(x)).rounded())
            // Grass tufts poking above the rim on a few columns.
            if hash(x, 7) < 0.22 {
                buf.set(x, top - 1, grass)
            }
            for y in max(0, top)..<buf.height {
                let depth = y - top
                let c: UInt32
                switch depth {
                case 0:
                    c = grassLight
                case 1:
                    c = grass
                case 2:
                    c = threshold(x, y) < 0.6 ? grass : grassDark
                case 3:
                    c = threshold(x, y) < 0.5 ? grassDark : earth1
                default:
                    // Earth darkens with depth through dithered steps.
                    let d = Double(depth - 4) / 26
                    let level = d * 3 + (threshold(x, y) - 0.5) * 0.9
                    switch level {
                    case ..<0.8: c = earth1
                    case ..<1.7: c = earth2
                    case ..<2.6: c = earth3
                    default: c = earth4
                    }
                }
                buf.set(x, y, c)
            }
        }
    }

    private static func drawStones(_ buf: inout PixelBuffer) {
        // (x, depth below the rim)
        let stones: [(Int, Int)] = [(4, 7), (31, 8), (58, 6), (83, 11), (104, 7), (136, 9), (152, 20), (22, 4)]
        for (x, depth) in stones {
            let top = Int(SceneGeometry.groundY(atX: Double(x + 1)).rounded()) + depth
            buf.set(x, top, stoneMid)
            buf.set(x + 1, top, stoneLight)
            buf.set(x + 2, top, stoneMid)
            buf.set(x - 1, top + 1, stoneDark)
            buf.set(x, top + 1, stoneMid)
            buf.set(x + 1, top + 1, stoneMid)
            buf.set(x + 2, top + 1, stoneDark)
            buf.set(x + 3, top + 1, stoneDark)
        }
    }

    /// A broken Doric column on the plateau, plus a fallen drum.
    private static func drawColumnRuin(_ buf: inout PixelBuffer, x: Int) {
        let ground = Int(SceneGeometry.slopeEnd.y) // plateau rim
        // Base (stylobate) 9 wide, 2 tall.
        for dx in -1...7 {
            buf.set(x + dx, ground - 1, dx == -1 || dx == 7 ? outline : marbleMid)
            buf.set(x + dx, ground - 2, dx == -1 || dx == 7 ? outline : marbleLight)
        }
        for dx in -1...7 { buf.set(x + dx, ground - 3, outline) }
        // Shaft 5 wide with fluting, broken top.
        let shaftTop = [ground - 15, ground - 16, ground - 14, ground - 13, ground - 15]
        for i in 0..<5 {
            let cx = x + 1 + i
            for y in shaftTop[i]...(ground - 4) {
                let c: UInt32
                switch i {
                case 0: c = marbleLight
                case 1: c = marbleMid
                case 2: c = marbleLight
                case 3: c = marbleMid
                default: c = marbleDark
                }
                buf.set(cx, y, c)
            }
            buf.set(cx, shaftTop[i] - 1, outline)
        }
        for y in (ground - 15)...(ground - 4) {
            buf.set(x, y, outline)
            buf.set(x + 6, y, outline)
        }
        // A crack across the shaft.
        buf.set(x + 2, ground - 9, marbleDark)
        buf.set(x + 3, ground - 8, marbleDark)
        buf.set(x + 4, ground - 8, marbleDark)
        // Fallen drum to the right.
        let fx = x + 10
        for dx in 0...4 {
            buf.set(fx + dx, ground - 4, outline)
            buf.set(fx + dx, ground - 3, dx == 4 ? marbleDark : marbleLight)
            buf.set(fx + dx, ground - 2, dx == 4 ? marbleDark : marbleMid)
            buf.set(fx + dx, ground - 1, outline)
        }
        buf.set(fx - 1, ground - 3, outline)
        buf.set(fx - 1, ground - 2, outline)
        buf.set(fx + 5, ground - 3, outline)
        buf.set(fx + 5, ground - 2, outline)
    }
}
