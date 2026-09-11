import SwiftUI
import TasksCore

/// The "what needs doing" screen (SPEC §5, §8).
struct MainListView: View {
    @Environment(Store.self) private var store
    @State private var editor: EditorRequest?

    var body: some View {
        let list = store.mainList
        List {
            if list.isSolo {
                rows(list.yours)
            } else {
                Section("Yours") { rows(list.yours) }
                Section("Everyone else's") { rows(list.everyoneElse) }
            }
        }
        .overlay {
            if list.yours.isEmpty && list.everyoneElse.isEmpty {
                ContentUnavailableView(
                    "Nothing needs doing",
                    systemImage: "checkmark.circle",
                    description: Text(store.chores.isEmpty
                        ? "Add a task with the + button."
                        : "Tasks appear here as they come due.")
                )
            }
        }
        .navigationTitle("To do")
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

    private func rows(_ items: [MainListItem]) -> some View {
        ForEach(items, id: \.chore.id) { item in
            DueRow(item: item) { editor = EditorRequest(chore: item.chore, isNew: false) }
        }
    }
}

private struct DueRow: View {
    @Environment(Store.self) private var store
    let item: MainListItem
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { store.record(.done, item.chore) }
            } label: {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(item.band.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.chore.title) done")

            Button(action: edit) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.chore.title)
                        Text(item.chore.rhythmDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.band.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.band.color)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            Button("Done", systemImage: "checkmark") {
                withAnimation { store.record(.done, item.chore) }
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            if !item.chore.isOneOff {
                Button("Skip", systemImage: "forward.end") {
                    withAnimation { store.record(.skipped, item.chore) }
                }
                .tint(.gray)
            }
        }
        .contextMenu {
            Button("Done", systemImage: "checkmark") { withAnimation { store.record(.done, item.chore) } }
            if !item.chore.isOneOff {
                Button("Skip this time", systemImage: "forward.end") { withAnimation { store.record(.skipped, item.chore) } }
            }
            Button("Pause", systemImage: "pause") { withAnimation { store.record(.paused, item.chore) } }
            Button("Edit…", systemImage: "pencil", action: edit)
        }
    }
}
