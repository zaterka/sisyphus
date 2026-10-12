import AppKit
import SwiftUI

/// The 28 pt strip at the top of the panel: drag grip + title, counter, list toggle and quit.
struct Toolbar: View {
    let store: TaskStore
    var onUserMoved: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Drag area: the AppKit view underneath receives the mouse; the label is decoration.
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                Text("SISYPHUS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 4)
                Text(counterText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .background(DragHandle(onDragStart: onUserMoved))

            Button {
                store.listVisible.toggle()
            } label: {
                Image(systemName: store.listVisible ? "chevron.up" : "list.bullet")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .help(store.listVisible ? "Hide task list (⌘T)" : "Show task list (⌘T)")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .help("Quit Sisyphus (⌘Q)")
            .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.secondaryText)
        .frame(height: PanelController.Layout.toolbarHeight)
        .background(Theme.toolbar)
    }

    private var counterText: String {
        "\(store.list.open.count) open · \(store.list.completed.count) done"
    }
}

/// An AppKit view that drags the window on mouse down.
struct DragHandle: NSViewRepresentable {
    var onDragStart: () -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.onDragStart = onDragStart
        return view
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.onDragStart = onDragStart
    }
}

final class DragHandleView: NSView {
    var onDragStart: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        onDragStart()
        window?.performDrag(with: event)
    }
}
