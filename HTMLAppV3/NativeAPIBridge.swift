import Foundation
import MapKit
import UIKit
import WebKit
import Contacts
import ContactsUI
import PhotosUI
import Photos
import UserNotifications
import EventKit
import LocalAuthentication
import UniformTypeIdentifiers
import AVFoundation
import ActivityKit
import CoreMotion
import Security
import WidgetKit
import SwiftUI

@MainActor
final class HTMLNativeAPIBridge: NSObject, CNContactPickerDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private weak var webView: WKWebView?
    private let appID: String
    private weak var permissionCoordinator: NativePermissionCoordinator?

    private var contactPickerCallbackID: String?
    private var photoPickerCallbackID: String?
    private var filePickerCallbackID: String?
    private let eventStore = EKEventStore()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let pedometer = CMPedometer()

    init(webView: WKWebView, appID: String, permissionCoordinator: NativePermissionCoordinator?) {
        self.webView = webView
        self.appID = appID
        self.permissionCoordinator = permissionCoordinator
        super.init()
    }

    func handle(_ body: [String: Any]) {
        guard let id = body["id"] as? String,
              let method = body["method"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]

        switch method {
        case "device.info":
            deviceInfo(id: id)
        case "capabilities.list":
            resolve(id, value: [
                "methods": [
                    "device.info", "device.keepAwake", "device.brightness", "device.torch",
                    "motion.pedometer",
                    "symbols.search", "symbols.render", "clipboard.readText", "clipboard.writeText",
                    "haptics.play", "share.present", "system.open", "externalApps.maps",
                    "externalApps.shortcuts", "files.pick", "contacts.pick", "contacts.list",
                    "contacts.create", "photos.pick", "photos.save", "calendar.createEvent",
                    "calendar.events", "calendar.updateEvent", "calendar.deleteEvent",
                    "reminders.create", "reminders.list", "reminders.update", "reminders.delete",
                    "notifications.schedule", "notifications.cancel", "biometrics.authenticate",
                    "secureStorage.set", "secureStorage.get", "secureStorage.remove",
                    "appStorage.get", "appStorage.set", "appStorage.remove", "appStorage.all",
                    "appStorage.clear", "liveActivities.start", "liveActivities.update",
                    "liveActivities.end", "liveActivities.list", "widgets.configure",
                    "widgets.list", "widgets.remove", "widgets.reload", "background.configure",
                    "background.list", "background.remove", "background.refreshNow",
                    "speech.speak", "speech.stop"
                ],
                "permissions": HTMLPermission.allCases.map { $0.rawValue },
                "torchAvailable": AVCaptureDevice.default(for: .video)?.hasTorch ?? false,
                "liveActivitiesAvailable": {
                    if #available(iOS 16.2, *) {
                        return ActivityAuthorizationInfo().areActivitiesEnabled
                    }
                    return false
                }()
            ])
        case "device.brightness":
            withPermission(.displayControl, id: id) { [weak self] in
                guard let self else { return }
                if let level = args["level"] as? NSNumber {
                    UIScreen.main.brightness = CGFloat(max(0, min(1, level.doubleValue)))
                }
                self.resolve(id, value: ["level": Double(UIScreen.main.brightness)])
            }
        case "motion.pedometer":
            withPermission(.motion, id: id) { [weak self] in
                guard let self else { return }
                guard CMPedometer.isStepCountingAvailable() else {
                    self.reject(id, code: "pedometer_unavailable",
                                message: "This device does not support step-count history.")
                    return
                }
                let days = min(7, max(1, (args["days"] as? NSNumber)?.intValue ?? 1))
                let today = Calendar.current.startOfDay(for: Date())
                guard let start = Calendar.current.date(byAdding: .day, value: 1 - days, to: today) else {
                    self.reject(id, code: "invalid_date", message: "Could not calculate the date range.")
                    return
                }
                self.pedometer.queryPedometerData(from: start, to: Date()) { [weak self] data, error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if error != nil || data == nil {
                            self.reject(id, code: "motion_denied",
                                message: "Steps were unavailable; allow Motion & Fitness in iOS Settings.")
                            return
                        }
                        guard let data else { return }
                        self.resolve(id, value: [
                            "steps": data.numberOfSteps.intValue,
                            "distanceMeters": data.distance?.doubleValue as Any? ?? NSNull(),
                            "floorsAscended": data.floorsAscended?.intValue as Any? ?? NSNull(),
                            "days": days
                        ])
                    }
                }
            }
        case "device.torch":
            withPermission(.camera, id: id) { [weak self] in
                guard let self else { return }
                Task {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    var permitted = status == .authorized
                    if status == .notDetermined {
                        permitted = await AVCaptureDevice.requestAccess(for: .video)
                    }
                    guard permitted else {
                        self.reject(id, code: "camera_denied", message: "Camera access must be allowed in iOS Settings.")
                        return
                    }
                    guard let camera = AVCaptureDevice.default(for: .video), camera.hasTorch else {
                        self.reject(id, code: "torch_unavailable", message: "There is no supported flashlight on this device.")
                        return
                    }
                    do {
                        try camera.lockForConfiguration()
                        defer { camera.unlockForConfiguration() }
                        camera.torchMode = (args["enabled"] as? Bool ?? false) ? .on : .off
                        self.resolve(id, value: ["enabled": camera.isTorchActive])
                    } catch {
                        self.reject(id, code: "torch_failed", message: "Flashlight could not be configured.")
                    }
                }
            }
        case "symbols.search":
            let query = (args["query"] as? String ?? "").lowercased()
            let names = HTMLAppSymbolCatalog.names.filter { query.isEmpty || $0.contains(query) }
            resolve(id, value: ["names": Array(names.prefix(100))])
        case "symbols.render":
            let name = args["name"] as? String ?? ""
            guard HTMLAppSymbolCatalog.names.contains(name),
                  let image = UIImage(systemName: name)?.withTintColor(.black, renderingMode: .alwaysOriginal),
                  let data = image.pngData() else {
                reject(id, code: "unsupported_symbol", message: "This SF Symbol is unavailable on this iOS version.")
                return
            }
            resolve(id, value: ["dataURL": "data:image/png;base64," + data.base64EncodedString()])

        case "device.keepAwake":
            withPermission(.displayControl, id: id) { [weak self] in
                guard let self else { return }
                UIApplication.shared.isIdleTimerDisabled = args["enabled"] as? Bool ?? false
                self.resolve(id, value: ["enabled": UIApplication.shared.isIdleTimerDisabled])
            }
        case "clipboard.readText":
            withPermission(.clipboard, id: id) { [weak self] in
                guard let self else { return }
                self.resolve(id, value: ["text": UIPasteboard.general.string ?? ""])
            }
        case "clipboard.writeText":
            withPermission(.clipboard, id: id) { [weak self] in
                guard let self else { return }
                UIPasteboard.general.string = args["text"] as? String ?? ""
                self.resolve(id, value: ["written": true])
            }
        case "haptics.play":
            let values = (args["pattern"] as? [NSNumber])?.map { $0.intValue } ?? [8]
            HTMLHapticsBridge.perform(pattern: values)
            resolve(id, value: ["played": true])
        case "share.present":
            presentShare(id: id, args: args)
        case "system.open":
            withPermission(.externalApps, id: id) { [weak self] in
                self?.openURL(id: id, value: args["url"] as? String ?? "")
            }
        case "externalApps.maps":
            withPermission(.externalApps, id: id) { [weak self] in
                self?.openMaps(id: id, args: args)
            }
        case "externalApps.shortcuts":
            withPermission(.externalApps, id: id) { [weak self] in
                self?.runShortcut(id: id, args: args)
            }
        case "files.pick":
            withPermission(.files, id: id) { [weak self] in self?.pickFiles(id: id, args: args) }
        case "contacts.pick":
            withPermission(.contacts, id: id) { [weak self] in self?.pickContact(id: id) }
        case "contacts.list":
            withPermission(.contacts, id: id) { [weak self] in self?.listContacts(id: id, args: args) }
        case "contacts.create":
            withPermission(.contacts, id: id) { [weak self] in self?.createContact(id: id, args: args) }
        case "photos.pick":
            withPermission(.photoLibrary, id: id) { [weak self] in self?.pickPhotos(id: id, args: args) }
        case "photos.save":
            withPermission(.photoLibrary, id: id) { [weak self] in self?.savePhotoLibraryAsset(id: id, args: args) }
        case "calendar.createEvent":
            withPermission(.calendar, id: id) { [weak self] in self?.createEvent(id: id, args: args) }
        case "calendar.events":
            withPermission(.calendar, id: id) { [weak self] in self?.listEvents(id: id, args: args) }
        case "calendar.updateEvent":
            withPermission(.calendar, id: id) { [weak self] in self?.updateEvent(id: id, args: args) }
        case "calendar.deleteEvent":
            withPermission(.calendar, id: id) { [weak self] in self?.deleteEvent(id: id, args: args) }
        case "reminders.create":
            withPermission(.reminders, id: id) { [weak self] in self?.createReminder(id: id, args: args) }
        case "reminders.list":
            withPermission(.reminders, id: id) { [weak self] in self?.listReminders(id: id, args: args) }
        case "reminders.update":
            withPermission(.reminders, id: id) { [weak self] in self?.updateReminder(id: id, args: args) }
        case "reminders.delete":
            withPermission(.reminders, id: id) { [weak self] in self?.deleteReminder(id: id, args: args) }
        case "notifications.schedule":
            withPermission(.notifications, id: id) { [weak self] in self?.scheduleNotification(id: id, args: args) }
        case "notifications.cancel":
            cancelNotifications(id: id, args: args)
        case "biometrics.authenticate":
            withPermission(.biometrics, id: id) { [weak self] in self?.authenticate(id: id, args: args) }
        case "secureStorage.set":
            secureStorageSet(id: id, args: args)
        case "secureStorage.get":
            secureStorageGet(id: id, args: args)
        case "secureStorage.remove":
            secureStorageRemove(id: id, args: args)
        case "appStorage.get":
            portableDataGet(id: id, args: args)
        case "appStorage.set":
            portableDataSet(id: id, args: args)
        case "appStorage.remove":
            portableDataRemove(id: id, args: args)
        case "appStorage.all":
            portableDataAll(id: id)
        case "appStorage.clear":
            HTMLAppPortableDataStore.clear(appID: appID)
            resolve(id, value: ["cleared": true])
        case "liveActivities.start":
            if #available(iOS 16.2, *) {
                withPermission(.liveActivities, id: id) { [weak self] in
                    guard let self else { return }
                    do {
                        let info = try HTMLAppLiveActivityService.start(appID: self.appID, args: args)
                        self.resolve(id, value: info)
                    } catch { self.reject(id, code: "live_activity_failed", message: error.localizedDescription) }
                }
            } else {
                reject(id, code: "unsupported_ios", message: "Live Activities require iOS 16.2 or later.")
            }
        case "liveActivities.update":
            if #available(iOS 16.2, *) {
                withPermission(.liveActivities, id: id) { [weak self] in
                    guard let self else { return }
                    Task {
                        do {
                            let result = try await HTMLAppLiveActivityService.update(appID: self.appID, args: args)
                            self.resolve(id, value: result)
                        } catch { self.reject(id, code: "live_activity_failed", message: error.localizedDescription) }
                    }
                }
            } else {
                reject(id, code: "unsupported_ios", message: "Live Activities require iOS 16.2 or later.")
            }
        case "liveActivities.end":
            if #available(iOS 16.2, *) {
                Task {
                    do {
                        let result = try await HTMLAppLiveActivityService.end(appID: appID, args: args)
                        resolve(id, value: result)
                    } catch { reject(id, code: "live_activity_failed", message: error.localizedDescription) }
                }
            } else {
                reject(id, code: "unsupported_ios", message: "Live Activities require iOS 16.2 or later.")
            }
        case "liveActivities.list":
            if #available(iOS 16.2, *) {
                resolve(id, value: ["activities": HTMLAppLiveActivityService.list(appID: appID)])
            } else {
                resolve(id, value: ["activities": []])
            }
        case "widgets.configure":
            configureWidget(id: id, args: args)
        case "widgets.list":
            listWidgets(id: id)
        case "widgets.remove":
            removeWidget(id: id, args: args)
        case "widgets.reload":
            HTMLAppWidgetReloadCoordinator.request()
            resolve(id, value: ["reloaded": true])
        case "background.configure":
            configureBackgroundJob(id: id, args: args)
        case "background.list":
            listBackgroundJobs(id: id)
        case "background.remove":
            removeBackgroundJob(id: id, args: args)
        case "background.refreshNow":
            refreshBackgroundJobNow(id: id, args: args)
        case "speech.speak":
            speak(id: id, args: args)
        case "speech.stop":
            speechSynthesizer.stopSpeaking(at: .immediate)
            resolve(id, value: ["stopped": true])
        default:
            reject(id, code: "unsupported_method", message: "Unknown native method: \(method)")
        }
    }

    private func withPermission(_ permission: HTMLPermission, id: String, action: @escaping @MainActor () -> Void) {
        guard appID != "PREVIEW" else {
            reject(id, code: "preview_restricted", message: "This native capability is unavailable in preview mode.")
            return
        }
        guard let permissionCoordinator else {
            reject(id, code: "bridge_unavailable", message: "The native permission coordinator is unavailable.")
            return
        }
        permissionCoordinator.requestHTMLPermission(permission) { [weak self] allowed in
            guard let self else { return }
            if allowed { action() }
            else { self.reject(id, code: "permission_denied", message: "\(permission.title) permission was denied for this HTML app.") }
        }
    }

    private func deviceInfo(id: String) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let screen = UIScreen.main
        let batteryLevel = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        var payload: [String: Any] = [
            "name": device.name,
            "model": device.model,
            "systemName": device.systemName,
            "systemVersion": device.systemVersion,
            "idiom": device.userInterfaceIdiom == .pad ? "pad" : "phone",
            "screen": [
                "width": screen.bounds.width,
                "height": screen.bounds.height,
                "scale": screen.scale,
                "nativeScale": screen.nativeScale,
                "brightness": screen.brightness
            ],
            "batteryState": batteryStateName(device.batteryState),
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "thermalState": thermalStateName(ProcessInfo.processInfo.thermalState),
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier
        ]
        if let batteryLevel { payload["batteryLevel"] = batteryLevel }
        resolve(id, value: payload)
    }

    private func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "unplugged"
        default: return "unknown"
        }
    }

    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func presentShare(id: String, args: [String: Any]) {
        guard let presenter = topViewController() else {
            reject(id, code: "presentation_failed", message: "No active view controller is available.")
            return
        }
        var items: [Any] = []
        if let text = args["text"] as? String, !text.isEmpty { items.append(text) }
        if let rawURL = args["url"] as? String, let url = URL(string: rawURL) { items.append(url) }
        guard !items.isEmpty else {
            reject(id, code: "invalid_arguments", message: "Share requires text or url.")
            return
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        configurePopover(sheet, presenter: presenter)
        sheet.completionWithItemsHandler = { [weak self] activity, completed, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.reject(id, code: "share_failed", message: error.localizedDescription)
                } else {
                    self.resolve(id, value: ["completed": completed, "activity": activity?.rawValue ?? ""])
                }
            }
        }
        presenter.present(sheet, animated: true)
    }

    private func portableDataGet(id: String, args: [String: Any]) {
        let key = (args["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty, key.count <= 200 else {
            reject(id, code: "invalid_key", message: "Portable app-data keys must be 1-200 characters.")
            return
        }
        if let stored = HTMLAppPortableDataStore.get(appID: appID, key: key) {
            resolve(id, value: ["value": stored])
        } else {
            resolve(id, value: ["value": NSNull()])
        }
    }

    private func portableDataSet(id: String, args: [String: Any]) {
        let key = (args["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = args["value"] as? String ?? ""
        guard !key.isEmpty, key.count <= 200 else {
            reject(id, code: "invalid_key", message: "Portable app-data keys must be 1-200 characters.")
            return
        }
        guard value.utf8.count <= 4 * 1024 * 1024 else {
            reject(id, code: "value_too_large", message: "One portable app-data value cannot exceed 4 MB.")
            return
        }
        HTMLAppPortableDataStore.set(appID: appID, key: key, value: value)
        resolve(id, value: ["saved": true])
    }

    private func portableDataRemove(id: String, args: [String: Any]) {
        let key = (args["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            reject(id, code: "invalid_key", message: "A portable app-data key is required.")
            return
        }
        HTMLAppPortableDataStore.remove(appID: appID, key: key)
        resolve(id, value: ["removed": true])
    }

    private func portableDataAll(id: String) {
        resolve(id, value: ["values": HTMLAppPortableDataStore.all(appID: appID)])
    }

    private func configureWidget(id: String, args: [String: Any]) {
        guard let widgetID = validGeneratedIdentifier(args["id"] as? String),
              let snapshotArgs = args["snapshot"] as? [String: Any] else {
            reject(id, code: "invalid_arguments", message: "widgets.configure requires a safe id and snapshot object.")
            return
        }

        let existing = HTMLAppWidgetStore.definitions(appID: appID)
        if !existing.contains(where: { $0.widgetID == widgetID }), existing.count >= 8 {
            reject(id, code: "widget_limit", message: "One HTMLApp can publish at most 8 widgets.")
            return
        }

        let rawName = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = String((rawName.isEmpty ? "HTMLApp Widget" : rawName).prefix(80))
        let allowedFamilies: Set<String> = [
            "systemSmall", "systemMedium", "systemLarge",
            "accessoryInline", "accessoryCircular", "accessoryRectangular"
        ]
        let requestedFamilies = (args["families"] as? [String] ?? [])
            .filter { allowedFamilies.contains($0) }
        let families = requestedFamilies.isEmpty
            ? ["systemSmall", "systemMedium", "systemLarge"]
            : Array(requestedFamilies.prefix(6))

        guard let snapshot = widgetSnapshot(from: snapshotArgs) else {
            reject(id, code: "invalid_widget", message: "The widget snapshot contains invalid or oversized content.")
            return
        }

        var refreshSpec: HTMLAppWidgetRefreshSpec?
        if let refresh = args["refresh"] as? [String: Any] {
            guard let rawURL = refresh["url"] as? String,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else {
                reject(id, code: "invalid_refresh_url", message: "Widget background refresh supports public HTTPS JSON endpoints only.")
                return
            }
            let interval = min(max((refresh["intervalMinutes"] as? NSNumber)?.intValue ?? 30, 15), 1440)
            let rawBindings = refresh["bindings"] as? [String: Any] ?? [:]
            var bindings: [String: String] = [:]
            for (target, source) in rawBindings.prefix(24) {
                guard let source = source as? String,
                      target.count <= 80,
                      source.count <= 240 else { continue }
                bindings[target] = source
            }
            refreshSpec = HTMLAppWidgetRefreshSpec(
                url: url.absoluteString,
                intervalMinutes: interval,
                bindings: bindings
            )
        }

        let definition = HTMLAppWidgetDefinition(
            appID: appID,
            widgetID: widgetID,
            name: name,
            primary: args["primary"] as? Bool ?? existing.first(where: { $0.widgetID == widgetID })?.primary ?? HTMLAppWidgetStore.all().isEmpty,
            families: families,
            snapshot: snapshot,
            refresh: refreshSpec,
            updatedAt: Date(),
            lastRefreshAt: existing.first(where: { $0.widgetID == widgetID })?.lastRefreshAt,
            lastError: nil
        )
        if appID != "PREVIEW" && !HTMLAppSharedContainer.appGroupAvailable {
            reject(id, code: "app_group_unavailable", message: "Widget shared storage is unavailable. Open Widgets & Background to select an authorized signing group. Both app and extension require matching App Group authorization.")
            return
        }
        if appID != "PREVIEW" {
            do {
                _ = try HTMLAppWidgetStore.saveVerified(definition)
                // A failed probe must not misrepresent a successfully persisted publication.
                _ = try? HTMLAppWidgetDiagnostics.begin()
                HTMLAppWidgetReloadCoordinator.request()
            } catch {
                let failure = (error as? HTMLAppWidgetStoreError) ?? HTMLAppWidgetRepository.failure("store_write_failed", error)
                reject(id, code: failure.code, message: failure.message)
                return
            }
        }
        resolve(id, value: [
            "id": definition.id,
            "widgetID": definition.widgetID,
            "name": definition.name,
            "families": definition.families,
            "backgroundRefresh": definition.refresh != nil,
            "preview": appID == "PREVIEW",
            "published": appID != "PREVIEW",
            "reloadRequested": appID != "PREVIEW",
            "extensionVerified": false,
            "appGroupAvailable": HTMLAppSharedContainer.appGroupAvailable
        ])
    }

    private func listWidgets(id: String) {
        let values: [[String: Any]]
        do { values = try HTMLAppWidgetStore.readAll().filter { $0.appID == appID }.map(widgetJSON) }
        catch {
            let failure = (error as? HTMLAppWidgetStoreError) ?? HTMLAppWidgetRepository.failure("store_read_failed", error)
            reject(id, code: failure.code, message: failure.message)
            return
        }
        resolve(id, value: ["widgets": values, "count": values.count, "appGroupAvailable": HTMLAppSharedContainer.appGroupAvailable, "iOS16PrimaryOnly": ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 17])
    }

    private func removeWidget(id: String, args: [String: Any]) {
        let widgetID = validGeneratedIdentifier(args["id"] as? String)
        do { try HTMLAppWidgetStore.removeVerified(appID: appID, widgetID: widgetID) }
        catch {
            let failure = (error as? HTMLAppWidgetStoreError) ?? HTMLAppWidgetRepository.failure("store_write_failed", error)
            reject(id, code: failure.code, message: failure.message)
            return
        }
        HTMLAppWidgetReloadCoordinator.request()
        resolve(id, value: ["removed": true, "all": widgetID == nil])
    }

    private func configureBackgroundJob(id: String, args: [String: Any]) {
        guard let jobID = validGeneratedIdentifier(args["id"] as? String),
              let rawURL = args["url"] as? String,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https",
              let storageKey = (args["storageKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storageKey.isEmpty,
              storageKey.count <= 200 else {
            reject(id, code: "invalid_arguments", message: "background.configure requires id, public HTTPS url, and storageKey.")
            return
        }

        let existing = HTMLAppBackgroundJobStore.jobs(appID: appID)
        if !existing.contains(where: { $0.jobID == jobID }), existing.count >= 6 {
            reject(id, code: "background_job_limit", message: "One HTMLApp can register at most 6 background fetch jobs.")
            return
        }

        let interval = min(max((args["intervalMinutes"] as? NSNumber)?.intValue ?? 30, 15), 1440)
        let jsonPath = (args["jsonPath"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240)
            .description
        let widgetID = validGeneratedIdentifier(args["widgetID"] as? String)
        let previous = existing.first(where: { $0.jobID == jobID })

        let job = HTMLAppBackgroundFetchJob(
            appID: appID,
            jobID: jobID,
            url: url.absoluteString,
            intervalMinutes: interval,
            storageKey: storageKey,
            jsonPath: jsonPath?.isEmpty == false ? jsonPath : nil,
            widgetID: widgetID,
            enabled: args["enabled"] as? Bool ?? true,
            updatedAt: Date(),
            lastRunAt: previous?.lastRunAt,
            lastError: previous?.lastError
        )
        if appID != "PREVIEW" {
            HTMLAppBackgroundJobStore.save(job)
            HTMLAppBackgroundCoordinator.shared.schedule()
        }
        resolve(id, value: backgroundJobJSON(job).merging([
            "scheduled": appID != "PREVIEW",
            "opportunistic": true,
            "preview": appID == "PREVIEW"
        ]) { _, new in new })
    }

    private func listBackgroundJobs(id: String) {
        let jobs = HTMLAppBackgroundJobStore.jobs(appID: appID).map(backgroundJobJSON)
        resolve(id, value: ["jobs": jobs, "count": jobs.count])
    }

    private func removeBackgroundJob(id: String, args: [String: Any]) {
        let jobID = validGeneratedIdentifier(args["id"] as? String)
        HTMLAppBackgroundJobStore.remove(appID: appID, jobID: jobID)
        HTMLAppBackgroundCoordinator.shared.schedule()
        resolve(id, value: ["removed": true, "all": jobID == nil])
    }

    private func refreshBackgroundJobNow(id: String, args: [String: Any]) {
        let jobID = validGeneratedIdentifier(args["id"] as? String)
        Task { [weak self] in
            guard let self else { return }
            let results = await HTMLAppBackgroundCoordinator.shared.runNow(appID: self.appID, jobID: jobID)
            let payload = results.map(self.backgroundJobJSON)
            self.resolve(id, value: ["jobs": payload, "count": payload.count])
        }
    }

    private func widgetSnapshot(from args: [String: Any]) -> HTMLAppWidgetSnapshot? {
        func text(_ key: String, limit: Int = 180) -> String? {
            guard let raw = args[key] as? String else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : String(value.prefix(limit))
        }

        let rawLayout = text("layout", limit: 24)?.lowercased()
        let allowedLayouts: Set<String> = ["metric", "list", "status", "progress", "image"]
        let layout = rawLayout.flatMap { allowedLayouts.contains($0) ? $0 : nil }

        var items: [HTMLAppWidgetItem] = []
        if let rawItems = args["items"] as? [[String: Any]] {
            for (index, raw) in rawItems.prefix(8).enumerated() {
                let label = String(((raw["label"] as? String) ?? "").prefix(80))
                let value = String(((raw["value"] as? String) ?? "").prefix(120))
                if label.isEmpty && value.isEmpty { continue }
                let detail = (raw["detail"] as? String).map { String($0.prefix(120)) }
                let symbol = (raw["systemSymbol"] as? String).map { String($0.prefix(80)) }
                let progress = (raw["progress"] as? NSNumber).map { min(max($0.doubleValue, 0), 1) }
                items.append(.init(
                    id: (raw["id"] as? String).flatMap(validGeneratedIdentifier) ?? "item-(index)",
                    label: label,
                    value: value,
                    detail: detail,
                    systemSymbol: symbol,
                    progress: progress
                ))
            }
        }

        let image = text("imageBase64", limit: 1_500_000)
        if let image, image.utf8.count > 1_500_000 { return nil }

        return HTMLAppWidgetSnapshot(
            layout: layout,
            eyebrow: text("eyebrow"),
            title: text("title"),
            subtitle: text("subtitle", limit: 240),
            value: text("value"),
            unit: text("unit", limit: 40),
            footer: text("footer", limit: 180),
            systemSymbol: text("systemSymbol", limit: 80),
            progress: (args["progress"] as? NSNumber).map { min(max($0.doubleValue, 0), 1) },
            backgroundHex: text("backgroundHex", limit: 16),
            backgroundSecondaryHex: text("backgroundSecondaryHex", limit: 16),
            foregroundHex: text("foregroundHex", limit: 16),
            accentHex: text("accentHex", limit: 16),
            imageBase64: image,
            items: items.isEmpty ? nil : items
        )
    }

    private func widgetJSON(_ widget: HTMLAppWidgetDefinition) -> [String: Any] {
        var value: [String: Any] = [
            "id": widget.id,
            "widgetID": widget.widgetID,
            "name": widget.name,
            "primary": widget.primary,
            "families": widget.families,
            "updatedAt": widget.updatedAt.timeIntervalSince1970
        ]
        if let last = widget.lastRefreshAt { value["lastRefreshAt"] = last.timeIntervalSince1970 }
        if let error = widget.lastError { value["lastError"] = error }
        value["backgroundRefresh"] = widget.refresh != nil
        return value
    }

    private func backgroundJobJSON(_ job: HTMLAppBackgroundFetchJob) -> [String: Any] {
        var value: [String: Any] = [
            "id": job.jobID,
            "url": job.url,
            "intervalMinutes": job.intervalMinutes,
            "storageKey": job.storageKey,
            "enabled": job.enabled,
            "opportunistic": true
        ]
        if let path = job.jsonPath { value["jsonPath"] = path }
        if let widgetID = job.widgetID { value["widgetID"] = widgetID }
        if let last = job.lastRunAt { value["lastRunAt"] = last.timeIntervalSince1970 }
        if let error = job.lastError { value["lastError"] = error }
        return value
    }

    private func validGeneratedIdentifier(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty, value.count <= 80 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return value
    }

    private func openURL(id: String, value: String) {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              !["javascript", "data", "blob", "file", "itms-services"].contains(scheme) else {
            reject(id, code: "invalid_url", message: "The requested URL uses a blocked or invalid scheme.")
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success { self.resolve(id, value: ["opened": true]) }
                else { self.reject(id, code: "open_failed", message: "iOS could not open the requested URL.") }
            }
        }
    }

    private func openMaps(id: String, args: [String: Any]) {
        let latitude = (args["latitude"] as? NSNumber)?.doubleValue
        let longitude = (args["longitude"] as? NSNumber)?.doubleValue
        let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directions = args["directions"] as? Bool ?? false

        if let latitude, let longitude,
           (-90...90).contains(latitude), (-180...180).contains(longitude) {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
            if let name, !name.isEmpty { item.name = name }
            let options = directions ? [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving] : [:]
            item.openInMaps(launchOptions: options)
            resolve(id, value: ["opened": true, "app": "maps"])
            return
        }

        guard !query.isEmpty else {
            reject(id, code: "invalid_arguments", message: "Provide a map query or valid latitude/longitude.")
            return
        }

        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ] + (directions ? [URLQueryItem(name: "dirflg", value: "d")] : [])
        guard let url = components?.url else {
            reject(id, code: "invalid_arguments", message: "The Maps request could not be created.")
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success { self.resolve(id, value: ["opened": true, "app": "maps"]) }
                else { self.reject(id, code: "open_failed", message: "Apple Maps could not be opened.") }
            }
        }
    }

    private func runShortcut(id: String, args: [String: Any]) {
        let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            reject(id, code: "invalid_arguments", message: "A Shortcut name is required.")
            return
        }

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        var items = [URLQueryItem(name: "name", value: name)]
        if let input = args["input"] as? String, !input.isEmpty {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = items
        guard let url = components.url else {
            reject(id, code: "invalid_arguments", message: "The Shortcut request could not be created.")
            return
        }

        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success { self.resolve(id, value: ["opened": true, "app": "shortcuts"]) }
                else { self.reject(id, code: "open_failed", message: "Shortcuts could not run the requested shortcut.") }
            }
        }
    }

    private func pickFiles(id: String, args: [String: Any]) {
        guard let presenter = topViewController() else {
            reject(id, code: "presentation_failed", message: "No active view controller is available.")
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = args["multiple"] as? Bool ?? false
        picker.delegate = self
        filePickerCallbackID = id
        presenter.present(picker, animated: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard let id = filePickerCallbackID else { return }
        filePickerCallbackID = nil
        reject(id, code: "cancelled", message: "File selection was cancelled.")
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = filePickerCallbackID else { return }
        filePickerCallbackID = nil
        var output: [[String: Any]] = []
        for url in urls {
            if let item = importFile(url: url, namespace: "files") { output.append(item) }
        }
        resolve(id, value: output)
    }

    private func pickContact(id: String) {
        guard let presenter = topViewController() else {
            reject(id, code: "presentation_failed", message: "No active view controller is available.")
            return
        }
        let picker = CNContactPickerViewController()
        picker.delegate = self
        contactPickerCallbackID = id
        presenter.present(picker, animated: true)
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        guard let id = contactPickerCallbackID else { return }
        contactPickerCallbackID = nil
        reject(id, code: "cancelled", message: "Contact selection was cancelled.")
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        guard let id = contactPickerCallbackID else { return }
        contactPickerCallbackID = nil
        resolve(id, value: contactPayload(contact))
    }

    private func listContacts(id: String, args: [String: Any]) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Contacts access was denied.")
                    return
                }
                let limit = max(1, min(args["limit"] as? Int ?? 500, 2000))
                let keys: [CNKeyDescriptor] = [
                    CNContactIdentifierKey as CNKeyDescriptor,
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactEmailAddressesKey as CNKeyDescriptor,
                    CNContactPostalAddressesKey as CNKeyDescriptor,
                    CNContactBirthdayKey as CNKeyDescriptor
                ]
                let request = CNContactFetchRequest(keysToFetch: keys)
                var values: [[String: Any]] = []
                do {
                    try store.enumerateContacts(with: request) { contact, stop in
                        values.append(self.contactPayload(contact))
                        if values.count >= limit { stop.pointee = true }
                    }
                    self.resolve(id, value: values)
                } catch {
                    self.reject(id, code: "contacts_failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func createContact(id: String, args: [String: Any]) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Contacts access was denied.")
                    return
                }

                let contact = CNMutableContact()
                contact.givenName = args["givenName"] as? String ?? ""
                contact.familyName = args["familyName"] as? String ?? ""
                contact.organizationName = args["organizationName"] as? String ?? ""

                if let phones = args["phones"] as? [[String: Any]] {
                    contact.phoneNumbers = phones.compactMap { item in
                        guard let value = item["value"] as? String, !value.isEmpty else { return nil }
                        let label = item["label"] as? String ?? CNLabelPhoneNumberMobile
                        return CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: value))
                    }
                }
                if let emails = args["emails"] as? [[String: Any]] {
                    contact.emailAddresses = emails.compactMap { item in
                        guard let value = item["value"] as? String, !value.isEmpty else { return nil }
                        let label = item["label"] as? String ?? CNLabelHome
                        return CNLabeledValue(label: label, value: value as NSString)
                    }
                }

                guard !contact.givenName.isEmpty || !contact.familyName.isEmpty || !contact.organizationName.isEmpty || !contact.phoneNumbers.isEmpty || !contact.emailAddresses.isEmpty else {
                    self.reject(id, code: "invalid_arguments", message: "A contact needs at least a name, organization, phone number, or email address.")
                    return
                }

                let request = CNSaveRequest()
                request.add(contact, toContainerWithIdentifier: nil)
                do {
                    try store.execute(request)
                    self.resolve(id, value: ["id": contact.identifier, "created": true])
                } catch {
                    self.reject(id, code: "contacts_failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func contactPayload(_ contact: CNContact) -> [String: Any] {
        let phones = contact.phoneNumbers.map { ["label": CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? ""), "value": $0.value.stringValue] }
        let emails = contact.emailAddresses.map { ["label": CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? ""), "value": String($0.value)] }
        let addresses = contact.postalAddresses.map {
            let value = $0.value
            return [
                "label": CNLabeledValue<CNPostalAddress>.localizedString(forLabel: $0.label ?? ""),
                "street": value.street,
                "city": value.city,
                "state": value.state,
                "postalCode": value.postalCode,
                "country": value.country,
                "isoCountryCode": value.isoCountryCode
            ]
        }
        var result: [String: Any] = [
            "id": contact.identifier,
            "givenName": contact.givenName,
            "familyName": contact.familyName,
            "organizationName": contact.organizationName,
            "phones": phones,
            "emails": emails,
            "addresses": addresses
        ]
        if let birthday = contact.birthday {
            var value: [String: Int] = [:]
            if let year = birthday.year { value["year"] = year }
            if let month = birthday.month { value["month"] = month }
            if let day = birthday.day { value["day"] = day }
            if !value.isEmpty { result["birthday"] = value }
        }
        return result
    }

    private func pickPhotos(id: String, args: [String: Any]) {
        guard let presenter = topViewController() else {
            reject(id, code: "presentation_failed", message: "No active view controller is available.")
            return
        }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = max(1, min(args["limit"] as? Int ?? 1, 20))
        switch (args["media"] as? String ?? "any").lowercased() {
        case "images": configuration.filter = .images
        case "videos": configuration.filter = .videos
        default: configuration.filter = .any(of: [.images, .videos, .livePhotos])
        }
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        photoPickerCallbackID = id
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let id = photoPickerCallbackID else { return }
        photoPickerCallbackID = nil
        guard !results.isEmpty else {
            reject(id, code: "cancelled", message: "Photo selection was cancelled.")
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var imported: [[String: Any]] = []
        for result in results {
            guard let typeIdentifier = result.itemProvider.registeredTypeIdentifiers.first else { continue }
            group.enter()
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
                Task { @MainActor in
                    defer { group.leave() }
                    guard let self, let url else { return }
                    if let item = self.importFile(url: url, namespace: "photos", preferredName: result.itemProvider.suggestedName, typeIdentifier: typeIdentifier) {
                        lock.lock()
                        imported.append(item)
                        lock.unlock()
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if imported.isEmpty { self.reject(id, code: "photo_import_failed", message: "The selected media could not be imported.") }
            else { self.resolve(id, value: imported) }
        }
    }

    private func savePhotoLibraryAsset(id: String, args: [String: Any]) {
        guard let relative = args["url"] as? String,
              let source = localResourceURL(relative) else {
            reject(id, code: "invalid_arguments", message: "photos.save requires a local relative url returned by HTMLAppNative.files.pick or photos.pick.")
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self.reject(id, code: "system_permission_denied", message: "iOS Photos add permission was denied.")
                }
                return
            }

            let type = UTType(filenameExtension: source.pathExtension)
            let resourceType: PHAssetResourceType = type?.conforms(to: .movie) == true ? .video : .photo
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: resourceType, fileURL: source, options: nil)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success { self.resolve(id, value: ["saved": true]) }
                    else { self.reject(id, code: "photos_save_failed", message: error?.localizedDescription ?? "The media could not be saved to Photos.") }
                }
            }
        }
    }

    private func createEvent(id: String, args: [String: Any]) {
        requestCalendarAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Calendar access was denied.")
                return
            }
            guard let title = args["title"] as? String, !title.isEmpty,
                  let start = self.date(from: args["start"]),
                  let end = self.date(from: args["end"]) else {
                self.reject(id, code: "invalid_arguments", message: "Calendar event requires title, start, and end.")
                return
            }
            let event = EKEvent(eventStore: self.eventStore)
            event.title = title
            event.startDate = start
            event.endDate = max(end, start.addingTimeInterval(60))
            event.notes = args["notes"] as? String
            event.location = args["location"] as? String
            event.isAllDay = args["allDay"] as? Bool ?? false
            if let rawURL = args["url"] as? String { event.url = URL(string: rawURL) }
            event.calendar = self.eventStore.defaultCalendarForNewEvents
            do {
                try self.eventStore.save(event, span: .thisEvent, commit: true)
                self.resolve(id, value: ["id": event.eventIdentifier ?? "", "created": true])
            } catch {
                self.reject(id, code: "calendar_failed", message: error.localizedDescription)
            }
        }
    }

    private func listEvents(id: String, args: [String: Any]) {
        requestCalendarAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Calendar access was denied.")
                return
            }
            let start = self.date(from: args["start"]) ?? Date()
            let end = self.date(from: args["end"]) ?? Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(2_592_000)
            let limit = max(1, min(args["limit"] as? Int ?? 250, 1000))
            let predicate = self.eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = Array(self.eventStore.events(matching: predicate).prefix(limit)).map { event in
                [
                    "id": event.eventIdentifier ?? "",
                    "title": event.title ?? "",
                    "start": ISO8601DateFormatter().string(from: event.startDate),
                    "end": ISO8601DateFormatter().string(from: event.endDate),
                    "allDay": event.isAllDay,
                    "location": event.location ?? "",
                    "notes": event.notes ?? "",
                    "calendarTitle": event.calendar.title
                ] as [String: Any]
            }
            self.resolve(id, value: events)
        }
    }

    private func updateEvent(id: String, args: [String: Any]) {
        requestCalendarAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Calendar access was denied.")
                return
            }
            guard let eventID = args["id"] as? String,
                  let event = self.eventStore.event(withIdentifier: eventID) else {
                self.reject(id, code: "not_found", message: "The calendar event could not be found.")
                return
            }
            if let title = args["title"] as? String { event.title = title }
            if let start = self.date(from: args["start"]) { event.startDate = start }
            if let end = self.date(from: args["end"]) { event.endDate = end }
            if let notes = args["notes"] as? String { event.notes = notes }
            if let location = args["location"] as? String { event.location = location }
            if let allDay = args["allDay"] as? Bool { event.isAllDay = allDay }
            if let rawURL = args["url"] as? String { event.url = rawURL.isEmpty ? nil : URL(string: rawURL) }
            if event.endDate <= event.startDate { event.endDate = event.startDate.addingTimeInterval(60) }
            do {
                try self.eventStore.save(event, span: .thisEvent, commit: true)
                self.resolve(id, value: ["id": event.eventIdentifier ?? eventID, "updated": true])
            } catch {
                self.reject(id, code: "calendar_failed", message: error.localizedDescription)
            }
        }
    }

    private func deleteEvent(id: String, args: [String: Any]) {
        requestCalendarAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Calendar access was denied.")
                return
            }
            guard let eventID = args["id"] as? String,
                  let event = self.eventStore.event(withIdentifier: eventID) else {
                self.reject(id, code: "not_found", message: "The calendar event could not be found.")
                return
            }
            do {
                try self.eventStore.remove(event, span: .thisEvent, commit: true)
                self.resolve(id, value: ["deleted": true])
            } catch {
                self.reject(id, code: "calendar_failed", message: error.localizedDescription)
            }
        }
    }

    private func requestCalendarAccess(_ completion: @escaping @MainActor (Bool, Error?) -> Void) {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                Task { @MainActor in completion(granted, error) }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                Task { @MainActor in completion(granted, error) }
            }
        }
    }

    private func createReminder(id: String, args: [String: Any]) {
        requestReminderAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Reminders access was denied.")
                return
            }
            guard let title = args["title"] as? String, !title.isEmpty else {
                self.reject(id, code: "invalid_arguments", message: "Reminder requires a title.")
                return
            }
            guard let calendar = self.eventStore.defaultCalendarForNewReminders() else {
                self.reject(id, code: "reminder_failed", message: "No writable reminders list is available.")
                return
            }
            let reminder = EKReminder(eventStore: self.eventStore)
            reminder.title = title
            reminder.notes = args["notes"] as? String
            reminder.calendar = calendar
            if let due = self.date(from: args["due"]) {
                reminder.dueDateComponents = Calendar.current.dateComponents(in: TimeZone.current, from: due)
            }
            do {
                try self.eventStore.save(reminder, commit: true)
                self.resolve(id, value: ["id": reminder.calendarItemIdentifier, "created": true])
            } catch {
                self.reject(id, code: "reminder_failed", message: error.localizedDescription)
            }
        }
    }

    private func listReminders(id: String, args: [String: Any]) {
        requestReminderAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Reminders access was denied.")
                return
            }
            let limit = max(1, min(args["limit"] as? Int ?? 250, 1000))
            let predicate = self.eventStore.predicateForReminders(in: nil)
            self.eventStore.fetchReminders(matching: predicate) { reminders in
                Task { @MainActor in
                    let values = (reminders ?? []).prefix(limit).map { reminder in
                        var item: [String: Any] = [
                            "id": reminder.calendarItemIdentifier,
                            "title": reminder.title ?? "",
                            "notes": reminder.notes ?? "",
                            "completed": reminder.isCompleted,
                            "calendarTitle": reminder.calendar.title
                        ]
                        if let components = reminder.dueDateComponents,
                           let date = Calendar.current.date(from: components) {
                            item["due"] = ISO8601DateFormatter().string(from: date)
                        }
                        return item
                    }
                    self.resolve(id, value: Array(values))
                }
            }
        }
    }

    private func updateReminder(id: String, args: [String: Any]) {
        requestReminderAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Reminders access was denied.")
                return
            }
            guard let reminderID = args["id"] as? String,
                  let reminder = self.eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
                self.reject(id, code: "not_found", message: "The reminder could not be found.")
                return
            }
            if let title = args["title"] as? String { reminder.title = title }
            if let notes = args["notes"] as? String { reminder.notes = notes }
            if let completed = args["completed"] as? Bool { reminder.isCompleted = completed }
            if args.keys.contains("due") {
                if let due = self.date(from: args["due"]) {
                    reminder.dueDateComponents = Calendar.current.dateComponents(in: TimeZone.current, from: due)
                } else {
                    reminder.dueDateComponents = nil
                }
            }
            do {
                try self.eventStore.save(reminder, commit: true)
                self.resolve(id, value: ["id": reminder.calendarItemIdentifier, "updated": true])
            } catch {
                self.reject(id, code: "reminder_failed", message: error.localizedDescription)
            }
        }
    }

    private func deleteReminder(id: String, args: [String: Any]) {
        requestReminderAccess { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Reminders access was denied.")
                return
            }
            guard let reminderID = args["id"] as? String,
                  let reminder = self.eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
                self.reject(id, code: "not_found", message: "The reminder could not be found.")
                return
            }
            do {
                try self.eventStore.remove(reminder, commit: true)
                self.resolve(id, value: ["deleted": true])
            } catch {
                self.reject(id, code: "reminder_failed", message: error.localizedDescription)
            }
        }
    }

    private func requestReminderAccess(_ completion: @escaping @MainActor (Bool, Error?) -> Void) {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToReminders { granted, error in
                Task { @MainActor in completion(granted, error) }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, error in
                Task { @MainActor in completion(granted, error) }
            }
        }
    }

    private func scheduleNotification(id: String, args: [String: Any]) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                Task { @MainActor in
                    self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS notification permission was denied.")
                }
                return
            }
            Task { @MainActor in
                let content = UNMutableNotificationContent()
                content.title = args["title"] as? String ?? "HTMLApp"
                content.body = args["body"] as? String ?? ""
                content.sound = (args["silent"] as? Bool ?? false) ? nil : .default

                let requestedID = (args["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let identifier = "native.\(self.appID)." + ((requestedID?.isEmpty == false ? requestedID! : UUID().uuidString))
                let fireDate = self.date(from: args["at"])
                let seconds = max(1, fireDate?.timeIntervalSinceNow ?? (args["afterSeconds"] as? Double ?? 1))
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    Task { @MainActor in
                        if let error { self.reject(id, code: "notification_failed", message: error.localizedDescription) }
                        else { self.resolve(id, value: ["id": identifier, "scheduled": true]) }
                    }
                }
            }
        }
    }

    private func cancelNotifications(id: String, args: [String: Any]) {
        let center = UNUserNotificationCenter.current()
        let prefix = "native.\(appID)."
        if let rawID = args["id"] as? String, !rawID.isEmpty {
            let identifier = rawID.hasPrefix(prefix) ? rawID : prefix + rawID
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            resolve(id, value: ["cancelled": true])
            return
        }

        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
            Task { @MainActor in self.resolve(id, value: ["cancelled": true, "count": ids.count]) }
        }
    }

    private func authenticate(id: String, args: [String: Any]) {
        let context = LAContext()
        let biometricsOnly = args["biometricsOnly"] as? Bool ?? false
        let policy: LAPolicy = biometricsOnly ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var authError: NSError?
        guard context.canEvaluatePolicy(policy, error: &authError) else {
            reject(id, code: "biometrics_unavailable", message: authError?.localizedDescription ?? "Device authentication is unavailable.")
            return
        }
        let reason = (args["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        context.evaluatePolicy(policy, localizedReason: reason?.isEmpty == false ? reason! : "Authenticate to continue in this HTML app.") { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.resolve(id, value: ["authenticated": true, "biometryType": self.biometryName(context.biometryType)])
                } else {
                    self.reject(id, code: "authentication_failed", message: error?.localizedDescription ?? "Authentication failed.")
                }
            }
        }
    }

    private func biometryName(_ type: LABiometryType) -> String {
        if #available(iOS 17.0, *), type == .opticID { return "opticID" }
        switch type {
        case .faceID: return "faceID"
        case .touchID: return "touchID"
        default: return "none"
        }
    }

    private func secureStorageSet(id: String, args: [String: Any]) {
        guard appID != "PREVIEW" else {
            reject(id, code: "preview_restricted", message: "Secure storage is unavailable in preview mode.")
            return
        }
        guard let key = validStorageKey(args["key"] as? String),
              let value = args["value"] as? String,
              let data = value.data(using: .utf8) else {
            reject(id, code: "invalid_arguments", message: "secureStorage.set requires a non-empty key and string value.")
            return
        }
        let service = secureStorageService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { resolve(id, value: ["stored": true]) }
        else { reject(id, code: "keychain_failed", message: "Keychain write failed (\(status)).") }
    }

    private func secureStorageGet(id: String, args: [String: Any]) {
        guard let key = validStorageKey(args["key"] as? String) else {
            reject(id, code: "invalid_arguments", message: "secureStorage.get requires a non-empty key.")
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secureStorageService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            resolve(id, value: ["value": NSNull()])
        } else if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) {
            resolve(id, value: ["value": value])
        } else {
            reject(id, code: "keychain_failed", message: "Keychain read failed (\(status)).")
        }
    }

    private func secureStorageRemove(id: String, args: [String: Any]) {
        guard let key = validStorageKey(args["key"] as? String) else {
            reject(id, code: "invalid_arguments", message: "secureStorage.remove requires a non-empty key.")
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secureStorageService,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { resolve(id, value: ["removed": true]) }
        else { reject(id, code: "keychain_failed", message: "Keychain delete failed (\(status)).") }
    }

    private var secureStorageService: String { "com.mekabrine.htmlapp.native.\(appID)" }

    private func validStorageKey(_ raw: String?) -> String? {
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty, key.count <= 128 else { return nil }
        return key
    }

    private func speak(id: String, args: [String: Any]) {
        guard let text = args["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reject(id, code: "invalid_arguments", message: "speech.speak requires text.")
            return
        }
        let utterance = AVSpeechUtterance(string: String(text.prefix(20_000)))
        if let language = args["language"] as? String { utterance.voice = AVSpeechSynthesisVoice(language: language) }
        if let rate = args["rate"] as? Double { utterance.rate = Float(max(0.1, min(rate, 0.6))) }
        if let pitch = args["pitch"] as? Double { utterance.pitchMultiplier = Float(max(0.5, min(pitch, 2.0))) }
        speechSynthesizer.speak(utterance)
        resolve(id, value: ["speaking": true])
    }

    private func date(from value: Any?) -> Date? {
        if let timestamp = value as? Double {
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
        }
        if let number = value as? NSNumber {
            let timestamp = number.doubleValue
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp)
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private func importFile(url: URL, namespace: String, preferredName: String? = nil, typeIdentifier: String? = nil) -> [String: Any]? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let root = SourceCache.shared.baseURL(appID: appID)
        let folderName = "native-imports/\(namespace)/\(UUID().uuidString)"
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var filename = (preferredName?.isEmpty == false ? preferredName! : url.lastPathComponent)
        if filename.isEmpty { filename = "import" }
        if URL(fileURLWithPath: filename).pathExtension.isEmpty,
           let typeIdentifier,
           let type = UTType(typeIdentifier),
           let ext = type.preferredFilenameExtension {
            filename += ".\(ext)"
        }
        filename = safeFilename(filename)
        let destination = folder.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: url, to: destination)
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            let relative = folderName + "/" + filename
            let type = UTType(filenameExtension: destination.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            return [
                "name": filename,
                "url": relative,
                "mimeType": type,
                "size": bytes
            ]
        } catch {
            return nil
        }
    }

    private func localResourceURL(_ relative: String) -> URL? {
        guard !relative.isEmpty,
              !relative.hasPrefix("/"),
              !relative.contains("..") else { return nil }
        let root = SourceCache.shared.baseURL(appID: appID).standardizedFileURL
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func safeFilename(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = raw.components(separatedBy: forbidden).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "import" : cleaned).prefix(180))
    }

    private func configurePopover(_ sheet: UIActivityViewController, presenter: UIViewController) {
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
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

    private func resolve(_ id: String, value: Any) {
        sendCallback(id: id, ok: true, value: value)
    }

    private func reject(_ id: String, code: String, message: String) {
        sendCallback(id: id, ok: false, value: ["code": code, "message": message])
    }

    private func sendCallback(id: String, ok: Bool, value: Any) {
        let payload: [Any] = [id, ok, value]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__htmlappNativeResolve && window.__htmlappNativeResolve.apply(null, \(json));")
    }
}

