import SwiftUI
import SisyphusCore

/// Popover editor for one task: title, priority, tag, optional due date, Delete and Done.
///
/// Changes are applied when the popover closes — either because the `isPresented` binding goes
/// false, or (belt and braces, in case a dismissal never flips the binding) when the view
/// disappears. `commit()` is idempotent: it applies the edit at most once per presentation, and
/// never after Delete, which removes the task itself and skips the save.
struct TaskEditorView: View {
    let item: TaskItem
    let store: TaskStore
    @Binding var isPresented: Bool

    @State private var title: String
    @State private var priority: Priority
    @State private var tag: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var deleted = false
    /// Guards `commit()` so the two dismissal hooks cannot apply the same edit twice.
    @State private var committed = false
    @FocusState private var titleFocused: Bool

    init(item: TaskItem, store: TaskStore, isPresented: Binding<Bool>) {
        self.item = item
        self.store = store
        self._isPresented = isPresented
        _title = State(initialValue: item.title)
        _priority = State(initialValue: item.priority)
        _tag = State(initialValue: item.tag ?? "")
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit { isPresented = false }

            Picker("Priority", selection: $priority) {
                ForEach(Priority.allCases, id: \.self) { value in
                    Text(Self.shortName(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 4) {
                Text("#").foregroundStyle(.secondary)
                TextField("tag", text: $tag)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Has due date", isOn: $hasDueDate)
                .toggleStyle(.checkbox)
            if hasDueDate {
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            HStack {
                Button("Delete", role: .destructive) {
                    deleted = true
                    store.delete(id: item.id)
                    isPresented = false
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(width: 240)
        .onAppear { titleFocused = true }
        .onChange(of: isPresented) { _, presented in
            if presented {
                // SwiftUI can reuse this view for a later presentation: start a new commit cycle.
                committed = false
            } else {
                commit()
            }
        }
        .onDisappear(perform: commit)
    }

    /// Applies the edited fields to the stored task. Safe to call more than once.
    private func commit() {
        guard !deleted, !committed else { return }
        committed = true
        var updated = item
        updated.title = title
        updated.priority = priority
        updated.tag = tag
        updated.dueDate = hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
        // TaskList.update sanitises and ignores an empty title.
        store.update(updated)
    }

    static func shortName(_ priority: Priority) -> String {
        switch priority {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        }
    }
}
