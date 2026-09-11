#if DEBUG
import Foundation
import TasksCore

/// Example tasks for App Store screenshots (launch with `-screenshots`), dated relative
/// to today so the list shows every band. Test builds only.
enum DemoData {
    static func snapshot(today: CalendarDay) -> StoreSnapshot {
        let list = UUID()
        let me: UserID = "demo"
        var chores: [Chore] = []
        var log: [LogEntry] = []

        func add(
            _ title: String,
            created: Int,
            every interval: Interval? = nil,
            mode: AnchorMode = .floating,
            anchor: CalendarDay? = nil,
            someday: Bool = false,
            done: [CalendarDay] = []
        ) {
            let chore = Chore(
                title: title,
                createdOn: today.adding(days: created),
                interval: interval,
                anchorMode: mode,
                anchorDate: anchor,
                someday: someday,
                listID: list
            )
            chores.append(chore)
            log += done.map { LogEntry(choreID: chore.id, kind: .done, at: $0.date, day: $0, by: me) }
        }

        let lastMonday = today.adding(days: -((today.weekday - 2 + 7) % 7))

        // Overdue: two cycles without watering.
        add("Water the plants", created: -60, every: Interval(3, .days), anchor: today.adding(days: -60),
            done: [today.adding(days: -9), today.adding(days: -6)])
        // Late (or Due early in the week): this week's bin day was missed.
        add("Put the bins out", created: -90, every: Interval(1, .weeks), mode: .fixed, anchor: lastMonday.adding(days: -84),
            done: [lastMonday.adding(days: -14), lastMonday.adding(days: -7)])
        // Late: an "at some point" job that has been waiting six weeks.
        add("Clear the gutters", created: -45, someday: true)
        // Due.
        add("Change the sheets", created: -120, every: Interval(2, .weeks), anchor: today.adding(days: -120),
            done: [today.adding(days: -30), today.adding(days: -16)])
        add("Descale the kettle", created: -200, every: Interval(1, .months), anchor: today.adding(days: -200),
            done: [today.adding(days: -33)])
        // Due soon.
        add("Book the chimney sweep", created: -20, anchor: today.adding(days: 2))
        add("Clean the oven", created: -200, every: Interval(3, .months), anchor: today.adding(days: -200),
            done: [today.adding(days: -80)])
        // Not yet: only under All tasks.
        add("Renew the car insurance", created: -10, anchor: today.adding(days: 40))
        add("Service the boiler", created: -100, every: Interval(1, .years), mode: .fixed, anchor: today.adding(days: 120))
        add("Wash the car", created: -60, every: Interval(1, .months), anchor: today.adding(days: -60),
            done: [today.adding(days: -5)])

        return StoreSnapshot(me: me, listID: list, chores: chores, log: log)
    }
}
#endif
