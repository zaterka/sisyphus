import AppKit
import Observation
import SwiftUI

/// Borderless, always-on-top panel that can still become key so its text fields accept typing.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // rounded corners and shadow are drawn by SwiftUI
        isMovableByWindowBackground = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Clicking the panel activates the app (it takes focus from the frontmost app), so that the
    /// first click into a text field can start typing right away.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !NSApp.isActive {
                NSApp.activate()
            }
            if !isKeyWindow {
                makeKeyAndOrderFront(nil)
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// Hosting view that accepts the click that activates the window, so buttons work on first click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shared UI state between the menu, the panel controller and the SwiftUI views.
@MainActor
@Observable
final class PanelUIState {
    /// Bumped every time the add field should take focus (⌘N).
    var focusAddRequest: Int = 0
    /// Set when focus is requested while the list is hidden; consumed when the list appears.
    var pendingAddFocus: Bool = false

    /// Called by the toolbar drag handle when the user starts moving the panel.
    @ObservationIgnored var onUserMoved: () -> Void = {}

    func requestAddFocus() {
        pendingAddFocus = true
        focusAddRequest &+= 1
    }
}

/// Owns the panel and keeps its size and position in sync with the store.
@MainActor
final class PanelController {
    // MARK: Layout (single source of truth)

    enum Layout {
        /// Outer transparent padding around the rounded card; room for the SwiftUI shadow.
        static let padding: CGFloat = 8
        static let sceneWidth: CGFloat = 320
        static let sceneHeight: CGFloat = 180
        static let toolbarHeight: CGFloat = 28
        static let maxListHeight: CGFloat = 380
        /// Distance from the edges of the screen's visible frame.
        static let screenMargin: CGFloat = 12
        /// Vertical space kept free when the list is shown.
        static let verticalReserve: CGFloat = 24

        static let width: CGFloat = sceneWidth + padding * 2 // 336
        static let collapsedHeight: CGFloat = toolbarHeight + sceneHeight + padding * 2

        static func listHeight(visibleFrame: NSRect) -> CGFloat {
            max(0, min(maxListHeight, visibleFrame.height - verticalReserve - collapsedHeight))
        }

        static func size(listVisible: Bool, visibleFrame: NSRect) -> NSSize {
            let height = collapsedHeight + (listVisible ? listHeight(visibleFrame: visibleFrame) : 0)
            return NSSize(width: width, height: height)
        }
    }

    let panel: FloatingPanel
    let store: TaskStore
    let sceneModel: SceneModel
    let uiState: PanelUIState

    /// Set once the user drags the panel; disables automatic re-pinning.
    private(set) var userMoved = false
    /// Registration token for the screen-parameters notification. `NSObjectProtocol` is not
    /// `Sendable`, so it is marked `nonisolated(unsafe)` — it is written on the main actor in
    /// `init`, read nowhere else, and only removed in the nonisolated `deinit`, where no other
    /// reference to the controller can exist.
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?

    init(store: TaskStore) {
        self.store = store
        self.sceneModel = SceneModel(store: store)
        self.uiState = PanelUIState()

        let visible = PanelController.primaryVisibleFrame
        let size = Layout.size(listVisible: store.listVisible, visibleFrame: visible)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))

        let root = RootView(store: store, sceneModel: sceneModel, ui: uiState)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = [] // the controller owns the window size
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        uiState.onUserMoved = { [weak self] in self?.userMoved = true }

        pin()
        observeListVisibility()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenParametersChanged()
            }
        }
    }

    /// Drops the screen-parameters registration with the controller. `self` is captured weakly by
    /// the observer block, but the registration itself lives in `NotificationCenter` until it is
    /// removed, and `deinit` is the only place that can do it without a main-actor hop.
    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: Showing

    func show() {
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        sceneModel.start()
    }

    func stop() {
        sceneModel.stop()
    }

    func toggleList() {
        store.listVisible.toggle()
    }

    /// Shows the list (if hidden) and focuses the add field.
    func newTask() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        uiState.requestAddFocus()
        if !store.listVisible {
            store.listVisible = true
        }
    }

    // MARK: Geometry

    private static var primaryVisibleFrame: NSRect {
        NSScreen.screens.first?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Visible frame used for the list-height cap: the panel's current screen, else the primary.
    private var currentVisibleFrame: NSRect {
        if userMoved, let screen = panel.screen { return screen.visibleFrame }
        return PanelController.primaryVisibleFrame
    }

    /// Puts the panel at the top-right of the primary screen's visible frame.
    private func pin() {
        let visible = PanelController.primaryVisibleFrame
        let size = Layout.size(listVisible: store.listVisible, visibleFrame: visible)
        let origin = NSPoint(
            x: visible.maxX - Layout.screenMargin - size.width,
            y: visible.maxY - Layout.screenMargin - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    /// Resizes for the current toggle state, keeping the top-right corner fixed, and pulls the
    /// result back inside the screen's visible frame so a panel that was moved (or a display that
    /// went away) can never end up stranded off-screen.
    private func resizeKeepingTopRight() {
        let visible = currentVisibleFrame
        let size = Layout.size(listVisible: store.listVisible, visibleFrame: visible)
        let frame = panel.frame
        let resized = frame.size == size
            ? frame
            : NSRect(
                x: frame.maxX - size.width,
                y: frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        let target = PanelController.clamped(resized, into: visible)
        guard target != frame else { return }
        panel.setFrame(target, display: true, animate: false)
    }

    /// Same size, moved as little as possible so it fits inside `bounds`.
    ///
    /// A frame larger than the bounds ends up flush with their top-right corner, which is where the
    /// panel's toolbar and scene live.
    private static func clamped(_ frame: NSRect, into bounds: NSRect) -> NSRect {
        NSRect(
            x: min(max(frame.origin.x, bounds.minX), bounds.maxX - frame.width),
            y: min(max(frame.origin.y, bounds.minY), bounds.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    private func screenParametersChanged() {
        if userMoved {
            resizeKeepingTopRight()
        } else {
            pin()
        }
    }

    /// Re-arms an observation of `store.listVisible` and resizes after each change.
    private func observeListVisibility() {
        withObservationTracking {
            _ = store.listVisible
        } onChange: { [weak self] in
            // onChange fires before the new value is stored; act on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resizeKeepingTopRight()
                self.observeListVisibility()
            }
        }
    }
}
