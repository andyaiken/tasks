import SwiftUI
import UserNotifications
import TasksCore

/// Settings: a sheet from the gear button on iPhone, and the standard
/// Tasks → Settings… window (⌘,) on the Mac.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(DigestSettings.enabledKey) private var enabled = DigestSettings.defaultEnabled
    @AppStorage(DigestSettings.minutesKey) private var minutes = DigestSettings.defaultMinutes
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        #if os(macOS)
        form
            .frame(width: 480, height: 600)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Daily digest", isOn: $enabled)
                if enabled {
                    DatePicker("Time", selection: time, in: timeRange, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(footer)
            }

            if enabled && status == .denied {
                Section {
                    Button("Turn on notifications in Settings") { openURL(Self.notificationSettingsURL) }
                } footer: {
                    Text("Notifications are turned off for Tasks, so the digest can't be sent.")
                }
            }

            if enabled {
                comingUp
            }

            Section {
                Text(sync.status)
            } header: {
                Text("iCloud")
            } footer: {
                Text("Your list is kept in your iCloud account and syncs to Tasks on your other iPhone and Mac.")
            }
        }
        .formStyle(.grouped)
        .task(id: enabled) {
            status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
        .onChange(of: enabled) { _, isOn in
            DigestScheduler.shared.reschedule(store, userInitiated: isOn)
        }
        .onChange(of: minutes) {
            DigestScheduler.shared.reschedule(store)
        }
    }

    private var comingUp: some View {
        // Reading store.now refreshes this every minute, so a digest drops off once sent.
        let plan = DigestScheduler.plan(for: store, minutes: minutes, now: store.now)
        return Section {
            if plan.isEmpty {
                Text("Nothing is due in the next two weeks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.prefix(7)) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fireDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.digest.summary)
                    Text(item.digest.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Coming up")
        } footer: {
            Text("Assuming nothing else gets done. Ticking tasks off updates these.")
        }
    }

    private var footer: String {
        #if os(macOS)
        "A morning notification listing your tasks that are due or worse. If you also use Tasks on your iPhone, leave this off here so you get one digest, not two."
        #else
        "A morning notification listing your tasks that are due or worse. Nothing is sent on days when nothing is due."
        #endif
    }

    /// The digest time as a Date for the picker; only the hour and minute matter.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now)!
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = max(DigestSettings.earliestMinutes, c.hour! * 60 + c.minute!)
        }
    }

    private var timeRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: CalendarDay.dayStartHour, minute: 0, second: 0, of: .now)!
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: .now)!
        return start...end
    }

    private static var notificationSettingsURL: URL {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        #else
        URL(string: UIApplication.openNotificationSettingsURLString)!
        #endif
    }
}
