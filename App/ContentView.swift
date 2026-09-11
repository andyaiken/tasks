import SwiftUI
import TasksCore

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("To do", systemImage: "checklist") {
                NavigationStack { MainListView() }
            }
            Tab("All tasks", systemImage: "list.bullet") {
                NavigationStack { AllTasksView() }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                store.now = .now
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.now = .now
                DigestScheduler.shared.reschedule(store)
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
