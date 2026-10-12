import Foundation

/// On-disk representation of the store: the two task lists plus the two app-level settings.
///
/// Decoding is tolerant: `version`, `completedSinceReset` and `listVisible` are optional on disk
/// and fall back to their defaults, so a file written by an older build still loads. Dates are
/// handled by the encoder/decoder produced by `Persistence` (ISO 8601).
public struct StoreFile: Codable, Equatable, Sendable {
    /// Format version written on save.
    public static let currentVersion = 1

    public var version: Int
    public var open: [TaskItem]
    public var completed: [TaskItem]
    public var completedSinceReset: Int
    /// Whether the task list section of the panel is visible (the ⌘T toggle state).
    public var listVisible: Bool

    public init(
        version: Int = StoreFile.currentVersion,
        open: [TaskItem] = [],
        completed: [TaskItem] = [],
        completedSinceReset: Int = 0,
        listVisible: Bool = true
    ) {
        self.version = version
        self.open = open
        self.completed = completed
        self.completedSinceReset = max(0, completedSinceReset)
        self.listVisible = listVisible
    }

    /// Wraps a `TaskList` plus the toggle state for saving.
    public init(list: TaskList, listVisible: Bool) {
        self.init(
            version: StoreFile.currentVersion,
            open: list.open,
            completed: list.completed,
            completedSinceReset: list.completedSinceReset,
            listVisible: listVisible
        )
    }

    /// The task data as a `TaskList`.
    ///
    /// List membership is authoritative (see `TaskList.update`), so `status` is re-derived from the
    /// list each item lives in. That also covers files written without `status`, which now decodes
    /// as `.open`: an item inside `completed` would otherwise look unchecked while its checkbox
    /// could only ever reopen an `open` task.
    public var list: TaskList {
        TaskList(
            open: open.map { $0.withStatus(.open) },
            completed: completed.map { $0.withStatus(.completed) },
            completedSinceReset: completedSinceReset
        )
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case version, open, completed, completedSinceReset, listVisible
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? StoreFile.currentVersion
        self.open = try container.decodeIfPresent([TaskItem].self, forKey: .open) ?? []
        self.completed = try container.decodeIfPresent([TaskItem].self, forKey: .completed) ?? []
        self.completedSinceReset = max(0, try container.decodeIfPresent(Int.self, forKey: .completedSinceReset) ?? 0)
        self.listVisible = try container.decodeIfPresent(Bool.self, forKey: .listVisible) ?? true
    }
}
