import Foundation
import Observation
import TasksCore
import WidgetKit

/// The on-device store: everything is held in memory and saved as one JSON file
/// after every change. `CloudSync` keeps it in step with iCloud (SPEC §7, §11).
@Observable
final class Store {
    private(set) var chores: [Chore]
    private(set) var log: [LogEntry]
    /// A local user ID (§3) until the list moves to iCloud, then the iCloud user record ID.
    private(set) var me: UserID
    private(set) var listID: UUID

    /// Refreshed every minute and whenever the app comes to the front, so "today" rolls over at 04:00.
    var now = Date()

    /// Goes up with every saved change, so observers (the digest) know to re-plan.
    private(set) var revision = 0

    /// The most recent action, offered for undo in a banner.
    private(set) var undo: UndoOffer?

    /// Called after a change made on this device, so sync can upload it.
    /// Not called for changes that arrived from iCloud.
    @ObservationIgnored var onChoreSaved: ((_ new: Chore, _ old: Chore?) -> Void)?
    @ObservationIgnored var onEntryAppended: ((LogEntry) -> Void)?

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

    func chore(id: UUID) -> Chore? {
        chores.first { $0.id == id }
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

    // MARK: Changes on this device

    func save(_ chore: Chore) {
        let old = self.chore(id: chore.id)
        upsert(chore)
        persist()
        onChoreSaved?(chore, old)
    }

    func record(_ kind: LogEntry.Kind, _ chore: Chore) {
        let entry = LogEntry.record(kind, for: chore.id, by: me)
        log.append(entry)
        persist()
        onEntryAppended?(entry)
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
        let retraction = LogEntry.record(.retracted, for: entry.choreID, by: me, retracts: entry.id)
        log.append(retraction)
        undo = nil
        persist()
        onEntryAppended?(retraction)
    }

    func undoLast() {
        guard let undo, let entry = log.first(where: { $0.id == undo.entryID }) else { return }
        retract(entry)
    }

    func dismissUndo(_ id: UUID) {
        if undo?.id == id { undo = nil }
    }

    // MARK: Changes from iCloud

    /// Adds or replaces tasks and adds log entries that arrived from iCloud.
    func applyRemote(chores remote: [Chore], entries: [LogEntry]) {
        guard !remote.isEmpty || !entries.isEmpty else { return }
        remote.forEach(upsert)
        var known = Set(log.map(\.id))
        for entry in entries where known.insert(entry.id).inserted {
            log.append(entry)
        }
        persist()
    }

    /// Switches to the iCloud user ID. A local ID (§3) is rewritten everywhere it was used,
    /// because nothing outside this device has seen it.
    func adoptUser(_ user: UserID) {
        guard user != me else { return }
        if me.hasPrefix(Store.localUserPrefix) {
            for index in log.indices where log[index].by == me {
                log[index].by = user
            }
            for index in chores.indices where chores[index].assigneeID == me {
                chores[index].assigneeID = user
            }
        }
        me = user
        persist()
    }

    func setListID(_ id: UUID) {
        listID = id
        persist()
    }

    /// Empties the list: another Apple Account's data, or data the user deleted from iCloud.
    func removeAll() {
        chores = []
        log = []
        undo = nil
        persist()
    }

    private func upsert(_ chore: Chore) {
        if let index = chores.firstIndex(where: { $0.id == chore.id }) {
            chores[index] = chore
        } else {
            chores.append(chore)
        }
    }

    // MARK: Persistence

    private static let localUserPrefix = "local-"

    /// Where this store saves: the shared App Group file, except for the screenshot store.
    @ObservationIgnored private let fileURL: URL

    private init(_ snapshot: StoreSnapshot, fileURL: URL = SharedStore.fileURL) {
        me = snapshot.me
        listID = snapshot.listID
        chores = snapshot.chores
        log = snapshot.log
        self.fileURL = fileURL
    }

    #if DEBUG
    /// Example tasks for App Store screenshots (launch with `-screenshots`). On a real device it
    /// saves to a separate file so the user's list is never touched; in the Simulator it uses
    /// the shared file, so the widgets show the same examples.
    static func demo() -> Store {
        #if targetEnvironment(simulator)
        let url = SharedStore.fileURL
        #else
        let url = URL.temporaryDirectory.appending(path: "demo-store.json")
        #endif
        let store = Store(DemoData.snapshot(today: CalendarDay(containing: .now, in: .current)), fileURL: url)
        store.persist()
        return store
    }
    #endif

    /// Where the list was kept before the widget needed to read it.
    private static var legacyFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "store.json")
    }

    /// Moves the list into the App Group container the first time this version runs.
    private static func moveLegacyFile(to url: URL) {
        let fileManager = FileManager.default
        guard url != legacyFileURL,
              !fileManager.fileExists(atPath: url.path),
              fileManager.fileExists(atPath: legacyFileURL.path)
        else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.moveItem(at: legacyFileURL, to: url)
    }

    static func load() -> Store {
        let url = SharedStore.fileURL
        moveLegacyFile(to: url)
        if let data = try? Data(contentsOf: url) {
            if let snapshot = try? JSONDecoder().decode(StoreSnapshot.self, from: data) {
                return Store(snapshot)
            }
            // Never overwrite a file we can't read: set it aside so nothing is lost.
            let aside = url.deletingLastPathComponent()
                .appending(path: "store-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
        return Store(StoreSnapshot(me: localUserPrefix + UUID().uuidString, listID: UUID(), chores: [], log: []))
    }

    private func persist() {
        revision += 1
        let snapshot = StoreSnapshot(me: me, listID: listID, chores: chores, log: log)
        do {
            let url = fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            print("Couldn't save: \(error)")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
