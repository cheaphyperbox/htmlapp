import Foundation
import UIKit
import CoreLocation
import WebKit

@MainActor
final class HTMLLocationBridge: NSObject, CLLocationManagerDelegate {
    private weak var webView: WKWebView?
    private let appID: String
    private let manager = CLLocationManager()
    private var callbacks: [String: DispatchWorkItem] = [:]

    init(webView: WKWebView, appID: String) {
        self.webView = webView
        self.appID = appID
        super.init()
        manager.delegate = self
    }

    func request(callbackID: String, highAccuracy: Bool, timeoutMS: Double?) {
        resolvePolicy { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.sendError(callbackID, code: 1, message: "Location permission was denied for this HTML app.")
                return
            }

            self.manager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
            self.queue(callbackID: callbackID, timeoutMS: timeoutMS)

            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(callbackID, code: 1, message: "Location access is disabled in iOS Settings.")
            @unknown default:
                self.finish(callbackID, code: 2, message: "Location is currently unavailable.")
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if !callbacks.isEmpty { manager.requestLocation() }
        case .denied, .restricted:
            finishAll(code: 1, message: "Location access is disabled in iOS Settings.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishAll(code: 2, message: "No location was returned.")
            return
        }

        let ids = Array(callbacks.keys)
        callbacks.values.forEach { $0.cancel() }
        callbacks.removeAll()

        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": max(0, location.horizontalAccuracy),
            "altitude": location.altitude,
            "altitudeAccuracy": max(0, location.verticalAccuracy),
            "heading": location.course >= 0 ? location.course : NSNull(),
            "speed": location.speed >= 0 ? location.speed : NSNull(),
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000
        ]

        for id in ids {
            callJavaScript(function: "__htmlappLocationSuccess", arguments: [id, payload])
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        let message: String
        if nsError.domain == kCLErrorDomain && nsError.code == CLError.locationUnknown.rawValue {
            message = "Location is temporarily unavailable. Try again in a moment."
        } else {
            message = error.localizedDescription
        }
        finishAll(code: 2, message: message)
    }

    private func queue(callbackID: String, timeoutMS: Double?) {
        callbacks[callbackID]?.cancel()
        let seconds = max(1, min((timeoutMS ?? 15000) / 1000, 60))
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.callbacks.removeValue(forKey: callbackID) != nil else { return }
            self.sendError(callbackID, code: 3, message: "The location request timed out.")
        }
        callbacks[callbackID] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    private func finish(_ callbackID: String, code: Int, message: String) {
        callbacks.removeValue(forKey: callbackID)?.cancel()
        sendError(callbackID, code: code, message: message)
    }

    private func finishAll(code: Int, message: String) {
        let ids = Array(callbacks.keys)
        callbacks.values.forEach { $0.cancel() }
        callbacks.removeAll()
        ids.forEach { sendError($0, code: code, message: message) }
    }

    private func resolvePolicy(completion: @escaping (Bool) -> Void) {
        guard appID != "PREVIEW" else {
            completion(false)
            return
        }

        switch HTMLPermissionStore.choice(for: .location, appID: appID) {
        case .allow:
            completion(true)
        case .deny:
            completion(false)
        case .ask:
            guard let presenter = topViewController() else {
                completion(false)
                return
            }
            let alert = UIAlertController(
                title: "Allow Location?",
                message: "This saved HTML app wants your current location. You can change this later from its Permissions page.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in
                HTMLPermissionStore.set(.deny, for: .location, appID: self.appID)
                completion(false)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                HTMLPermissionStore.set(.allow, for: .location, appID: self.appID)
                completion(true)
            })
            presenter.present(alert, animated: true)
        }
    }

    private func sendError(_ callbackID: String, code: Int, message: String) {
        callJavaScript(function: "__htmlappLocationError", arguments: [callbackID, code, message])
    }

    private func callJavaScript(function: String, arguments: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.\(function).apply(null, \(json));")
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }

        var current = root
        while let presented = current.presentedViewController { current = presented }
        if let navigation = current as? UINavigationController { return navigation.visibleViewController ?? navigation }
        if let tab = current as? UITabBarController { return tab.selectedViewController ?? tab }
        return current
    }
}
