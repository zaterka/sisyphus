import CoreGraphics
import Foundation

/// The pixel-art logo of Sisyphus: a black-figure Attic pottery emblem, drawn as a character grid.
///
/// One character is one pixel and one palette entry, exactly like the scene sprites, but the logo
/// has its own palette, its own validator and its own renderer: it is not part of the scene, and a
/// change to a sprite must never be able to move the icon.
///
/// Two grids exist, and no rep is ever interpolated or decimated — every size is an exact
/// whole-number multiple of one of them:
///
/// * `master()` (64×64) is the emblem used from 64 px up. It is composed procedurally — a Greek-key
///   meander band, a marble slope, a shaded boulder and a sun — with a hand-authored black-figure
///   silhouette stamped on top, all inside a staircase rounded square.
/// * `small` (16×16) is hand-authored for the 16 px and 32 px reps, where a meander band and a
///   shaded boulder would collapse into noise.
enum LogoArt {

    // MARK: - Palette

    /// Palette character → `0xRRGGBB`. `.` is transparent.
    ///
    /// The field colours are the two tones of fired Attic terracotta: the emblem is painted *on*
    /// the orange clay, the figure and the meander are the black slip, and cream and gold are the
    /// reserved highlights — marble for the hill, gold leaf for the frame line.
    static let palette: [Character: UInt32] = [
        // Field: terracotta, dithered between its two tones.
        "T": 0xC8753A, // lit terracotta
        "t": 0xB0602C, // shaded terracotta
        "d": 0x8A4520, // ground below the slope
        // Black slip.
        "o": 0x1B1216, // figure, meander band, outlines
        // Marble, cream and gold.
        "c": 0xF0E5C9, // marble cream
        "C": 0xD3C29E, // marble in shade
        "y": 0xE0AC48, // gold
        "Y": 0xB27E22, // gold in shade
        // Boulder: grey stone, lit from the upper left.
        "L": 0xC9C4CE, // highlight
        "l": 0xA8A2B0, // light
        "G": 0x847F8E, // mid
        "g": 0x5F5A6B, // shadow
        "e": 0x3A3446, // deep shadow, cracks
    ]

    // MARK: - Sizes

    /// Side of the master grid. 64 divides every icon rep above it: 64, 128, 256, 512, 1024.
    static let size = 64
    /// Side of the hand-authored small grid: 16 and 32 are exact multiples of it.
    static let smallSize = 16

    /// The art sits inside a rounded square inset by 6 cells (9.4% of the icon) and everything
    /// outside it is transparent, which is what a macOS icon looks like. The corner is a pixel
    /// staircase — a circle test evaluated cell by cell — never an antialiased curve.
    static let shapeInset = 6
    static let shapeRadius = 11
    /// The small grid gets the same shape, scaled down: one cell of inset, a three-cell radius.
    static let smallShapeInset = 1
    static let smallShapeRadius = 3

    /// The meander band is six cells wide, so the emblem inside it is 40×40 cells at (12, 12).
    static let artInset = 12
    static let artSize = 40
    /// The band, from the panel's edge inwards: a gold line, four rows of meander, a cream line.
    private static let bandDepth = 6

    /// Cells 6…57 are the shaped icon; everything outside is transparent.
    private static var panelMin: Int { shapeInset }
    private static var panelMax: Int { size - 1 - shapeInset }
    /// The vertical bands stop short of the horizontal ones, which own the four corner blocks.
    private static var bandMin: Int { artInset }
    private static var bandMax: Int { artInset + artSize - 1 }

    // MARK: - The emblem's geometry (in field coordinates, 0…39)

    /// The slope, as `y = intercept - gradient * x`: it rises to the right, which is the way he
    /// pushes. The gradient is steep enough to read as a hill and shallow enough that the boulder
    /// still rests on it instead of rolling off.
    static let slopeGradient = 0.26
    static let slopeIntercept = 34.0

    /// The surface of the slope under `x`, in field coordinates.
    static func slopeY(_ x: Double) -> Double { slopeIntercept - slopeGradient * x }

    /// The boulder: a disc resting on the slope, so its centre sits one radius above the surface.
    static let boulderRadius = 9.5
    static var boulderCenter: (x: Double, y: Double) {
        let x = 26.0
        return (x, slopeY(x) - boulderRadius)
    }

