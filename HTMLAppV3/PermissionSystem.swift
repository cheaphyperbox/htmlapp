import SwiftUI
import UIKit
import AVFoundation
import CoreLocation
import UserNotifications
import WebKit

enum HTMLPermission: String, CaseIterable, Identifiable {
    case ai
    case spotlight
    case health
    case nfc
    case camera
    case microphone
    case location
    case roadData
    case motion
    case bluetooth
    case notifications
    case liveActivities
    case contacts
    case photoLibrary
    case calendar
    case reminders
    case biometrics
    case localNetwork
    case clipboard
    case files
    case externalApps
    case displayControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI Provider Access"
        case .spotlight: return "Spotlight Search"
        case .health: return "Health Data"
        case .nfc: return "NFC Reader"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .location: return "Location"
        case .roadData: return "Road Data Lookup"
        case .motion: return "Motion & Steps"
        case .bluetooth: return "Bluetooth Devices"
        case .notifications: return "Notifications"
        case .liveActivities: return "Live Activities"
        case .contacts: return "Contacts"
        case .photoLibrary: return "Photos"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .biometrics: return "Biometrics"
        case .localNetwork: return "Local Network"
        case .clipboard: return "Clipboard"
        case .files: return "Choose Files"
        case .externalApps: return "Open Other Apps"
        case .displayControl: return "Screen & Display Controls"
        }
    }

    var detail: String {
        switch self {
        case .ai: return "Allows this HTML app to send prompts to your chosen AI provider, unless on-device processing is used. Requests may consume API credits."
        case .spotlight: return "Allows this saved HTML app to index selected titles and summaries in iOS Spotlight search."
        case .health: return "Allows this saved app to request read-only HealthKit access to the data types you approve in the iOS Health authorization screen."
        case .nfc: return "Allows this saved app to initiate foreground NFC tag scans after your approval."
        case .camera: return "Allows this HTML app to capture video."
        case .microphone: return "Allows this HTML app to record audio."
        case .location: return "Allows this HTML app to request your current position."
        case .roadData: return "Allows this saved app to share GPS coordinates with an OpenStreetMap Overpass server to request mapped road and speed-limit tags. Third-party service; requires internet."
        case .motion: return "Allows this HTML app to read motion and walking-step history after iOS permission."
        case .bluetooth: return "Allows this HTML app to discover nearby Bluetooth Low Energy devices when you ask it to scan."
        case .notifications: return "Allows this HTML app to send native iOS notifications."
        case .liveActivities: return "Allows this HTML app to show a running status on the Lock Screen and Dynamic Island."
        case .contacts: return "Allows this HTML app to select or read contacts through the native Contacts framework."
        case .photoLibrary: return "Allows this HTML app to open the native photo picker for selected photos and videos."
        case .calendar: return "Allows this HTML app to read and create calendar events through EventKit."
        case .reminders: return "Allows this HTML app to read and create reminders through EventKit."
        case .biometrics: return "Allows this HTML app to request Face ID, Touch ID, or device authentication."
        case .localNetwork: return "Allows this HTML app to connect to devices and servers on your private Wi-Fi or LAN."
        case .clipboard: return "Allows this HTML app to read and write text on your device clipboard."
        case .files: return "Allows this HTML app to open the iOS file picker for files you explicitly select."
        case .externalApps: return "Allows this HTML app to open links or other installed apps outside HTMLApp."
        case .displayControl: return "Allows this HTML app to keep the display awake or adjust brightness when you request it."
        }
    }

    var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .spotlight: return "magnifyingglass"
        case .health: return "heart.text.square"
        case .nfc: return "wave.3.right"
        case .camera: return "camera.fill"
        case .microphone: return "mic.fill"
        case .location: return "location.fill"
        case .roadData: return "road.lanes"
        case .motion: return "figure.walk"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .notifications: return "bell.fill"
        case .liveActivities: return "timer"
        case .contacts: return "person.crop.circle.badge.checkmark"
        case .photoLibrary: return "photo.on.rectangle.angled"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .biometrics: return "faceid"
        case .localNetwork: return "network"
        case .clipboard: return "doc.on.clipboard"
        case .files: return "folder"
        case .externalApps: return "arrow.up.forward.app"
        case .displayControl: return "sun.max"
        }
    }
}

