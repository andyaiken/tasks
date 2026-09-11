import Foundation
import Observation
import TasksCore

/// The local-only store (SPEC §7, §11): everything is held in memory and saved
/// as one JSON file after every change.
@Observable
final class Store {
    private(set) var chores: [Chore]
    private(set) var log: [LogEntry]
    /// The local user ID (§3), replaced by the iCloud user record ID when sharing arrives.
    let me: UserID
    let listID: UUID

    /// Refreshed every minute and whenever the app comes to the front, so "today" rolls over at 04:00.
    var now = Date()

    /// The most recent action, offered for undo in a banner.
    private(set) var undo: UndoOffer?

    struct UndoOffer: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let entryID: UUID
    }

    var today: CalendarDay { CalendarDay(containing: now, in: .current) }

    var mainList: MainList {
        // No sharing yet, so the list is always solo (§8).
        MainList(chores: chores, log: log, today: today, me: me, participants: [])
    }

    func state(of chore: Chore) -> ChoreState {
        chore.state(log: log, today: today)
    }

    /// Counting and pause/resume entries for a task that haven't been undone, newest first.
    func history(of chore: Chore) -> [LogEntry] {
        let retracted = Set(log.compactMap(\.retracts))
        return log
            .filter { $0.choreID == chore.id && $0.kind != .retracted && $0.kind != .deleted && !retracted.contains($0.id) }
            .sorted(by: LogEntry.chronological)
            .reversed()
    }

    func newChore() -> Chore {
        Chore(title: "", createdOn: today, interval: nil, listID: listID)
    }

    // MARK: Changes

    func save(_ chore: Chore) {
        if let index = chores.firstIndex(where: { $0.id == chore.id }) {
            chores[index] = chore
        } else {
            chores.append(chore)
        }
        persist()
    }

    func record(_ kind: LogEntry.Kind, _ chore: Chore) {
        let entry = LogEntry.record(kind, for: chore.id, by: me)
        log.append(entry)
        persist()
        let verb = switch kind {
        case .done: "Done"
        case .skipped: "Skipped"
        case .paused: "Paused"
        case .resumed: "Resumed"
        case .deleted: "Deleted"
        case .retracted: "Undone"
        }
        undo = UndoOffer(message: "\(verb): \(chore.title)", entryID: entry.id)
    }

    func retract(_ entry: LogEntry) {
        log.append(.record(.retracted, for: entry.choreID, by: me, retracts: entry.id))
        undo = nil
        persist()
    }

    func undoLast() {
        guard let undo, let entry = log.first(where: { $0.id == undo.entryID }) else { return }
        retract(entry)
    }

    func dismissUndo(_ id: UUID) {
        if undo?.id == id { undo = nil }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var version = 1
        var me: UserID
        var listID: UUID
        var chores: [Chore]
        var log: [LogEntry]
    }

    private init(_ snapshot: Snapshot) {
        me = snapshot.me
        listID = snapshot.listID
        chores = snapshot.chores
        log = snapshot.log
    }

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "store.json")
    }

    static func load() -> Store {
        let url = fileURL
        if let data = try? Data(contentsOf: url) {
            if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                return Store(snapshot)
            }
            // Never overwrite a file we can't read: set it aside so nothing is lost.
            let aside = url.deletingLastPathComponent()
                .appending(path: "store-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
        return Store(Snapshot(me: "local-\(UUID().uuidString)", listID: UUID(), chores: [], log: []))
    }

    private func persist() {
        let snapshot = Snapshot(me: me, listID: listID, chores: chores, log: log)
        do {
            let url = Store.fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            print("Couldn't save: \(error)")
        }
    }
}
