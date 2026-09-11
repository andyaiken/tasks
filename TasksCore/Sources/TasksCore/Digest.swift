/// A person's daily digest (§9): their own tasks that are Due or worse.
public struct Digest: Hashable, Sendable {
    public let items: [MainListItem]

    public var overdueCount: Int {
        items.count { $0.band == .overdue }
    }

    /// The staleness at which a task enters the digest (§9).
    public static let threshold = 1.0

    /// `nil` when there is nothing to send. Build `list` with a future `today`
    /// to compute the digests for the days ahead.
    public init?(list: MainList) {
        let items = list.yours.filter { $0.staleness >= Digest.threshold }
        guard !items.isEmpty else { return nil }
        self.items = items
    }

    /// "4 tasks for you today, 1 overdue."
    public var summary: String {
        let tasks = items.count == 1 ? "1 task" : "\(items.count) tasks"
        return overdueCount == 0
            ? "\(tasks) for you today."
            : "\(tasks) for you today, \(overdueCount) overdue."
    }
}
