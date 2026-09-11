import Foundation
import Testing
@testable import TasksCore

// MARK: Helpers

private func d(_ s: String) -> CalendarDay { CalendarDay(s)! }

private let list = UUID()
private let me: UserID = "me"

private func entry(_ kind: LogEntry.Kind, _ chore: Chore, on day: String, by user: UserID = me, retracts: UUID? = nil) -> LogEntry {
    let day = d(day)
    // Noon UTC on that day, so `at` orders the same way as `day`.
    let at = Date(timeIntervalSince1970: Double(day.ordinal) * 86_400 + 43_200)
    return LogEntry(choreID: chore.id, kind: kind, at: at, day: day, by: user, retracts: retracts)
}

private func staleness(_ chore: Chore, _ log: [LogEntry] = [], on today: String) -> Double? {
    chore.state(log: log, today: d(today)).staleness(on: d(today))
}

private func nextDue(_ chore: Chore, _ log: [LogEntry] = [], on today: String) -> CalendarDay? {
    if case let .active(_, next) = chore.state(log: log, today: d(today)) { return next }
    return nil
}

// MARK: Calendar days

@Suite struct CalendarDayTests {
    @Test func parsesAndPrints() {
        #expect(d("2026-09-11").description == "2026-09-11")
        #expect(CalendarDay("2026-02-29") == nil)
        #expect(CalendarDay("2028-02-29") != nil)
        #expect(CalendarDay("2026-9-11") == nil)
    }

    @Test func ordinalRoundTrips() {
        for n in stride(from: -800_000, through: 800_000, by: 997) {
            #expect(CalendarDay(ordinal: n).ordinal == n)
        }
        #expect(d("1970-01-01").ordinal == 0)
        #expect(d("2027-01-01") - d("2026-01-01") == 365)
    }

    @Test func monthsClampToMonthEnd() {
        let anchor = d("2027-01-31")
        let month = Interval(1, .months)
        #expect(anchor.adding(month, times: 1) == d("2027-02-28"))
        #expect(anchor.adding(month, times: 2) == d("2027-03-31"))
        #expect(anchor.adding(month, times: 3) == d("2027-04-30"))
        #expect(d("2028-01-31").adding(month) == d("2028-02-29"))
        #expect(d("2028-02-29").adding(Interval(1, .years)) == d("2029-02-28"))
        #expect(d("2027-03-15").adding(month, times: -3) == d("2026-12-15"))
    }

    @Test func weekdays() {
        #expect(d("1970-01-01").weekday == 5) // Thursday
        #expect(d("2026-09-11").weekday == 6) // Friday
        #expect(d("2026-09-14").weekday == 2) // Monday
        #expect(d("1969-12-28").weekday == 1) // Sunday
    }

    @Test func dayStartsAtFourAM() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let iso = ISO8601DateFormatter()
        // 01:00 on Wednesday belongs to Tuesday.
        #expect(CalendarDay(containing: iso.date(from: "2026-09-09T01:00:00Z")!, in: utc) == d("2026-09-08"))
        #expect(CalendarDay(containing: iso.date(from: "2026-09-09T03:59:59Z")!, in: utc) == d("2026-09-08"))
        #expect(CalendarDay(containing: iso.date(from: "2026-09-09T04:00:00Z")!, in: utc) == d("2026-09-09"))
    }

    @Test func dayBoundaryIgnoresDST() throws {
        // UK clocks go forward at 01:00 GMT on 29 March 2026.
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let iso = ISO8601DateFormatter()
        #expect(CalendarDay(containing: iso.date(from: "2026-03-29T02:30:00Z")!, in: london) == d("2026-03-28")) // 03:30 BST
        #expect(CalendarDay(containing: iso.date(from: "2026-03-29T03:30:00Z")!, in: london) == d("2026-03-29")) // 04:30 BST
    }
}

// MARK: Bands

