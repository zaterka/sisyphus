import Foundation
import Testing

import SisyphusCore

/// Creates a unique, empty temporary directory and returns a store URL inside it.
private func makeTempStoreURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sisyphus-tests-\(UUID().uuidString)", isDirectory: true)
    return directory.appendingPathComponent("tasks.json", isDirectory: false)
}

private func removeDirectory(of url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

private func siblings(of url: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
}

@Suite("Persistence")
struct PersistenceTests {
    @Test("Round trip through a temp directory")
    func roundTrip() throws {
        let url = makeTempStoreURL()
        defer { removeDirectory(of: url) }

        var list = TaskList()
        let done = try requireAdded(list.add(
            title: "Buy milk",
            priority: .high,
            tag: "#home",
            dueDate: Date(timeIntervalSince1970: 1_700_086_400),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let shipped = try requireAdded(list.add(
            title: "Ship it",
            priority: .low,
            tag: "work",
            now: Date(timeIntervalSince1970: 1_700_000_100)
        ))
        list.complete(id: shipped.id, now: Date(timeIntervalSince1970: 1_700_000_200))

        let persistence = Persistence(url: url)
        persistence.save(list, listVisible: false)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let (loaded, listVisible) = persistence.load()
        #expect(loaded == list)
        #expect(listVisible == false)
        #expect(loaded.open.first?.id == done.id)
        #expect(loaded.open.first?.tag == "home")
        #expect(loaded.open.first?.dueDate == Date(timeIntervalSince1970: 1_700_086_400))
        #expect(loaded.completedSinceReset == 1)
    }

    @Test("Dates are written as ISO 8601")
    func iso8601Dates() throws {
        let url = makeTempStoreURL()
        defer { removeDirectory(of: url) }

        var list = TaskList()
        _ = try requireAdded(list.add(
            title: "A",
            dueDate: Date(timeIntervalSince1970: 1_700_086_400),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        Persistence(url: url).save(list, listVisible: true)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("2023-11-14T22:13:20Z"))
        #expect(raw.contains("2023-11-15T22:13:20Z"))

        let object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        #expect((object?["version"] as? Int) == 1)
        #expect((object?["listVisible"] as? Bool) == true)
    }

    @Test("A missing file loads as empty and creates nothing")
    func missingFile() {
        let url = makeTempStoreURL()
        defer { removeDirectory(of: url) }

        let (list, listVisible) = Persistence(url: url).load()
        #expect(list == TaskList())
        #expect(listVisible == true)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A corrupt file is renamed and an empty store is returned")
    func corruptFileRecovery() throws {
        let url = makeTempStoreURL()
        defer { removeDirectory(of: url) }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ this is not json".utf8).write(to: url)

        let (list, listVisible) = Persistence(url: url).load()
        #expect(list == TaskList())
        #expect(listVisible == true)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(siblings(of: url).contains { $0.hasPrefix("tasks.corrupt-") && $0.hasSuffix(".json") })
    }

    @Test("Truncated JSON is treated as corrupt")
    func truncatedJSON() throws {
        let url = makeTempStoreURL()
        defer { removeDirectory(of: url) }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":1,"open":[{"id""#.utf8).write(to: url)

        let (list, _) = Persistence(url: url).load()
        #expect(list == TaskList())
        #expect(siblings(of: url).contains { $0.hasPrefix("tasks.corrupt-") })
    }

    @Test("A file without version or listVisible still decodes")
    func tolerantDecoding() throws {
        let id = UUID().uuidString
        let json = """
        {
          "open": [
            {
              "id": "\(id)",
              "title": "A",
              "priority": 2,
              "status": "open",
              "createdAt": "2023-11-14T22:13:20Z"
            }
          ],
          "completed": []
        }
        """
        let file = try Persistence.makeDecoder().decode(StoreFile.self, from: Data(json.utf8))
        #expect(file.version == StoreFile.currentVersion)
        #expect(file.listVisible == true)
        #expect(file.completedSinceReset == 0)

        let list = file.list
        #expect(list.open.count == 1)
        #expect(list.open[0].id.uuidString == id)
        #expect(list.open[0].priority == .medium)
        #expect(list.open[0].tag == nil)
        #expect(list.open[0].dueDate == nil)
        #expect(list.open[0].completedAt == nil)
        #expect(list.open[0].createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("A task missing priority, status and createdAt still decodes")
    func tolerantTaskDecoding() throws {
        let id = UUID().uuidString
        let json = """
        {
          "open": [
            { "id": "\(id)", "title": "A" }
          ],
          "completed": []
        }
        """
        let file = try Persistence.makeDecoder().decode(StoreFile.self, from: Data(json.utf8))

        #expect(file.open.count == 1)
        let task = try #require(file.open.first)
        #expect(task.id.uuidString == id)
        #expect(task.title == "A")
        #expect(task.priority == .none)
        #expect(task.status == .open)
        #expect(task.tag == nil)
        #expect(task.dueDate == nil)
        #expect(task.completedAt == nil)
        // createdAt defaults to "now", not to a fixed epoch.
        #expect(abs(task.createdAt.timeIntervalSinceNow) < 60)
    }

    @Test("A task without an id gets one, and a task without a title is rejected")
    func tolerantTaskIdentity() throws {
        let anon = """
        { "open": [ { "title": "No id" } ], "completed": [] }
        """
        let file = try Persistence.makeDecoder().decode(StoreFile.self, from: Data(anon.utf8))
        let task = try #require(file.open.first)
        #expect(task.title == "No id")

        // A fresh id is minted per decode, not a shared default.
        let again = try Persistence.makeDecoder().decode(StoreFile.self, from: Data(anon.utf8))
        #expect(again.open.first?.id != task.id)
        #expect(again.open.first?.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

        // The one required key: a title-less entry fails the decode, and Persistence then
        // quarantines the whole file instead of loading half of it.
        let titleless = """
        { "open": [ { "id": "\(UUID().uuidString)" } ], "completed": [] }
        """
        #expect(throws: (any Error).self) {
            _ = try Persistence.makeDecoder().decode(StoreFile.self, from: Data(titleless.utf8))
        }
    }

    @Test("Status is re-derived from the list that holds the task")
    func normalisesStatusByMembership() throws {
        let openID = UUID().uuidString
        let doneID = UUID().uuidString
        let json = """
        {
          "open": [ { "id": "\(openID)", "title": "Open one", "status": "completed" } ],
          "completed": [ { "id": "\(doneID)", "title": "Done one" } ]
        }
        """
        let list = try Persistence.makeDecoder().decode(StoreFile.self, from: Data(json.utf8)).list
        #expect(list.open.map(\.status) == [.open])
        #expect(list.completed.map(\.status) == [.completed])
        #expect(list.open.first?.isCompleted == false)
        #expect(list.completed.first?.isCompleted == true)
    }

    @Test("StoreFile wraps a TaskList and the toggle state")
    func storeFileWrapper() throws {
        var list = TaskList()
        let item = try requireAdded(list.add(title: "A", now: Date(timeIntervalSince1970: 1_700_000_000)))
        list.complete(id: item.id, now: Date(timeIntervalSince1970: 1_700_000_100))

        let file = StoreFile(list: list, listVisible: false)
        #expect(file.version == StoreFile.currentVersion)
        #expect(file.listVisible == false)
        #expect(file.completedSinceReset == 1)
        #expect(file.list == list)
    }

    @Test("Saving twice overwrites rather than appends")
    func overwrites() throws {
        let url = makeTempStoreURL()
        defer { removeDirectory(of: url) }
        let persistence = Persistence(url: url)

        var first = TaskList()
        _ = try requireAdded(first.add(title: "first", now: Date(timeIntervalSince1970: 1_700_000_000)))
        persistence.save(first, listVisible: true)

        var second = TaskList()
        _ = try requireAdded(second.add(title: "second", now: Date(timeIntervalSince1970: 1_700_000_000)))
        persistence.save(second, listVisible: true)

        let (loaded, _) = persistence.load()
        #expect(loaded.open.map(\.title) == ["second"])
    }

    @Test("An unwritable location is logged and swallowed, not thrown")
    func unwritableLocationIsSwallowed() throws {
        var list = TaskList()
        _ = try requireAdded(list.add(title: "A", now: Date(timeIntervalSince1970: 1_700_000_000)))
        // /dev/null is a file, so it cannot be a directory: saving must fail quietly.
        let persistence = Persistence(url: URL(fileURLWithPath: "/dev/null/tasks.json"))
        persistence.save(list, listVisible: true)
        let (loaded, listVisible) = persistence.load()
        #expect(loaded == TaskList())
        #expect(listVisible == true)
    }

    @Test("defaultURL lives in Application Support/Sisyphus")
    func defaultURL() {
        let path = Persistence.defaultURL.path
        #expect(path.hasSuffix("/Library/Application Support/Sisyphus/tasks.json"))
        #expect(Persistence().url == Persistence.defaultURL)
    }
}
