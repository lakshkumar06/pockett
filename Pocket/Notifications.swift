import SwiftUI
import UserNotifications

@MainActor final class PocketNotifications: ObservableObject {
    static let shared = PocketNotifications()
    @Published var pendingURL: URL?
    @Published var token: String?
    @Published var status = "Activity is available in Pocket. Device push has not been enabled."
    var deviceID: String {
        if let value = UserDefaults.standard.string(forKey: "pocket.installation") { return value }
        let value = UUID().uuidString; UserDefaults.standard.set(value, forKey: "pocket.installation"); return value
    }
    var environment: String { Bundle.main.object(forInfoDictionaryKey: "PocketAPNSEnvironment") as? String == "production" ? "production" : "sandbox" }
    func requestPermission() async {
        guard Bundle.main.object(forInfoDictionaryKey: "PocketPushEnabled") as? String == "YES" else {
            status = "Local test mode: refresh Activity to see updates. This build has no signed APNs capability."; return
        }
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if allowed { status = "Registering this device…"; UIApplication.shared.registerForRemoteNotifications() }
            else { status = "Device notifications are off. Activity is still available in Pocket." }
        } catch { status = "Couldn't enable device notifications. Activity is still available." }
    }
    func clearSession() {
        pendingURL = nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UIApplication.shared.unregisterForRemoteNotifications(); token = nil
    }
    func received(_ info: [AnyHashable: Any]) {
        guard let app = info["appId"] as? String, let event = info["eventId"] as? String,
              app.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
              event.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil,
              let url = URL(string: "pocket://app/\(app)?event=\(event)") else { return }
        pendingURL = url // Backend reauthorizes and resolves the target; payload URLs are ignored.
    }
}

final class PocketAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PocketNotifications.shared.token = deviceToken.map { String(format: "%02x", $0) }.joined()
            PocketNotifications.shared.status = "Device registered with Apple. Delivery still depends on your Pocket server."
        }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PocketNotifications.shared.status = "Device push is unavailable. Activity refresh still works." }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in PocketNotifications.shared.received(info); completionHandler() }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Foreground inbox refresh is authoritative. Don't show a stale cross-account banner.
        completionHandler([])
    }
}
