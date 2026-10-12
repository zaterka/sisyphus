import Foundation

/// The whole task store: a pure `Sendable` value type with all mutations expressed as methods.
///
/// The type holds no reference to the file system and no clock; `now` is injected everywhere a
/// timestamp is needed. `TaskList` is the single source of truth for progress and for the
/// summit trigger that drives the scene animation.
public struct TaskList: Equatable, Sendable {
    /// Open tasks, in the manual order the user chose by dragging.
    public var open: [TaskItem]
    /// Completed tasks, newest `completedAt` first.
    public var completed: [TaskItem]
    /// How many tasks were completed since the last summit. Deliberately independent of
    /// `completed.count`: deleting or clearing completed rows does not revoke progress.
    public var completedSinceReset: Int

    public static let empty = TaskList()

    public init(open: [TaskItem] = [], completed: [TaskItem] = [], completedSinceReset: Int = 0) {
        self.open = open
        self.completed = completed
        self.completedSinceReset = max(0, completedSinceReset)
    }

    // MARK: - Derived state

    /// `true` when there is nothing left to push and progress has been earned since the last reset.
    public var summitPending: Bool {
        open.isEmpty && completedSinceReset > 0
    }

    /// Fraction of the earned work: `completedSinceReset / (completedSinceReset + open.count)`.
    ///
    /// - An empty store (no open tasks and no counter) is `0` — never `NaN`.
    /// - A finished run (no open tasks, counter > 0) is `1`.
    public var progress: Double {
        let openCount = open.count
        if openCount == 0 && completedSinceReset == 0 { return 0 }
        let total = Double(completedSinceReset + openCount)
        guard total > 0 else { return 0 }
        return min(max(Double(completedSinceReset) / total, 0), 1)
    }

    // MARK: - Mutations

    /// Appends a new open task.
    ///
    /// - The title is trimmed; a title that is empty after trimming is rejected and `nil` is returned.
    /// - The tag is trimmed, a leading `#` is stripped, and an empty tag becomes `nil`.
    @discardableResult
    public mutating func add(
        title: String,
        priority: Priority = .none,
        tag: String? = nil,
        dueDate: Date? = nil,
        now: Date = Date()
    ) -> TaskItem? {
        let cleanTitle = TaskItem.sanitizeTitle(title)
        guard !cleanTitle.isEmpty else { return nil }
        let item = TaskItem(
            title: cleanTitle,
            priority: priority,
            tag: TaskItem.sanitizeTag(tag),
            dueDate: dueDate,
            status: .open,
            createdAt: now,
            completedAt: nil
        )
        open.append(item)
        return item
    }

    /// Replaces the stored task with the same `id`, in whichever list holds it.
    ///
    /// The title and tag are re-sanitised. An empty title is a no-op, and so is an unknown `id`.
    /// List membership wins over `item.status`/`item.completedAt`: an item that lives in `open`
    /// stays open, an item that lives in `completed` stays completed with its original
    /// `completedAt`. `createdAt` is preserved from the stored copy.
    public mutating func update(_ item: TaskItem) {
        let cleanTitle = TaskItem.sanitizeTitle(item.title)
        guard !cleanTitle.isEmpty else { return }

        var replacement = item
        replacement.title = cleanTitle
        replacement.tag = TaskItem.sanitizeTag(item.tag)

        if let index = open.firstIndex(where: { $0.id == item.id }) {
            replacement.status = .open
            replacement.completedAt = nil
            replacement.createdAt = open[index].createdAt
            open[index] = replacement
        } else if let index = completed.firstIndex(where: { $0.id == item.id }) {
            replacement.status = .completed
            replacement.completedAt = completed[index].completedAt ?? item.completedAt
            replacement.createdAt = completed[index].createdAt
            completed[index] = replacement
        }
    }

    /// Moves an open task to the front of `completed` and counts it once toward the summit.
    ///
    /// Unknown ids and already completed tasks are ignored.
    public mutating func complete(id: UUID, now: Date = Date()) {
        guard let index = open.firstIndex(where: { $0.id == id }) else { return }
        var item = open.remove(at: index)
        item.status = .completed
        item.completedAt = now
        completed.insert(item, at: 0)
        completedSinceReset += 1
    }

    /// Moves a completed task back to the end of `open`.
    ///
    /// The counter is decremented but never goes below 0. Unknown ids are ignored.
    public mutating func reopen(id: UUID) {
        guard let index = completed.firstIndex(where: { $0.id == id }) else { return }
        var item = completed.remove(at: index)
        item.status = .open
        item.completedAt = nil
        open.append(item)
        completedSinceReset = max(0, completedSinceReset - 1)
    }

    /// Removes a task from either list. The counter does not change.
    public mutating func delete(id: UUID) {
        open.removeAll { $0.id == id }
        completed.removeAll { $0.id == id }
    }

    /// Empties `completed`. The counter does not change.
    public mutating func clearCompleted() {
        completed.removeAll()
    }

    /// Reorders `open` with the same semantics as SwiftUI's `onMove`.
    ///
    /// - `toOffset` is clamped to `0...open.count`.
    /// - Out-of-range source indices are ignored; an empty index set is a no-op.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let count = open.count
        guard count > 0 else { return }

        let indices = source.filter { $0 >= 0 && $0 < count }.sorted()
        guard !indices.isEmpty else { return }

        let destination = min(max(destination, 0), count)
        var items = open
        let moving = indices.map { items[$0] }
        for index in indices.reversed() {
            items.remove(at: index)
        }
        let removedBefore = indices.filter { $0 < destination }.count
        let insertion = min(max(destination - removedBefore, 0), items.count)
        items.insert(contentsOf: moving, at: insertion)
        open = items
    }

    /// Ends a summit run: resets the counter when a summit is pending.
    ///
    /// - Returns: `true` only when `summitPending` was `true`.
    /// - Calling it again (or while tasks are still open) is a safe no-op returning `false`.
    @discardableResult
    public mutating func consumeSummit() -> Bool {
        guard summitPending else { return false }
        completedSinceReset = 0
        return true
    }

    // MARK: - Quick add

    /// Splits a quick-add string into a title and an optional tag.
    ///
    /// The first whitespace-separated word starting with `#` becomes the tag (leading `#`s
    /// stripped, empty tag → `nil`); that word is removed from the text. The remaining words are
    /// re-joined with single spaces and trimmed, which collapses the gap the tag left behind.
    ///
    /// - `"buy milk #home"` → `("buy milk", "home")`
    /// - `"buy   milk  #home "` → `("buy milk", "home")`
    /// - `"no tag here"` → `("no tag here", nil)`
    public static func parseQuickAdd(_ text: String) -> (title: String, tag: String?) {
        var tag: String?
        var titleWords: [String] = []

        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            let token = String(word)
            if tag == nil, token.hasPrefix("#") {
                tag = TaskItem.sanitizeTag(token) // may stay nil for a bare "#"
                continue
            }
            titleWords.append(token)
        }

        return (titleWords.joined(separator: " "), tag)
    }
}
