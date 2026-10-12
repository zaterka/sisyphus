import AppKit
import SisyphusCore

/// Builds the menu and the panel, flushes the store on quit and brings the panel back on reopen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TaskStore?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = TaskStore()
        self.store = store
        NSApp.mainMenu = buildMainMenu()

        let controller = PanelController(store: store)
        panelController = controller
        controller.show()
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
        store?.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu actions

    @objc func newTask(_ sender: Any?) {
        panelController?.newTask()
    }

    @objc func toggleTaskList(_ sender: Any?) {
        panelController?.toggleList()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Sisyphus",
            // The joke keeps its own paragraph; the second one is the GPL's "Appropriate Legal
            // Notices" for a GUI program, which has to be reachable from the About box. The
            // copyright line itself comes from NSHumanReadableCopyright in Info.plist.
            .credits: NSAttributedString(
                string: """
                    One must imagine Sisyphus happy.

                    This program is free software: you can \
                    redistribute it and/or modify it under the terms of the GNU General Public \
                    License v3 or later. It comes with ABSOLUTELY NO WARRANTY. Source: \
                    https://github.com/zaterka/sisyphus
                    """,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Sisyphus")
        appMenu.addItem(withTitle: "About Sisyphus", action: #selector(showAbout(_:)), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sisyphus", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Sisyphus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Edit menu (target nil → first responder)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Tasks menu
        let tasksItem = NSMenuItem()
        let tasksMenu = NSMenu(title: "Tasks")
        tasksMenu.addItem(withTitle: "New Task", action: #selector(newTask(_:)), keyEquivalent: "n").target = self
        tasksMenu.addItem(withTitle: "Toggle Task List", action: #selector(toggleTaskList(_:)), keyEquivalent: "t").target = self
        tasksItem.submenu = tasksMenu
        main.addItem(tasksItem)

        return main
    }
}
