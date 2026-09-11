import SwiftUI
import UserNotifications

@main
struct TasksApp: App {
    @State private var store = Store.load()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

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