enum HTMLPermissionChoice: String, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: return "Ask"
        case .allow: return "Allow"
        case .deny: return "Don’t allow"
        }
    }
}

enum HTMLPermissionStore {
    static func requested(appID: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "htmlPermission.used." + appID) ?? [])
    }
    static func markRequested(_ name: String, appID: String) {
        var names = requested(appID: appID)
        guard names.insert(name).inserted else { return }
        UserDefaults.standard.set(Array(names), forKey: "htmlPermission.used." + appID)
    }

    static func choice(for permission: HTMLPermission, appID: String) -> HTMLPermissionChoice {
        let key = storageKey(permission, appID: appID)
        return HTMLPermissionChoice(rawValue: UserDefaults.standard.string(forKey: key) ?? "ask") ?? .ask
    }

    static func set(_ choice: HTMLPermissionChoice, for permission: HTMLPermission, appID: String) {
        UserDefaults.standard.set(choice.rawValue, forKey: storageKey(permission, appID: appID))
    }

    static func reset(appID: String) {
        for permission in HTMLPermission.allCases {
            UserDefaults.standard.removeObject(forKey: storageKey(permission, appID: appID))
        }
    }

    private static func storageKey(_ permission: HTMLPermission, appID: String) -> String {
        "htmlPermission.\(appID).\(permission.rawValue)"
    }
}

@MainActor
final class NativePermissionCoordinator: NSObject, CLLocationManagerDelegate {
    private weak var webView: WKWebView?
    private let appID: String
    private var locationManager: CLLocationManager?
    private var pendingLocationCallbacks: [String] = []
    private var locationTimeouts: [String: DispatchWorkItem] = [:]

    init(webView: WKWebView, appID: String) {
        self.webView = webView
        self.appID = appID
        super.init()
    }

    func requestMedia(type: WKMediaCaptureType, completion: @escaping (WKPermissionDecision) -> Void) {
        let required: [HTMLPermission]
        switch type {
        case .camera: required = [.camera]
        case .microphone: required = [.microphone]
        case .cameraAndMicrophone: required = [.camera, .microphone]
        @unknown default: required = [.camera, .microphone]
        }

        resolvePolicies(required) { [weak self] allowed in
            guard let self, allowed else {
                completion(.deny)
                return
            }
            self.requestSystemMedia(required) { granted in
                completion(granted ? .grant : .deny)
            }
        }
    }

