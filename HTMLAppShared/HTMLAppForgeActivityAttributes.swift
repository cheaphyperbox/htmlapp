import Foundation
import ActivityKit

@available(iOS 16.2, *)
struct HTMLAppForgeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var progress: Double
    }
    var jobID: String
    var isEdit: Bool
}