    /// The sun, in the upper left of the field: clear of the boulder and of his head.
    static let sunOrigin = (x: 1, y: 1)

    /// Where the hand-authored figure is stamped, in field coordinates. His feet land on the
    /// slope and his hands reach the boulder's left face.
    static let figureOrigin = (x: 2, y: 14)

    // MARK: - The figure (hand-authored, black-figure silhouette)

    /// Sisyphus, 18×20, all black: he leans into the slope, both arms out to the boulder, the head
    /// forward of the shoulders, the near leg bent under him and the far leg stretched back down
    /// the hill.
    ///
    /// His feet are three rows apart on purpose. Over the stride the slope drops 0.26 × 10 ≈ 3 px,
    /// so this is the pose of someone pushing uphill rather than the same flat-footed figure pasted
    /// onto a diagonal.
    static let figure: [String] = [
        "..........ooo.....",
        ".........ooooo....",
        ".........ooooo....",
        "..........ooo.....",
        "..........oooo....",
        ".........ooooooooo",
        "........oooooooo..",
        ".......ooooooo....",
        ".......oooooo.....",
        "......oooooo......",
        "......ooooo.......",
        ".....oooooo.......",
        "....ooo..ooo......",
        "...ooo....ooo.....",
        "...ooo.....ooo....",
        "..ooo......oooo...",
        "..ooo......oooo...",
        ".ooo..............",
        "oooo..............",
        "oooo..............",
    ]

    // MARK: - The sun (hand-authored, 11×11)

    /// Gold, eight-pointed: a 5×5 core with a cross of rays and four diagonal sparks, its rim in
    /// the darker gold so the disc reads as a raised surface and not as a flat blob.
    static let sun: [String] = [
        ".....y.....",
        ".....y.....",
        "..y.....y..",
        "....YYY....",
        "...YyyyY...",
        "yyyYyyyYyyy",
        "...YyyyY...",
        "....YYY....",
        "..y.....y..",
        ".....y.....",
        ".....y.....",
    ]

    // MARK: - The meander band

    /// The Greek key, as a repeating tile: `X` is the reserved cream line, `.` the black slip.
    ///
    /// The line enters at the top right, drops to the bottom of the band, runs back to the left,
    /// turns up and ends inside its own previous turn. That nested turn is what makes it a key and
    /// not a comb — and the band is tiled with this tile, so the pattern is generated, not drawn.
    enum Meander {
        /// The period, in cells. The tile is exactly this wide.
        static let period = 8
        /// Four rows, because the band is four cells tall.
        static let tile: [String] = [
            "XXXXXXXX",
            ".......X",
            ".XXXXX.X",
            ".XXXXXXX",
        ]
        /// `true` where the tile draws the line `offset` cells along the band.
        static func hasLine(row: Int, offset: Int) -> Bool {
            let line = Array(tile[row])
            return line[((offset % period) + period) % period] == "X"
        }
    }

    // MARK: - Master grid

    /// Builds the 64×64 emblem: clay, slope, sun, boulder, figure, band, then the icon shape.
    static func master() -> [String] {
        var canvas = Canvas(size: size)
        paintField(&canvas)
        paintSlope(&canvas)
        paintSun(&canvas)
        paintBoulder(&canvas)
        paintFigure(&canvas)
        paintBand(&canvas)
        canvas.carveRoundedSquare(inset: shapeInset, radius: shapeRadius)
        return canvas.rows
    }

    // MARK: - Small grid (hand-authored, 16×16)

