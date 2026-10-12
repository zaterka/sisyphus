import Foundation
import Testing

import SisyphusCore

private let base = Date(timeIntervalSince1970: 1_700_000_000)

/// Builds a list of `count` open tasks titled "a", "b", "c", … and returns it with their ids.
private func makeList(_ titles: [String]) -> (list: TaskList, ids: [UUID]) {
    var list = TaskList()
    var ids: [UUID] = []
    for title in titles {
        if let item = list.add(title: title, now: base) {
            ids.append(item.id)
        }
    }
    return (list, ids)
}

private func titles(_ items: [TaskItem]) -> [String] { items.map(\.title) }

@Suite("TaskList progress")
struct ProgressTests {
    @Test("An empty store is 0, not NaN")
    func emptyStore() {
        let list = TaskList()
        #expect(list.progress == 0)
        #expect(!list.progress.isNaN)
        #expect(!list.summitPending)
    }

    @Test("One open task is 0")
    func oneOpen() throws {
        var list = TaskList()
        _ = try requireAdded(list.add(title: "a", now: base))
        #expect(list.progress == 0)
    }

    @Test("One done plus one open is 0.5")
    func oneDoneOneOpen() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[0], now: base)
        #expect(list.progress == 0.5)
        #expect(list.open.count == 1)
        #expect(list.completed.count == 1)
    }

    @Test("Adding a task lowers progress and completing one raises it")
    func movesInBothDirections() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[0], now: base)
        list.complete(id: ids[1], now: base)
        #expect(list.progress == 1)

        _ = try requireAdded(list.add(title: "c", now: base))
        #expect(list.progress == 2.0 / 3.0)

        let c = try #require(list.open.first)
        list.complete(id: c.id, now: base)
        #expect(list.progress == 1)
    }

    @Test("Progress is clamped to 0...1 and never NaN")
    func clamped() throws {
        var (list, ids) = makeList(["a"])
        list.complete(id: ids[0], now: base)
        _ = try requireAdded(list.add(title: "b", now: base))
        #expect(list.progress >= 0 && list.progress <= 1)
        #expect(!list.progress.isNaN)
    }
}

@Suite("TaskList summit")
struct SummitTests {
    @Test("summitPending becomes true when the last open task is completed")
    func pendingAfterLastCompletion() throws {
        var (list, ids) = makeList(["a", "b"])
        #expect(!list.summitPending)
        list.complete(id: ids[0], now: base)
        #expect(!list.summitPending)
        list.complete(id: ids[1], now: base)
        #expect(list.summitPending)
        #expect(list.progress == 1)
    }

    @Test("consumeSummit resets the counter, returns true once, then false")
    func consumeOnce() throws {
        var (list, ids) = makeList(["a"])
        list.complete(id: ids[0], now: base)
        #expect(list.summitPending)

        #expect(list.consumeSummit() == true)
        #expect(list.completedSinceReset == 0)
        #expect(!list.summitPending)
        #expect(list.progress == 0)

        #expect(list.consumeSummit() == false)
        #expect(list.completedSinceReset == 0)
    }

    @Test("consumeSummit is a no-op while tasks are open")
    func noOpWithOpenTasks() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[0], now: base)
        #expect(list.consumeSummit() == false)
        #expect(list.completedSinceReset == 1)
    }
}

@Suite("TaskList reopen")
struct ReopenTests {
    @Test("Reopening decreases the counter and appends to the end of open")
    func reopenDecrementsAndAppends() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[0], now: base)
        list.complete(id: ids[1], now: base)
        #expect(list.completedSinceReset == 2)

        list.reopen(id: ids[0])
        #expect(list.completedSinceReset == 1)
        #expect(titles(list.open) == ["a"])
        #expect(list.completed.count == 1)

        _ = try requireAdded(list.add(title: "c", now: base))
        list.reopen(id: ids[1])
        #expect(titles(list.open) == ["a", "c", "b"])
        #expect(list.completedSinceReset == 0)
        #expect(list.open.allSatisfy { $0.status == .open && $0.completedAt == nil })
    }

    @Test("The counter never goes below 0")
    func neverNegative() {
        let item = TaskItem(title: "a", status: .completed, createdAt: base, completedAt: base)
        var list = TaskList(completed: [item], completedSinceReset: 0)
        list.reopen(id: item.id)
        #expect(list.completedSinceReset == 0)
        #expect(titles(list.open) == ["a"])
        #expect(list.progress == 0)
    }
}

