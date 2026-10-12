import SwiftUI
import SisyphusCore

/// One task row. Open rows: checkbox completes, pencil/double-click/context menu edits.
/// Completed rows: struck through and dimmed, checkbox reopens, context menu deletes.
struct TaskRowView: View {
    let item: TaskItem
    let store: TaskStore

    @State private var editing = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if item.isCompleted {
                    store.reopen(id: item.id)
                } else {
                    store.complete(id: item.id)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(item.isCompleted ? Theme.accent.opacity(0.8) : Theme.secondaryText)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .help(item.isCompleted ? "Reopen" : "Complete")

            if let color = Theme.color(for: item.priority) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .help(Self.priorityName(item.priority) + " priority")
            }

            Text(item.title)
                .font(.system(size: 12))
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? Theme.secondaryText : Theme.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let tag = item.tag {
                Text("#\(tag)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.primaryText.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .lineLimit(1)
            }

            if let due = item.dueDate {
                Text(Self.dueLabel(for: due))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            if !item.isCompleted {
                Button {
                    editing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .help("Edit")
                .opacity(hovering || editing ? 1 : 0.35)
                .popover(isPresented: $editing, arrowEdge: .leading) {
                    TaskEditorView(item: item, store: store, isPresented: $editing)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(item.isCompleted ? 0.6 : 1)
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            if !item.isCompleted { editing = true }
        }
        .contextMenu {
            if !item.isCompleted {
                Button("Edit") { editing = true }
            }
            Button("Delete", role: .destructive) { store.delete(id: item.id) }
        }
    }

    static func priorityName(_ priority: Priority) -> String {
        switch priority {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// "Today", "Tomorrow", otherwise a short date (year only when it differs). No overdue style.
    static func dueLabel(for date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year(.twoDigits)
        return date.formatted(style)
    }
}
