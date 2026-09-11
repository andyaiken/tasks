import CloudKit
import Foundation
import Observation
import os
import TasksCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let logger = Logger(subsystem: "com.andyaiken.tasks", category: "sync")

/// What sync needs to remember between launches, kept next to the store.
struct SyncState: Codable {
    /// CKSyncEngine's own bookkeeping.
    var engine: CKSyncEngine.State.Serialization?
    /// The last-known server system fields (change tag etc.) of each record, by record name.
    var systemFields: [String: Data] = [:]
    /// Task fields changed on this device that iCloud hasn't confirmed, by record name.
    /// These win when merging with another device's edit to the same task (§7).
    var dirtyFields: [String: Set<ChoreField>] = [:]
    /// Whether this device's list has been merged into iCloud (§7).
    var merged = false
    /// Whether the zone is known to have a List record.
    var hasListRecord = false
    /// The iCloud user this state belongs to.
    var userRecordName: String?
}

/// Keeps the list in step with the user's own iCloud, across their devices (SPEC §7, §11).
@Observable
final class CloudSync {
    static let containerIdentifier = "iCloud.com.andyaiken.tasks"
    static let zoneID = CKRecordZone.ID(zoneName: "List", ownerName: CKCurrentUserDefaultName)

    private(set) var status = "Checking iCloud…"

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let container = CKContainer(identifier: CloudSync.containerIdentifier)
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var starting = false
    /// Off for the screenshot store, which must never reach iCloud or touch the real sync state.
    @ObservationIgnored private let enabled: Bool

    private static let onStatus = "On. Your list syncs across your devices."
    private static let offStatus = "Not signed into iCloud, so this list is only on this device."

    init(store: Store, enabled: Bool = true) {
        self.store = store
        self.enabled = enabled
        guard enabled else {
            state = SyncState()
            status = "Off while taking screenshots."
            return
        }
        state = Self.loadState()
        store.onChoreSaved = { [weak self] new, old in self?.choreSaved(new, old: old) }
        store.onEntryAppended = { [weak self] entry in self?.entryAppended(entry) }
    }

    // MARK: Starting and stopping

