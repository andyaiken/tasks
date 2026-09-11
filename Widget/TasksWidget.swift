import SwiftUI
import TasksCore
import WidgetKit

/// The app's widgets (SPEC §11). Both are read-only; tapping one opens the app.
@main
struct TasksWidgets: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        NextTaskWidget()
    }
}

/// The To do widget: what needs doing, most urgent first.
struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TasksWidget", provider: Provider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("To do")
        .description("What needs doing, most urgent first.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct DueEntry: TimelineEntry {
    let date: Date
    /// That day's main list, most urgent first.
    let items: [MainListItem]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DueEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (DueEntry) -> Void) {
        let entry = Self.entry(at: .now, snapshot: SharedStore.load())
        completion(context.isPreview && entry.items.isEmpty ? .sample : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DueEntry>) -> Void) {
        let snapshot = SharedStore.load()
        // Urgency only changes when a new day starts at 04:00 (§4), so a week of days can be
        // planned now. The app asks for a fresh timeline whenever the list changes.
        var dates = [Date.now]
        for _ in 0..<7 {
            dates.append(Self.nextDayStart(after: dates[dates.count - 1]))
        }
        completion(Timeline(entries: dates.map { Self.entry(at: $0, snapshot: snapshot) }, policy: .atEnd))
    }

    static func entry(at date: Date, snapshot: StoreSnapshot?) -> DueEntry {
        guard let snapshot else { return DueEntry(date: date, items: []) }
        let list = MainList(
            chores: snapshot.chores,
            log: snapshot.log,
            today: CalendarDay(containing: date, in: .current),
            me: snapshot.me,
            participants: []
        )
        return DueEntry(date: date, items: list.yours + list.everyoneElse)
    }

    /// The next 04:00 after `date`, local time.
    static func nextDayStart(after date: Date) -> Date {
        Calendar.current.nextDate(
            after: date,
            matching: DateComponents(hour: CalendarDay.dayStartHour, minute: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(86_400)
    }
}

extension DueEntry {
    /// Shown in the widget gallery, and while the real content loads.
    static var sample: DueEntry {
        let today = CalendarDay(containing: .now, in: .current)
        let created = today.adding(days: -30)
        let list = UUID()
        let chores = [
            Chore(title: "Water the plants", createdOn: created, interval: Interval(3, .days), anchorDate: today.adding(days: -6), listID: list),
            Chore(title: "Put the bins out", createdOn: created, interval: Interval(1, .weeks), anchorDate: today.adding(days: -10), listID: list),
            Chore(title: "Sort the loft", createdOn: created, interval: nil, someday: true, listID: list),
            Chore(title: "Change the bedding", createdOn: created, interval: Interval(2, .weeks), anchorDate: today.adding(days: -12), listID: list),
        ]
        let main = MainList(chores: chores, log: [], today: today, me: "sample", participants: [])
        return DueEntry(date: .now, items: main.yours)
    }
}

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DueEntry

    var body: some View {
        #if os(iOS)
        if family == .accessoryRectangular {
            lockScreen
        } else {
            homeScreen
        }
        #else
        homeScreen
        #endif
    }

    @ViewBuilder
    private var homeScreen: some View {
        if entry.items.isEmpty {
            NothingToDoView()
        } else {
            list
        }
    }

    private var rowLimit: Int {
        family == .systemLarge ? 10 : 4
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("To do")
                    .font(.headline)
                Spacer()
                Text("\(entry.items.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.items.prefix(rowLimit), id: \.chore.id) { item in
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(item.band.color, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    Text(item.chore.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if family != .systemSmall {
                        Text(item.band.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item.band.color)
                    }
                }
            }
            if entry.items.count > rowLimit {
                Text("+\(entry.items.count - rowLimit) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.items.isEmpty ? "Nothing to do" : "To do · \(entry.items.count)")
                .font(.headline)
                .widgetAccentable()
            ForEach(entry.items.prefix(2), id: \.chore.id) { item in
                Text(item.chore.title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
