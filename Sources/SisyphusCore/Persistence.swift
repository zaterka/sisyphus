import Foundation
import os

/// Reads and writes the store file.
///
/// The type never throws and never crashes the caller: every failure is logged through
/// `os.Logger` and the app keeps running with an empty or last-known-good state. The file URL is
/// injectable so tests (and a future "export" feature) can point it anywhere.
public struct Persistence: Sendable {
    private static let subsystem = "com.sisyphus.app"
    private static let category = "persistence"
    private static let fileExtension = "json"
    private static let fileName = "tasks"

    /// Location of the store file.
    public let url: URL

    /// - Parameter url: File to read and write. Defaults to `defaultURL`.
    public init(url: URL = Persistence.defaultURL) {
        self.url = url
    }

    /// `~/Library/Application Support/Sisyphus/tasks.json`.
    public static var defaultURL: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Sisyphus", isDirectory: true)
            .appendingPathComponent("\(fileName).\(fileExtension)", isDirectory: false)
    }

    /// The directory that holds the store file.
    public var directoryURL: URL {
        url.deletingLastPathComponent()
    }

    private var logger: Logger {
        Logger(subsystem: Persistence.subsystem, category: Persistence.category)
    }

    // MARK: - Coding helpers

    /// Encoder used for the store file: ISO 8601 dates, stable key order, human-readable.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Decoder used for the store file: ISO 8601 dates.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Load

    /// Loads the store.
    ///
    /// - A missing file (or an unreadable one) loads as an empty store with the list visible.
    /// - A file that exists but does not decode is renamed to `tasks.corrupt-<unix>.json` next to
    ///   the original and the store loads as empty, so the app never gets stuck on bad data.
    public func load() -> (TaskList, listVisible: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.info("No store file at \(self.url.path, privacy: .public); starting empty")
            return (TaskList(), true)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Could not read store file at \(self.url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return (TaskList(), true)
        }

        do {
            let file = try Persistence.makeDecoder().decode(StoreFile.self, from: data)
            logger.info("Loaded \(file.open.count) open and \(file.completed.count) completed tasks from \(self.url.path, privacy: .public)")
            return (file.list, file.listVisible)
        } catch {
            logger.error("Store file at \(self.url.path, privacy: .public) is corrupt (\(String(describing: error), privacy: .public)); renaming and starting empty")
            quarantineCorruptFile()
            return (TaskList(), true)
        }
    }

    // MARK: - Save

    /// Writes the store atomically, creating the containing directory when needed.
    ///
    /// Failures are logged and swallowed.
    public func save(_ list: TaskList, listVisible: Bool) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try Persistence.makeEncoder().encode(StoreFile(list: list, listVisible: listVisible))
            try data.write(to: url, options: .atomic)
            logger.debug("Saved \(list.open.count) open and \(list.completed.count) completed tasks to \(self.url.path, privacy: .public)")
        } catch {
            logger.error("Could not save store file at \(self.url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Corrupt-file recovery

    @discardableResult
    private func quarantineCorruptFile() -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = directoryURL
            .appendingPathComponent("\(Persistence.fileName).corrupt-\(stamp).\(Persistence.fileExtension)", isDirectory: false)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            logger.notice("Moved corrupt store file to \(destination.path, privacy: .public)")
            return destination
        } catch {
            logger.error("Could not rename corrupt store file at \(self.url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
