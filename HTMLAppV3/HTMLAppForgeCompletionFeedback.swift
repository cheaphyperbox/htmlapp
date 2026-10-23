import UIKit
import UserNotifications

@MainActor
enum HTMLAppForgeCompletionFeedback {
    static func announce(edit: Bool) async {
        guard UIApplication.shared.applicationState != .active else {
            for index in 0..<3 {
                if index > 0 { try? await Task.sleep(nanoseconds: 260_000_000) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = edit ? "Your HTMLApp edit is ready" : "Your new HTMLApp is ready"
        content.body = "Open HTMLApp to review your completed AI work."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        try? await center.add(request)
    }
}