    /// The 16 px and 32 px art: the same emblem reduced to what a handful of pixels can carry.
    ///
    /// It is drawn the other way round from the master — a plain black frame, a 12×12 field inside
    /// it, the boulder in grey, and the figure nine cells tall (the smallest he can be and still read
    /// as a man pushing a rock) leaning in from the left with one arm out to the stone. The meander
    /// band, the boulder's shading and the sun are all dropped: at sixteen pixels they are noise, and
    /// what has to survive is the silhouette.
    ///
    /// The frame sits on the panel's own edge, one cell in from the corner of the canvas, because the
    /// shape mask makes everything outside that cell transparent — a frame on the canvas edge would
    /// be carved away entirely. The mask cuts the frame's corner cells just as it cuts the master's,
    /// which is what a rounded square looks like.
    static let small: [String] = [
        "................",
        ".oooooooooooooo.",
        ".oTtTtTtTtTtTto.",
        ".otTtTtTtTtTtTo.",
        ".oTtTtotTtTtTto.",
        ".otTtoootoootTo.",
        ".oTtTooooLLloto.",
        ".otTootToLlGoTo.",
        ".oTtotTtolGgoto.",
        ".otototTtoootco.",
        ".oToTtotTccccCo.",
        ".ooTtccccCCCCto.",
        ".occcCCCCdtdtdo.",
        ".oCCCtdtdtdtdto.",
        ".oooooooooooooo.",
        "................",
    ]

    /// The small grid with the icon shape cut into it, ready to render.
    static func smallShaped() -> [String] {
        var canvas = Canvas(size: smallSize)
        canvas.stamp(small, atX: 0, y: 0)
        canvas.carveRoundedSquare(inset: smallShapeInset, radius: smallShapeRadius)
        return canvas.rows
    }

    // MARK: - Errors

    /// Why a grid could not be turned into an image.
    ///
    /// The grids are literals, so these are programming errors — but the export reports them
    /// instead of trapping: `--export-logo` has to fail with exit code 1 and a readable message,
    /// whether it ran from a shell or from CI.
    enum GridError: Error, CustomStringConvertible {
        case wrongRowCount(name: String, expected: Int, found: Int)
        case wrongRowWidth(name: String, row: Int, expected: Int, found: Int)
        case unknownCharacter(name: String, row: Int, character: Character)
        case imageFailed(name: String, width: Int, height: Int)

        var description: String {
            switch self {
            case let .wrongRowCount(name, expected, found):
                return "\(name): expected \(expected) rows, found \(found)"
            case let .wrongRowWidth(name, row, expected, found):
                return "\(name): row \(row) is \(found) cells wide, expected \(expected)"
            case let .unknownCharacter(name, row, character):
                return "\(name): unknown palette character '\(character)' in row \(row)"
            case let .imageFailed(name, width, height):
                return "\(name): could not build a \(width)×\(height) image"
            }
        }
    }

    // MARK: - Conversion

    /// Checks a grid and turns it into a `CGImage` scaled by `scale`, an exact whole number.
    ///
    /// The image is sRGB RGBA with `shouldInterpolate` off, and scaling means copying whole pixels:
    /// nothing here filters, blurs or averages anything, so the art is crisp at every size the icon
    /// needs.
    ///
    /// - Throws: `GridError` when the grid is not `side`×`side` or uses an unknown character.
    static func makeImage(_ rows: [String], name: String, side: Int, scale: Int) throws -> CGImage {
        try validate(rows, name: name, side: side)

        let width = side * scale
        var buffer = [UInt8](repeating: 0, count: width * width * 4)
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() {
                guard let rgb = palette[character] else { continue } // `.` stays transparent
                for sy in 0..<scale {
                    for sx in 0..<scale {
                        let i = ((y * scale + sy) * width + (x * scale + sx)) * 4
                        buffer[i] = UInt8((rgb >> 16) & 0xFF)
                        buffer[i + 1] = UInt8((rgb >> 8) & 0xFF)
                        buffer[i + 2] = UInt8(rgb & 0xFF)
                        buffer[i + 3] = 0xFF
                    }
                }
            }
        }

