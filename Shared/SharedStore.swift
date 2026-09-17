import Foundation
import TasksCore

/// Whose list this device is showing (§7).
enum ListSharing: Hashable, Codable {
    /// The user's own list, not shared with anyone (or not yet accepted by anyone).
    case notShared
    /// The user's own list, shared with other people.
    case owner
    /// Someone else's list that the user has joined. `owner` is its owner's user record name.
    case member(owner: UserID)
}

/// The list as saved on disk. Shared by the app, which reads and writes it, and the
/// widget, which only reads it (SPEC §11).
struct StoreSnapshot: Codable {
    var version = 1
    var me: UserID
    var listID: UUID
    var chores: [Chore]
    var log: [LogEntry]
    /// Everyone in a shared list, including the user. Empty for a list that isn't shared.
    var participants: [Participant] = []
    var sharing: ListSharing = .notShared

    init(me: UserID, listID: UUID, chores: [Chore], log: [LogEntry], participants: [Participant] = [], sharing: ListSharing = .notShared) {
        self.me = me
        self.listID = listID
        self.chores = chores
        self.log = log
        self.participants = participants
        self.sharing = sharing
    }

    /// Files saved by 1.0 have no participants or sharing.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        me = try container.decode(UserID.self, forKey: .me)
        listID = try container.decode(UUID.self, forKey: .listID)
        chores = try container.decode([Chore].self, forKey: .chores)
        log = try container.decode([LogEntry].self, forKey: .log)
        participants = try container.decodeIfPresent([Participant].self, forKey: .participants) ?? []
        sharing = try container.decodeIfPresent(ListSharing.self, forKey: .sharing) ?? .notShared
    }

    /// The people tasks can be assigned to: everyone who has accepted (§8).
    var members: Set<UserID> {
        Set(participants.filter(\.isAssignable).compactMap(\.userID))
    }
}

/// Where the list lives: the App Group container, so the widget can read it.
enum SharedStore {
    /// `group.com.andyaiken.tasks`, or the test builds' own group (see project.yml).
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? "group.com.andyaiken.tasks"

    static var fileURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
        return base.appending(path: "Library/Application Support/store.json")
    }

    static func load() -> StoreSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StoreSnapshot.self, from: data)
    }
}
