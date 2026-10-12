import CoreGraphics
import Foundation

/// Hand-authored SNES-style pixel sprites.
///
/// Every sprite is a `[String]` grid: one string per row, one character per pixel, `.` is
/// transparent and every other character is looked up in `palette`. Grids are validated
/// (equal row widths, expected size, known characters) when they are first converted into
/// `CGImage`s; a malformed grid stops the app at load with a clear message instead of rendering
/// garbage.
///
/// All sprites face right. The renderer mirrors them with a context transform when the man
/// faces left.
enum SpriteFrames {

    // MARK: - Palette

    /// Palette character → `0xRRGGBB`.
    static let palette: [Character: UInt32] = [
        // Man
        "o": 0x24161C, // outline
        "s": 0xE0A070, // skin
        "S": 0xA8643C, // skin shadow
        "h": 0xF8D0A0, // skin highlight
        "e": 0x180C10, // eye
        "k": 0x3C2214, // hair
        "K": 0x684028, // hair highlight
        "w": 0xF8F0DC, // chiton
        "W": 0xC0B494, // chiton shadow
        "y": 0xD8A830, // golden belt
        "b": 0x7C4420, // sandals
        // Rock
        "L": 0xDEDCE6, // highlight
        "l": 0xA8A4B4, // light stone
        "G": 0x7A7688, // mid stone
        "g": 0x4E4A5E, // shadow stone
        "r": 0x262230, // deep shadow
        "c": 0x34303E, // crack
        // Glyphs
        "z": 0xF4F0FF, // sleep "z"
    ]

    // MARK: - Sizes

    static let manSize = 16
    static let rockSize = 12
    static let zWidth = 3
    static let zHeight = 5

    // MARK: - Man: push ×4 (leaning ~30° into the slope, arms out to the rock, striding)

    static let push: [[String]] = [
        [
            ".........ooooo..",
            "........okkKkko.",
            ".......okKkkkkKo",
            ".......okkkkkhho",
            ".......okkkkhseo",
            ".......ookkhhsso",
            "......owoooSsoo.",
            ".....owwwwossooo",
            "....owwwwwSsssss",
            "...owwwwwwWoooSo",
            "...owwwwwWWo.oo.",
            "...oyyyyyyoSSo..",
            "..owwWWWo.oSso..",
            ".oswWWo...obbbo.",
            "osSoo...........",
            "obbo............",
        ],
        [
            ".........ooooo..",
            "........okkKkko.",
            ".......okKkkkkKo",
            ".......okkkkkhho",
            ".......okkkkhseo",
            ".......ookkhhsso",
            "......owoooSsoo.",
            ".....owwwwossooo",
            "....owwwwwSsssss",
            "...owwwwwwWoooSo",
            "...owwwwwWWo.oo.",
            "...oyyyyyySso...",
            "..owwWWWooSso...",
            "..osSWo..obbbo..",
            ".oSso...........",
            ".obbo...........",
        ],
        [
            ".........ooooo..",
            "........okkKkko.",
            ".......okKkkkkKo",
            ".......okkkkkhho",
            ".......okkkkhseo",
            ".......ookkhhsso",
            "......owoooSsoo.",
            ".....owwwwossooo",
            "....owwwwwSsssss",
            "...owwwwwwWoooSo",
            "...owwwwwWWo.oo.",
            "...oyyyyyyo.....",
            "...owWWWWSso....",
            "...osSoooSso....",
            "..oSso..obbbo...",
            "..obbo..........",
        ],
        [
            "................",
            ".........ooooo..",
            "........okkKkko.",
            ".......okKkkkkKo",
            ".......okkkkkhho",
            ".......okkkkhseo",
            ".......ookkhhsso",
            "......owoooSsoo.",
            ".....owwwwossooo",
            "....owwwwwSsssss",
            "...owwwwwwWoooSo",
            "...owwwwwWWo.oo.",
            "...oyyyyyyoo....",
            "...owWWWWosSo...",
            ".oSso....obbbo..",
            ".obbo...........",
        ],
    ]

    // MARK: - Man: walk ×4 (upright, arms and legs swinging)