    func requestLocation(callbackID: String, highAccuracy: Bool, timeoutMS: Double?) {
        resolvePolicy(.location) { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.resolveLocationError(callbackID, code: 1, message: "Location permission was denied for this HTML app.")
                return
            }

            let manager = self.locationManager ?? CLLocationManager()
            self.locationManager = manager
            manager.delegate = self
            manager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters

            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.beginLocation(callbackID: callbackID, manager: manager, timeoutMS: timeoutMS)
            case .denied, .restricted:
                self.resolveLocationError(callbackID, code: 1, message: "Location access is disabled in iOS Settings.")
            @unknown default:
                self.resolveLocationError(callbackID, code: 2, message: "Location is currently unavailable.")
            }
        }
    }

    func requestNotificationPermission(callbackID: String) {
        resolvePolicy(.notifications) { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.resolveNotificationPermission(callbackID, value: "denied")
                return
            }

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    self.resolveNotificationPermission(callbackID, value: granted ? "granted" : "denied")
                }
            }
        }
    }

    func sendNotification(title: String, body: String, tag: String?, silent: Bool) {
        guard HTMLPermissionStore.choice(for: .notifications, appID: appID) == .allow else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title.isEmpty ? "HTMLApp" : title
            content.body = body
            content.sound = silent ? nil : .default
            content.userInfo = ["htmlAppID": self.appID]
            let identifier = tag?.isEmpty == false ? "\(self.appID).\(tag!)" : "\(self.appID).\(UUID().uuidString)"
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    private func beginLocation(callbackID: String, manager: CLLocationManager, timeoutMS: Double?) {
        pendingLocationCallbacks.append(callbackID)
        manager.requestLocation()

        let seconds = max(1, min((timeoutMS ?? 15000) / 1000, 60))
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingLocationCallbacks.contains(callbackID) else { return }
            self.pendingLocationCallbacks.removeAll { $0 == callbackID }
            self.resolveLocationError(callbackID, code: 3, message: "The location request timed out.")
        }
        locationTimeouts[callbackID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            let callbacks = pendingLocationCallbacks
            if callbacks.isEmpty {
                // A request arrived before the system authorization prompt completed.
                return
            }
            manager.requestLocation()
        case .denied, .restricted:
            finishAllLocationErrors(code: 1, message: "Location access is disabled in iOS Settings.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishAllLocationErrors(code: 2, message: "No location was returned.")
            return
        }
        let callbacks = pendingLocationCallbacks
        pendingLocationCallbacks.removeAll()
        for callback in callbacks {
            locationTimeouts.removeValue(forKey: callback)?.cancel()
            resolveLocation(callback, location: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        let message: String
        if nsError.domain == kCLErrorDomain, nsError.code == CLError.locationUnknown.rawValue {
            message = "Location is temporarily unavailable. Try again in a moment."
        } else {
            message = error.localizedDescription
        }
        finishAllLocationErrors(code: 2, message: message)
    }

    private func finishAllLocationErrors(code: Int, message: String) {
        let callbacks = pendingLocationCallbacks
        pendingLocationCallbacks.removeAll()
        for callback in callbacks {
            locationTimeouts.removeValue(forKey: callback)?.cancel()
            resolveLocationError(callback, code: code, message: message)
        }
    }

    func requestHTMLPermission(_ permission: HTMLPermission, completion: @escaping (Bool) -> Void) {
        resolvePolicy(permission, completion: completion)
    }

    private func resolvePolicies(_ permissions: [HTMLPermission], completion: @escaping (Bool) -> Void) {
        guard let first = permissions.first else {
            completion(true)
            return
        }
        resolvePolicy(first) { [weak self] allowed in
            guard allowed else {
                completion(false)
                return
            }
            self?.resolvePolicies(Array(permissions.dropFirst()), completion: completion)
        }
    }

    private func resolvePolicy(_ permission: HTMLPermission, completion: @escaping (Bool) -> Void) {
        guard appID != "PREVIEW" else {
            completion(false)
            return
        }

        HTMLPermissionStore.markRequested(permission.rawValue, appID: appID)
        if HTMLPermissionStore.choice(for: permission, appID: appID) == .ask {
            switch PermissionRequestGate.check(appID: appID, permission: permission.rawValue) {
            case .ignore:
                if PermissionRequestGate.hasPending(appID: appID, permission: permission.rawValue) {
                    _ = PermissionRequestGate.queue(appID: appID,
                        permission: permission.rawValue, completion: completion)
                } else { completion(false) }
                return
            case .autoDenied:
                HTMLPermissionStore.set(.deny, for: permission, appID: appID)
                PermissionRequestGate.finish(appID: appID, permission: permission.rawValue, allowed: false)
                PermissionRequestGate.showNotice(appID: appID, title: permission.title)
                completion(false)
                return
            case .proceed: break
            }
        }
        switch HTMLPermissionStore.choice(for: permission, appID: appID) {
        case .allow:
            completion(true)
        case .deny:
            completion(false)
        case .ask:
            guard PermissionRequestGate.queue(appID: appID, permission: permission.rawValue, completion: completion) else { return }
            guard let presenter = UIViewController.htmlAppTopViewController else {
                PermissionRequestGate.finish(appID: appID, permission: permission.rawValue, allowed: false)
                return
            }
            let alert = UIAlertController(
                title: "Allow \(permission.title)?",
                message: "This saved HTML app wants to use \(permission.title.lowercased()). You can change this later from its Permissions page.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in
                HTMLPermissionStore.set(.deny, for: permission, appID: self.appID)
                PermissionRequestGate.finish(appID: self.appID, permission: permission.rawValue, allowed: false)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                let blocked = HTMLPermissionStore.choice(for: permission, appID: self.appID) == .deny
                if !blocked { HTMLPermissionStore.set(.allow, for: permission, appID: self.appID) }
                PermissionRequestGate.finish(appID: self.appID, permission: permission.rawValue, allowed: !blocked)
            })
            presenter.present(alert, animated: true)
        }
    }

    private func requestSystemMedia(_ permissions: [HTMLPermission], completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var allGranted = true

        for permission in permissions {
            let mediaType: AVMediaType = permission == .camera ? .video : .audio
            group.enter()
            let status = AVCaptureDevice.authorizationStatus(for: mediaType)
            switch status {
            case .authorized:
                group.leave()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    lock.lock(); allGranted = allGranted && granted; lock.unlock()
                    group.leave()
                }
            case .denied, .restricted:
                lock.lock(); allGranted = false; lock.unlock()
                group.leave()
            @unknown default:
                lock.lock(); allGranted = false; lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { completion(allGranted) }
    }

    private func resolveLocation(_ callbackID: String, location: CLLocation) {
        let payload: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "altitude": location.altitude,
            "altitudeAccuracy": location.verticalAccuracy,
            "heading": location.course,
            "speed": location.speed,
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000
        ]
        callJavaScript(function: "__htmlappLocationSuccess", arguments: [callbackID, payload])
    }

    private func resolveLocationError(_ callbackID: String, code: Int, message: String) {
        callJavaScript(function: "__htmlappLocationError", arguments: [callbackID, code, message])
    }

    private func resolveNotificationPermission(_ callbackID: String, value: String) {
        callJavaScript(function: "__htmlappNotificationPermission", arguments: [callbackID, value])
    }

    private func callJavaScript(function: String, arguments: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.\(function).apply(null, \(json));")
    }
}

struct AppPermissionsView: View {
    let app: SavedHTMLApp
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [HTMLPermission: HTMLPermissionChoice]

    init(app: SavedHTMLApp) {
        self.app = app
        _choices = State(initialValue: Dictionary(uniqueKeysWithValues: HTMLPermission.allCases.map {
            ($0, HTMLPermissionStore.choice(for: $0, appID: app.id))
        }))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AppIconView(app: app, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.headline)
                            Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("HTML App Permissions") {
                    ForEach(HTMLPermission.allCases) { permission in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(permission.title, systemImage: permission.symbol)
                                .font(.headline)
                            Text(permission.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker(permission.title, selection: binding(for: permission)) {
                                ForEach(HTMLPermissionChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    Button("Open HTMLApp in iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Reset All to Ask", role: .destructive) {
                        HTMLPermissionStore.reset(appID: app.id)
                        for permission in HTMLPermission.allCases { choices[permission] = .ask }
                    }
                } footer: {
                    Text("Allowing an HTML app here does not bypass iOS. Sensitive native capabilities can still require a separate iOS system permission or system picker.")
                }
            }
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func binding(for permission: HTMLPermission) -> Binding<HTMLPermissionChoice> {
        Binding(
            get: { choices[permission] ?? .ask },
            set: {
                choices[permission] = $0
                HTMLPermissionStore.set($0, for: permission, appID: app.id)
            }
        )
    }
}

private extension UIViewController {
    static var htmlAppTopViewController: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        return root.htmlAppTopmost
    }

    var htmlAppTopmost: UIViewController {
        if let presentedViewController { return presentedViewController.htmlAppTopmost }
        if let nav = self as? UINavigationController { return nav.visibleViewController?.htmlAppTopmost ?? nav }
        if let tab = self as? UITabBarController { return tab.selectedViewController?.htmlAppTopmost ?? tab }
        return self
    }
}
