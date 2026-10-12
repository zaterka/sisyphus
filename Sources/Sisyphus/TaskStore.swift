import Foundation
import Observation
import os
import SisyphusCore

/// `@MainActor` observable adapter around the pure `TaskList` value.
///
/// Every mutation goes through `TaskList` and then schedules a debounced (0.3 s) save. `flush()`
/// writes any pending change immediately; the app delegate calls it on terminate.
@MainActor
@Observable
final class TaskStore {
    /// The task data. Mutated only through the methods below.
    private(set) var list: TaskList

    /// Whether the task list section is visible (the ⌘T toggle). Persisted.
    var listVisible: Bool {
        didSet {
            if oldValue != listVisible { scheduleSave() }
        }
    }

    /// Debounce interval for saves.
    static let saveDelay: Duration = .milliseconds(300)

    @ObservationIgnored private let persistence: Persistence
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.sisyphus.app", category: "store")

    init(persistence: Persistence = Persistence()) {
        self.persistence = persistence
        let loaded = persistence.load()
        self.list = loaded.0
        self.listVisible = loaded.listVisible
        logger.info("Task store at \(persistence.url.path, privacy: .public)")
    }

    /// File the store reads and writes.
    var fileURL: URL { persistence.url }

    // MARK: - Mutations

    func add(title: String, priority: Priority = .none, tag: String? = nil, dueDate: Date? = nil) {
        if list.add(title: title, priority: priority, tag: tag, dueDate: Self.normalizedDay(dueDate)) != nil {
            scheduleSave()
        }
    }

    func update(_ item: TaskItem) {
        var item = item
        item.dueDate = Self.normalizedDay(item.dueDate)
        let before = list
        list.update(item)
        if list != before { scheduleSave() }
    }

    func complete(id: UUID) {
        list.complete(id: id, now: Date())
        scheduleSave()
    }

    func reopen(id: UUID) {
        list.reopen(id: id)
        scheduleSave()
    }

    func delete(id: UUID) {
        list.delete(id: id)
        scheduleSave()
    }

    func clearCompleted() {
        list.clearCompleted()
        scheduleSave()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        list.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// Ends a summit run (called by the scene when `.summitFinished` fires).
    @discardableResult
    func consumeSummit() -> Bool {
        let consumed = list.consumeSummit()
        if consumed { scheduleSave() }
        return consumed
    }

    // MARK: - Saving

    /// Writes any pending change now and cancels the debounce timer.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty else { return }
        dirty = false
        persistence.save(list, listVisible: listVisible)
    }

    private func scheduleSave() {
        dirty = true
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: TaskStore.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Due dates are stored as the start of the chosen day, in local time.
    static func normalizedDay(_ date: Date?) -> Date? {
        date.map { Calendar.current.startOfDay(for: $0) }
    }
}
