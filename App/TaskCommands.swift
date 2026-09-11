import SwiftUI

extension FocusedValues {
    /// Opens the editor for a new task, for File → New Task (⌘N).
    @Entry var newTask: (() -> Void)?
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
