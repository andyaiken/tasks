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
        .alert(invitationTitle, isPresented: showingInvitation, presenting: sync.invitation) { invitation in
            if invitation.blocked != nil {
                Button("OK") {}
            } else if invitation.taskCount > 0 {
                Button("Join and Bring My Tasks") { Task { await sync.accept(invitation, bringingTasks: true) } }
                Button("Join Without Them") { Task { await sync.accept(invitation, bringingTasks: false) } }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("Join") { Task { await sync.accept(invitation, bringingTasks: false) } }
                Button("Not Now", role: .cancel) {}
            }
        } message: { invitation in
            Text(invitationMessage(invitation))
        }
        .background {
            Color.clear
                .alert("Needs Doing", isPresented: showingNotice) {
                    Button("OK") {}
                } message: {
                    Text(sync.notice ?? "")
                }
        }
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

extension ContentView {
    private var showingInvitation: Binding<Bool> {
        Binding { sync.invitation != nil } set: { if !$0 { sync.invitation = nil } }
    }

    private var showingNotice: Binding<Bool> {
        Binding { sync.notice != nil } set: { if !$0 { sync.notice = nil } }
    }

    private var invitationTitle: String {
        guard let invitation = sync.invitation else { return "" }
        return invitation.blocked == nil
            ? "Join \(invitation.ownerName)'s List?"
            : "Can't Join \(invitation.ownerName)'s List"
    }

    /// One list at a time (§7, §13).
    private func invitationMessage(_ invitation: Invitation) -> String {
        if let blocked = invitation.blocked { return blocked }
        let owner = invitation.ownerName
        if let leaving = invitation.leaving {
            return "You'll leave \(leaving)'s list, because you can only be in one list at a time."
        }
        var message = "You'll see and tick off the same tasks as everyone in \(owner)'s list."
        if invitation.taskCount > 0 {
            let tasks = invitation.taskCount == 1 ? "a task" : "\(invitation.taskCount) tasks"
            message += "\n\nYou have \(tasks) of your own. Bring them into \(owner)'s list? Either way they stay in your own list, for if you ever leave."
        }
        return message
    }
}

/// A request to open the task editor.
struct EditorRequest: Identifiable {
    let chore: Chore
    let isNew: Bool
    var id: UUID { chore.id }
}
