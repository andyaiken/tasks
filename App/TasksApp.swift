import SwiftUI

@main
struct TasksApp: App {
    @State private var store = Store.load()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        #if os(macOS)
        .defaultSize(width: 480, height: 680)
        #endif
    }
}
