import AppKit
import Foundation

// Hidden CLI modes. `Sisyphus --export-gif <path>` renders the scene to an animated GIF and
// `Sisyphus --export-logo <directory>` renders the logo and the icon set; exactly one mode per run,
// because both of them exit.
//
// They are handled before anything else exists — no `NSApplication`, no `AppDelegate`, no
// `TaskStore` — so an export never touches the user's tasks, never shows a panel and never claims
// a Dock icon.
let gifRequest = GIFExportRequest(arguments: CommandLine.arguments)
let logoRequest = LogoExportRequest(arguments: CommandLine.arguments)

switch (gifRequest, logoRequest) {
case (.none, .none):
    break // no export mode: start the app normally, below

case let (.export(path), .none):
    // Off-screen rendering needs the main actor but not a running app; top-level code is on the
    // main thread, so this is a promise the compiler cannot check for itself.
    MainActor.assumeIsolated {
        exit(GIFExporter.export(to: path) ? 0 : 1)
    }

case let (.none, .export(directory)):
    exit(LogoExporter.export(to: directory) ? 0 : 1)

default:
    // Both modes at once, or one of them without a path. Each named mode gets its own usage line,
    // so the message says which flag was wrong.
    var message = "error: expected exactly one export mode, with a path\n"
    if gifRequest != .none { message += GIFExportRequest.usage + "\n" }
    if logoRequest != .none { message += LogoExportRequest.usage + "\n" }
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

// Plain AppKit entry point: a regular (Dock icon) app whose only window is the floating panel.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
