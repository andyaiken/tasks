import CloudKit
import SwiftUI
import UserNotifications

@main
struct TasksApp: App {
    @State private var store: Store
    @State private var sync: CloudSync
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        #if DEBUG
        // Test builds only: `-screenshots` shows example tasks and leaves iCloud and the real list alone.
        let screenshots = CommandLine.arguments.contains("-screenshots")
        let store = screenshots ? Store.demo() : Store.load()
        #else
        let screenshots = false
        let store = Store.load()
        #endif
        _store = State(initialValue: store)
        _sync = State(initialValue: CloudSync(store: store, enabled: !screenshots))
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(sync)
                .task { await sync.start() }
                .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                    Task { await sync.start() }
                }
        }
        .commands { TaskCommands() }
        #if os(macOS)
        .defaultSize(width: 480, height: 680)
        #endif

        #if os(macOS)
        // Tasks → Settings… (⌘,), the Mac's standard place for settings.
        Settings {
            SettingsView()
                .environment(store)
                .environment(sync)
        }
        #endif
    }
}

#if os(macOS)
/// Quits the app when its window closes, rather than leaving it running with no window.
/// The digest still arrives — it's booked with the system in advance — and sync catches up at next launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
