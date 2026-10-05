import Foundation
import UIKit
import WebKit
import Contacts
import PhotosUI
import EventKit
import LocalAuthentication
import UniformTypeIdentifiers
import AVFoundation
import Security

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
        case "device.keepAwake":
            UIApplication.shared.isIdleTimerDisabled = args["enabled"] as? Bool ?? false
            resolve(id, value: ["enabled": UIApplication.shared.isIdleTimerDisabled])
        case "clipboard.readText":
            resolve(id, value: ["text": UIPasteboard.general.string ?? ""])
        case "clipboard.writeText":
            UIPasteboard.general.string = args["text"] as? String ?? ""
            resolve(id, value: ["written": true])
        case "haptics.play":
            let values = (args["pattern"] as? [NSNumber])?.map { $0.intValue } ?? [8]
            HTMLHapticsBridge.perform(pattern: values)
            resolve(id, value: ["played": true])
        case "share.present":
            presentShare(id: id, args: args)
        case "system.open":
            openURL(id: id, value: args["url"] as? String ?? "")
        case "files.pick":
            pickFiles(id: id, args: args)
        case "contacts.pick":
            withPermission(.contacts, id: id) { [weak self] in self?.pickContact(id: id) }
        case "contacts.list":
            withPermission(.contacts, id: id) { [weak self] in self?.listContacts(id: id, args: args) }
        case "photos.pick":
            withPermission(.photoLibrary, id: id) { [weak self] in self?.pickPhotos(id: id, args: args) }
        case "calendar.createEvent":
            withPermission(.calendar, id: id) { [weak self] in self?.createEvent(id: id, args: args) }
        case "calendar.events":
            withPermission(.calendar, id: id) { [weak self] in self?.listEvents(id: id, args: args) }
        case "reminders.create":
            withPermission(.reminders, id: id) { [weak self] in self?.createReminder(id: id, args: args) }
        case "reminders.list":
            withPermission(.reminders, id: id) { [weak self] in self?.listReminders(id: id, args: args) }
        case "biometrics.authenticate":
            withPermission(.biometrics, id: id) { [weak self] in self?.authenticate(id: id, args: args) }
        case "secureStorage.set":
            secureStorageSet(id: id, args: args)
        case "secureStorage.get":
            secureStorageGet(id: id, args: args)
        case "secureStorage.remove":
            secureStorageRemove(id: id, args: args)
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
        permissionCoordinator?.requestHTMLPermission(permission) { [weak self] allowed in
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

    private func openURL(id: String, value: String) {
        guard let url = URL(string: value), UIApplication.shared.canOpenURL(url) else {
            reject(id, code: "invalid_url", message: "The requested URL cannot be opened.")
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
            guard let self else { return }
            guard granted else {
                Task { @MainActor in
                    self.reject(id, code: "system_permission_denied", message: error?.localizedDescription ?? "iOS Contacts access was denied.")
                }
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
                Task { @MainActor in self.resolve(id, value: values) }
            } catch {
                Task { @MainActor in self.reject(id, code: "contacts_failed", message: error.localizedDescription) }
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
                defer { group.leave() }
                guard let self, let url else { return }
                if let item = self.importFile(url: url, namespace: "photos", preferredName: result.itemProvider.suggestedName, typeIdentifier: typeIdentifier) {
                    lock.lock()
                    imported.append(item)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if imported.isEmpty { self.reject(id, code: "photo_import_failed", message: "The selected media could not be imported.") }
            else { self.resolve(id, value: imported) }
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
                Task { @MainActor in self.resolve(id, value: Array(values)) }
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
        pending.set(id, { resolve, reject });
        handler.postMessage({ id, method, args });
      });

      window.__htmlappNativeResolve = (id, ok, value) => {
        const item = pending.get(id);
        if (!item) return;
        pending.delete(id);
        if (ok) {
          item.resolve(value);
          return;
        }
        const error = new Error(value?.message || 'Native operation failed.');
        error.code = value?.code || 'native_error';
        item.reject(error);
      };

      const api = {
        call,
        device: {
          info: () => call('device.info'),
          keepAwake: (enabled = true) => call('device.keepAwake', { enabled: !!enabled })
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
        files: {
          pick: (options = {}) => call('files.pick', options)
        },
        contacts: {
          pick: () => call('contacts.pick'),
          list: (options = {}) => call('contacts.list', options)
        },
        photos: {
          pick: (options = {}) => call('photos.pick', options)
        },
        calendar: {
          createEvent: (event) => call('calendar.createEvent', event || {}),
          events: (options = {}) => call('calendar.events', options)
        },
        reminders: {
          create: (reminder) => call('reminders.create', reminder || {}),
          list: (options = {}) => call('reminders.list', options)
        },
        biometrics: {
          authenticate: (options = {}) => call('biometrics.authenticate', options)
        },
        secureStorage: {
          set: (key, value) => call('secureStorage.set', { key: String(key || ''), value: String(value ?? '') }),
          get: (key) => call('secureStorage.get', { key: String(key || '') }),
          remove: (key) => call('secureStorage.remove', { key: String(key || '') })
        },
        speech: {
          speak: (text, options = {}) => call('speech.speak', { ...options, text: String(text ?? '') }),
          stop: () => call('speech.stop')
        }
      };

      Object.defineProperty(window, 'HTMLAppNative', {
        configurable: false,
        enumerable: true,
        writable: false,
        value: Object.freeze(api)
      });
    })();
    """#
}
