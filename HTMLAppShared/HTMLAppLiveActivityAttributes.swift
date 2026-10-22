import Foundation
import ActivityKit

// Restricted native presentation for an HTMLApp's running activity.
// HTML and JavaScript never execute inside the WidgetKit extension.
@available(iOS 16.2, *)
struct HTMLAppLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var primaryDeadline: Date?
        var secondaryDeadline: Date?
        var subtitle: String
        var value: String
        var progress: Double?
        var accentHex: String
        var secondaryLabel: String?
        var secondaryValue: String?
        var footer: String?
        var backgroundHex: String?
        var compactLabel: String?
    }

    var appID: String
    var activityID: String
    var title: String
    var systemSymbol: String
}
