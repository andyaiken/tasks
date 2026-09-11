import SwiftUI
import TasksCore

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    /// A new task started from the menu bar (⌘N) rather than a + button.
    @State private var menuEditor: EditorRequest?

    var body: some View {
        TabView {
            Tab("To do", systemImage: "checklist") {
                NavigationStack { MainListView() }
            }
            Tab("All tasks", systemImage: "list.bullet") {
                NavigationStack { AllTasksView() }
            }
        }
        .focusedSceneValue(\.newTask) {
            menuEditor = EditorRequest(chore: store.newChore(), isNew: true)
        }
        .sheet(item: $menuEditor) { TaskEditor(chore: $0.chore, isNew: $0.isNew) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                store.now = .now
                // A backstop for missed iCloud pushes (§12.4).
                await sync.fetchNow()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.now = .now
                DigestScheduler.shared.reschedule(store)
                Task { await sync.fetchNow() }
            }
        }
        .onChange(of: store.revision, initial: true) {
            DigestScheduler.shared.reschedule(store)
        }
    }
}

/// A request to open the task editor.
struct EditorRequest: Identifiable {
    let chore: Chore
    let isNew: Bool
    var id: UUID { chore.id }
}
