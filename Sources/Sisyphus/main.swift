import AppKit
import Foundation

// Hidden CLI mode: `Sisyphus --export-gif <path>` renders the scene to an animated GIF and exits.
//
// It is handled before anything else exists — no `NSApplication`, no `AppDelegate`, no `TaskStore` —
// so the export never touches the user's tasks, never shows a panel and never claims a Dock icon.
switch GIFExportRequest(arguments: CommandLine.arguments) {
case .none:
    break
case .missingPath:
    FileHandle.standardError.write(Data("error: \(GIFExportRequest.usage)\n".utf8))
    exit(1)
case let .export(path):
    // Off-screen rendering needs the main actor but not a running app; top-level code is on the
    // main thread, so this is a promise the compiler cannot check for itself.
    MainActor.assumeIsolated {
        exit(GIFExporter.export(to: path) ? 0 : 1)
    }
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
