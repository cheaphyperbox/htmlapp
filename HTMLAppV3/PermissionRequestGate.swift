import Foundation
import UIKit

@MainActor
enum PermissionRequestGate {
    enum Verdict { case proceed, ignore, autoDenied }
    private static var recent: [String: [TimeInterval]] = [:]
    private static var notices: Set<String> = []
    private static var pending: [String: [(Bool) -> Void]] = [:]

    static func queue(appID: String, permission: String,
                      completion: @escaping (Bool) -> Void) -> Bool {
        let key = appID + ":" + permission
        let first = pending[key] == nil
        pending[key, default: []].append(completion)
        return first
    }

    static func hasPending(appID: String, permission: String) -> Bool {
        pending[appID + ":" + permission] != nil
    }

    static func finish(appID: String, permission: String, allowed: Bool) {
        let callbacks = pending.removeValue(forKey: appID + ":" + permission) ?? []
        callbacks.forEach { $0(allowed) }
    }

    static func showNotice(appID: String, title: String) {
        guard !notices.contains(appID + title) else { return }
        notices.insert(appID + title)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var current = root
        while let next = current.presentedViewController { current = next }
        if let shown = current as? UIAlertController {
            shown.title = title + " blocked"
            shown.message = "This HTML app requested this permission too often. It is now denied. To change it, open Library, hold the app and choose Permissions."
            shown.actions.forEach { $0.isEnabled = $0.style == .cancel }
            return
        }
        let alert = UIAlertController(title: title + " blocked",
            message: "This HTML app requested this permission more than 10 times in 15 seconds. Open Library, hold this app, and select Permissions to change it.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        current.present(alert, animated: true)
    }

    static func check(appID: String, permission: String) -> Verdict {
        let key = appID + ":" + permission
        let now = ProcessInfo.processInfo.systemUptime
        var times = (recent[key] ?? []).filter { now - $0 < 15 }
        let repeated = times.last.map { now - $0 < 1 } ?? false
        times.append(now)
        recent[key] = times
        if times.count > 10 { return .autoDenied }
        return repeated ? .ignore : .proceed
    }
}
