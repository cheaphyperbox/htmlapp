import Foundation
import WidgetKit

/// WidgetKit owns the actual render time. This coalesces nearby committed writes
/// without delaying user-driven changes by minutes or polling in the background.
enum HTMLAppWidgetReloadCoordinator {
    private static var pending = false

    static func request() {
        DispatchQueue.main.async {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                pending = false
                WidgetCenter.shared.reloadTimelines(ofKind: "HTMLAppPrimaryWidget")
                WidgetCenter.shared.reloadTimelines(ofKind: "HTMLAppVoiceCreate")
            }
        }
    }
}
