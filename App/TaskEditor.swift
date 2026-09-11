import SwiftUI
import TasksCore

/// Creates or edits a task, asking "when" in plain words (SPEC §4, "In the UI").
struct TaskEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Chore
    private let isNew: Bool

    @State private var title: String
    @State private var notes: String
    @State private var when: When
    @State private var dueDate: Date
    @State private var count: Int
    @State private var unit: Interval.Unit
    @State private var weekday: Int
    @State private var startDate: Date
    @State private var lastDone: Date
    @State private var backlog: BacklogPolicy
    @State private var confirmation: String?

    enum When: CaseIterable, Identifiable {
        case today, byDate, someday, schedule, roughly
        var id: Self { self }

        var label: String {
            switch self {
            case .today: "Today"
            case .byDate: "By a date"
            case .someday: "At some point"
            case .schedule: "On a schedule"
            case .roughly: "Roughly every…"
            }
        }
    }

    init(chore: Chore, isNew: Bool) {
        original = chore
        self.isNew = isNew
        _title = State(initialValue: chore.title)
        _notes = State(initialValue: chore.notes)

        let when: When = if let _ = chore.interval {
            chore.anchorMode == .fixed ? .schedule : .roughly
        } else if chore.someday {
            .someday
        } else {
            isNew ? .today : .byDate
        }
        _when = State(initialValue: when)

        let anchor = chore.anchorDate.date
        _dueDate = State(initialValue: anchor)
        _startDate = State(initialValue: anchor)
        _lastDone = State(initialValue: anchor)
        _count = State(initialValue: chore.interval?.count ?? 1)
        _unit = State(initialValue: chore.interval?.unit ?? .weeks)
        _weekday = State(initialValue: chore.anchorDate.weekday)
        _backlog = State(initialValue: chore.backlogPolicy)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section {
                    Picker("When", selection: $when) {
                        ForEach(When.allCases) { Text($0.label).tag($0) }
                    }
                    whenDetails
                } footer: {
                    Text(footer)
                }

                if when == .schedule {
                    Section {
                        Picker("If it's missed", selection: $backlog) {
                            Text("Drop it").tag(BacklogPolicy.skip)
                            Text("Each one must be done").tag(BacklogPolicy.debt)
                        }
                    } footer: {
                        Text("For most things, like bin day, a missed one is simply gone. Choose \"Each one must be done\" only when every occurrence is a real obligation.")
                    }
                }

                if !isNew {
                    actions
                    history
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New task" : "Edit task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .alert("Task added", isPresented: .init(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            )) {
                Button("OK") { dismiss() }
            } message: {
                Text(confirmation ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    // MARK: When

    @ViewBuilder
    private var whenDetails: some View {
        switch when {
        case .today, .someday:
            EmptyView()
        case .byDate:
            DatePicker("Due", selection: $dueDate, displayedComponents: .date)
        case .schedule:
            intervalControls
            if unit == .weeks {
                Picker("On", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
            } else {
                DatePicker("Starting", selection: $startDate, displayedComponents: .date)
            }
        case .roughly:
            intervalControls
            if store.history(of: original).allSatisfy({ $0.kind != .done && $0.kind != .skipped }) {
                DatePicker("Last done", selection: $lastDone, displayedComponents: .date)
            }
        }
    }

    private var intervalControls: some View {
        Group {
            Picker("Repeat", selection: $unit) {
                ForEach(Interval.Unit.allCases, id: \.self) { Text($0.pluralName.capitalized).tag($0) }
            }
            Stepper(value: $count, in: 1...99) {
                Text(Interval(count, unit).phrase.capitalizedFirst)
            }
        }
    }

    private var footer: String {
        switch when {
        case .today: "Due today."
        case .byDate: "Moves up the list as the date gets closer."
        case .someday: "No date. It creeps up the list over a few weeks so it isn't forgotten."
        case .schedule: "Tied to the calendar, like bin day. Doing it late doesn't move the next one."
        case .roughly: "The next one is counted from when it was last done."
        }
    }

    // MARK: Existing tasks

    @ViewBuilder
    private var actions: some View {
        let state = store.state(of: original)
        Section {
            Button("Mark done") { store.record(.done, original); dismiss() }
            if !original.isOneOff {
                Button("Skip this time") { store.record(.skipped, original); dismiss() }
            }
            if state == .paused {
                Button("Resume") { store.record(.resumed, original); dismiss() }
            } else {
                Button("Pause") { store.record(.paused, original); dismiss() }
            }
            Button("Delete task", role: .destructive) { store.record(.deleted, original); dismiss() }
        }
    }

    @ViewBuilder
    private var history: some View {
        let entries = store.history(of: original).prefix(20)
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.kind.historyLabel)
                        Spacer()
                        Text(entry.day.formatted)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Undo", role: .destructive) { store.retract(entry) }
                    }
                    .contextMenu {
                        Button("Undo", systemImage: "arrow.uturn.backward") { store.retract(entry) }
                    }
                }
            } header: {
                Text("History")
            } footer: {
                Text("Swipe an entry to undo it.")
            }
        }
    }

    // MARK: Saving

    private func save() {
        let chore = built()
        store.save(chore)
        let today = store.today
        if isNew, let first = chore.firstDayOnMainList(log: store.log, from: today), first > today {
            confirmation = "It'll appear on your To do list \(reappearance(days: first - today))."
        } else {
            dismiss()
        }
    }

    private func built() -> Chore {
        var chore = original
        let today = store.today
        chore.title = trimmedTitle
        chore.notes = notes
        if isNew { chore.createdOn = today }

        switch when {
        case .today:
            chore.interval = nil
            chore.someday = false
            chore.anchorDate = today
        case .byDate:
            chore.interval = nil
            chore.someday = false
            chore.anchorDate = CalendarDay(date: dueDate)
        case .someday:
            chore.interval = nil
            chore.someday = true
        case .schedule:
            chore.interval = Interval(count, unit)
            chore.anchorMode = .fixed
            chore.someday = false
            chore.backlogPolicy = backlog
            if unit == .weeks {
                // Keep the anchor if the weekday hasn't changed, so "every 2 weeks" keeps its rhythm.
                let unchanged = original.interval?.unit == .weeks && original.anchorMode == .fixed
                    && original.anchorDate.weekday == weekday
                if !unchanged {
                    chore.anchorDate = today.adding(days: (weekday - today.weekday + 7) % 7)
                }
            } else {
                chore.anchorDate = CalendarDay(date: startDate)
            }
        case .roughly:
            chore.interval = Interval(count, unit)
            chore.anchorMode = .floating
            chore.someday = false
            chore.anchorDate = CalendarDay(date: lastDone)
        }
        return chore
    }
}
