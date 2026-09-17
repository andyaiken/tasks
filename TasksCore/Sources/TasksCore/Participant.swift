import Foundation

/// Someone in a shared list: the owner, or a person they invited (§7, §8).
/// Built from the list's CKShare; kept free of CloudKit types so it can be tested and saved.
public struct Participant: Hashable, Sendable, Codable, Identifiable {
    public enum Status: String, Hashable, Sendable, Codable {
        /// Invited but hasn't accepted, so there's no user record ID to assign tasks to.
        case invited
        case joined
    }

    /// CloudKit's participant ID, stable for as long as they're in the share.
    public var id: String
    /// Their iCloud user record name. `nil` until they accept.
    public var userID: UserID?
    public var givenName: String?
    public var familyName: String?
    /// The address they were invited with, when this device can see it (§8).
    public var email: String?
    public var phone: String?
    public var isOwner: Bool
    public var status: Status

    public init(
        id: String,
        userID: UserID?,
        givenName: String? = nil,
        familyName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        isOwner: Bool = false,
        status: Status
    ) {
        self.id = id
        self.userID = userID
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.phone = phone
        self.isOwner = isOwner
        self.status = status
    }

    /// Whether tasks can be assigned to them (§8: only accepted participants).
    public var isAssignable: Bool { status == .joined && userID != nil }
}

extension Participant {
    /// Each participant's label, by participant ID (§8), in order of preference: their Apple
    /// Account first name (or full name), the viewer's contact name for them (first, or full),
    /// a monogram from their email address, or "User". Two people who'd both be "Sam" get
    /// their family initial: "Sam K.", "Sam T.".
    ///
    /// - Parameter contactNames: names from the viewer's own Contacts, by participant ID.
    public static func labels(
        for participants: [Participant],
        contactNames: [String: PersonNameComponents] = [:]
    ) -> [String: String] {
        struct Name { var first: String; var family: String? }

        var names: [String: Name] = [:]
        var labels: [String: String] = [:]
        for participant in participants {
            let account = PersonNameComponents(givenName: participant.givenName, familyName: participant.familyName)
            if let name = Self.name(from: account) ?? contactNames[participant.id].flatMap(Self.name(from:)) {
                names[participant.id] = Name(first: name.first, family: name.family)
            } else if let initial = participant.email?.trimmingCharacters(in: .whitespaces).first {
                labels[participant.id] = String(initial).uppercased()
            } else {
                labels[participant.id] = "User"
            }
        }

        let counts = Dictionary(grouping: names.values, by: { $0.first.lowercased() }).mapValues(\.count)
        for (id, name) in names {
            if counts[name.first.lowercased()]! > 1, let initial = name.family?.first {
                labels[id] = "\(name.first) \(initial)."
            } else {
                labels[id] = name.first
            }
        }
        return labels
    }

    /// The first name, or the full name if there isn't one; `nil` if there's neither.
    private static func name(from components: PersonNameComponents) -> (first: String, family: String?)? {
        let given = components.givenName.flatMap(nonEmpty)
        let family = components.familyName.flatMap(nonEmpty)
        if let given { return (given, family) }
        if let family { return (family, nil) }
        return nil
    }

    private static func nonEmpty(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
