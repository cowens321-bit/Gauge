import AppKit
import UserNotifications

/// Posts high-usage alerts as user notifications; clicking one opens Gauge on that app.
@MainActor
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotifier()
    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
        MonitorModel.shared.onAlerts = { [weak self] in self?.post($0) }
    }

    static func requestAuthorization(_ done: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    static func isDenied(_ done: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let denied = s.authorizationStatus == .denied
            Task { @MainActor in done(denied) }
        }
    }

    func post(_ alerts: [UsageAlertTracker.Alert]) {
        let units = ByteUnits(rawValue: UserDefaults.standard.string(forKey: Pref.displayUnits) ?? "") ?? .binary
        for a in alerts {
            let c = UNMutableNotificationContent()
            let minutes = max(1, Int((a.duration / 60).rounded()))
            switch a.kind {
            case .cpu:
                c.title = "\(a.name) is using a lot of CPU"
                c.body = "About \(Int(a.value.rounded()))% of a core for \(minutes) minute\(minutes == 1 ? "" : "s"). Click to see what it’s doing."
            case .memory:
                c.title = "\(a.name) is using a lot of memory"
                c.body = "\(Fmt.bytes(UInt64(a.value), units)), more than a quarter of your Mac’s memory, for \(minutes) minute\(minutes == 1 ? "" : "s")."
            }
            c.sound = nil
            c.userInfo = ["group": a.groupID]
            center.add(UNNotificationRequest(identifier: "gauge.\(a.kind.rawValue).\(a.groupID)", content: c, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["group"] as? String
        Task { @MainActor in
            MonitorModel.shared.requestedSelection = id
            NotificationCenter.default.post(name: .gaugeOpenMainWindow, object: nil)
            done()
        }
    }
}