@Suite struct BandTests {
    @Test func boundariesIncludeTheLowerBound() {
        #expect(Band(staleness: 0.79) == .notYet)
        #expect(Band(staleness: 0.8) == .dueSoon)
        #expect(Band(staleness: 4.0 / 5.0) == .dueSoon)
        #expect(Band(staleness: 1.0) == .due)
        #expect(Band(staleness: 1.5) == .late)
        #expect(Band(staleness: 2.0) == .overdue)
    }
}

// MARK: One-offs

@Suite struct OneOffTests {
    @Test func dueTodayShowsToday() {
        let chore = Chore(title: "Book sweep", createdOn: d("2026-09-11"), interval: nil, listID: list)
        #expect(staleness(chore, on: "2026-09-11") == 1.0)
    }

    @Test func alreadyOverdueWhenCreatedShowsLate() {
        let chore = Chore(title: "Renew passport", createdOn: d("2026-09-11"), interval: nil, anchorDate: d("2026-08-11"), listID: list)
        #expect(Band(staleness: staleness(chore, on: "2026-09-11")!) == .overdue)
    }

    @Test func dueInAYearAppearsAboutTenWeeksAhead() {
        let chore = Chore(title: "Service boiler", createdOn: d("2026-09-11"), interval: nil, anchorDate: d("2027-09-11"), listID: list)
        let created = d("2026-09-11")
        #expect(Band(staleness: staleness(chore, on: created.adding(days: 291).description)!) == .notYet)
        #expect(Band(staleness: staleness(chore, on: created.adding(days: 292).description)!) == .dueSoon)
    }

    @Test func atSomePointCreepsUpOverFourWeeks() {
        let chore = Chore(title: "Sort the loft", createdOn: d("2026-09-01"), interval: nil, someday: true, listID: list)
        #expect(Band(staleness: staleness(chore, on: "2026-09-01")!) == .notYet)
        #expect(Band(staleness: staleness(chore, on: "2026-09-23")!) == .notYet)  // day 22
        #expect(Band(staleness: staleness(chore, on: "2026-09-24")!) == .dueSoon) // day 23
        #expect(Band(staleness: staleness(chore, on: "2026-09-29")!) == .due)     // day 28
        #expect(Band(staleness: staleness(chore, on: "2026-10-27")!) == .overdue) // day 56
        #expect(chore.state(log: [entry(.done, chore, on: "2026-09-05")], today: d("2026-09-05")) == .completed)
    }

    @Test func atSomePointRestartsOnResume() {
        let chore = Chore(title: "Sort the loft", createdOn: d("2026-09-01"), interval: nil, someday: true, listID: list)
        let log = [entry(.paused, chore, on: "2026-09-02"), entry(.resumed, chore, on: "2027-01-01")]
        #expect(staleness(chore, log, on: "2027-01-01") == 0)
    }

    @Test func doneCompletesAndRetractingBringsItBack() {
        let chore = Chore(title: "Book sweep", createdOn: d("2026-09-11"), interval: nil, listID: list)
        let done = entry(.done, chore, on: "2026-09-11")
        #expect(chore.state(log: [done], today: d("2026-09-12")) == .completed)
        let undo = entry(.retracted, chore, on: "2026-09-11", retracts: done.id)
        #expect(nextDue(chore, [done, undo], on: "2026-09-12") == d("2026-09-11"))
    }
}

// MARK: Floating

@Suite struct FloatingTests {
    let chore = Chore(title: "Water plants", createdOn: d("2026-09-01"), interval: Interval(1, .weeks), listID: list)

    @Test func firstCycleStartsAtAnchor() {
        #expect(staleness(chore, on: "2026-09-01") == 0)
        #expect(staleness(chore, on: "2026-09-08") == 1.0)
    }

    @Test func lateOrEarlyCompletionMovesTheSchedule() {
        #expect(nextDue(chore, [entry(.done, chore, on: "2026-09-03")], on: "2026-09-03") == d("2026-09-10"))
        #expect(nextDue(chore, [entry(.done, chore, on: "2026-09-12")], on: "2026-09-12") == d("2026-09-19"))
    }

