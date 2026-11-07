import Foundation
import UserNotifications

/// Daily study reminder (local notifications only — nothing leaves the Mac).
/// Pending notifications for the next 7 days are rebuilt at launch, when the settings change and when today's goal
/// is reached, so a met day never nags and a few days away from the app still get reminders.
enum Reminder {
    static let days = 7
    static let idPrefix = "parley.reminder."
    static let defaultMinutes = 20 * 60 // 20:00

    /// When to remind: the chosen time on each of the next `days` days, skipping today once the time has passed or
    /// the goal is already met.
    nonisolated static func fireDates(now: Date, minutes: Int, metToday: Bool, days: Int = days,
                                      calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: now)
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        let dates = (0...days).compactMap { d -> Date? in
            guard let day = calendar.date(byAdding: .day, value: d, to: start),
                  let at = calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: day) else { return nil }
            if d == 0, metToday || at <= now { return nil }
            return at
        }
        return Array(dates.prefix(days))
    }

    nonisolated static func body(remaining: Int?) -> String {
        if let remaining, remaining > 0 {
            return "Còn \(remaining) XP nữa là đạt mục tiêu hôm nay — 10 phút luyện nghe hoặc ôn từ là đủ."
        }
        return "Dành 10 phút luyện tiếng Anh để giữ chuỗi ngày học nhé."
    }

    /// The app's activity log, set at launch so Settings can reschedule without holding the store.
    @MainActor static weak var activity: ActivityStore?

    /// Rebuilds the pending reminders from the saved settings (off → removes them). Never in a sandboxed run.
    @MainActor static func reschedule() { reschedule(activity: activity) }

    /// The previous rebuild; each new one waits for it, so a quick off/on can't leave stale reminders behind.
    @MainActor private static var last: Task<Void, Never>?

    @MainActor static func reschedule(activity: ActivityStore?) {
        guard !AppDefaults.sandboxed else { return }
        let d = AppDefaults.store
        let on = d.bool(forKey: "reminderOn")
        let minutes = d.object(forKey: "reminderMinutes") as? Int ?? defaultMinutes
        let met = activity?.metToday ?? false
        let remaining = activity.map { max($0.goal - $0.todayXP, 0) }
        let dates = on ? fireDates(now: .now, minutes: minutes, metToday: met) : []
        let previous = last
        last = Task { @MainActor in
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            let calendar = Calendar.current
            for (i, date) in dates.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Parley — giờ học tiếng Anh"
                content.body = body(remaining: i == 0 && calendar.isDateInToday(date) ? remaining : nil)
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let request = UNNotificationRequest(identifier: idPrefix + StudyStore.day(date), content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                do { try await center.add(request) } catch { print("reminder:", error.localizedDescription) }
            }
        }
    }

    /// True when macOS currently blocks Parley's notifications (checked each time Settings opens).
    @MainActor static func isDenied() async -> Bool {
        guard !AppDefaults.sandboxed else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Asks for permission when the user turns reminders on; false when macOS says no.
    @MainActor static func requestPermission() async -> Bool {
        guard !AppDefaults.sandboxed else { return false }
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } catch {
            print("reminder permission:", error.localizedDescription)
            return false
        }
    }
}
