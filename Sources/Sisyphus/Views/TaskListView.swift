import SwiftUI
import SisyphusCore

/// Add field, the reorderable open tasks and the collapsible "Completed" section.
struct TaskListView: View {
    let store: TaskStore
    let ui: PanelUIState

    @State private var newText = ""
    @State private var showCompleted = true
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            addField
            Rectangle().fill(Theme.border).frame(height: 1)
            List {
                if store.list.open.isEmpty {
                    Text(store.list.completed.isEmpty ? "No tasks. Add one above." : "Nothing left to push.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.list.open) { item in
                    TaskRowView(item: item, store: store)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .onMove { source, destination in
                    store.move(fromOffsets: source, toOffset: destination)
                }

                if !store.list.completed.isEmpty {
                    completedHeader
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6))
                    if showCompleted {
                        ForEach(store.list.completed) { item in
                            TaskRowView(item: item, store: store)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 22)
        }
        .onChange(of: ui.focusAddRequest) { _, _ in focusAddField() }
        .onAppear {
            if ui.pendingAddFocus { focusAddField() }
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
            TextField("Add a task…  #tag", text: $newText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .focused($addFocused)
                .onSubmit(addTask)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.field)
        )
        .padding(8)
    }

    private var completedHeader: some View {
        HStack(spacing: 4) {
            Button {
                showCompleted.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 10)
                    Text("Completed (\(store.list.completed.count))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .contentShape(Rectangle())
            }
            Spacer()
            Button("Clear completed") {
                store.clearCompleted()
            }
            .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondaryText)
    }

    private func addTask() {
        let parsed = TaskList.parseQuickAdd(newText)
        guard !parsed.title.isEmpty else { return }
        store.add(title: parsed.title, priority: .none, tag: parsed.tag, dueDate: nil)
        newText = ""
        addFocused = true
    }

    /// Focus after the field exists and the panel is key (the list may just have appeared).
    private func focusAddField() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            addFocused = true
            ui.pendingAddFocus = false
        }
    }
}