enum HTMLNativeAPIScript {
    static let source = #"""
    (() => {
      if (window.HTMLAppNative) return;

      let sequence = 0;
      const pending = new Map();

      const call = (method, args = {}) => new Promise((resolve, reject) => {
        const handler = window.webkit?.messageHandlers?.htmlappNative;
        if (!handler) {
          reject(Object.assign(new Error('HTMLApp native bridge is unavailable.'), { code: 'bridge_unavailable' }));
          return;
        }
        const id = `native-${Date.now()}-${++sequence}`;
        pending.set(id, { resolve, reject, method });
        handler.postMessage({ id, method, args });
      });

      window.__htmlappNativeResolve = (id, ok, value) => {
        const item = pending.get(id);
        if (!item) return;
        pending.delete(id);
        if (ok) {
          if (item.method === 'widgets.configure') document.getElementById('__htmlappWidgetError')?.remove();
          item.resolve(value);
          return;
        }
        const error = new Error(value?.message || 'Native operation failed.');
        error.code = value?.code || 'native_error';
        if (item.method === 'widgets.configure') {
          // Existing generated apps may swallow the rejection behind a generic error.
          // Show a safe native diagnostic without changing their saved HTML/local data.
          let panel = document.getElementById('__htmlappWidgetError');
          if (!panel) {
            panel = document.createElement('div');
            panel.id = '__htmlappWidgetError';
            panel.setAttribute('role', 'alert');
            panel.style.cssText = 'position:fixed;bottom:12px;left:12px;right:12px;z-index:2147483647;padding:16px;background:#321b20;color:white;border:1px solid #f99;border-radius:12px;font:14px system-ui;max-height:40vh;overflow:auto';
            (document.body || document.documentElement).appendChild(panel);
          }
          panel.replaceChildren();
          const detail = document.createElement('div');
          detail.textContent = 'Widget publication failed [' + error.code + ']: ' + error.message;
          const close = document.createElement('button');
          close.textContent = 'Dismiss';
          close.onclick = () => panel.remove();
          panel.append(detail, close);
        }
        item.reject(error);
      };

      const api = {
        call,
        capabilities: () => call('capabilities.list'),
        motion: {
          pedometer: (days = 1) => call('motion.pedometer', { days: Number(days) })
        },
        symbols: {
          search: (query = '') => call('symbols.search', { query: String(query) }),
          render: (name) => call('symbols.render', { name: String(name || '') })
        },
        device: {
          info: () => call('device.info'),
          keepAwake: (enabled = true) => call('device.keepAwake', { enabled: !!enabled }),
          brightness: (level) => call('device.brightness', level == null ? {} : { level: Number(level) }),
          torch: (enabled = true) => call('device.torch', { enabled: !!enabled })
        },
        clipboard: {
          readText: () => call('clipboard.readText'),
          writeText: (text) => call('clipboard.writeText', { text: String(text ?? '') })
        },
        haptics: {
          play: (pattern = [8]) => call('haptics.play', { pattern: Array.isArray(pattern) ? pattern : [pattern] })
        },
        share: {
          present: (options = {}) => call('share.present', options)
        },
        system: {
          open: (url) => call('system.open', { url: String(url || '') })
        },
        externalApps: {
          maps: (options = {}) => call('externalApps.maps', options || {}),
          shortcuts: (name, input = '') => call('externalApps.shortcuts', {
            name: String(name || ''),
            input: String(input ?? '')
          })
        },
        files: {
          pick: (options = {}) => call('files.pick', options)
        },
        contacts: {
          pick: () => call('contacts.pick'),
          list: (options = {}) => call('contacts.list', options),
          create: (contact) => call('contacts.create', contact || {})
        },
        photos: {
          pick: (options = {}) => call('photos.pick', options),
          save: (url) => call('photos.save', { url: String(url || '') })
        },
        calendar: {
          createEvent: (event) => call('calendar.createEvent', event || {}),
          events: (options = {}) => call('calendar.events', options),
          updateEvent: (event) => call('calendar.updateEvent', event || {}),
          deleteEvent: (id) => call('calendar.deleteEvent', { id: String(id || '') })
        },
        reminders: {
          create: (reminder) => call('reminders.create', reminder || {}),
          list: (options = {}) => call('reminders.list', options),
          update: (reminder) => call('reminders.update', reminder || {}),
          delete: (id) => call('reminders.delete', { id: String(id || '') })
        },
        notifications: {
          schedule: (notification) => call('notifications.schedule', notification || {}),
          cancel: (options = {}) => call('notifications.cancel', options)
        },
        biometrics: {
          authenticate: (options = {}) => call('biometrics.authenticate', options)
        },
        secureStorage: {
          set: (key, value) => call('secureStorage.set', { key: String(key || ''), value: String(value ?? '') }),
          get: (key) => call('secureStorage.get', { key: String(key || '') }),
          remove: (key) => call('secureStorage.remove', { key: String(key || '') })
        },
        appStorage: {
          get: async (key) => {
            const result = await call('appStorage.get', { key: String(key || '') });
            if (result?.value == null) return null;
            try { return JSON.parse(result.value); } catch (_) { return result.value; }
          },
          set: (key, value) => call('appStorage.set', {
            key: String(key || ''),
            value: JSON.stringify(value)
          }),
          remove: (key) => call('appStorage.remove', { key: String(key || '') }),
          all: async () => {
            const result = await call('appStorage.all');
            const output = {};
            for (const [key, value] of Object.entries(result?.values || {})) {
              try { output[key] = JSON.parse(value); } catch (_) { output[key] = value; }
            }
            return output;
          },
          clear: () => call('appStorage.clear')
        },
        liveActivities: {
          start: (definition) => call('liveActivities.start', definition || {}),
          update: (id, state = {}) => call('liveActivities.update', { ...state, id: String(id || '') }),
          end: (id) => call('liveActivities.end', { id: String(id || '') }),
          list: () => call('liveActivities.list')
        },
        widgets: {
          configure: (definition) => call('widgets.configure', definition || {}),
          list: () => call('widgets.list'),
          remove: (id) => call('widgets.remove', id ? { id: String(id) } : {}),
          reload: () => call('widgets.reload')
        },
        background: {
          configure: (job) => call('background.configure', job || {}),
          list: () => call('background.list'),
          remove: (id) => call('background.remove', id ? { id: String(id) } : {}),
          refreshNow: (id) => call('background.refreshNow', id ? { id: String(id) } : {})
        },
        speech: {
          speak: (text, options = {}) => call('speech.speak', { ...options, text: String(text ?? '') }),
          stop: () => call('speech.stop')
        }
      };

      window.HTMLApp = window.HTMLApp || {};
      window.HTMLApp.capabilities = () => api.capabilities();
      Object.defineProperty(window, 'HTMLAppNative', {
        configurable: false,
        enumerable: true,
        writable: false,
        value: Object.freeze(api)
      });
    })();
    """#
}


// Curated, stable iOS 16-compatible catalog; avoid claiming the system can
// enumerate all SF Symbols, which UIKit does not publicly expose.
enum HTMLAppSymbolCatalog {
    static let names: [String] = """
house house.fill gearshape gearshape.fill plus plus.circle plus.circle.fill minus minus.circle checkmark checkmark.circle checkmark.circle.fill xmark xmark.circle
star star.fill heart heart.fill bell bell.fill calendar clock stopwatch timer hourglass magnifyingglass line.3.horizontal slider.horizontal.3
square.grid.2x2 square.grid.2x2.fill list.bullet folder folder.fill doc doc.text doc.on.doc square.and.arrow.up arrow.down.doc
arrow.clockwise arrow.counterclockwise arrow.left arrow.right arrow.up arrow.down chevron.left chevron.right chevron.up chevron.down
trash trash.fill pencil pencil.circle paintbrush paintpalette scissors paperclip link lock lock.fill lock.open shield checkmark.shield
person person.fill person.crop.circle person.2 person.3 figure.walk figure.run figure.strengthtraining.traditional
bolt bolt.fill flame flame.fill leaf leaf.fill drop drop.fill sun.max sun.max.fill moon moon.fill cloud cloud.fill cloud.rain cloud.sun
wifi antenna.radiowaves.left.and.right airplane car bicycle bus tram map map.fill mappin location location.fill globe
camera camera.fill photo photo.fill video video.fill mic mic.fill speaker.wave.2 headphones play play.fill pause pause.fill stop stop.fill
backward.fill forward.fill music.note waveform chart.bar chart.bar.fill chart.line.uptrend.xyaxis chart.pie gauge speedometer
battery.100percent battery.50percent iphone ipad desktopcomputer laptopcomputer keyboard printer externaldrive
book book.fill bookmark bookmark.fill text.alignleft textformat text.cursor rectangle.stack square.stack cube.box shippingbox
fork.knife cup.and.saucer cart cart.fill bag bag.fill creditcard dollar signpost.right gift gift.fill
questionmark.circle info.circle exclamationmark.triangle hand.tap hand.raised eye eye.slash wrench screwdriver hammer
square.on.square rectangle.portrait.on.rectangle.portrait app.badge apps.iphone square.grid.3x3.fill
""".split(whereSeparator: \.isWhitespace).map(String.init)
}
