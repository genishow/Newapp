import Foundation
import UIKit
import UserNotifications

/// Notifications (D-449):
/// - "Your voiceover is ready" pushed by the server when a job finishes. Pushes need the
///   App Store or TestFlight build; a SideStore build never gets a token and simply skips it.
/// - "Deleted in 3 hours" reminders, scheduled on the phone itself, so they work in every build.
/// Permission is asked once, after the first finished voiceover or video, never at launch.
@MainActor
enum Notifications {
    static let tokenKey = "kinbir.pushToken"
    private static let askedKey = "kinbir.notificationsAsked"
    /// Server files are deleted 48 hours after they finish; the reminder comes 3 hours before.
    static let reminderAfter: TimeInterval = 45 * 3600

    weak static var state: AppState?

    /// True when the phone has never been asked: the app can still offer it.
    static func canAsk() async -> Bool {
        guard !Launch.isMock else { return false }
        return await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .notDetermined
    }

    /// Asks now, because the person tapped "Tell me when it is ready".
    static func askNow() async {
        guard !Launch.isMock else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Called when a result is ready to play. Asks the first time only.
    static func askOnce() async {
        guard !Launch.isMock else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
            UserDefaults.standard.set(true, forKey: askedKey)
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    /// At launch: refresh the token when permission was already given.
    static func refreshRegistration() async {
        guard !Launch.isMock else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func didRegister(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        guard let state, state.accessCode != nil else { return }
        Task { try? await state.api.registerDevice(token: token) }
    }

    /// On sign out: this phone stops getting that account's notifications.
    static func signedOut(api: KinbirAPI, accessCode: String?) {
        guard !Launch.isMock else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard let token = UserDefaults.standard.string(forKey: tokenKey), let accessCode else { return }
        Task { try? await api.unregisterDevice(token: token, accessCode: accessCode) }
    }

    /// A reminder 3 hours before the server deletes this result. Only when allowed.
    static func remindBeforeDelete(id: String, isVideo: Bool, finishedAt: String?) async {
        guard !Launch.isMock else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }
        let finished = Fmt.date(fromServer: finishedAt) ?? Date()
        let fireAt = finished.addingTimeInterval(reminderAfter)
        let wait = fireAt.timeIntervalSinceNow
        guard wait > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = isVideo ? T("Your video is deleted in 3 hours") : T("Your voiceover is deleted in 3 hours")
        content.body = T("Save it now if you want to keep it.")
        content.sound = .default
        content.userInfo = ["kind": isVideo ? "video" : "voiceover", "job_id": id]
        let request = UNNotificationRequest(
            identifier: "expiry." + id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
        try? await center.add(request)
    }

    /// A tapped notification opens what it is about.
    static func route(from userInfo: [AnyHashable: Any]) -> Route? {
        // "Your video was approved": open the page that shows it
        if (userInfo["kind"] as? String) == "promo" { return .promo }
        guard let id = userInfo["job_id"] as? String, !id.isEmpty else { return nil }
        if (userInfo["kind"] as? String) == "video" {
            return .videoJob(id, landscape: false)
        }
        return .job(id)
    }
}

/// Receives the push token and taps on notifications.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Notifications.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected in builds without push (SideStore). The reminders still work.
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            if let route = Notifications.route(from: info) {
                Notifications.state?.open(route)
            }
            completionHandler()
        }
    }
}