    @Test func pastAnchorMeansLastDoneThen() {
        let oven = Chore(title: "Clean oven", createdOn: d("2026-09-11"), interval: Interval(3, .months), anchorDate: d("2026-06-11"), listID: list)
        #expect(staleness(oven, on: "2026-09-11") == 1.0)
    }

    @Test func pauseHidesAndResumeStartsFresh() {
        let log = [entry(.done, chore, on: "2026-09-03"), entry(.paused, chore, on: "2026-09-05")]
        #expect(chore.state(log: log, today: d("2026-12-01")) == .paused)
        let resumed = log + [entry(.resumed, chore, on: "2027-03-01")]
        #expect(staleness(chore, resumed, on: "2027-03-01") == 0)
        #expect(staleness(chore, resumed, on: "2027-03-08") == 1.0)
    }

    @Test func dailyTaskOneDayLateIsOverdue() {
        let dishes = Chore(title: "Washing up", createdOn: d("2026-09-01"), interval: Interval(1, .days), listID: list)
        let log = [entry(.done, dishes, on: "2026-09-01")]
        #expect(Band(staleness: staleness(dishes, log, on: "2026-09-02")!) == .due)
        #expect(Band(staleness: staleness(dishes, log, on: "2026-09-03")!) == .overdue)
    }
}

// MARK: Fixed

@Suite struct FixedTests {
    // Occurrences: 09-01, 09-08, 09-15, 09-22, 09-29, 10-06 …
    func bin(_ policy: BacklogPolicy) -> Chore {
        Chore(title: "Bins", createdOn: d("2026-09-01"), interval: Interval(1, .weeks), anchorMode: .fixed, backlogPolicy: policy, listID: list)
    }

    @Test func firstOccurrenceIsDueOnTheAnchor() {
        #expect(staleness(bin(.skip), on: "2026-09-01") == 1.0)
    }

    @Test func skipLateCompletionCountsForTheMissedOccurrence() {
        let chore = bin(.skip)
        // 09-08 was missed; done four days late, on 09-12.
        let log = [entry(.done, chore, on: "2026-09-01"), entry(.done, chore, on: "2026-09-12")]
        #expect(nextDue(chore, log, on: "2026-09-12") == d("2026-09-15"))
    }

    @Test func skipNightBeforeCountsForNextDay() {
        let chore = bin(.skip)
        let log = [entry(.done, chore, on: "2026-09-08"), entry(.done, chore, on: "2026-09-14")]
        #expect(nextDue(chore, log, on: "2026-09-14") == d("2026-09-22"))
    }

    @Test func skipMissedMonthIsDueNotOverdue() {
        let chore = bin(.skip)
        let log = [entry(.done, chore, on: "2026-09-01")]
        #expect(nextDue(chore, log, on: "2026-10-02") == d("2026-09-29"))
        #expect(Band(staleness: staleness(chore, log, on: "2026-10-02")!) == .due)
    }

    @Test func debtPaysOffOldestFirst() {
        let chore = bin(.debt)
        var log = [entry(.done, chore, on: "2026-09-01")]
        #expect(nextDue(chore, log, on: "2026-10-02") == d("2026-09-08"))
        #expect(Band(staleness: staleness(chore, log, on: "2026-10-02")!) == .overdue)
        log.append(entry(.done, chore, on: "2026-10-02"))
        #expect(nextDue(chore, log, on: "2026-10-02") == d("2026-09-15"))
    }

    @Test func occurrencesBeforeCreationAreIgnored() {
        let chore = Chore(title: "Bins", createdOn: d("2026-09-01"), interval: Interval(1, .weeks), anchorMode: .fixed,
                          anchorDate: d("2025-09-02"), backlogPolicy: .debt, listID: list)
        #expect(nextDue(chore, on: "2026-09-01") == d("2026-09-01"))
        #expect(staleness(chore, on: "2026-09-01") == 1.0)
    }

    @Test func monthlyFromThe31stDoesNotDrift() {
        let rent = Chore(title: "Rent", createdOn: d("2027-01-31"), interval: Interval(1, .months), anchorMode: .fixed, listID: list)
        let log = [entry(.done, rent, on: "2027-01-31"), entry(.done, rent, on: "2027-02-28")]
        #expect(nextDue(rent, log, on: "2027-03-01") == d("2027-03-31"))
    }

