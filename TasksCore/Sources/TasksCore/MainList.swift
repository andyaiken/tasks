import Foundation

/// One row of the main list.
public struct MainListItem: Hashable, Sendable {
    public let chore: Chore
    public let nextDue: CalendarDay
    public let staleness: Double
    public let band: Band
    /// The assignee if they are a current participant; `nil` means "Anyone" (§8).
    public let assignee: UserID?
}

extension Chore {
    /// The first day from `today` on which the task is on the main list, assuming nothing more
    /// is logged — for "You'll see this again in about three weeks" (§8). `nil` if the task
    /// isn't active, or doesn't appear within `limit` days.
    public func firstDayOnMainList(log: [LogEntry], from today: CalendarDay, limit: Int = 4000) -> CalendarDay? {
        let own = log.filter { $0.choreID == id }
        for offset in 0...limit {
            let day = today.adding(days: offset)
            let state = state(log: own, today: day)
            guard let staleness = state.staleness(on: day) else { return nil }
            if staleness >= MainList.threshold { return day }
        }
        return nil
    }
}

/// The main screen (§5, §8): your tasks first, then everyone else's, each in urgency order.
public struct MainList: Hashable, Sendable {
    public let yours: [MainListItem]
    public let everyoneElse: [MainListItem]
    /// Nobody else has joined: show one list without headings or assignment controls (§8).
    public let isSolo: Bool

    /// The staleness at which a task appears on the main screen (§5).
    public static let threshold = 0.8

    /// - Parameters:
    ///   - me: the viewer.
    ///   - participants: accepted share participants, which may or may not include `me`.
    ///     Empty for a list that isn't shared, or in local-only mode.
    public init(chores: [Chore], log: [LogEntry], today: CalendarDay, me: UserID, participants: Set<UserID>) {
        let logByChore = Dictionary(grouping: log, by: \.choreID)
        let members = participants.union([me])
        let isSolo = members.count == 1

        var yours: [MainListItem] = []
        var everyoneElse: [MainListItem] = []
        for chore in chores {
            let state = chore.state(log: logByChore[chore.id] ?? [], today: today)
            guard case let .active(_, nextDue) = state,
                  let staleness = state.staleness(on: today),
                  staleness >= MainList.threshold
            else { continue }

            let assignee = chore.assigneeID.flatMap { members.contains($0) ? $0 : nil }
            let item = MainListItem(
                chore: chore,
                nextDue: nextDue,
                staleness: staleness,
                band: Band(staleness: staleness),
                assignee: assignee
            )
            if assignee == me || isSolo {
                yours.append(item)
            } else {
                everyoneElse.append(item)
            }
        }

        self.yours = yours.sorted(by: MainList.urgencyOrder)
        self.everyoneElse = everyoneElse.sorted(by: MainList.urgencyOrder)
        self.isSolo = isSolo
    }

    static func urgencyOrder(_ a: MainListItem, _ b: MainListItem) -> Bool {
        if a.staleness != b.staleness { return a.staleness > b.staleness }
        if a.chore.title != b.chore.title { return a.chore.title.localizedStandardCompare(b.chore.title) == .orderedAscending }
        return a.chore.id.uuidString < b.chore.id.uuidString
    }
}