    /// Starts syncing if iCloud is available. Safe to call again whenever the account may have changed.
    func start() async {
        guard enabled, !starting else { return }
        starting = true
        defer { starting = false }

        do {
            logger.log("Starting sync")
            let accountStatus = try await container.accountStatus()
            logger.log("iCloud account status: \(Self.describe(accountStatus), privacy: .public)")
            guard accountStatus == .available else {
                stop()
                status = accountStatus == .temporarilyUnavailable
                    ? "iCloud is temporarily unavailable. Changes will sync later."
                    : Self.offStatus
                return
            }
            let user = try await container.userRecordID().recordName
            logger.log("Got iCloud user record ID")
            if let previous = state.userRecordName, previous != user {
                // A different Apple Account: this device's copy belongs to the old one,
                // which still has it in iCloud.
                logger.log("iCloud account changed; removing the previous account's list from this device")
                stop()
                store.removeAll()
                state = SyncState()
            }
            state.userRecordName = user
            saveState()

            if engine == nil { startEngine() }
            if !state.merged { try await mergeIntoCloud(user: user) }
            status = Self.onStatus
            // Catch up straight away on launch: pushes sent while the app wasn't running
            // aren't delivered, and the app starts out active, so the come-to-the-front
            // check in ContentView doesn't fire until it's been in the background once.
            await fetchNow()
        } catch {
            logger.error("Couldn't start sync: \(error, privacy: .public)")
            status = "Can't reach iCloud right now. Changes will sync later."
        }
    }

    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: "available"
        case .noAccount: "no account"
        case .restricted: "restricted"
        case .couldNotDetermine: "could not determine"
        case .temporarilyUnavailable: "temporarily unavailable"
        @unknown default: "unknown (\(status.rawValue))"
        }
    }

    /// Checks iCloud for changes now. The silent pushes that normally trigger a fetch are
    /// delivered at the system's discretion and can be late or dropped (§12.4), so the app
    /// also calls this when it comes to the front and once a minute while it's open.
    func fetchNow() async {
        guard let engine, state.merged else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            logger.error("Couldn't fetch changes: \(error, privacy: .public)")
        }
    }

    private func startEngine() {
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state.engine,
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Stops syncing but keeps the list on this device. Unconfirmed task edits are kept,
    /// so they still win when the list merges again at the next sign-in.
    private func stop() {
        guard engine != nil || state.userRecordName != nil else { return }
        engine = nil
        state.engine = nil
        state.systemFields = [:]
        state.merged = false
        state.hasListRecord = false
        state.userRecordName = nil
        saveState()
    }

    /// Moves this device's list into iCloud, merging with whatever the user's other
    /// devices already put there (§7: merged automatically).
    private func mergeIntoCloud(user: UserID) async throws {
        guard let engine else { return }
        status = "Merging with iCloud…"

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        try await engine.sendChanges()
        // Other devices' tasks, and the list's ID if one exists.
        try await engine.fetchChanges()

        store.adoptUser(user)

        // Upload what iCloud doesn't have yet, plus edits made here while signed out.
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for chore in store.chores {
            let id = RecordRef.chore(chore.id).recordID
            if state.systemFields[id.recordName] == nil || state.dirtyFields[id.recordName]?.isEmpty == false {
                changes.append(.saveRecord(id))
            }
        }
        for entry in store.log {
            let id = RecordRef.entry(entry.id).recordID
            if state.systemFields[id.recordName] == nil { changes.append(.saveRecord(id)) }
        }
        if !state.hasListRecord { changes.append(.saveRecord(RecordRef.list.recordID)) }
        engine.state.add(pendingRecordZoneChanges: changes)

        state.merged = true
        saveState()
        logger.log("Merged into iCloud; uploading \(changes.count) records")
        try await engine.sendChanges()
    }

    // MARK: Local changes

    private func choreSaved(_ chore: Chore, old: Chore?) {
        let fields = old.map { chore.changedFields(from: $0) } ?? Set(ChoreField.allCases)
        guard !fields.isEmpty else { return }
        let id = RecordRef.chore(chore.id).recordID
        state.dirtyFields[id.recordName, default: []].formUnion(fields)
        saveState()
        if state.merged { engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)]) }
    }

    private func entryAppended(_ entry: LogEntry) {
        if state.merged { engine?.state.add(pendingRecordZoneChanges: [.saveRecord(RecordRef.entry(entry.id).recordID)]) }
    }

    // MARK: Changes from iCloud

    private func applyFetched(_ records: [CKRecord]) {
        var chores: [Chore] = []
        var entries: [LogEntry] = []
        for record in records {
            guard let ref = RecordRef(record.recordID) else { continue }
            switch ref {
            case .chore:
                if let chore = Chore(record: record) { chores.append(keepingDirtyFields(chore)) }
            case .entry:
                if let entry = LogEntry(record: record) { entries.append(entry) }
            case .list:
                state.hasListRecord = true
                if let id = (record["listID"] as? String).flatMap(UUID.init(uuidString:)) { adoptList(id) }
            }
            saveSystemFields(of: record)
        }
        store.applyRemote(chores: chores, entries: entries)
        saveState()
    }

    /// The iCloud copy of a task, with this device's unconfirmed edits on top.
    private func keepingDirtyFields(_ remote: Chore) -> Chore {
        let name = RecordRef.chore(remote.id).recordID.recordName
        guard let dirty = state.dirtyFields[name], !dirty.isEmpty, let local = store.chore(id: remote.id) else { return remote }
        var merged = remote
        for field in dirty { merged.take(field, from: local) }
        return merged
    }

    /// Another device created the list first: move this device's tasks onto its ID.
    private func adoptList(_ id: UUID) {
        guard id != store.listID else { return }
        store.setListID(id)
        for chore in store.chores where chore.listID != id {
            var moved = chore
            moved.listID = id
            store.save(moved)
        }
    }

    private func zoneDeleted(purged: Bool) {
        state.systemFields = [:]
        state.hasListRecord = false
        state.merged = false
        if purged {
            // The user deleted Tasks' data from iCloud in Settings, which deletes it from every device.
            logger.log("iCloud data was deleted by the user; removing it here too")
            store.removeAll()
            state.dirtyFields = [:]
        } else {
            logger.log("iCloud zone was deleted; uploading this device's list again")
        }
        saveState()
        Task { await start() }
    }

    // MARK: Sending

    private func record(for id: CKRecord.ID) -> CKRecord? {
        guard let ref = RecordRef(id) else { return nil }
        let record = cachedRecord(id) ?? CKRecord(recordType: ref.recordType, recordID: id)
        switch ref {
        case .chore(let uuid):
            guard let chore = store.chore(id: uuid) else { return nil }
            for field in ChoreField.allCases { chore.write(field, to: record) }
        case .entry(let uuid):
            guard let entry = store.log.first(where: { $0.id == uuid }) else { return nil }
            entry.write(to: record)
        case .list:
            record["listID"] = store.listID.uuidString
        }
        return record
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        for record in sent.savedRecords {
            saveSystemFields(of: record)
            state.dirtyFields[record.recordID.recordName] = nil
            if RecordRef(record.recordID) == .list { state.hasListRecord = true }
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord, resolveConflict(with: server) {
                    retry.append(.saveRecord(id))
                }
            case .zoneNotFound:
                needsZone = true
                retry.append(.saveRecord(id))
            case .unknownItem:
                state.systemFields[id.recordName] = nil
                retry.append(.saveRecord(id))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break // CKSyncEngine retries these itself.
            default:
                logger.error("Couldn't save \(id.recordName, privacy: .public): \(failure.error, privacy: .public)")
                status = "iCloud couldn't save a change: \(failure.error.localizedDescription)"
            }
        }
        if needsZone { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))]) }
        engine.state.add(pendingRecordZoneChanges: retry)
        saveState()
    }

    /// Takes a newer iCloud copy after a failed save. Returns whether to save again.
    private func resolveConflict(with server: CKRecord) -> Bool {
        saveSystemFields(of: server)
        switch RecordRef(server.recordID) {
        case .chore:
            guard let remote = Chore(record: server) else { return false }
            let dirty = state.dirtyFields[server.recordID.recordName] ?? []
            store.applyRemote(chores: [keepingDirtyFields(remote)], entries: [])
            return !dirty.isEmpty
        case .entry:
            // Entries never change, so iCloud's copy is this one.
            if let entry = LogEntry(record: server) { store.applyRemote(chores: [], entries: [entry]) }
            return false
        case .list:
            // Two devices created the list at once; theirs won.
            state.hasListRecord = true
            if let id = (server["listID"] as? String).flatMap(UUID.init(uuidString:)) { adoptList(id) }
            return false
        case nil:
            return false
        }
    }

    // MARK: Account changes

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            Task { await start() }
        case .signOut:
            stop()
            status = Self.offStatus
        case .switchAccounts:
            stop()
            store.removeAll()
            state = SyncState()
            saveState()
            Task { await start() }
        @unknown default:
            break
        }
    }

    // MARK: System fields

    private func saveSystemFields(of record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        state.systemFields[record.recordID.recordName] = coder.encodedData
    }

    private func cachedRecord(_ id: CKRecord.ID) -> CKRecord? {
        guard let data = state.systemFields[id.recordName],
              let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Persistence

    private static var stateURL: URL {
        URL.applicationSupportDirectory.appending(path: "sync.json")
    }

    private static func loadState() -> SyncState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SyncState.self, from: data)
        else { return SyncState() }
        return state
    }

    private func saveState() {
        do {
            let url = Self.stateURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            logger.error("Couldn't save sync state: \(error, privacy: .public)")
        }
    }
}

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            state.engine = update.stateSerialization
            saveState()
        case .accountChange(let change):
            accountChanged(change)
        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID.zoneName == Self.zoneID.zoneName {
                zoneDeleted(purged: deletion.reason == .purged)
            }
        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes.modifications.map(\.record))
        case .sentRecordZoneChanges(let sent):
            handleSent(sent, engine: syncEngine)
        case .didFetchChanges, .didSendChanges:
            if state.merged { status = Self.onStatus }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.record(for: id)
        }
    }
}
