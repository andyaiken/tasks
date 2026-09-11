import SwiftUI
import TasksCore

/// Every task that isn't deleted or completed, due or not (SPEC §8).
struct AllTasksView: View {
    @Environment(Store.self) private var store
    @State private var editor: EditorRequest?

    struct Row: Identifiable {
        let chore: Chore
        let state: ChoreState
        var id: UUID { chore.id }
    }

    private var rows: [Row] {
        store.chores
            .map { Row(chore: $0, state: store.state(of: $0)) }
            .filter { $0.state != .deleted && $0.state != .completed }
            .sorted { $0.chore.title.localizedStandardCompare($1.chore.title) == .orderedAscending }
    }

    var body: some View {
        let rows = rows
        List(rows) { row in
            AllTasksRow(row: row) { editor = EditorRequest(chore: row.chore, isNew: false) }
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No tasks yet", systemImage: "list.bullet", description: Text("Add a task with the + button."))
            }
        }
        .navigationTitle("All tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add task", systemImage: "plus") {
                    editor = EditorRequest(chore: store.newChore(), isNew: true)
                }
            }
        }
        .sheet(item: $editor) { TaskEditor(chore: $0.chore, isNew: $0.isNew) }
        .undoBanner()
    }
}

private struct AllTasksRow: View {
    @Environment(Store.self) private var store
    let row: AllTasksView.Row
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.chore.title)
                    Text(row.chore.rhythmDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                status
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.record(.deleted, row.chore) }
            }
            pauseButton
        }
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: edit)
            pauseButton
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation { store.record(.deleted, row.chore) }
            }
        }
    }

    @ViewBuilder
    private var pauseButton: some View {
        if row.state == .paused {
            Button("Resume", systemImage: "play") { withAnimation { store.record(.resumed, row.chore) } }
                .tint(.blue)
        } else {
            Button("Pause", systemImage: "pause") { withAnimation { store.record(.paused, row.chore) } }
                .tint(.gray)
        }
    }

    @ViewBuilder
    private var status: some View {
        if row.state == .paused {
            Text("Paused")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else if let staleness = row.state.staleness(on: store.today) {
            let band = Band(staleness: staleness)
            Text(band.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(band.color)
        }
    }
}