@Suite("TaskList delete and clearCompleted")
struct DeleteTests {
    @Test("Deleting does not change the counter")
    func deleteKeepsCounter() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[1], now: base)
        #expect(list.completedSinceReset == 1)

        list.delete(id: ids[0]) // open
        #expect(list.completedSinceReset == 1)
        #expect(list.open.isEmpty)

        list.delete(id: ids[1]) // completed
        #expect(list.completedSinceReset == 1)
        #expect(list.completed.isEmpty)
    }

    @Test("clearCompleted does not change the counter")
    func clearKeepsCounter() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[0], now: base)
        list.complete(id: ids[1], now: base)
        list.clearCompleted()
        #expect(list.completed.isEmpty)
        #expect(list.completedSinceReset == 2)
    }

    @Test("Deleting the last open task with counter > 0 makes the summit pending")
    func deleteLastOpenTriggersSummit() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[1], now: base)
        list.delete(id: ids[0])
        #expect(list.summitPending)
        #expect(list.progress == 1)
    }

    @Test("Deleting the last open task with counter 0 gives progress 0 and no summit")
    func deleteLastOpenWithoutCounter() throws {
        var (list, ids) = makeList(["a"])
        list.delete(id: ids[0])
        #expect(!list.summitPending)
        #expect(list.progress == 0)
    }

    @Test("Deleting an unknown id changes nothing")
    func deleteUnknown() throws {
        let (list, _) = makeList(["a", "b"])
        var copy = list
        copy.delete(id: UUID())
        #expect(copy == list)
    }
}

@Suite("TaskList move")
struct MoveTests {
    @Test("A normal move")
    func normalMove() throws {
        var (list, _) = makeList(["a", "b", "c", "d", "e"])
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(titles(list.open) == ["b", "c", "a", "d", "e"])
    }

    @Test("Multiple indices move together, preserving their relative order")
    func multipleIndices() throws {
        var (list, _) = makeList(["a", "b", "c", "d", "e"])
        list.move(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        #expect(titles(list.open) == ["b", "d", "e", "a", "c"])
    }

    @Test("An out-of-range toOffset gets clamped")
    func clampedDestination() throws {
        var (list, _) = makeList(["a", "b", "c", "d", "e"])
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(titles(list.open) == ["b", "c", "d", "e", "a"])

        var (low, _) = makeList(["a", "b", "c", "d", "e"])
        low.move(fromOffsets: IndexSet(integer: 4), toOffset: -3)
        #expect(titles(low.open) == ["e", "a", "b", "c", "d"])
    }

    @Test("An empty index set is a no-op")
    func emptyIndexSet() throws {
        let (list, _) = makeList(["a", "b", "c"])
        var copy = list
        copy.move(fromOffsets: IndexSet(), toOffset: 2)
        #expect(copy == list)
    }

    @Test("Invalid source indices are ignored")
    func invalidIndices() throws {
        let (list, _) = makeList(["a", "b", "c"])
        var copy = list
        copy.move(fromOffsets: IndexSet([7, 9]), toOffset: 1)
        #expect(copy == list)

        var mixed = list
        mixed.move(fromOffsets: IndexSet([9]), toOffset: 0)
        #expect(mixed == list)
    }

    @Test("Moving into an empty list is a no-op")
    func emptyList() {
        var list = TaskList()
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 0)
        #expect(list == TaskList())
    }

    @Test("Move changes only the order, not the items")
    func preservesItems() throws {
        var (list, _) = makeList(["a", "b", "c"])
        let before = Set(list.open.map(\.id))
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(Set(list.open.map(\.id)) == before)
        #expect(titles(list.open) == ["c", "a", "b"])
    }
}

@Suite("TaskList sanitisation")
struct SanitisationTests {
    @Test("Titles are trimmed")
    func trimsTitles() throws {
        var list = TaskList()
        let item = try requireAdded(list.add(title: "  buy milk\n", now: base))
        #expect(item.title == "buy milk")
        #expect(list.open[0].title == "buy milk")
    }

    @Test("Empty titles are rejected")
    func rejectsEmptyTitles() {
        var list = TaskList()
        #expect(list.add(title: "", now: base) == nil)
        #expect(list.add(title: "   \n\t ", now: base) == nil)
        #expect(list.open.isEmpty)
    }

    @Test("A leading # is stripped from tags and an empty tag becomes nil")
    func tags() throws {
        var list = TaskList()
        let a = try requireAdded(list.add(title: "a", tag: "#home", now: base))
        let b = try requireAdded(list.add(title: "b", tag: "  #  work  ", now: base))
        let c = try requireAdded(list.add(title: "c", tag: "#", now: base))
        let d = try requireAdded(list.add(title: "d", tag: "   ", now: base))
        let e = try requireAdded(list.add(title: "e", tag: nil, now: base))
        #expect(a.tag == "home")
        #expect(b.tag == "work")
        #expect(c.tag == nil)
        #expect(d.tag == nil)
        #expect(e.tag == nil)
    }

