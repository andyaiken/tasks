import CloudKit
import Foundation
import TasksCore

/// How tasks, log entries and the list are stored as CloudKit records (SPEC §11).
/// Field types can't change once the schema is deployed, so they're listed in the spec.
enum RecordRef: Equatable {
    case chore(UUID)
    case entry(UUID)
    case list

    var recordType: CKRecord.RecordType {
        switch self {
        case .chore: "Chore"
        case .entry: "LogEntry"
        case .list: "List"
        }
    }

    var recordID: CKRecord.ID {
        let name = switch self {
        case .chore(let id): "chore.\(id.uuidString)"
        case .entry(let id): "entry.\(id.uuidString)"
        case .list: "list"
        }
        return CKRecord.ID(recordName: name, zoneID: CloudSync.zoneID)
    }

    /// `nil` for records this version doesn't know, e.g. from a newer version of the app.
    init?(_ id: CKRecord.ID) {
        let name = id.recordName
        if name == "list" {
            self = .list
        } else if name.hasPrefix("chore."), let uuid = UUID(uuidString: String(name.dropFirst(6))) {
            self = .chore(uuid)
        } else if name.hasPrefix("entry."), let uuid = UUID(uuidString: String(name.dropFirst(6))) {
            self = .entry(uuid)
        } else {
            return nil
        }
    }
}

/// The parts of a task that merge independently when two devices edit it (§7).
enum ChoreField: String, CaseIterable, Codable {
    case title, notes, createdOn, interval, anchorMode, anchorDate, backlogPolicy, someday, assigneeID, listID
}

extension Chore {
    init?(record: CKRecord) {
        guard case .chore(let id) = RecordRef(record.recordID),
              let createdOn = (record["createdOn"] as? String).flatMap(CalendarDay.init),
              let anchorDate = (record["anchorDate"] as? String).flatMap(CalendarDay.init),
              let listID = (record["listID"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }

        let count = (record["intervalCount"] as? Int64).map(Int.init) ?? 0
        let unit = (record["intervalUnit"] as? String).flatMap(Interval.Unit.init(rawValue:))
        self.init(
            id: id,
            title: record["title"] as? String ?? "",
            notes: record["notes"] as? String ?? "",
            createdOn: createdOn,
            interval: count >= 1 ? unit.map { Interval(count, $0) } : nil,
            anchorMode: (record["anchorMode"] as? String).flatMap(AnchorMode.init(rawValue:)) ?? .floating,
            anchorDate: anchorDate,
            backlogPolicy: (record["backlogPolicy"] as? String).flatMap(BacklogPolicy.init(rawValue:)) ?? .skip,
            someday: (record["someday"] as? Int64 ?? 0) != 0,
            assigneeID: record["assigneeID"] as? String,
            listID: listID
        )
    }

    func write(_ field: ChoreField, to record: CKRecord) {
        switch field {
        case .title: record["title"] = title
        case .notes: record["notes"] = notes
        case .createdOn: record["createdOn"] = createdOn.description
        case .interval:
            record["intervalCount"] = Int64(interval?.count ?? 0)
            record["intervalUnit"] = interval?.unit.rawValue ?? ""
        case .anchorMode: record["anchorMode"] = anchorMode.rawValue
        case .anchorDate: record["anchorDate"] = anchorDate.description
        case .backlogPolicy: record["backlogPolicy"] = backlogPolicy.rawValue
        case .someday: record["someday"] = Int64(someday ? 1 : 0)
        case .assigneeID: record["assigneeID"] = assigneeID
        case .listID: record["listID"] = listID.uuidString
        }
    }

    /// Copies one field from `other`.
    mutating func take(_ field: ChoreField, from other: Chore) {
        switch field {
        case .title: title = other.title
        case .notes: notes = other.notes
        case .createdOn: createdOn = other.createdOn
        case .interval: interval = other.interval
        case .anchorMode: anchorMode = other.anchorMode
        case .anchorDate: anchorDate = other.anchorDate
        case .backlogPolicy: backlogPolicy = other.backlogPolicy
        case .someday: someday = other.someday
        case .assigneeID: assigneeID = other.assigneeID
        case .listID: listID = other.listID
        }
    }

    func changedFields(from old: Chore) -> Set<ChoreField> {
        Set(ChoreField.allCases.filter { field in
            var copy = old
            copy.take(field, from: self)
            return copy != old
        })
    }
}

extension LogEntry {
    init?(record: CKRecord) {
        guard case .entry(let id) = RecordRef(record.recordID),
              let choreID = (record["choreID"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = (record["kind"] as? String).flatMap(Kind.init(rawValue:)),
              let at = record["at"] as? Date,
              let day = (record["day"] as? String).flatMap(CalendarDay.init),
              let by = record["by"] as? String
        else { return nil }
        self.init(
            id: id,
            choreID: choreID,
            kind: kind,
            at: at,
            day: day,
            by: by,
            retracts: (record["retracts"] as? String).flatMap(UUID.init(uuidString:)),
            note: record["note"] as? String
        )
    }

    func write(to record: CKRecord) {
        record["choreID"] = choreID.uuidString
        record["kind"] = kind.rawValue
        record["at"] = at
        record["day"] = day.description
        record["by"] = by
        record["retracts"] = retracts?.uuidString
        record["note"] = note
    }
}
