import Foundation
import CoreMotion
import CoreLocation

final class HTMLMotionSupport: NSObject {
    let motionManager = CMMotionManager()
    let compassManager = CLLocationManager()
}
