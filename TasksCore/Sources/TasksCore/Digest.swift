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

    /// The most urgent titles: "Water the plants, Put the bins out and 2 more".
    public var body: String {
        let titles = items.map(\.chore.title)
        switch titles.count {
        case 1: return titles[0]
        case 2: return "\(titles[0]) and \(titles[1])"
        case 3: return "\(titles[0]), \(titles[1]) and \(titles[2])"
        default: return "\(titles[0]), \(titles[1]) and \(titles.count - 2) more"
        }
    }
}

/// The digest for one day ahead.
public struct UpcomingDigest: Hashable, Sendable {
    public let day: CalendarDay
    public let digest: Digest
}

extension Digest {
    /// The digests for `days` days starting with `today`, assuming nothing more is logged (§9,
    /// "Schedule days ahead"). Days with nothing due are left out.
    public static func upcoming(
        chores: [Chore],
        log: [LogEntry],
        me: UserID,
        participants: Set<UserID>,
        from today: CalendarDay,
        days: Int
    ) -> [UpcomingDigest] {
        (0..<days).compactMap { offset in
            let day = today.adding(days: offset)
            let list = MainList(chores: chores, log: log, today: day, me: me, participants: participants)
            return Digest(list: list).map { UpcomingDigest(day: day, digest: $0) }
        }
    }
}
