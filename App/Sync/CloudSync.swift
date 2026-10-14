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

/// Which of the user's iCloud databases a sync engine works on (§7).
enum SyncScope: String, Codable, CaseIterable {
    /// The private database, holding the user's own list, whether it's shared or not.
    case own
    /// The shared database, holding a list someone else owns that the user has joined.
    case shared

    var path: WritableKeyPath<SyncState, DatabaseState> {
        switch self {
        case .own: \.own
        case .shared: \.shared
        }
    }
}

/// What sync remembers about one database.
struct DatabaseState: Codable {
    /// CKSyncEngine's own bookkeeping.
    var engine: CKSyncEngine.State.Serialization?
    /// The last-known server system fields (change tag etc.) of each record, by record name.
    var systemFields: [String: Data] = [:]
    /// Task fields changed on this device that iCloud hasn't confirmed, by record name.
    /// These win when merging with another device's edit to the same task (§7).
    var dirtyFields: [String: Set<ChoreField>] = [:]
    /// Whether the list's zone is known to have a List record.
    var hasListRecord = false
}

/// What sync needs to remember between launches, kept next to the store.
struct SyncState: Codable {
    /// The iCloud user this state belongs to.
    var userRecordName: String?
    /// Whether this device's own list has been merged into iCloud (§7).
    var merged = false
    /// The owner of the shared list the user has joined, or `nil` when they're using their own (§7).
    var joinedOwner: UserID?
    var own = DatabaseState()
    var shared = DatabaseState()

    init() {}

    enum CodingKeys: String, CodingKey {
        case userRecordName, merged, joinedOwner, own, shared
    }

    /// Version 1.0 had one database, saved at the top level.
    private enum LegacyKeys: String, CodingKey {
        case engine, systemFields, dirtyFields, hasListRecord
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userRecordName = try container.decodeIfPresent(String.self, forKey: .userRecordName)
        merged = try container.decodeIfPresent(Bool.self, forKey: .merged) ?? false
        joinedOwner = try container.decodeIfPresent(UserID.self, forKey: .joinedOwner)
        shared = try container.decodeIfPresent(DatabaseState.self, forKey: .shared) ?? DatabaseState()
        if let own = try container.decodeIfPresent(DatabaseState.self, forKey: .own) {
            self.own = own
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            own.engine = try legacy.decodeIfPresent(CKSyncEngine.State.Serialization.self, forKey: .engine)
            own.systemFields = try legacy.decodeIfPresent([String: Data].self, forKey: .systemFields) ?? [:]
            own.dirtyFields = try legacy.decodeIfPresent([String: Set<ChoreField>].self, forKey: .dirtyFields) ?? [:]
            own.hasListRecord = try legacy.decodeIfPresent(Bool.self, forKey: .hasListRecord) ?? false
        }
    }
}

/// An invitation to someone else's list, waiting for the user to decide (§7, §13).
struct Invitation: Identifiable {
    let id = UUID()
    let metadata: CKShare.Metadata
    /// What to call the list's owner.
    let ownerName: String
    /// Tasks in the user's own list that could come along; 0 if there's no choice to make.
    let taskCount: Int
    /// The owner of a list the user would leave by joining this one.
    let leaving: String?
    /// Why the user can't join, if they can't.
    let blocked: String?
}

/// Keeps the list in step with iCloud: the user's own list across their devices, and a
/// shared list between the people in it (SPEC §7, §11).
@Observable
final class CloudSync {
    static let containerIdentifier = "iCloud.com.andyaiken.tasks"
    static let listZoneName = "List"
    static let ownZoneID = CKRecordZone.ID(zoneName: listZoneName, ownerName: CKCurrentUserDefaultName)

    private(set) var status = "Checking iCloud…"
    /// Signed in and synced, so the list can be shared.
    private(set) var isSignedIn = false
    /// An invitation the user has opened, waiting for them to confirm.
    var invitation: Invitation?
    /// Something to tell the user, such as that they've lost access to a list.
    var notice: String?

    @ObservationIgnored let container = CKContainer(identifier: CloudSync.containerIdentifier)
    @ObservationIgnored private let store: Store
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var ownEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    @ObservationIgnored private var starting = false
    /// Whether this launch has found out if iCloud is available.
    @ObservationIgnored private var checkedAccount = false
    /// An invitation that arrived before sync had started, e.g. one that launched the app.
    @ObservationIgnored private var waitingInvitation: CKShare.Metadata?
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