    static let walk: [[String]] = [
        [
            ".....ooooo......",
            "....okKkkko.....",
            "...okKkkkkKo....",
            "...okkkkkhho....",
            "...okkkkhseo....",
            "...ookkhhsso....",
            "....oowwSsoo....",
            "...owwwwwwwso...",
            "..oswwwwwwWWso..",
            ".osoowwwwWWooso.",
            ".oo.oyyyyyyoso..",
            "....owwwWWWooo..",
            "...oswWWWWWoso..",
            "..oSo.....oosso.",
            ".obbo......oso..",
            "............obbo",
        ],
        [
            "................",
            ".....ooooo......",
            "....okKkkko.....",
            "...okKkkkkKo....",
            "...okkkkkhho....",
            "...okkkkhseo....",
            "...ookkhhsso....",
            "....oowwSsoo....",
            "...owwwwwwwso...",
            "..oswwwwwwWWso..",
            "..osowwwwWWoso..",
            "..ooSyyyyyyooo..",
            "....owwwWWWo....",
            ".....oSsosso....",
            ".....obbooso....",
            ".........obbo...",
        ],
        [
            ".....ooooo......",
            "....okKkkko.....",
            "...okKkkkkKo....",
            "...okkkkkhho....",
            "...okkkkhseo....",
            "...ookkhhsso....",
            "....oowwSsoo....",
            "...owwwwwwwso...",
            "...owwwwwwWWso..",
            "..osowwwwWWoosso",
            "..osoyyyyyyo.oo.",
            "..oSowwwWWWo....",
            "...oswWWWWWso...",
            "..oso.....oSSo..",
            ".obbo......oSo..",
            "............obbo",
        ],
        [
            "................",
            ".....ooooo......",
            "....okKkkko.....",
            "...okKkkkkKo....",
            "...okkkkkhho....",
            "...okkkkhseo....",
            "...ookkhhsso....",
            "....oowwSsoo....",
            "...owwwwwwwso...",
            "..oswwwwwwWWso..",
            "..osowwwwWWoso..",
            "..oooyyyyyySoo..",
            "....owwwWWWo....",
            ".....ossoSSo....",
            ".....obbooSo....",
            ".........obbo...",
        ],
    ]

    // MARK: - Man: stand ×1

    static let stand: [String] = [
        ".....ooooo......",
        "....okKkkko.....",
        "...okKkkkkKo....",
        "...okkkkkhho....",
        "...okkkkhseo....",
        "...ookkhhsso....",
        "....oowwSsoo....",
        "...owwwwwwwso...",
        "..oswwwwwwWWso..",
        "..osowwwwWWoso..",
        "..osoyyyyyyoso..",
        "..oSowwwWWWoSo..",
        "...oowwwWWWoo...",
        "....osso.oso....",
        "....osso.oso....",
        "....obbbo.obbbo.",
    ]

    // MARK: - Man: sit ×2 (on the ground, leaning back against the rock; breathing)

    static let sit: [[String]] = [
        [
            "................",
            "................",
            "................",
            "........ooooo...",
            ".......okKkkko..",
            "......okkkKkkko.",
            "......ohhkkkkko.",
            "......oeshkkkko.",
            "......ossshkkoo.",
            ".......osSoowwo.",
            "......owwwwwwwo.",
            ".....oswwwwwwWo.",
            "...oossoowwwWWo.",
            ".oossSsoyyyyyyo.",
            "osssSoowwwWWWWo.",
            "obboooooooooooo.",
        ],
        [
            "................",
            "................",
            "................",
            "................",
            "........ooooo...",
            ".......okKkkko..",
            "......okkkKkkko.",
            "......ohhkkkkko.",
            "......oeshkkkko.",
            "......ossshkkoo.",
            "......owsSoowwo.",
            ".....oswwwwwwWo.",
            "...oossoowwwWWo.",
            ".oossSsoyyyyyyo.",
            "osssSoowwwWWWWo.",
            "obboooooooooooo.",
        ],
    ]

    // MARK: - Rock: roll ×4 (each frame turns the cracks a quarter turn clockwise)

