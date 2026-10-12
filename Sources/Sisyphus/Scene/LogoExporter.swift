import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Command line

/// The `--export-logo <directory>` request, parsed out of `CommandLine.arguments` before anything
/// else in the app is created.
///
/// Like `--export-gif`, this is a hidden CLI mode of the app binary rather than a second target:
/// the art lives in the executable target, so the logo, the README header image and the app icon
/// are all rendered by exactly the code that is committed, with nothing to keep in sync.
enum LogoExportRequest: Equatable {
    static let flag = "--export-logo"
    static let usage = "usage: Sisyphus \(flag) <output directory>"

    /// The flag is not present.
    case none
    /// The flag is present but is not followed by a usable directory.
    case missingPath
    /// Render the logo and the icon set into `directory`.
    case export(directory: String)

    init(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.flag) else {
            self = .none
            return
        }
        let pathIndex = arguments.index(after: index)
        guard pathIndex < arguments.endIndex else {
            self = .missingPath
            return
        }
        let path = arguments[pathIndex]
        // A following option means the directory was forgotten; a path starting with "-" would be
        // indistinguishable from one, and is rejected rather than guessed.
        guard !path.isEmpty, !path.hasPrefix("-") else {
            self = .missingPath
            return
        }
        self = .export(directory: path)
    }
}

// MARK: - Exporter

/// Writes the logo: `logo.png` for the README and `AppIcon.iconset/` for `iconutil`.
///
/// Nothing here is hand-checked into the repository at a fixed size: both outputs are rendered from
/// `LogoArt` every time, so the icon can never drift away from the art.
///
/// Exit codes are the caller's (`main.swift`): `true` → 0, `false` → 1.
enum LogoExporter {

    // MARK: Output

    /// The README logo, in pixels: the master grid at ×8. It is the same emblem as the 1024 px rep,
    /// at half of it — that is exactly the ×8 render, so the README keeps crisp pixels instead of a
    /// resampled one.
    static let logoScale = 8

    /// File names `iconutil` expects, each with the grid it comes from and its exact whole-number
    /// scale. 16 and 32 come from the hand-authored 16×16 grid, everything above from the master:
    /// no rep is decimated, and none is interpolated.
    static let reps: [(name: String, side: Int, scale: Int, fromSmallGrid: Bool)] = [
        ("icon_16x16.png", 16, 1, true),
        ("icon_16x16@2x.png", 16, 2, true),
        ("icon_32x32.png", 16, 2, true),
        ("icon_32x32@2x.png", 64, 1, false),
        ("icon_128x128.png", 64, 2, false),
        ("icon_128x128@2x.png", 64, 4, false),
        ("icon_256x256.png", 64, 4, false),
        ("icon_256x256@2x.png", 64, 8, false),
        ("icon_512x512.png", 64, 8, false),
        ("icon_512x512@2x.png", 64, 16, false),
    ]

    /// The icon set directory and the README image, both created inside the requested directory.
    static let iconsetName = "AppIcon.iconset"
    static let logoName = "logo.png"

    // MARK: Failures

    /// Why an image could not be written.
    enum ExportError: Error, CustomStringConvertible {
        case couldNotCreate(String)
        case couldNotWrite(String)

        var description: String {
            switch self {
            case let .couldNotCreate(path): return "could not create \(path)"
            case let .couldNotWrite(path): return "writing \(path) failed"
            }
        }
    }

    // MARK: Entry point

    /// Renders the logo and the ten icon reps into `directory`, creating it if needed.
    ///
    /// Any existing `AppIcon.iconset` is replaced rather than merged: a rep left over from an older
    /// set would silently end up inside the `.icns`.
    ///
    /// - Returns: `true` on success; `false` after printing the reason to standard error.
    static func export(to directory: String) -> Bool {
        let master: [String]
        let small: [String]
        do {
            // The grids are validated before anything is written, so a broken grid cannot leave a
            // half-written icon set behind.
            master = LogoArt.master()
            small = LogoArt.smallShaped()
            try LogoArt.validate(master, name: "logo", side: LogoArt.size)
            try LogoArt.validate(small, name: "logo-small", side: LogoArt.smallSize)
        } catch {
            fail("\(error)")
            return false
        }

        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let iconset = root.appendingPathComponent(iconsetName, isDirectory: true)

        do {
            let manager = FileManager.default
            if manager.fileExists(atPath: iconset.path) {
                try manager.removeItem(at: iconset)
            }
            try manager.createDirectory(at: iconset, withIntermediateDirectories: true)

            for rep in reps {
                let grid = rep.fromSmallGrid ? small : master
                let image = try LogoArt.makeImage(
                    grid,
                    name: rep.name,
                    side: rep.side,
                    scale: rep.scale
                )
                try write(image, to: iconset.appendingPathComponent(rep.name))
            }

            let logo = try LogoArt.makeImage(
                master,
                name: logoName,
                side: LogoArt.size,
                scale: logoScale
            )
            try write(logo, to: root.appendingPathComponent(logoName))
        } catch {
            fail("\(error)")
            return false
        }

        print("Exported \(logoName) (\(LogoArt.size * logoScale)px) and \(reps.count) icons to \(root.path)")
        return true
    }

    // MARK: Writing

    /// Writes one image as a PNG through ImageIO.
    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.couldNotCreate(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.couldNotWrite(url.path)
        }
    }

    // MARK: Reporting

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}