        let data = Data(buffer) as CFData
        guard
            let provider = CGDataProvider(data: data),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width,
                height: width,
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
            throw GridError.imageFailed(name: name, width: width, height: width)
        }
        return image
    }

    /// Checks one grid: `side` rows, every row `side` cells wide, only palette characters.
    static func validate(_ rows: [String], name: String, side: Int) throws {
        guard rows.count == side else {
            throw GridError.wrongRowCount(name: name, expected: side, found: rows.count)
        }
        for (index, row) in rows.enumerated() {
            guard row.count == side else {
                throw GridError.wrongRowWidth(name: name, row: index, expected: side, found: row.count)
            }
            for character in row where character != "." && palette[character] == nil {
                throw GridError.unknownCharacter(name: name, row: index, character: character)
            }
        }
    }

    // MARK: - Painting

    /// The clay: a two-tone checkerboard, which is how a pixel artist suggests a flat fired
    /// surface without a gradient.
    private static func paintField(_ canvas: inout Canvas) {
        for y in 0..<size {
            for x in 0..<size {
                canvas.set(x, y, (x + y) % 2 == 0 ? "T" : "t")
            }
        }
    }

    /// The hill: a lit cream edge, two cells of marble, and then the darker clay of the ground —
    /// all following `slopeY`, so the surface is one continuous line across the emblem.
    private static func paintSlope(_ canvas: inout Canvas) {
        for x in 0..<size {
            let surface = Int(slopeY(Double(x - artInset)).rounded(.down)) + artInset
            for y in surface..<size {
                switch y - surface {
                case 0: canvas.set(x, y, "c")
                case 1: canvas.set(x, y, (x + surface) % 2 == 0 ? "c" : "C")
                case 2: canvas.set(x, y, "C")
                default: canvas.set(x, y, (x + y) % 2 == 0 ? "t" : "d")
                }
            }
        }
    }

    /// The sun: gold, stamped from its own grid.
    private static func paintSun(_ canvas: inout Canvas) {
        canvas.stamp(sun, atX: sunOrigin.x + artInset, y: sunOrigin.y + artInset)
    }

    /// The boulder: a black outline and an inside shaded in four dithered bands lit from the upper
    /// left, plus two cracks.
    ///
    /// The shade of a pixel follows `dx + dy`, its projection onto the light direction, so the
    /// sphere is computed rather than drawn. The checkerboard nudge pushes each pixel across the
    /// boundary between two greys, which dithers four flat bands into a rounder gradient.
    private static func paintBoulder(_ canvas: inout Canvas) {
        // The geometry is in field coordinates; the canvas is the whole icon, so it is shifted by
        // the meander band exactly once, like the sun and the figure.
        let center = (x: boulderCenter.x + Double(artInset), y: boulderCenter.y + Double(artInset))
        let radius = boulderRadius
        let inner = radius - 1
        let reach = Int(radius.rounded(.up)) + 1

        for y in (Int(center.y) - reach)...(Int(center.y) + reach) {
            for x in (Int(center.x) - reach)...(Int(center.x) + reach) {
                let dx = Double(x) - center.x
                let dy = Double(y) - center.y
                let distance = dx * dx + dy * dy
                if distance > radius * radius {
                    continue
                }
                if distance > inner * inner {
                    canvas.set(x, y, "o") // outline
                    continue
                }
                // 0 at the lit corner (upper left), 1 at the dark one (lower right); the checker
                // nudges each pixel across the band boundary, which dithers the four greys into a
                // rounder gradient than four flat bands could be.
                var shade = 0.5 + (dx + dy) / (radius * 2)
                shade += (x + y) % 2 == 0 ? 0.07 : -0.07
                canvas.set(x, y, grey(shade))
            }
        }

        // Two cracks in the deep grey: long enough to break up the stone, short enough not to read
        // as a second shape.
        for (dx, dy) in [(0, -2), (0, -1), (1, 0), (0, 1), (-1, 1)] {
            canvas.set(Int(center.x) + dx, Int(center.y) + dy, "e")
        }
        for (dx, dy) in [(3, -3), (4, -2), (4, -1)] {
            canvas.set(Int(center.x) + dx, Int(center.y) + dy, "e")
        }

        // The shadow it casts on the hill. A disc resting on a slope touches the surface at a
        // single point, so without this the downhill half of the outline hangs in the clay and the
        // boulder reads as floating; dimming the surface it overhangs is what settles it down.
        //
        // Only cells the boulder does not cover are touched: uphill of the contact point the
        // surface line runs *through* the disc, and painting there would stripe the stone.
        for x in (Int(center.x - radius) - 1)...(Int(center.x + radius) + 1) {
            let surface = Int(slopeY(Double(x - artInset)).rounded(.down)) + artInset
            let dx = Double(x) - center.x
            let dy = Double(surface) - center.y
            guard dx * dx + dy * dy > radius * radius else { continue }
            let span = abs(dx) / radius
            canvas.set(x, surface, span < 0.5 ? "e" : "g")
        }
    }

    /// The grey for a `shade` in 0…1, where 0 is the lit corner and 1 the dark one.
    private static func grey(_ shade: Double) -> Character {
        switch shade {
        case ..<0.22: return "L"
        case ..<0.48: return "l"
        case ..<0.74: return "G"
        default: return "g"
        }
    }

    /// Stamps the hand-authored silhouette onto the clay.
    private static func paintFigure(_ canvas: inout Canvas) {
        canvas.stamp(figure, atX: figureOrigin.x + artInset, y: figureOrigin.y + artInset)
    }

    /// The Greek-key band: a gold line on the outside, a cream line on the inside, four rows of
    /// meander between them.
    ///
    /// The horizontal bands run the full width and own the four corner blocks; the vertical bands
    /// cover only the straight part between them, so the corners show the pattern turning rather
    /// than four unrelated squares.
    private static func paintBand(_ canvas: inout Canvas) {
        for x in panelMin...panelMax {
            for depth in 0..<bandDepth {
                let line = meanderLine(depth: depth, offset: x)
                canvas.set(x, panelMin + depth, bandCell(depth: depth, line: line))
                canvas.set(x, panelMax - depth, bandCell(depth: depth, line: line))
            }
        }
        for y in bandMin...bandMax {
            for depth in 0..<bandDepth {
                let line = meanderLine(depth: depth, offset: y)
                canvas.set(panelMin + depth, y, bandCell(depth: depth, line: line))
                canvas.set(panelMax - depth, y, bandCell(depth: depth, line: line))
            }
        }
    }

    /// Whether the meander's line passes through a band cell at `depth`, `offset` cells along the
    /// band. Only the four cells between the two frame lines carry the pattern.
    private static func meanderLine(depth: Int, offset: Int) -> Bool {
        guard (1...4).contains(depth) else { return false }
        return Meander.hasLine(row: depth - 1, offset: offset)
    }

    /// One cell of the band, `depth` cells in from the panel's edge.
    private static func bandCell(depth: Int, line: Bool) -> Character {
        switch depth {
        case 0: return "y" // gold frame line
        case 1...4: return line ? "c" : "o" // meander, cream on black
        default: return "c" // cream frame line
        }
    }
}

