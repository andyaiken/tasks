import Foundation
import UserNotifications
import TasksCore

/// This device's digest settings (SPEC §9), kept in UserDefaults.
enum DigestSettings {
    static let enabledKey = "digestEnabled"
    static let minutesKey = "digestMinutes"

    /// One digest device per person: on for iPhone, off for Mac unless turned on (§9).
    #if os(macOS)
    static let defaultEnabled = false
    #else
    static let defaultEnabled = true
    #endif

    /// Minutes after midnight; 08:00 by default.
    static let defaultMinutes = 8 * 60

    /// The digest can't come before the day has started (§4, §9).
    static let earliestMinutes = CalendarDay.dayStartHour * 60

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled
    }

    static var minutes: Int {
        max(earliestMinutes, UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes)
    }
}

/// A digest with the moment it will be delivered.
struct ScheduledDigest: Identifiable {
    let day: CalendarDay
    let fireDate: Date
    let digest: Digest
    var id: String { DigestScheduler.identifierPrefix + day.description }
}

/// Schedules the daily digest as local notifications, days ahead (§9). Every change
/// re-plans the whole window, so a stale schedule is corrected rather than added to.
final class DigestScheduler {
    static let shared = DigestScheduler()

    static let daysAhead = 14
    static let identifierPrefix = "digest-"

    private var pending: Task<Void, Never>?

    /// The digests this device would send from `now` on.
    static func plan(for store: Store, minutes: Int, now: Date = .now) -> [ScheduledDigest] {
        let today = CalendarDay(containing: now, in: .current)
        return Digest.upcoming(chores: store.chores, log: store.log, me: store.me, participants: [], from: today, days: daysAhead)
            .compactMap { upcoming in
                guard let fire = Calendar.current.date(from: components(for: upcoming.day, minutes: minutes)),
                      fire > now
                else { return nil }
                return ScheduledDigest(day: upcoming.day, fireDate: fire, digest: upcoming.digest)
            }
    }

    private static func components(for day: CalendarDay, minutes: Int) -> DateComponents {
        DateComponents(year: day.year, month: day.month, day: day.day, hour: minutes / 60, minute: minutes % 60)
    }

    /// Re-plans the digests shortly after a burst of changes. Runs one at a time.
    /// - Parameter userInitiated: the user just turned the digest on, so ask for permission even with no tasks.
    func reschedule(_ store: Store, userInitiated: Bool = false) {
        let previous = pending
        previous?.cancel()
        pending = Task {
            await previous?.value
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await apply(store, userInitiated: userInitiated)
        }
    }

    private func apply(_ store: Store, userInitiated: Bool) async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus

        // Ask once there's something to tell the user about.
        if status == .notDetermined && DigestSettings.enabled && (userInitiated || !store.chores.isEmpty) {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }

        let allowed = DigestSettings.enabled && (status == .authorized || status == .provisional)
        let plan = allowed ? Self.plan(for: store, minutes: DigestSettings.minutes) : []

        // Same identifier for the same day, so adding replaces what was there.
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.digest.summary
            content.body = item.digest.body
            content.sound = .default
            content.threadIdentifier = "digest"
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Self.components(for: item.day, minutes: DigestSettings.minutes),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }

        let wanted = Set(plan.map(\.id))
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }
}

/// Shows notifications even when the app is open at digest time.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