    // MARK: Which list

    /// The database holding the list the user is using.
    private var activeScope: SyncScope { state.joinedOwner == nil ? .own : .shared }

    /// The zone holding the list in `scope`'s database, if that's the list in use.
    private func activeZone(_ scope: SyncScope) -> CKRecordZone.ID? {
        switch scope {
        case .own: state.joinedOwner == nil ? Self.ownZoneID : nil
        case .shared: state.joinedOwner.map { CKRecordZone.ID(zoneName: Self.listZoneName, ownerName: $0) }
        }
    }

    private func engine(_ scope: SyncScope) -> CKSyncEngine? {
        scope == .own ? ownEngine : sharedEngine
    }

    private func scope(of syncEngine: CKSyncEngine) -> SyncScope? {
        if syncEngine === ownEngine { return .own }
        if syncEngine === sharedEngine { return .shared }
        return nil // An engine replaced when the user joined or left a list.
    }

    /// Whether changes in `scope` are uploaded yet: the user's own list waits for its first merge (§7).
    private func isUploading(_ scope: SyncScope) -> Bool {
        engine(scope) != nil && (scope == .shared || state.merged)
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
                checkedAccount = true
                status = accountStatus == .temporarilyUnavailable
                    ? "iCloud is temporarily unavailable. Changes will sync later."
                    : Self.offStatus
                if waitingInvitation != nil {
                    waitingInvitation = nil
                    notice = "Sign into iCloud on this device to join a shared list."
                }
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
                store.setSharing(.notShared, participants: [])
                state = SyncState()
            }
            state.userRecordName = user
            saveState()

