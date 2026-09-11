import Foundation
import TasksCore

/// The list as saved on disk. Shared by the app, which reads and writes it, and the
/// widget, which only reads it (SPEC §11).
struct StoreSnapshot: Codable {
    var version = 1
    var me: UserID
    var listID: UUID
    var chores: [Chore]
    var log: [LogEntry]
}

/// Where the list lives: the App Group container, so the widget can read it.
enum SharedStore {
    static let appGroup = "group.com.andyaiken.tasks"

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
