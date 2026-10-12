import SwiftUI
import SisyphusCore

/// Colours and metrics shared by the panel views.
enum Theme {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let toolbar = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let field = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.09)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.55)
    static let accent = Color(red: 0.98, green: 0.78, blue: 0.35)
    static let cornerRadius: CGFloat = 12

    static func color(for priority: Priority) -> Color? {
        switch priority {
        case .none: return nil
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

/// The whole panel content: toolbar, scene, and (when visible) the task list, on a rounded dark
/// card with a SwiftUI shadow inside the transparent window padding.
struct RootView: View {
    let store: TaskStore
    let sceneModel: SceneModel
    let ui: PanelUIState

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(store: store, onUserMoved: { ui.onUserMoved() })
            SceneView(model: sceneModel)
                .frame(width: PanelController.Layout.sceneWidth, height: PanelController.Layout.sceneHeight)
                .clipped()
            if store.listVisible {
                TaskListView(store: store, ui: ui)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: PanelController.Layout.sceneWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
        .padding(PanelController.Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
    }
}
