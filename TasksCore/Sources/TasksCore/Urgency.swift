/// Display bands for staleness (§5). Each includes its lower bound and excludes its upper one.
public enum Band: Int, Comparable, Hashable, Sendable, CaseIterable {
    case notYet, dueSoon, due, late, overdue

    public init(staleness: Double) {
        switch staleness {
        case ..<0.8: self = .notYet
        case ..<1.0: self = .dueSoon
        case ..<1.5: self = .due
        case ..<2.0: self = .late
        default: self = .overdue
        }
    }

    public var name: String {
        switch self {
        case .notYet: "Not yet"
        case .dueSoon: "Due soon"
        case .due: "Due"
        case .late: "Late"
        case .overdue: "Overdue"
        }
    }

    public static func < (lhs: Band, rhs: Band) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