    @Test("update re-sanitises and ignores an empty title")
    func updateSanitises() throws {
        var (list, ids) = makeList(["a"])
        var item = try #require(list.open.first)
        item.title = "  renamed #x  "
        item.tag = " #nova "
        list.update(item)
        #expect(list.open[0].title == "renamed #x")
        #expect(list.open[0].tag == "nova")
        #expect(list.open[0].createdAt == base)

        var empty = try #require(list.open.first)
        empty.title = "   "
        list.update(empty)
        #expect(list.open[0].title == "renamed #x")
        #expect(list.open[0].id == ids[0])
    }

    @Test("update keeps the item in its own list")
    func updateKeepsMembership() throws {
        var (list, ids) = makeList(["a", "b"])
        list.complete(id: ids[0], now: base)
        var completed = try #require(list.completed.first)
        completed.title = "done"
        completed.status = .open // the UI should not be able to move an item this way
        list.update(completed)
        #expect(list.completed.count == 1)
        #expect(list.open.count == 1)
        #expect(list.completed[0].title == "done")
        #expect(list.completed[0].status == .completed)
    }

    @Test("update ignores an unknown id")
    func updateUnknown() throws {
        let (list, _) = makeList(["a"])
        var copy = list
        copy.update(TaskItem(title: "ghost", createdAt: base))
        #expect(copy == list)
    }

    @Test("complete sets completedAt and keeps createdAt")
    func completeSetsTimestamps() throws {
        var (list, ids) = makeList(["a"])
        let done = Date(timeIntervalSince1970: 1_700_000_500)
        list.complete(id: ids[0], now: done)
        let item = try #require(list.completed.first)
        #expect(item.completedAt == done)
        #expect(item.createdAt == base)
        #expect(item.status == .completed)

        list.reopen(id: ids[0])
        #expect(list.open[0].completedAt == nil)
        #expect(list.open[0].status == .open)
    }

    @Test("Completing an unknown or already completed id is ignored")
    func completeUnknown() throws {
        var (list, ids) = makeList(["a"])
        list.complete(id: ids[0], now: base)
        let after = list
        list.complete(id: ids[0], now: base)
        list.complete(id: UUID(), now: base)
        #expect(list == after)
    }

    @Test("Completed tasks are ordered newest first")
    func completedOrder() throws {
        var (list, ids) = makeList(["a", "b", "c"])
        list.complete(id: ids[0], now: Date(timeIntervalSince1970: 100))
        list.complete(id: ids[1], now: Date(timeIntervalSince1970: 200))
        list.complete(id: ids[2], now: Date(timeIntervalSince1970: 300))
        #expect(titles(list.completed) == ["c", "b", "a"])
    }
}

@Suite("TaskList quick add")
struct QuickAddTests {
    @Test("The first #word becomes the tag and leaves the title")
    func extractsTag() {
        let result = TaskList.parseQuickAdd("buy milk #home")
        #expect(result.title == "buy milk")
        #expect(result.tag == "home")
    }

    @Test("Whitespace is collapsed and trimmed")
    func collapsesWhitespace() {
        let result = TaskList.parseQuickAdd("  buy   milk   #home  ")
        #expect(result.title == "buy milk")
        #expect(result.tag == "home")
    }

    @Test("No tag yields a nil tag and the whole title")
    func noTag() {
        let result = TaskList.parseQuickAdd("  no tags here  ")
        #expect(result.title == "no tags here")
        #expect(result.tag == nil)
    }

    @Test("A leading tag leaves a clean title")
    func leadingTag() {
        let result = TaskList.parseQuickAdd("#work ship the thing")
        #expect(result.title == "ship the thing")
        #expect(result.tag == "work")
    }

    @Test("Only the first tag is used")
    func firstTagOnly() {
        let result = TaskList.parseQuickAdd("a #one b #two")
        #expect(result.title == "a b #two")
        #expect(result.tag == "one")
    }

    @Test("A bare # is dropped and yields no tag")
    func bareHash() {
        let result = TaskList.parseQuickAdd("a # b")
        #expect(result.title == "a b")
        #expect(result.tag == nil)
    }

    @Test("The parsed pair feeds add")
    func feedsAdd() throws {
        var list = TaskList()
        let parsed = TaskList.parseQuickAdd("  pay rent  #money ")
        let item = try requireAdded(list.add(title: parsed.title, tag: parsed.tag, now: base))
        #expect(item.title == "pay rent")
        #expect(item.tag == "money")
    }
}
