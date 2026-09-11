import Foundation

/// A CloudKit user record name — never the `__defaultOwner__` placeholder (§8),
/// or, in local-only mode, a locally generated ID (§3).
public typealias UserID = String

/// A repeat rhythm: a count and a unit (§3).
public struct Interval: Hashable, Sendable, Codable {
    public enum Unit: String, Hashable, Sendable, Codable, CaseIterable {
        case days, weeks, months, years
    }

    public var count: Int
    public var unit: Unit

    public init(_ count: Int, _ unit: Unit) {
        precondition(count >= 1, "interval count must be at least 1")
        self.count = count
        self.unit = unit
    }

    /// Whether the interval is at least two days, which enables the
    /// "night before" rule for skip-policy tasks (§6).
    var spansAtLeastTwoDays: Bool {
        unit != .days || count >= 2
    }
}

extension CalendarDay {
    /// `self + k × interval`, computed in one step from `self` so months don't drift (§4).
    public func adding(_ interval: Interval, times k: Int = 1) -> CalendarDay {
        switch interval.unit {
        case .days: adding(days: interval.count * k)
        case .weeks: adding(days: 7 * interval.count * k)
        case .months: adding(months: interval.count * k)
        case .years: adding(months: 12 * interval.count * k)
        }
    }
}

public enum AnchorMode: String, Hashable, Sendable, Codable {
    case floating, fixed
}

public enum BacklogPolicy: String, Hashable, Sendable, Codable {
    case skip, debt
}

/// A task (§3). Called `Chore` in code because Swift already has a `Task` type.
public struct Chore: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var createdOn: CalendarDay
    /// `nil` for a one-off.
    public var interval: Interval?
    public var anchorMode: AnchorMode
    public var anchorDate: CalendarDay
    public var backlogPolicy: BacklogPolicy
    /// An "at some point" one-off: no due date (§4). Ignored for repeating tasks.
    public var someday: Bool
    public var assigneeID: UserID?
    public var listID: UUID

    /// An "at some point" one-off is ranked as if due this long after it was added (§4).
    public static let somedayHorizon = Interval(4, .weeks)

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        createdOn: CalendarDay,
        interval: Interval?,
        anchorMode: AnchorMode = .floating,
        anchorDate: CalendarDay? = nil,
        backlogPolicy: BacklogPolicy = .skip,
        someday: Bool = false,
        assigneeID: UserID? = nil,
        listID: UUID
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdOn = createdOn
        self.interval = interval
        self.anchorMode = anchorMode
        self.anchorDate = anchorDate ?? createdOn
        self.backlogPolicy = backlogPolicy
        self.someday = someday
        self.assigneeID = assigneeID
        self.listID = listID
    }

    public var isOneOff: Bool { interval == nil }
}

/// An append-only log entry (§3).
public struct LogEntry: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case done, skipped, paused, resumed, deleted, retracted
    }

    public var id: UUID
    public var choreID: UUID
    public var kind: Kind
    /// When it was recorded.
    public var at: Date
    /// The day it belongs to, fixed by the recording device (§4).
    public var day: CalendarDay
    public var by: UserID
    /// The entry this one undoes; `retracted` entries only.
    public var retracts: UUID?
    public var note: String?

    public init(
        id: UUID = UUID(),
        choreID: UUID,
        kind: Kind,
        at: Date,
        day: CalendarDay,
        by: UserID,
        retracts: UUID? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.choreID = choreID
        self.kind = kind
        self.at = at
        self.day = day
        self.by = by
        self.retracts = retracts
        self.note = note
    }

    /// Creates an entry for "now", working out its day from the device's time zone (§4).
    public static func record(
        _ kind: Kind,
        for choreID: UUID,
        by user: UserID,
        at instant: Date = Date(),
        in timeZone: TimeZone = .current,
        retracts: UUID? = nil,
        note: String? = nil
    ) -> LogEntry {
        LogEntry(
            choreID: choreID,
            kind: kind,
            at: instant,
            day: CalendarDay(containing: instant, in: timeZone),
            by: user,
            retracts: retracts,
            note: note
        )
    }

    /// Whether this entry satisfies an occurrence (§4).
    var counts: Bool { kind == .done || kind == .skipped }

    /// The canonical order: day, then time recorded, then id (§3).
    public static func chronological(_ a: LogEntry, _ b: LogEntry) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.at != b.at { return a.at < b.at }
        return a.id.uuidString < b.id.uuidString
    }
}
