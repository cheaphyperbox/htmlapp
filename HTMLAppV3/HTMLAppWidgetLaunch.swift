import Foundation

/// Widget URLs contain identifiers only. The app resolves every action from
/// its own widget store, never from arbitrary URL-supplied route or payload.
@MainActor
enum HTMLAppWidgetLaunchStore {
    static let changed = Notification.Name("HTMLApp.WidgetLaunchContext")
    private static var pending: [String: [String: String]] = [:]

    static func receive(url: URL, appID: String) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = parts.queryItems,
              let widgetID = items.first(where: { $0.name == "widget" })?.value,
              let actionID = items.first(where: { $0.name == "action" })?.value,
              let definition = HTMLAppWidgetStore.definitions(appID: appID)
                .first(where: { $0.widgetID == widgetID }) else { return }
        let itemID = items.first(where: { $0.name == "item" })?.value
        let action: HTMLAppWidgetAction?
        if let itemID {
            action = definition.snapshot.items?.first(where: { $0.id == itemID })?.action
        } else {
            action = definition.action
        }
        guard let action, action.id == actionID,
              ["open", "route", "event"].contains(action.type) else { return }
        var context = [
            "source": "widget",
            "widgetId": widgetID,
            "actionId": actionID,
            "type": action.type,
            "route": action.route ?? ""
        ]
        if let itemID { context["itemId"] = itemID }
        if let payload = action.payload { context["payload"] = payload }
        pending[appID] = context
        NotificationCenter.default.post(name: changed, object: appID)
    }

    static func take(appID: String) -> [String: String]? {
        pending.removeValue(forKey: appID)
    }

    static func javascript(for context: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: context, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return """
        window.htmlappLaunch = \(json);
        window.dispatchEvent(new CustomEvent('htmlapplaunch', {detail: window.htmlappLaunch}));
        """
    }
}