            if ownEngine == nil { ownEngine = makeEngine(.own) }
            if sharedEngine == nil { sharedEngine = makeEngine(.shared) }
            registerForPushes()
            if state.joinedOwner == nil, !state.merged { try await mergeIntoCloud(user: user) }
            store.adoptUser(user)
            status = Self.onStatus
            isSignedIn = true
            checkedAccount = true
            // Catch up straight away on launch: pushes sent while the app wasn't running
            // aren't delivered, and the app starts out active, so the come-to-the-front
            // check in ContentView doesn't fire until it's been in the background once.
            await fetchNow()
            if let metadata = waitingInvitation {
                waitingInvitation = nil
                received(metadata)
            }
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
        // The shared database first: it's where a newly joined list turns up.
        for scope in [SyncScope.shared, .own] {
            guard let engine = engine(scope), scope == .shared || state.merged || state.joinedOwner != nil else { continue }
            do {
                try await engine.fetchChanges()
            } catch {
                logger.error("Couldn't fetch \(scope.rawValue, privacy: .public) changes: \(error, privacy: .public)")
            }
        }
    }

    private func makeEngine(_ scope: SyncScope) -> CKSyncEngine {
        CKSyncEngine(CKSyncEngine.Configuration(
            database: scope == .own ? container.privateCloudDatabase : container.sharedCloudDatabase,
            stateSerialization: state[keyPath: scope.path].engine,
            delegate: self
        ))
    }

    private func registerForPushes() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Stops syncing. The user's own list stays on the device, and unconfirmed task edits are
    /// kept so they still win when it merges again at the next sign-in. Someone else's list
    /// doesn't stay: it's theirs, and still in iCloud.
    private func stop() {
        guard ownEngine != nil || state.userRecordName != nil else { return }
        ownEngine = nil
        sharedEngine = nil
        isSignedIn = false
        if state.joinedOwner != nil {
            store.switchList(to: .notShared)
            state.joinedOwner = nil
            state.own.dirtyFields = [:]
        } else {
            store.setSharing(.notShared, participants: [])
        }
        let dirty = state.own.dirtyFields
        state = SyncState()
        state.own.dirtyFields = dirty
        saveState()
    }

    /// Moves this device's list into iCloud, merging with whatever the user's other
    /// devices already put there (§7: merged automatically).
    private func mergeIntoCloud(user: UserID) async throws {
        guard let engine = ownEngine else { return }
        status = "Merging with iCloud…"

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.ownZoneID))])
        try await engine.sendChanges()
        // Other devices' tasks, and the list's ID if one exists.
        try await engine.fetchChanges()

        store.adoptUser(user)

        // Upload what iCloud doesn't have yet, plus edits made here while signed out.
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for chore in store.chores {
            let id = RecordRef.chore(chore.id).recordID(in: Self.ownZoneID)
            if state.own.systemFields[id.recordName] == nil || state.own.dirtyFields[id.recordName]?.isEmpty == false {
                changes.append(.saveRecord(id))
            }
        }
        for entry in store.log {
            let id = RecordRef.entry(entry.id).recordID(in: Self.ownZoneID)
            if state.own.systemFields[id.recordName] == nil { changes.append(.saveRecord(id)) }
        }
        if !state.own.hasListRecord { changes.append(.saveRecord(RecordRef.list.recordID(in: Self.ownZoneID))) }
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
        let scope = activeScope
        let name = RecordRef.chore(chore.id).recordName
        state[keyPath: scope.path].dirtyFields[name, default: []].formUnion(fields)
        saveState()
        if isUploading(scope), let zone = activeZone(scope) {
            engine(scope)?.state.add(pendingRecordZoneChanges: [.saveRecord(RecordRef.chore(chore.id).recordID(in: zone))])
        }
    }

    private func entryAppended(_ entry: LogEntry) {
        let scope = activeScope
        if isUploading(scope), let zone = activeZone(scope) {
            engine(scope)?.state.add(pendingRecordZoneChanges: [.saveRecord(RecordRef.entry(entry.id).recordID(in: zone))])
        }
    }

    // MARK: Changes from iCloud

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, scope: SyncScope) {
        // Records from a list that isn't in use are ignored. If the user goes back to it,
        // its engine starts afresh and fetches everything again.
        guard let zone = activeZone(scope) else { return }
        var chores: [Chore] = []
        var entries: [LogEntry] = []
        for modification in changes.modifications {
            let record = modification.record
            guard record.recordID.zoneID == zone else { continue }
            if let share = record as? CKShare {
                shareChanged(share, scope: scope)
                continue
            }
            guard let ref = RecordRef(record.recordID) else { continue }
            switch ref {
            case .chore:
                if let chore = Chore(record: record) { chores.append(keepingDirtyFields(chore, scope: scope)) }
            case .entry:
                if let entry = LogEntry(record: record) { entries.append(entry) }
            case .list:
                state[keyPath: scope.path].hasListRecord = true
                if let id = (record["listID"] as? String).flatMap(UUID.init(uuidString:)) { adoptList(id) }
            }
            saveSystemFields(of: record, scope: scope)
        }
        for deletion in changes.deletions
        where deletion.recordID.zoneID == zone && deletion.recordType == CKRecord.SystemType.share {
            shareRemoved(scope: scope)
        }
        store.applyRemote(chores: chores, entries: entries)
        saveState()
    }

    /// The iCloud copy of a task, with this device's unconfirmed edits on top.
    private func keepingDirtyFields(_ remote: Chore, scope: SyncScope) -> Chore {
        let name = RecordRef.chore(remote.id).recordName
        guard let dirty = state[keyPath: scope.path].dirtyFields[name], !dirty.isEmpty,
              let local = store.chore(id: remote.id)
        else { return remote }
        var merged = remote
        for field in dirty { merged.take(field, from: local) }
        return merged
    }

    /// Another device created the list first, or the user joined someone else's:
    /// move this device's tasks onto its ID.
    private func adoptList(_ id: UUID) {
        guard id != store.listID || store.chores.contains(where: { $0.listID != id }) else { return }
        store.setListID(id)
        for chore in store.chores where chore.listID != id {
            var moved = chore
            moved.listID = id
            store.save(moved)
        }
    }

    private func databaseChanged(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges, scope: SyncScope) {
        switch scope {
        case .own:
            for deletion in changes.deletions where deletion.zoneID == Self.ownZoneID {
                ownZoneDeleted(purged: deletion.reason == .purged)
            }
        case .shared:
            if let owner = state.joinedOwner,
               changes.deletions.contains(where: { $0.zoneID.zoneName == Self.listZoneName && $0.zoneID.ownerName == owner }) {
                let name = store.listOwner.flatMap { store.participantLabels[$0.id] }
                logger.log("Lost access to the shared list")
                returnToOwnList(notice: name.map { "You're no longer in \($0)'s list. This is your own list again." }
                    ?? "You're no longer in the shared list. This is your own list again.")
            }
            // A list joined on another of the user's devices (§7: one list per person).
            if state.joinedOwner == nil,
               let zone = changes.modifications.map(\.zoneID)
                   .filter({ $0.zoneName == Self.listZoneName })
                   .min(by: { $0.ownerName < $1.ownerName }) {
                join(owner: zone.ownerName, bringing: nil)
            }
        }
    }

    private func ownZoneDeleted(purged: Bool) {
        state.own = DatabaseState(engine: state.own.engine)
        state.merged = false
        if state.joinedOwner != nil {
            // The shared list in use is unaffected. The user's own list is recreated if they go back to it.
            logger.log("The user's own iCloud list was deleted while they're in a shared list")
            saveState()
            return
        }
        if purged {
            // The user deleted Needs Doing's data from iCloud in Settings, which deletes it from every device.
            logger.log("iCloud data was deleted by the user; removing it here too")
            store.removeAll()
            store.setSharing(.notShared, participants: [])
        } else {
            logger.log("iCloud zone was deleted; uploading this device's list again")
        }
        saveState()
        Task { await start() }
    }

    // MARK: Sharing (§7)

    /// Options for the system's invite screens: named people only, who can all edit.
    static var sharingOptions: CKAllowedSharingOptions {
        let options = CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .readWrite,
            allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )
        if #available(iOS 26, macOS 26, *) {
            options.allowsParticipantsToInviteOthers = false
        }
        // Access requests (asking to join from a link) are left alone: they need an extra
        // entitlement the app doesn't have, so they're off, and even setting them off logs an error.
        return options
    }

    /// The share for the user's own list, created if it doesn't exist yet.
    func shareForOwnList() async throws -> CKShare {
        guard isSignedIn, state.merged, state.joinedOwner == nil else { throw SharingError.notReady }
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: Self.ownZoneID)
        do {
            if let existing = try await database.record(for: shareID) as? CKShare { return existing }
        } catch let error as CKError where error.code == .unknownItem {
            // Not shared yet.
        }
        let share = CKShare(recordZoneID: Self.ownZoneID)
        share[CKShare.SystemFieldKey.title] = "Needs Doing"
        share.publicPermission = .none
        let (results, _) = try await database.modifyRecords(saving: [share], deleting: [])
        switch results[shareID] {
        case .success(let saved as CKShare): return saved
        case .failure(let error): throw error
        default: return share
        }
    }

    /// Picks up changes made in the system's sharing screens.
    func sharingScreenClosed() {
        Task { await fetchNow() }
    }

    enum SharingError: LocalizedError {
        case notReady

        var errorDescription: String? {
            "Sharing needs iCloud. Check you're signed in, then try again in a moment."
        }
    }

    private func shareChanged(_ share: CKShare, scope: SyncScope) {
        let participants = share.participants.compactMap { Participant($0, me: store.me) }
        switch scope {
        case .own:
            let othersInvited = participants.contains { !$0.isOwner }
            store.setSharing(othersInvited ? .owner : .notShared, participants: othersInvited ? participants : [])
        case .shared:
            guard let owner = state.joinedOwner else { return }
            store.setSharing(.member(owner: owner), participants: participants)
        }
    }

    private func shareRemoved(scope: SyncScope) {
        if scope == .own {
            logger.log("The user stopped sharing their list")
            store.setSharing(.notShared, participants: [])
        }
        // For a list the user joined, losing the share also removes its zone, handled in databaseChanged.
    }

    /// Called when the user opens an invitation link.
    func received(_ metadata: CKShare.Metadata) {
        guard enabled else { return }
        guard isSignedIn else {
            if checkedAccount && !starting {
                notice = "Sign into iCloud on this device to join a shared list."
            } else {
                // Handled once start() knows whether iCloud is available.
                waitingInvitation = metadata
            }
            return
        }
        let owner = metadata.share.recordID.zoneID.ownerName
        let ownerName = metadata.ownerIdentity.nameComponents
            .map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"

        if metadata.participantRole == .owner || owner == CKCurrentUserDefaultName || owner == state.userRecordName {
            notice = "That's the invitation to your own list."
            return
        }
        if owner == state.joinedOwner {
            notice = "You're already in \(ownerName)'s list."
            return
        }

        let leaving = state.joinedOwner == nil ? nil : store.listOwner.flatMap { store.participantLabels[$0.id] } ?? "the other"
        let blocked: String? = store.sharing == .owner
            ? "You're sharing your own list. Stop sharing it in Settings before joining someone else's."
            : nil
        let taskCount = state.joinedOwner == nil
            ? store.chores.filter { store.state(of: $0) != .deleted && store.state(of: $0) != .completed }.count
            : 0
        invitation = Invitation(metadata: metadata, ownerName: ownerName, taskCount: taskCount, leaving: leaving, blocked: blocked)
    }

    /// Joins the list the user was invited to (§7).
    /// - Parameter bringingTasks: copy the user's own tasks, with their history, into it.
    ///   They also stay in the user's own list, for if they ever leave.
    func accept(_ invitation: Invitation, bringingTasks: Bool) async {
        self.invitation = nil
        let owner = invitation.metadata.share.recordID.zoneID.ownerName
        let bringing = bringingTasks && state.joinedOwner == nil ? (store.chores, store.log) : nil
        do {
            _ = try await container.accept(invitation.metadata)
            if let previous = state.joinedOwner {
                try await leaveZone(owner: previous)
            }
            join(owner: owner, bringing: bringing)
        } catch {
            logger.error("Couldn't accept the invitation: \(error, privacy: .public)")
            notice = "Couldn't join \(invitation.ownerName)'s list. Invitations only work for the Apple Account they were sent to, so check this device is signed into iCloud with the email address or phone number you were invited with."
        }
    }

    /// Leaves the shared list the user is in and goes back to their own (§7).
    func leaveSharedList() async {
        guard let owner = state.joinedOwner else { return }
        do {
            try await leaveZone(owner: owner)
            returnToOwnList(notice: nil)
        } catch {
            logger.error("Couldn't leave the shared list: \(error, privacy: .public)")
            notice = "Couldn't leave the list right now. Check you're online and try again."
        }
    }

    /// Deleting a shared zone from the shared database removes the user from its share.
    private func leaveZone(owner: UserID) async throws {
        let zoneID = CKRecordZone.ID(zoneName: Self.listZoneName, ownerName: owner)
        _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
    }

    private func join(owner: UserID, bringing: ([Chore], [LogEntry])?) {
        logger.log("Switching to a shared list")
        state.joinedOwner = owner
        // A fresh engine fetches the whole list, including anything seen before it was joined.
        state.shared = DatabaseState()
        store.switchList(to: .member(owner: owner), keeping: bringing?.0 ?? [], log: bringing?.1 ?? [])
        sharedEngine = makeEngine(.shared)

        if let (chores, entries) = bringing, let zone = activeZone(.shared) {
            for chore in chores {
                state.shared.dirtyFields[RecordRef.chore(chore.id).recordName] = Set(ChoreField.allCases)
            }
            sharedEngine?.state.add(pendingRecordZoneChanges:
                chores.map { .saveRecord(RecordRef.chore($0.id).recordID(in: zone)) }
                + entries.map { .saveRecord(RecordRef.entry($0.id).recordID(in: zone)) })
            logger.log("Bringing \(chores.count) tasks into the shared list")
        }
        saveState()
        Task { await fetchNow() }
    }

    /// Goes back to the user's own list after leaving or losing a shared one. Its engine starts
    /// afresh, because it ignored the user's own list while they were away (§7).
    private func returnToOwnList(notice: String?) {
        state.joinedOwner = nil
        state.shared = DatabaseState()
        state.own = DatabaseState()
        store.switchList(to: .notShared)
        if isSignedIn {
            ownEngine = makeEngine(.own)
            sharedEngine = makeEngine(.shared)
        }
        saveState()
        self.notice = notice
        Task {
            if state.merged { await fetchNow() } else { await start() }
        }
    }

    // MARK: Sending

    private func record(for id: CKRecord.ID, scope: SyncScope) -> CKRecord? {
        guard id.zoneID == activeZone(scope), let ref = RecordRef(id) else { return nil }
        let record = cachedRecord(id, scope: scope) ?? CKRecord(recordType: ref.recordType, recordID: id)
        switch ref {
        case .chore(let uuid):
            guard let chore = store.chore(id: uuid) else { return nil }
            for field in ChoreField.allCases { chore.write(field, to: record) }
        case .entry(let uuid):
            guard let entry = store.log.first(where: { $0.id == uuid }) else { return nil }
            entry.write(to: record)
        case .list:
            // Only the owner writes the List record.
            guard scope == .own else { return nil }
            record["listID"] = store.listID.uuidString
        }
        return record
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, scope: SyncScope, engine: CKSyncEngine) {
        for record in sent.savedRecords where record.recordID.zoneID == activeZone(scope) {
            saveSystemFields(of: record, scope: scope)
            state[keyPath: scope.path].dirtyFields[record.recordID.recordName] = nil
            if RecordRef(record.recordID) == .list { state[keyPath: scope.path].hasListRecord = true }
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        var lostAccess = false
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            guard id.zoneID == activeZone(scope) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord, resolveConflict(with: server, scope: scope) {
                    retry.append(.saveRecord(id))
                }
            case .zoneNotFound, .userDeletedZone:
                if scope == .own {
                    needsZone = true
                    retry.append(.saveRecord(id))
                } else {
                    lostAccess = true
                }
            case .unknownItem:
                state[keyPath: scope.path].systemFields[id.recordName] = nil
                retry.append(.saveRecord(id))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited:
                break // CKSyncEngine retries these itself.
            default:
                logger.error("Couldn't save \(id.recordName, privacy: .public): \(failure.error, privacy: .public)")
                status = "iCloud couldn't save a change: \(failure.error.localizedDescription)"
            }
        }
        if needsZone { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.ownZoneID))]) }
        engine.state.add(pendingRecordZoneChanges: retry)
        saveState()
        if lostAccess {
            returnToOwnList(notice: "You're no longer in the shared list. This is your own list again.")
        }
    }

    /// Takes a newer iCloud copy after a failed save. Returns whether to save again.
    private func resolveConflict(with server: CKRecord, scope: SyncScope) -> Bool {
        saveSystemFields(of: server, scope: scope)
        switch RecordRef(server.recordID) {
        case .chore:
            guard let remote = Chore(record: server) else { return false }
            let dirty = state[keyPath: scope.path].dirtyFields[server.recordID.recordName] ?? []
            store.applyRemote(chores: [keepingDirtyFields(remote, scope: scope)], entries: [])
            return !dirty.isEmpty
        case .entry:
            // Entries never change, so iCloud's copy is this one.
            if let entry = LogEntry(record: server) { store.applyRemote(chores: [], entries: [entry]) }
            return false
        case .list:
            // Two devices created the list at once; theirs won.
            state[keyPath: scope.path].hasListRecord = true
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

    private func saveSystemFields(of record: CKRecord, scope: SyncScope) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        state[keyPath: scope.path].systemFields[record.recordID.recordName] = coder.encodedData
    }

    private func cachedRecord(_ id: CKRecord.ID, scope: SyncScope) -> CKRecord? {
        guard let data = state[keyPath: scope.path].systemFields[id.recordName],
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
        guard let scope = scope(of: syncEngine) else { return }
        switch event {
        case .stateUpdate(let update):
            state[keyPath: scope.path].engine = update.stateSerialization
            saveState()
        case .accountChange(let change):
            // Both engines report it; act once.
            if scope == .own { accountChanged(change) }
        case .fetchedDatabaseChanges(let changes):
            databaseChanged(changes, scope: scope)
        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes, scope: scope)
        case .sentRecordZoneChanges(let sent):
            handleSent(sent, scope: scope, engine: syncEngine)
        case .didFetchChanges, .didSendChanges:
            if isSignedIn { status = Self.onStatus }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let scope = scope(of: syncEngine) else { return nil }
        let zone = activeZone(scope)
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        var stale: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in syncEngine.state.pendingRecordZoneChanges where context.options.scope.contains(change) {
            let id = switch change {
            case .saveRecord(let id), .deleteRecord(let id): id
            @unknown default: nil as CKRecord.ID?
            }
            if let id, id.zoneID == zone { changes.append(change) } else { stale.append(change) }
        }
        // Changes for a list the user has left.
        if !stale.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: stale) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await self.record(for: id, scope: scope)
        }
    }
}

extension Participant {
    /// A participant as this device sees them, or `nil` for someone who's been removed.
    init?(_ participant: CKShare.Participant, me: UserID) {
        guard participant.acceptanceStatus != .removed else { return nil }
        let identity = participant.userIdentity
        var userID = identity.userRecordID?.recordName
        // CloudKit's placeholder for the current user, never stored (§8).
        if userID == CKCurrentUserDefaultName { userID = me }
        let isOwner = participant.role == .owner
        self.init(
            id: participant.participantID,
            userID: userID,
            givenName: identity.nameComponents?.givenName,
            familyName: identity.nameComponents?.familyName,
            email: identity.lookupInfo?.emailAddress,
            phone: identity.lookupInfo?.phoneNumber,
            isOwner: isOwner,
            status: isOwner || participant.acceptanceStatus == .accepted ? .joined : .invited
        )
    }
}