    @Test func resumeForgetsPausedOccurrences() {
        let chore = bin(.debt)
        let log = [entry(.done, chore, on: "2026-09-01"), entry(.paused, chore, on: "2026-09-02"), entry(.resumed, chore, on: "2026-11-02")]
        #expect(nextDue(chore, log, on: "2026-11-02") == d("2026-11-03"))
    }
}

// MARK: Log interpretation

@Suite struct LogTests {
    let chore = Chore(title: "Plants", createdOn: d("2026-09-01"), interval: Interval(3, .days), listID: list)

    @Test func deleteAndUndoDelete() {
        let delete = entry(.deleted, chore, on: "2026-09-02")
        #expect(chore.state(log: [delete], today: d("2026-09-02")) == .deleted)
        let undo = entry(.retracted, chore, on: "2026-09-02", retracts: delete.id)
        #expect(nextDue(chore, [delete, undo], on: "2026-09-02") == d("2026-09-04"))
    }

    @Test func retractingARetractionDoesNothing() {
        let done = entry(.done, chore, on: "2026-09-02")
        let undo = entry(.retracted, chore, on: "2026-09-02", retracts: done.id)
        let redo = entry(.retracted, chore, on: "2026-09-02", retracts: undo.id)
        #expect(nextDue(chore, [done, undo, redo], on: "2026-09-02") == d("2026-09-04"))
    }

    @Test func otherTasksEntriesAreIgnored() {
        let other = Chore(title: "Other", createdOn: d("2026-09-01"), interval: nil, listID: list)
        #expect(nextDue(chore, [entry(.deleted, other, on: "2026-09-02")], on: "2026-09-02") == d("2026-09-04"))
    }
}

// MARK: Main list and digest

@Suite struct MainListTests {
    let today = d("2026-09-08")
    // Weekly floating tasks created 09-01 are exactly Due (1.0) on 09-08.
    func task(_ title: String, assignee: UserID?, created: String = "2026-09-01") -> Chore {
        Chore(title: title, createdOn: d(created), interval: Interval(1, .weeks), assigneeID: assignee, listID: list)
    }

    @Test func sharedListSplitsIntoSections() {
        let mine = task("Mine", assignee: me)
        let priyas = task("Priya's", assignee: "priya", created: "2026-08-25") // 2.0, overdue
        let anyone = task("Anyone", assignee: nil)
        let departed = task("Departed", assignee: "sam")
        let notYet = task("Not yet", assignee: me, created: "2026-09-07")
        let result = MainList(chores: [mine, priyas, anyone, departed, notYet], log: [], today: today, me: me, participants: [me, "priya"])

        #expect(!result.isSolo)
        #expect(result.yours.map(\.chore.title) == ["Mine"])
        #expect(result.everyoneElse.map(\.chore.title) == ["Priya's", "Anyone", "Departed"])
        #expect(result.everyoneElse.last?.assignee == nil)
    }

    @Test func groupedByBandMostUrgentFirst() {
        let chores = [
            task("Due", assignee: nil),                          // 1.0
            task("Overdue", assignee: nil, created: "2026-08-25"), // 2.0
            task("Soon", assignee: nil, created: "2026-09-02"),   // 6/7
            task("Also due", assignee: nil, created: "2026-08-31"), // 8/7
        ]
        let list = MainList(chores: chores, log: [], today: today, me: me, participants: [])
        let groups = MainList.grouped(list.yours)
        #expect(groups.map(\.band) == [.overdue, .due, .dueSoon])
        #expect(groups[1].items.map(\.chore.title) == ["Also due", "Due"])
    }

    @Test func soloListTreatsEverythingAsYours() {
        let result = MainList(chores: [task("A", assignee: nil), task("B", assignee: "gone")], log: [], today: today, me: me, participants: [])
        #expect(result.isSolo)
        #expect(result.yours.count == 2)
        #expect(result.everyoneElse.isEmpty)
    }

