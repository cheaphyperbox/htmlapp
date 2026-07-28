import Foundation
import UserNotifications

final class HTMLNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = HTMLNotificationCenterDelegate()

    private override init() {
        super.init()
    }

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let appID = response.notification.request.content.userInfo["htmlAppID"] as? String,
           let url = URL(string: "htmlapp://open?id=\(appID)") {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .htmlAppNotificationOpened, object: url)
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let htmlAppNotificationOpened = Notification.Name("HTMLAppNotificationOpened")
}
