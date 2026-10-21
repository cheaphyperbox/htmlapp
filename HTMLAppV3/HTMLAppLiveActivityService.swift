import Foundation
import ActivityKit

@available(iOS 16.2, *)
enum HTMLAppLiveActivityService {
    enum Failure: LocalizedError {
        case unavailable, badArguments, limit, notFound
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Live Activities are disabled or not available on this iOS device."
            case .badArguments: return "A Live Activity needs a safe id and a nonempty title."
            case .limit: return "This HTML app can run up to three Live Activities at once."
            case .notFound: return "No active Live Activity with that id belongs to this HTML app."
            }
        }
    }

    private static func clip(_ any: Any?, max: Int) -> String {
        String(((any as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(max))
    }

    private static func validID(_ any: Any?) -> String? {
        let raw = clip(any, max: 65)
        guard !raw.isEmpty, raw.count <= 64,
              raw.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return raw
    }

    private static func symbol(_ value: Any?) -> String {
        let requested = clip(value, max: 48)
        let allowed: Set<String> = [
            "timer", "clock.fill", "calendar", "checklist", "checkmark.circle.fill",
            "airplane", "shippingbox.fill", "car.fill", "bicycle", "figure.walk",
            "heart.fill", "star.fill", "bell.fill", "bolt.fill", "flame.fill",
            "moon.stars.fill", "sun.max.fill", "music.note", "flag.fill", "fork.knife",
            "map.fill", "location.fill", "book.fill", "figure.run", "leaf.fill"
        ]
        return allowed.contains(requested) ? requested : "app.fill"
    }

    private static func content(_ args: [String: Any],
                                previous: HTMLAppLiveActivityAttributes.ContentState? = nil
    ) -> HTMLAppLiveActivityAttributes.ContentState {
        let hex = clip(args["accentHex"], max: 7)
        let goodHex = hex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
        let value = args["progress"] as? NSNumber
        return .init(
            subtitle: args["subtitle"] == nil ? (previous?.subtitle ?? "") : clip(args["subtitle"], max: 120),
            value: args["value"] == nil ? (previous?.value ?? "") : clip(args["value"], max: 24),
            progress: value.map { max(0, min(1, $0.doubleValue)) } ?? previous?.progress,
            accentHex: goodHex ? hex : (previous?.accentHex ?? "#3576D3"),
            secondaryLabel: args["secondaryLabel"] == nil ? previous?.secondaryLabel : clip(args["secondaryLabel"], max: 36),
            secondaryValue: args["secondaryValue"] == nil ? previous?.secondaryValue : clip(args["secondaryValue"], max: 28),
            footer: args["footer"] == nil ? previous?.footer : clip(args["footer"], max: 90)
        )
    }

    private static func matching(appID: String, id: String) -> Activity<HTMLAppLiveActivityAttributes>? {
        Activity<HTMLAppLiveActivityAttributes>.activities.first {
            $0.attributes.appID == appID && $0.attributes.activityID == id
        }
    }

    static func list(appID: String) -> [[String: Any]] {
        Activity<HTMLAppLiveActivityAttributes>.activities
            .filter { $0.attributes.appID == appID }
            .map {
                ["id": $0.attributes.activityID, "title": $0.attributes.title,
                 "systemSymbol": $0.attributes.systemSymbol,
                 "subtitle": $0.content.state.subtitle,
                 "value": $0.content.state.value,
                 "secondaryLabel": $0.content.state.secondaryLabel ?? "",
                 "secondaryValue": $0.content.state.secondaryValue ?? "",
                 "footer": $0.content.state.footer ?? "",
                 "state": String(describing: $0.activityState)]
            }
    }

    static func start(appID: String, args: [String: Any]) throws -> [String: Any] {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw Failure.unavailable }
        guard let id = validID(args["id"]),
              !clip(args["title"], max: 75).isEmpty else { throw Failure.badArguments }
        if let existing = matching(appID: appID, id: id) {
            return ["id": id, "activityID": existing.id, "alreadyActive": true]
        }
        guard list(appID: appID).count < 3 else { throw Failure.limit }
        let attrs = HTMLAppLiveActivityAttributes(
            appID: appID, activityID: id,
            title: clip(args["title"], max: 75),
            systemSymbol: symbol(args["systemSymbol"])
        )
        let activity = try Activity.request(
            attributes: attrs,
            content: ActivityContent(state: content(args), staleDate: nil),
            pushType: nil
        )
        return ["id": id, "activityID": activity.id, "started": true]
    }

    static func update(appID: String, args: [String: Any]) async throws -> [String: Any] {
        guard let id = validID(args["id"]) else { throw Failure.badArguments }
        guard let activity = matching(appID: appID, id: id) else { throw Failure.notFound }
        await activity.update(ActivityContent(state: content(args, previous: activity.content.state), staleDate: nil))
        return ["id": id, "updated": true]
    }

    static func end(appID: String, args: [String: Any]) async throws -> [String: Any] {
        guard let id = validID(args["id"]) else { throw Failure.badArguments }
        guard let activity = matching(appID: appID, id: id) else { throw Failure.notFound }
        await activity.end(ActivityContent(state: activity.content.state, staleDate: nil),
                           dismissalPolicy: .immediate)
        return ["id": id, "ended": true]
    }
}
