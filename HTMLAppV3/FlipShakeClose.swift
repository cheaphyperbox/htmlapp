import CoreMotion
import UIKit

@MainActor
final class FlipShakeClose {
    private let manager = CMMotionManager()
    private var duration: TimeInterval = 0
    private var previous: TimeInterval = 0
    private var lastMovement: TimeInterval = 0
    private var action: (() -> Void)?

    func start(onClose: @escaping () -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        action = onClose
        duration = 0
        previous = 0
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let self, let sample else { return }
            let t = sample.timestamp
            let dt = self.previous == 0 ? 0 : max(0, min(0.15, t - self.previous))
            self.previous = t
            guard sample.gravity.z > 0.82 else { self.duration = 0; return }
            let a = sample.userAcceleration
            let force = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if force > 0.13 {
                self.duration += dt
                self.lastMovement = t
            } else if t - self.lastMovement > 0.25 {
                self.duration = 0
            }
            if self.duration >= 1 {
                self.stop()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.action?()
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        duration = 0
        previous = 0
        action = nil
    }
}
