import SwiftUI
import TasksCore

extension CalendarDay {
    /// Midday on this day in the current time zone, for date pickers and formatting.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// The calendar date a date picker shows — not the 04:00 day of the moment.
    init(date: Date) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// "14 Sep", or "14 Sep 2027" outside the current year.
    var formatted: String {
        let sameYear = year == Calendar.current.component(.year, from: .now)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    var weekdayName: String {
        Calendar.current.weekdaySymbols[weekday - 1]
    }
}

extension Interval.Unit {
    var singularName: String {
        switch self {
        case .days: "day"
        case .weeks: "week"
        case .months: "month"
        case .years: "year"
        }
    }

    var pluralName: String { rawValue }
}

extension Interval {
    /// "every week", "every 2 weeks".
    var phrase: String {
        count == 1 ? "every \(unit.singularName)" : "every \(count) \(unit.pluralName)"
    }
}

extension Chore {
    /// The rhythm in words: "Every week on Monday", "Roughly every 2 weeks", "At some point".
    var rhythmDescription: String {
        guard let interval else {
            if someday { return "At some point" }
            return anchorDate == CalendarDay(containing: .now, in: .current) ? "Today" : "By \(anchorDate.formatted)"
        }
        switch anchorMode {
        case .floating:
            return "Roughly \(interval.phrase)"
        case .fixed:
            let every = interval.phrase.capitalizedFirst
            switch interval.unit {
            case .weeks:
                return "\(every) on \(anchorDate.weekdayName)"
            case .months:
                let ordinal = NumberFormatter.localizedString(from: anchorDate.day as NSNumber, number: .ordinal)
                return "\(every) on the \(ordinal)"
            case .years:
                return "\(every) on \(anchorDate.date.formatted(.dateTime.day().month(.abbreviated)))"
            case .days:
                return "\(every) from \(anchorDate.formatted)"
            }
        }
    }
}

extension LogEntry.Kind {
    var historyLabel: String {
        switch self {
        case .done: "Done"
        case .skipped: "Skipped"
        case .paused: "Paused"
        case .resumed: "Resumed"
        case .deleted: "Deleted"
        case .retracted: "Undone"
        }
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

/// "tomorrow", "in 5 days", "in about 3 weeks".
func reappearance(days: Int) -> String {
    switch days {
    case ...1: "tomorrow"
    case ..<14: "in \(days) days"
    case ..<60: "in about \(Int((Double(days) / 7).rounded())) weeks"
    case ..<730: "in about \(Int((Double(days) / 30.44).rounded())) months"
    default: "in about \(Int((Double(days) / 365.25).rounded())) years"
    }
}
