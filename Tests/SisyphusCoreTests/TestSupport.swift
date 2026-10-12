import Testing

import SisyphusCore

/// Captures the result of a mutating call so it can be checked with `#require`.
///
/// `#require` rewrites its argument into a closure over an immutable copy, so it cannot wrap a
/// `mutating` method such as `TaskList.add`. Call the method first, then pass the result here.
func requireAdded(_ item: TaskItem?) throws -> TaskItem {
    try #require(item)
}
