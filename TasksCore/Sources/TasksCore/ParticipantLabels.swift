/// What the share tells us about a participant (§8).
public struct ParticipantIdentity: Hashable, Sendable {
    public var userID: UserID
    public var givenName: String?
    public var familyName: String?
    /// The formatted full name, if the identity has one.
    public var fullName: String?
    public var email: String?

    public init(userID: UserID, givenName: String? = nil, familyName: String? = nil, fullName: String? = nil, email: String? = nil) {
        self.userID = userID
        self.givenName = givenName
        self.familyName = familyName
        self.fullName = fullName
        self.email = email
    }
}

/// The name on the viewer's own contact card for a participant (§8).
public struct ContactName: Hashable, Sendable {
    public var givenName: String?
    public var familyName: String?
    public var fullName: String?

    public init(givenName: String? = nil, familyName: String? = nil, fullName: String? = nil) {
        self.givenName = givenName
        self.familyName = familyName
        self.fullName = fullName
    }
}

/// Builds each participant's label (§8): Apple Account name, else contact name,
/// else a monogram from their email, else "User". Participants who share a first
/// name get their family initial ("Sam K.").
public func participantLabels(
    _ participants: [ParticipantIdentity],
    contacts: [UserID: ContactName]
) -> [UserID: String] {
    struct Candidate {
        var label: String
        var familyName: String?
        var isName: Bool
    }

    func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    var candidates: [UserID: Candidate] = [:]
    for p in participants {
        if let name = nonEmpty(p.givenName) ?? nonEmpty(p.fullName) {
            candidates[p.userID] = Candidate(label: name, familyName: nonEmpty(p.familyName), isName: true)
        } else if let c = contacts[p.userID], let name = nonEmpty(c.givenName) ?? nonEmpty(c.fullName) {
            candidates[p.userID] = Candidate(label: name, familyName: nonEmpty(c.familyName), isName: true)
        } else if let first = nonEmpty(p.email)?.first {
            candidates[p.userID] = Candidate(label: String(first).uppercased(), familyName: nil, isName: false)
        } else {
            candidates[p.userID] = Candidate(label: "User", familyName: nil, isName: false)
        }
    }

    let nameCounts = Dictionary(grouping: candidates.values.filter(\.isName), by: { $0.label.lowercased() })
        .mapValues(\.count)

    return candidates.mapValues { c in
        guard c.isName, nameCounts[c.label.lowercased(), default: 0] > 1,
              let initial = c.familyName?.first
        else { return c.label }
        return "\(c.label) \(String(initial).uppercased())."
    }
}
