import Foundation

/// Priority of a task.
///
/// Raw values are ordered from lowest to highest, so priorities can be compared directly.
public enum Priority: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
}

/// Whether a task is still to be pushed uphill or has already been completed.
public enum TaskStatus: String, Codable, Sendable {
    case open
    case completed
}

/// A single task.
///
/// `TaskItem` is a plain `Sendable` value type; it is never mutated in place by the store,
/// all changes go through `TaskList`.
///
/// Decoding is tolerant, so a file written by an older build (or edited by hand) still loads:
/// only `title` is required. A missing `id` gets a fresh one, missing `priority`, `status` and
/// `createdAt` fall back to `.none`, `.open` and "now", and `tag`, `dueDate` and `completedAt` are
/// optional. A key that is *present* but undecodable (say `"priority": 7`) still fails the decode;
/// `Persistence` answers that by quarantining the file.
public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    /// Stable identity; survives edits and the move between the open and completed lists.
    public var id: UUID
    /// Display title, always stored trimmed and non-empty.
    public var title: String
    public var priority: Priority
    /// A single optional tag, stored without the leading `#`.
    public var tag: String?
    public var dueDate: Date?
    /// Kept in sync with the list (`open` or `completed`) that holds the item.
    public var status: TaskStatus
    public var createdAt: Date
    /// Set by `TaskList.complete(id:now:)`, cleared by `TaskList.reopen(id:)`.
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        priority: Priority = .none,
        tag: String? = nil,
        dueDate: Date? = nil,
        status: TaskStatus = .open,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.tag = tag
        self.dueDate = dueDate
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    // MARK: - Tolerant decoding

    private enum CodingKeys: String, CodingKey {
        case id, title, priority, tag, dueDate, status, createdAt, completedAt
    }

    /// Tolerant counterpart of the synthesised initialiser: every key but `title` is optional.
    /// `encode(to:)` stays synthesised, so the written format is unchanged.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag)
        self.dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        self.status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .open
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    /// Same task, with a different status. Used to keep the flag in sync with the list holding it.
    func withStatus(_ status: TaskStatus) -> TaskItem {
        var copy = self
        copy.status = status
        return copy
    }

    public var isCompleted: Bool { status == .completed }

    // MARK: - Sanitisation

    /// Trims leading and trailing whitespace (including newlines). An empty result means "reject".
    public static func sanitizeTitle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trims a tag, strips any leading `#` characters, and maps an empty result to `nil`.
    ///
    /// - `"  #home "` → `"home"`
    /// - `"##work"` → `"work"`
    /// - `"   "` and `"#"` → `nil`
    public static func sanitizeTag(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("#") {
            value.removeFirst()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
