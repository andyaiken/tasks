import Foundation

/// Where a task stands on a given day, derived entirely from the task and its log (§3–§6).
public enum ChoreState: Hashable, Sendable {
    case active(cycleStart: CalendarDay, nextDue: CalendarDay)
    case paused
    /// A one-off that has been done or skipped.
    case completed
    case deleted

    /// How far through its cycle the task is on `today` (§5). `nil` unless active.
    public func staleness(on today: CalendarDay) -> Double? {
        guard case let .active(cycleStart, nextDue) = self else { return nil }
        return Double(today - cycleStart) / Double(max(1, nextDue - cycleStart))
    }
}

extension Chore {
    /// Derives the task's state on `today` from `log`. Entries for other tasks are ignored.
    public func state(log: [LogEntry], today: CalendarDay) -> ChoreState {
        let own = log.filter { $0.choreID == id }
        let retracted = Set(own.filter { $0.kind == .retracted }.compactMap(\.retracts))
        let effective = own
            .filter { $0.kind != .retracted && !retracted.contains($0.id) }
            .sorted(by: LogEntry.chronological)

        if effective.contains(where: { $0.kind == .deleted }) {
            return .deleted
        }
        let counting = effective.filter(\.counts)
        if isOneOff && !counting.isEmpty {
            return .completed
        }
        if effective.last(where: { $0.kind == .paused || $0.kind == .resumed })?.kind == .paused {
            return .paused
        }

        let lastResume = effective.last(where: { $0.kind == .resumed })?.day
        // Occurrences before this day don't count (§4).
        let floor = max(createdOn, lastResume ?? createdOn)

        guard let interval else {
            if someday {
                return .active(cycleStart: floor, nextDue: floor.adding(Chore.somedayHorizon))
            }
            return .active(cycleStart: min(floor, anchorDate.adding(days: -1)), nextDue: anchorDate)
        }

        switch anchorMode {
        case .floating:
            var start = anchorDate
            if let lastResume { start = max(start, lastResume) }
            if let lastDone = counting.last?.day { start = max(start, lastDone) }
            return .active(cycleStart: start, nextDue: start.adding(interval))

        case .fixed:
            let schedule = FixedSchedule(anchor: anchorDate, interval: interval)
            let firstIndex = schedule.latestIndex(onOrBefore: floor.adding(days: -1)) + 1
            let entries = counting.filter { lastResume == nil || $0.day >= lastResume! }

            let next: Int
            switch backlogPolicy {
            case .debt:
                // Each entry pays off the oldest unsatisfied occurrence (§6).
                next = firstIndex + entries.count

            case .skip:
                var lastSatisfied = firstIndex - 1
                for entry in entries {
                    var i = schedule.latestIndex(onOrBefore: entry.day)
                    // The night before counts for the next day (§6).
                    if interval.spansAtLeastTwoDays && schedule.occurrence(i + 1) == entry.day.adding(days: 1) {
                        i += 1
                    }
                    lastSatisfied = max(lastSatisfied, max(i, firstIndex))
                }
                let latestPast = schedule.latestIndex(onOrBefore: today)
                next = latestPast > lastSatisfied ? latestPast : lastSatisfied + 1
            }
            return .active(cycleStart: schedule.occurrence(next - 1), nextDue: schedule.occurrence(next))
        }
    }
}

/// Occurrences of a fixed task: `anchor + k × interval` for any integer k (§4).
struct FixedSchedule {
    let anchor: CalendarDay
    let interval: Interval

    func occurrence(_ k: Int) -> CalendarDay {
        anchor.adding(interval, times: k)
    }

    /// The largest k with `occurrence(k) <= day`.
    func latestIndex(onOrBefore day: CalendarDay) -> Int {
        var k: Int
        switch interval.unit {
        case .days: k = floorDiv(day - anchor, interval.count)
        case .weeks: k = floorDiv(day - anchor, 7 * interval.count)
        case .months, .years:
            let months = (day.year - anchor.year) * 12 + (day.month - anchor.month)
            k = floorDiv(months, interval.count * (interval.unit == .years ? 12 : 1))
        }
        // The estimate can be one off either way because of month-end clamping.
        while occurrence(k) > day { k -= 1 }
        while occurrence(k + 1) <= day { k += 1 }
        return k
    }
}