    static let rock: [[String]] = [
        [
            "....oooo....",
            "..ooLLlloo..",
            ".oLLLGllGGo.",
            ".oLLLlllGGo.",
            "oLLLcllGcGgo",
            "olllclGGlggo",
            "olllLcGGgggo",
            "ollGGccgggro",
            ".oGGGlgggro.",
            ".oGgggggrro.",
            "..oogggroo..",
            "....oooo....",
        ],
        [
            "....oooo....",
            "..ooLLlloo..",
            ".oLLLlllGGo.",
            ".oLLLlllGGo.",
            "oLLLllccGGgo",
            "olllccllGrgo",
            "olllclGGgggo",
            "ollGlGGgggro",
            ".oGGGGgrgro.",
            ".oGgggggrro.",
            "..oogggroo..",
            "....oooo....",
        ],
        [
            "....oooo....",
            "..ooLLlloo..",
            ".oLLLlllGGo.",
            ".oLLLlllGGo.",
            "oLLLlccGGGgo",
            "ollllLcGGggo",
            "ollllGlcgggo",
            "ollcGGGrggro",
            ".oGlGGgggro.",
            ".oGgggrgrro.",
            "..oogggroo..",
            "....oooo....",
        ],
        [
            "....oooo....",
            "..ooLLlloo..",
            ".oLLLlllGGo.",
            ".oLLclllGGo.",
            "oLLLLllGGGgo",
            "olllllGcGggo",
            "olGllGccgggo",
            "ollGcclgggro",
            ".oGGllgggro.",
            ".oGgggggrro.",
            "..oogggroo..",
            "....oooo....",
        ],
    ]

    // MARK: - Glyph: sleep "z" (3×5)

    static let z: [String] = [
        "zzz",
        "..z",
        ".z.",
        "z..",
        "zzz",
    ]

    // MARK: - Validation and conversion

    /// Checks one grid: exact `width`×`height`, every row the same width, only palette characters.
    /// Called for every grid before conversion, so a typo fails loudly at load time.
    static func validate(_ grid: [String], name: String, width: Int, height: Int) {
        precondition(grid.count == height, "Sprite \(name): expected \(height) rows, found \(grid.count)")
        for (index, row) in grid.enumerated() {
            precondition(
                row.count == width,
                "Sprite \(name): row \(index) is \(row.count) px wide, expected \(width)"
            )
            for ch in row where ch != "." {
                precondition(palette[ch] != nil, "Sprite \(name): unknown palette character '\(ch)' in row \(index)")
            }
        }
    }

    /// Converts a validated grid into a `CGImage` (transparent where the grid has `.`).
    static func makeImage(_ grid: [String], name: String, width: Int, height: Int) -> CGImage {
        validate(grid, name: name, width: width, height: height)
        var buffer = PixelBuffer(width: width, height: height)
        for (y, row) in grid.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                if let rgb = palette[ch] {
                    buffer.set(x, y, rgb)
                }
            }
        }
        return buffer.makeImage()
    }
}

/// The sprites converted once into `CGImage`s. Built lazily on first access and immutable after.
final class SpriteImages: @unchecked Sendable {
    static let shared = SpriteImages()

    let push: [CGImage]
    let walk: [CGImage]
    let stand: CGImage
    let sit: [CGImage]
    let rock: [CGImage]
    let z: CGImage

    private init() {
        let man = SpriteFrames.manSize
        let rockSize = SpriteFrames.rockSize
        precondition(SpriteFrames.push.count == 4, "Expected 4 push frames")
        precondition(SpriteFrames.walk.count == 4, "Expected 4 walk frames")
        precondition(SpriteFrames.sit.count == 2, "Expected 2 sit frames")
        precondition(SpriteFrames.rock.count == 4, "Expected 4 rock frames")

        push = SpriteFrames.push.enumerated().map {
            SpriteFrames.makeImage($0.element, name: "push\($0.offset)", width: man, height: man)
        }
        walk = SpriteFrames.walk.enumerated().map {
            SpriteFrames.makeImage($0.element, name: "walk\($0.offset)", width: man, height: man)
        }
        stand = SpriteFrames.makeImage(SpriteFrames.stand, name: "stand", width: man, height: man)
        sit = SpriteFrames.sit.enumerated().map {
            SpriteFrames.makeImage($0.element, name: "sit\($0.offset)", width: man, height: man)
        }
        rock = SpriteFrames.rock.enumerated().map {
            SpriteFrames.makeImage($0.element, name: "rock\($0.offset)", width: rockSize, height: rockSize)
        }
        z = SpriteFrames.makeImage(
            SpriteFrames.z, name: "z", width: SpriteFrames.zWidth, height: SpriteFrames.zHeight
        )
    }
}