// MARK: - Canvas

/// A square grid of palette characters, filled with `.` (transparent) and painted in place.
private struct Canvas {
    let size: Int
    private var cells: [[Character]]

    init(size: Int) {
        self.size = size
        self.cells = Array(repeating: Array(repeating: ".", count: size), count: size)
    }

    /// Writes one cell. Out-of-bounds writes are ignored, so a stamp may hang off the edge.
    mutating func set(_ x: Int, _ y: Int, _ character: Character) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        cells[y][x] = character
    }

    /// Draws a literal grid, skipping its transparent cells so it can be laid over the field.
    mutating func stamp(_ rows: [String], atX x: Int, y: Int) {
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character != "." {
                set(x + column, y + row, character)
            }
        }
    }

    /// Makes everything outside the rounded square transparent.
    ///
    /// The distance to the corner circle is measured per cell, which is what produces the pixel
    /// staircase: a cell is kept when `dx² + dy² ≤ radius²`, where `dx` and `dy` are how far the
    /// cell is pushed in from the edge of the straight part of each axis. Away from a corner one of
    /// them is zero, so the straight edges pass through untouched.
    mutating func carveRoundedSquare(inset: Int, radius: Int) {
        let far = Double(size - 1 - inset)
        let corner = Double(inset + radius)
        let limit = Double(radius * radius)
        for y in 0..<size {
            for x in 0..<size {
                let dx = max(corner - Double(x), Double(x) - (far - Double(radius)), 0)
                let dy = max(corner - Double(y), Double(y) - (far - Double(radius)), 0)
                if dx * dx + dy * dy > limit {
                    cells[y][x] = "."
                }
            }
        }
    }

    /// The grid as strings, one per row.
    var rows: [String] { cells.map { String($0) } }
}
