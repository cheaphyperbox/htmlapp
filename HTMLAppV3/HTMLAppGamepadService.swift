import Foundation
import GameController

/// Foreground-only gamepad events for generated games, explicitly started by
/// the saved app. Rate-limited to avoid flooding WKWebView with axis updates.
@MainActor
final class HTMLAppGamepadService {
    private var tokens: [NSObjectProtocol] = []
    private var sink: (([String: Any]) -> Void)?
    private var lastEventAt: [ObjectIdentifier: TimeInterval] = [:]

    func list() -> [[String: Any]] {
        GCController.controllers().enumerated().map { index, controller in
            [
                "id": index,
                "name": controller.vendorName ?? "Game controller",
                "extendedGamepad": controller.extendedGamepad != nil,
                "microGamepad": controller.microGamepad != nil
            ] as [String: Any]
        }
    }

    func start(_ onEvent: @escaping ([String: Any]) -> Void) -> [[String: Any]] {
        stop()
        sink = onEvent
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.bindControllers() }
            })
        tokens.append(center.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.bindControllers() }
            })
        GCController.startWirelessControllerDiscovery {}
        bindControllers()
        return list()
    }

    private func bindControllers() {
        let controllers = GCController.controllers()
        for (index, controller) in controllers.enumerated() {
            controller.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
                Task { @MainActor in
                    guard let self, self.sink != nil else { return }
                    let key = ObjectIdentifier(controller)
                    let now = Date().timeIntervalSince1970
                    guard now - (self.lastEventAt[key] ?? 0) >= 1.0 / 30.0 else { return }
                    self.lastEventAt[key] = now
                    self.sink?([
                        "id": index,
                        "axes": [
                            pad.leftThumbstick.xAxis.value,
                            pad.leftThumbstick.yAxis.value,
                            pad.rightThumbstick.xAxis.value,
                            pad.rightThumbstick.yAxis.value
                        ],
                        "buttons": [
                            pad.buttonA.value, pad.buttonB.value,
                            pad.buttonX.value, pad.buttonY.value,
                            pad.leftShoulder.value, pad.rightShoulder.value,
                            pad.leftTrigger.value, pad.rightTrigger.value
                        ],
                        "dpad": [pad.dpad.xAxis.value, pad.dpad.yAxis.value]
                    ])
                }
            }
        }
        sink?(["type": "controllersChanged", "controllers": list()])
    }

    func stop() {
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
        GCController.stopWirelessControllerDiscovery()
        sink = nil
        lastEventAt.removeAll()
    }
}