    @Test func pausedTasksNeverAppear() {
        let chore = task("Paused", assignee: me)
        let result = MainList(chores: [chore], log: [entry(.paused, chore, on: "2026-09-02")], today: today, me: me, participants: [])
        #expect(result.yours.isEmpty)
    }

    @Test func firstDayOnMainList() {
        let weekly = task("Weekly", assignee: nil, created: "2026-09-08")
        #expect(weekly.firstDayOnMainList(log: [], from: today) == d("2026-09-14")) // 6/7 ≥ 0.8
        let dueToday = Chore(title: "Today", createdOn: today, interval: nil, listID: list)
        #expect(dueToday.firstDayOnMainList(log: [], from: today) == today)
        let paused = task("Paused", assignee: nil)
        #expect(paused.firstDayOnMainList(log: [entry(.paused, paused, on: "2026-09-02")], from: today) == nil)
    }

    @Test func digestListsYourDueTasks() throws {
        let chores = [task("A", assignee: nil), task("B", assignee: nil, created: "2026-08-25"), task("Soon", assignee: nil, created: "2026-09-02")]
        let digest = try #require(Digest(list: MainList(chores: chores, log: [], today: today, me: me, participants: [])))
        #expect(digest.items.map(\.chore.title) == ["B", "A"])
        #expect(digest.summary == "2 tasks for you today, 1 overdue.")
    }

    @Test func digestBodyNamesTheMostUrgent() throws {
        func body(_ titles: [String]) throws -> String {
            let chores = titles.enumerated().map { i, title in
                // All at least a week old, so all Due or worse; earlier titles are staler, so they come first.
                task(title, assignee: nil, created: d("2026-08-20").adding(days: i).description)
            }
            return try #require(Digest(list: MainList(chores: chores, log: [], today: today, me: me, participants: []))).body
        }
        #expect(try body(["A"]) == "A")
        #expect(try body(["A", "B"]) == "A and B")
        #expect(try body(["A", "B", "C"]) == "A, B and C")
        #expect(try body(["A", "B", "C", "D", "E"]) == "A, B and 3 more")
    }

    @Test func upcomingDigestsSkipQuietDays() {
        // Weekly, created 09-01: Due from 09-08, and nothing logged, so due every day after.
        let upcoming = Digest.upcoming(chores: [task("A", assignee: nil)], log: [], me: me, participants: [], from: d("2026-09-01"), days: 14)
        #expect(upcoming.map(\.day) == (7..<14).map { d("2026-09-01").adding(days: $0) })
        #expect(upcoming.first?.digest.summary == "1 task for you today.")
    }

    @Test func noDigestWhenNothingIsYours() {
        let shared = MainList(chores: [task("A", assignee: nil)], log: [], today: today, me: me, participants: [me, "priya"])
        #expect(Digest(list: shared) == nil)
    }
}

// MARK: Participant labels

@Suite struct LabelTests {
    @Test func preferenceOrder() {
        let labels = participantLabels([
            ParticipantIdentity(userID: "a", givenName: "Priya", familyName: "Shah"),
            ParticipantIdentity(userID: "b", fullName: "Madonna"),
            ParticipantIdentity(userID: "c", email: "jo@example.com"),
            ParticipantIdentity(userID: "d", email: "kim@example.com"),
            ParticipantIdentity(userID: "e"),
        ], contacts: ["c": ContactName(givenName: "Jo")])
        #expect(labels == ["a": "Priya", "b": "Madonna", "c": "Jo", "d": "K", "e": "User"])
    }

    @Test func sameFirstNameGetsFamilyInitial() {
        let labels = participantLabels([
            ParticipantIdentity(userID: "a", givenName: "Sam", familyName: "Khan"),
            ParticipantIdentity(userID: "b"),
        ], contacts: ["b": ContactName(givenName: "Sam", familyName: "Taylor")])
        #expect(labels == ["a": "Sam K.", "b": "Sam T."])
    }
}
