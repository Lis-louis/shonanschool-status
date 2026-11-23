import Foundation
import UserNotifications

/// 締切のローカル通知。通知は端末内だけで完結する。
/// `swift run` で起動した場合は .app バンドルではないため通知は使えない。
enum DeadlineNotifier {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    private static let prefix = "deadline-"

    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func reschedule(_ deadlines: [Deadline], hoursBefore: Int, now: Date = .now) async {
        guard isAvailable else { return }
        await cancelAll()
        let center = UNUserNotificationCenter.current()
        for d in deadlines.prefix(50) {
            let fire = d.due.addingTimeInterval(-Double(hoursBefore) * 3600)
            guard fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "締切が近づいています"
            content.body = [d.title, d.course].compactMap { $0 }.joined(separator: " / ")
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(identifier: prefix + d.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }

    static func cancelAll() async {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }
}
