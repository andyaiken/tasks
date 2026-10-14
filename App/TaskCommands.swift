import SwiftUI

extension FocusedValues {
    /// Opens the editor for a new task, for File → New Task (⌘N).
    @Entry var newTask: NewTaskAction?
}

/// The window's "new task" action. SwiftUI compares focused values to decide what to update,
/// and closures can't be compared. Every copy does the same thing — opens a new task in the
/// window that provided it — so any two count as equal.
struct NewTaskAction: Equatable {
    let perform: () -> Void

    func callAsFunction() { perform() }

    static func == (lhs: NewTaskAction, rhs: NewTaskAction) -> Bool { true }
}

/// Menu-bar commands. On the Mac, File → New Task replaces File → New Window:
/// there's only one list, so a second window adds nothing.
struct TaskCommands: Commands {
    @FocusedValue(\.newTask) private var newTask

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { newTask?() }
                .keyboardShortcut("n")
                .disabled(newTask == nil)
        }
    }
}
