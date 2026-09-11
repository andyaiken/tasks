import Foundation

/// A calendar date with no time and no time zone — the unit of scheduling (§4).
/// Stored as a `YYYY-MM-DD` string (§3).
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        precondition((1...12).contains(month), "month out of range")
        precondition((1...CalendarDay.daysInMonth(year: year, month: month)).contains(day), "day out of range")
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m),
              (1...CalendarDay.daysInMonth(year: y, month: m)).contains(d)
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: Day arithmetic

    /// Days since 1970-01-01 (proleptic Gregorian). Algorithm from
    /// Howard Hinnant's "chrono-compatible low-level date algorithms".
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(ordinal: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`'s numbering.
    public var weekday: Int {
        let mod = (ordinal + 4) % 7 // 1970-01-01 was a Thursday.
        return (mod < 0 ? mod + 7 : mod) + 1
    }

    public func adding(days: Int) -> CalendarDay {
        CalendarDay(ordinal: ordinal + days)
    }

    /// Adds calendar months, clamping to the last day of the target month
    /// (Jan 31 + 1 month = Feb 28 or 29).
    public func adding(months: Int) -> CalendarDay {
        let total = year * 12 + (month - 1) + months
        let y = floorDiv(total, 12)
        let m = total - y * 12 + 1
        return CalendarDay(year: y, month: m, day: min(day, CalendarDay.daysInMonth(year: y, month: m)))
    }

    /// Whole days from `rhs` to `lhs`.
    public static func - (lhs: CalendarDay, rhs: CalendarDay) -> Int {
        lhs.ordinal - rhs.ordinal
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: The 04:00 day

    /// The hour at which one day ends and the next begins (§4).
    public static let dayStartHour = 4

    /// The 04:00-to-04:00 day containing `instant` in `timeZone` (§4).
    /// Works from local wall-clock time, so DST changes can't move the boundary.
    public init(containing instant: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: instant)
        let local = CalendarDay(year: c.year!, month: c.month!, day: c.day!)
        self = c.hour! < CalendarDay.dayStartHour ? local.adding(days: -1) : local
    }
}

extension CalendarDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = CalendarDay(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(string)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Division rounding towards negative infinity.
func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}
