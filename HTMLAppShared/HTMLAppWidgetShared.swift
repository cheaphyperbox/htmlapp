import Foundation
import CryptoKit

enum HTMLAppSharedContainer {
    static let appGroupID = "group.com.mekabrine.htmlapp"

    static var appGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

struct HTMLAppWidgetItem: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var value: String
    var detail: String?
    var systemSymbol: String?
    var progress: Double?

    init(
        id: String = UUID().uuidString,
        label: String,
        value: String,
        detail: String? = nil,
        systemSymbol: String? = nil,
        progress: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.detail = detail
        self.systemSymbol = systemSymbol
        self.progress = progress
    }
}

struct HTMLAppWidgetSnapshot: Codable, Hashable {
    var layout: String?
    var eyebrow: String?
    var title: String?
    var subtitle: String?
    var value: String?
    var unit: String?
    var footer: String?
    var systemSymbol: String?
    var progress: Double?
    var backgroundHex: String?
    var backgroundSecondaryHex: String?
    var foregroundHex: String?
    var accentHex: String?
    var imageBase64: String?
    var items: [HTMLAppWidgetItem]?

    static let placeholder = HTMLAppWidgetSnapshot(
        layout: "metric",
        eyebrow: "HTMLApp",
        title: "Generated Widget",
        subtitle: "Open HTMLApp to configure this widget.",
        value: "—",
        unit: nil,
        footer: nil,
        systemSymbol: "square.grid.2x2.fill",
        progress: nil,
        backgroundHex: "#15171B",
        backgroundSecondaryHex: "#242832",
        foregroundHex: "#FFFFFF",
        accentHex: "#65A9FF",
        imageBase64: nil,
        items: nil
    )
}

struct HTMLAppWidgetRefreshSpec: Codable, Hashable {
    var url: String
    var intervalMinutes: Int
    var bindings: [String: String]

    init(url: String, intervalMinutes: Int = 30, bindings: [String: String] = [:]) {
        self.url = url
        self.intervalMinutes = min(max(intervalMinutes, 15), 1440)
        self.bindings = bindings
    }
}

struct HTMLAppWidgetDefinition: Codable, Hashable, Identifiable {
    var appID: String
    var widgetID: String
    var name: String
    var primary: Bool
    var families: [String]
    var snapshot: HTMLAppWidgetSnapshot
    var refresh: HTMLAppWidgetRefreshSpec?
    var updatedAt: Date
    var lastRefreshAt: Date?
    var lastError: String?

    var id: String { appID + "::" + widgetID }

    static func unavailable() -> HTMLAppWidgetDefinition {
        var definition = placeholder(id: "unavailable")
        definition.snapshot.title = "Widget unavailable"
        definition.snapshot.subtitle = "HTMLApp and Widgets need the same signed App Group."
        definition.snapshot.eyebrow = "SIGNING"
        definition.snapshot.value = "!"
        definition.snapshot.footer = "Check Settings"
        definition.snapshot.systemSymbol = "exclamationmark.triangle.fill"
        definition.snapshot.accentHex = "#FFB347"
        return definition
    }

    static func placeholder(id: String = "placeholder") -> HTMLAppWidgetDefinition {
        HTMLAppWidgetDefinition(
            appID: "placeholder",
            widgetID: id,
            name: "HTMLApp Widget",
            primary: true,
            families: ["systemSmall", "systemMedium", "systemLarge", "accessoryInline", "accessoryCircular", "accessoryRectangular"],
            snapshot: .placeholder,
            refresh: nil,
            updatedAt: Date(),
            lastRefreshAt: nil,
            lastError: nil
        )
    }
}

struct HTMLAppWidgetStoreError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { "\(code): \(message)" }
    static let unavailable = Self(code: "app_group_unavailable", message: "Shared container unavailable in this process. Both app and extension need the same App Group authorized by their signing profiles. Entitlement injection alone cannot authorize Feather installations.")
}

// All read/modify/write transactions coordinate on the same URL across processes.
// The existing array schema and filename remain compatible with installed versions.
final class HTMLAppWidgetRepository {
    let file: URL
    let legacy: () -> Data?
    init(directory: URL, legacy: @escaping () -> Data? = { nil }) {
        file = directory.appendingPathComponent("htmlapp-widgets-v2.json")
        self.legacy = legacy
    }

    private func coordinated<T>(write: Bool, _ body: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let accessor: (URL) -> Void = { url in result = Result { try body(url) } }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if write {
            coordinator.coordinate(writingItemAt: file, options: [], error: &coordinationError, byAccessor: accessor)
        } else {
            coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError, byAccessor: accessor)
        }
        if let error = coordinationError { throw Self.failure("store_coordination_failed", error) }
        guard let result else { throw HTMLAppWidgetStoreError(code: "store_coordination_failed", message: "Shared file access did not run.") }
        return try result.get()
    }

    static func failure(_ code: String, _ error: Error) -> HTMLAppWidgetStoreError {
        // Never emit localized filesystem errors: they can contain private paths.
        let e = error as NSError
        return .init(code: code, message: "Shared widget storage failed (\(e.domain), \(e.code)). Unlock the device and check both signing profiles and App Group authorization.")
    }

    private func read(_ url: URL) throws -> [HTMLAppWidgetDefinition] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch {
            let e = error as NSError
            guard e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError else {
                throw Self.failure("store_read_failed", error)
            }
            guard let old = legacy() else { return [] }
            data = old
        }
        do { return Self.normalized(try JSONDecoder().decode([HTMLAppWidgetDefinition].self, from: data)) }
        catch { throw HTMLAppWidgetStoreError(code: "store_decode_failed", message: "Widget data could not be decoded. Existing data was preserved; restore a compatible backup or republish after diagnosis.") }
    }

    static func normalized(_ values: [HTMLAppWidgetDefinition]) -> [HTMLAppWidgetDefinition] {
        let sorted = values.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        var seen = Set<String>()
        var unique = sorted.filter { seen.insert($0.id).inserted }
        let primary = unique.first(where: { $0.primary })?.id ?? unique.first?.id
        for i in unique.indices { unique[i].primary = unique[i].id == primary }
        return unique
    }

    func all() throws -> [HTMLAppWidgetDefinition] { try coordinated(write: false, read) }

    @discardableResult
    func mutate(_ change: (inout [HTMLAppWidgetDefinition]) throws -> Void) throws -> [HTMLAppWidgetDefinition] {
        try coordinated(write: true) { url in
            var values = try read(url)
            try change(&values)
            values = Self.normalized(values)
            do {
                let data = try JSONEncoder().encode(values)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                let verified = try JSONDecoder().decode([HTMLAppWidgetDefinition].self, from: Data(contentsOf: url))
                guard verified == values else { throw HTMLAppWidgetStoreError(code: "store_verify_failed", message: "Saved snapshot did not match read-back.") }
            } catch let error as HTMLAppWidgetStoreError { throw error }
            catch { throw Self.failure("store_write_failed", error) }
            return values
        }
    }

    func save(_ definition: HTMLAppWidgetDefinition) throws -> HTMLAppWidgetDefinition {
        let values = try mutate { values in
            values.removeAll { $0.id == definition.id }
            var fresh = definition
            fresh.updatedAt = Date()
            if fresh.primary { for i in values.indices { values[i].primary = false } }
            values.append(fresh)
        }
        return values.first { $0.id == definition.id }!
    }

    // A network request started before a publication must never overwrite that publication.
    func refresh(_ refreshed: HTMLAppWidgetDefinition, original: HTMLAppWidgetDefinition) throws {
        try mutate { values in
            guard let i = values.firstIndex(where: { $0.id == original.id }), values[i] == original else { return }
            values[i].snapshot = refreshed.snapshot
            values[i].lastRefreshAt = refreshed.lastRefreshAt
            values[i].lastError = refreshed.lastError
            values[i].updatedAt = refreshed.updatedAt
        }
    }
}

enum HTMLAppWidgetStore {
    static func repository() throws -> HTMLAppWidgetRepository {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HTMLAppSharedContainer.appGroupID) else { throw HTMLAppWidgetStoreError.unavailable }
        return HTMLAppWidgetRepository(directory: directory) {
            UserDefaults(suiteName: HTMLAppSharedContainer.appGroupID)?.data(forKey: "htmlapp.shared.widgets.v1")
        }
    }
    static func readAll() throws -> [HTMLAppWidgetDefinition] { try repository().all() }
    static func all() -> [HTMLAppWidgetDefinition] { (try? readAll()) ?? [] }
    static func definitions(appID: String) -> [HTMLAppWidgetDefinition] { all().filter { $0.appID == appID } }
    static func definition(compositeID: String) -> HTMLAppWidgetDefinition? { all().first { $0.id == compositeID } }
    static func preferredDefinition() -> HTMLAppWidgetDefinition? { all().first(where: { $0.primary }) }
    @discardableResult
    static func saveVerified(_ definition: HTMLAppWidgetDefinition) throws -> HTMLAppWidgetDefinition { try repository().save(definition) }
    static func save(_ definition: HTMLAppWidgetDefinition) { report { _ = try saveVerified(definition) } }
    static func setPrimaryVerified(compositeID: String) throws {
        try repository().mutate { values in
            guard values.contains(where: { $0.id == compositeID }) else { throw HTMLAppWidgetStoreError(code: "widget_not_found", message: "Republish this widget before selecting it.") }
            for i in values.indices { values[i].primary = values[i].id == compositeID }
        }
    }
    static func setPrimary(compositeID: String) { report { try setPrimaryVerified(compositeID: compositeID) } }
    static func replace(appID: String, with definitions: [HTMLAppWidgetDefinition]) {
        report {
            try repository().mutate { values in
                values.removeAll { $0.appID == appID }
                values.append(contentsOf: definitions.map { value in
                    var copy = value; copy.appID = appID; copy.updatedAt = Date(); return copy
                })
            }
        }
    }
    static func removeVerified(appID: String, widgetID: String? = nil) throws {
        try repository().mutate { values in values.removeAll { $0.appID == appID && (widgetID == nil || $0.widgetID == widgetID) } }
    }
    static func remove(appID: String, widgetID: String? = nil) { report { try removeVerified(appID: appID, widgetID: widgetID) } }
    static func report(_ work: () throws -> Void) {
        do { try work() } catch { NSLog("HTMLApp widget operation failed: %@", error.localizedDescription) }
    }
}

struct HTMLAppWidgetProbe: Codable {
    let nonce: String
    let createdAt: Date
}
struct HTMLAppWidgetReceipt: Codable {
    let nonce: String
    let process: String
    let phase: String
    let family: String
    let definitionDigest: String?
    let status: String
    let date: Date
}

enum HTMLAppWidgetDiagnostics {
    private static func url(_ name: String) throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HTMLAppSharedContainer.appGroupID) else { throw HTMLAppWidgetStoreError.unavailable }
        return root.appendingPathComponent(name)
    }
    static func digest(_ definition: HTMLAppWidgetDefinition) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(definition)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    static func begin() throws -> String {
        let probe = HTMLAppWidgetProbe(nonce: UUID().uuidString, createdAt: Date())
        do {
            try JSONEncoder().encode(probe).write(to: url("widget-probe.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { throw HTMLAppWidgetRepository.failure("probe_write_failed", error) }
        return probe.nonce
    }
    static func acknowledge(phase: String, family: String, definition: HTMLAppWidgetDefinition?, status: String) {
        // Only an extension process can acknowledge; app-side preview reads are not evidence.
        guard Bundle.main.bundleURL.pathExtension == "appex",
              let data = try? Data(contentsOf: url("widget-probe.json")),
              let probe = try? JSONDecoder().decode(HTMLAppWidgetProbe.self, from: data) else { return }
        let receipt = HTMLAppWidgetReceipt(nonce: probe.nonce, process: "widget-extension", phase: phase, family: family,
            definitionDigest: definition.map(digest), status: status, date: Date())
        try? JSONEncoder().encode(receipt).write(to: url("widget-receipt-\(phase).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func summary() -> String {
        var lines = ["Main process container: \(HTMLAppSharedContainer.appGroupAvailable ? "available" : "unavailable")",
            "Effective entitlements: not inspectable using public iOS APIs; verify installed signatures and profiles separately."]
        do { lines.append("Decoded definitions: \(try HTMLAppWidgetStore.readAll().count)") }
        catch { lines.append(error.localizedDescription) }
        guard let data = try? Data(contentsOf: url("widget-probe.json")),
              let probe = try? JSONDecoder().decode(HTMLAppWidgetProbe.self, from: data) else { return lines.joined(separator: "\n") }
        lines.append("Probe: \(probe.nonce)")
        if let data = try? Data(contentsOf: url("widget-receipt-timeline.json")),
           let receipt = try? JSONDecoder().decode(HTMLAppWidgetReceipt.self, from: data), receipt.nonce == probe.nonce {
            lines.append("Extension acknowledged: \(receipt.status), \(receipt.family), \(receipt.date.formatted())")
            let matches = HTMLAppWidgetStore.all().contains { digest($0) == receipt.definitionDigest }
            lines.append("Timeline decoded current published snapshot: \(matches ? "yes" : "no")")
        } else { lines.append("Extension acknowledgement pending. This does not prove a signing failure; add a widget and request reload.") }
        return lines.joined(separator: "\n")
    }
}

// Both providers use this resolver. Failures are real timeline entries, never a generic gallery placeholder.
enum HTMLAppWidgetResolver {
    static let primaryID = "htmlapp-primary"
    static func resolve(values: [HTMLAppWidgetDefinition], selectedID: String?, family: String) throws -> HTMLAppWidgetDefinition {
        let values = HTMLAppWidgetRepository.normalized(values)
        let definition: HTMLAppWidgetDefinition?
        if let id = selectedID, id != primaryID {
            definition = values.first { $0.id == id }
        } else { definition = values.first { $0.primary } }
        guard let definition else { throw HTMLAppWidgetStoreError(code: "widget_not_found", message: "Publish a widget in HTMLApp, then select it in Widgets & Background or Edit Widget.") }
        guard definition.families.contains(family) else { throw HTMLAppWidgetStoreError(code: "widget_family_mismatch", message: "Republish this widget for this size or add one of its published sizes.") }
        return definition
    }
    static func load(selectedID: String?, family: String, phase: String) -> HTMLAppWidgetDefinition {
        do {
            let definition = try resolve(values: HTMLAppWidgetStore.readAll(), selectedID: selectedID, family: family)
            HTMLAppWidgetDiagnostics.acknowledge(phase: phase, family: family, definition: definition, status: "decoded")
            return definition
        } catch {
            let error = (error as? HTMLAppWidgetStoreError) ?? HTMLAppWidgetRepository.failure("store_read_failed", error)
            HTMLAppWidgetDiagnostics.acknowledge(phase: phase, family: family, definition: nil, status: error.code)
            var definition = HTMLAppWidgetDefinition.unavailable()
            definition.snapshot.title = "Widget needs attention"
            definition.snapshot.eyebrow = error.code
            definition.snapshot.subtitle = error.message
            definition.snapshot.footer = "Open Widgets & Background"
            return definition
        }
    }
}

struct HTMLAppBackgroundFetchJob: Codable, Hashable, Identifiable {
    var appID: String
    var jobID: String
    var url: String
    var intervalMinutes: Int
    var storageKey: String
    var jsonPath: String?
    var widgetID: String?
    var enabled: Bool
    var updatedAt: Date
    var lastRunAt: Date?
    var lastError: String?

    var id: String { appID + "::" + jobID }
}

enum HTMLAppBackgroundJobStore {
    private static let key = "htmlapp.shared.backgroundJobs.v1"

    static func all() -> [HTMLAppBackgroundFetchJob] {
        guard HTMLAppSharedContainer.appGroupAvailable else { return [] }
        guard let data = HTMLAppSharedContainer.defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([HTMLAppBackgroundFetchJob].self, from: data) else {
            return []
        }
        return values
    }

    static func jobs(appID: String) -> [HTMLAppBackgroundFetchJob] {
        all().filter { $0.appID == appID }
    }

    static func save(_ job: HTMLAppBackgroundFetchJob) {
        var values = all()
        values.removeAll { $0.id == job.id }
        var fresh = job
        fresh.intervalMinutes = min(max(fresh.intervalMinutes, 15), 1440)
        fresh.updatedAt = Date()
        values.append(fresh)
        persist(values)
    }

    static func replace(appID: String, with jobs: [HTMLAppBackgroundFetchJob]) {
        var values = all().filter { $0.appID != appID }
        values.append(contentsOf: jobs.map { value in
            var copy = value
            copy.appID = appID
            copy.updatedAt = Date()
            return copy
        })
        persist(values)
    }

    static func remove(appID: String, jobID: String? = nil) {
        var values = all()
        if let jobID {
            values.removeAll { $0.appID == appID && $0.jobID == jobID }
        } else {
            values.removeAll { $0.appID == appID }
        }
        persist(values)
    }

    static func updateRuntimeState(id: String, lastRunAt: Date?, lastError: String?) {
        var values = all()
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].lastRunAt = lastRunAt
        values[index].lastError = lastError
        persist(values)
    }

    private static func persist(_ values: [HTMLAppBackgroundFetchJob]) {
        guard HTMLAppSharedContainer.appGroupAvailable else { return }
        guard let data = try? JSONEncoder().encode(values) else { return }
        HTMLAppSharedContainer.defaults.set(data, forKey: key)
    }
}

enum HTMLAppJSONPath {
    static func value(at path: String, in root: Any) -> Any? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return root }

        var current: Any? = root
        for component in trimmed.split(separator: ".").map(String.init) {
            guard let currentValue = current else { return nil }
            if let dictionary = currentValue as? [String: Any] {
                current = dictionary[component]
            } else if let array = currentValue as? [Any],
                      let index = Int(component),
                      array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }

    static func displayString(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    static func jsonString(_ value: Any) -> String? {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            return String(data: data, encoding: .utf8)
        }
        return displayString(value)
    }

    static func applyBindings(_ bindings: [String: String], json: Any, to original: HTMLAppWidgetSnapshot) -> HTMLAppWidgetSnapshot {
        var snapshot = original
        for (target, sourcePath) in bindings {
            let value = value(at: sourcePath, in: json)
            switch target {
            case "eyebrow": snapshot.eyebrow = displayString(value)
            case "title": snapshot.title = displayString(value)
            case "subtitle": snapshot.subtitle = displayString(value)
            case "value": snapshot.value = displayString(value)
            case "unit": snapshot.unit = displayString(value)
            case "footer": snapshot.footer = displayString(value)
            case "progress":
                if let number = value as? NSNumber {
                    snapshot.progress = min(max(number.doubleValue, 0), 1)
                } else if let string = displayString(value), let number = Double(string) {
                    snapshot.progress = min(max(number, 0), 1)
                }
            default:
                applyItemBinding(target: target, value: value, snapshot: &snapshot)
            }
        }
        return snapshot
    }

    private static func applyItemBinding(target: String, value: Any?, snapshot: inout HTMLAppWidgetSnapshot) {
        let parts = target.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "items", let index = Int(parts[1]), index >= 0, index < 8 else { return }

        var items = snapshot.items ?? []
        while items.count <= index {
            items.append(HTMLAppWidgetItem(label: "", value: ""))
        }

        switch parts[2] {
        case "label": items[index].label = displayString(value) ?? ""
        case "value": items[index].value = displayString(value) ?? ""
        case "detail": items[index].detail = displayString(value)
        case "progress":
            if let number = value as? NSNumber {
                items[index].progress = min(max(number.doubleValue, 0), 1)
            } else if let string = displayString(value), let number = Double(string) {
                items[index].progress = min(max(number, 0), 1)
            }
        default: break
        }
        snapshot.items = items
    }
}

enum HTMLAppWidgetNetwork {
    static func refreshed(_ definition: HTMLAppWidgetDefinition) async -> HTMLAppWidgetDefinition {
        guard let refresh = definition.refresh,
              let url = URL(string: refresh.url),
              url.scheme?.lowercased() == "https" else {
            return definition
        }

        var result = definition
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 18
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 2_000_000,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let json = try JSONSerialization.jsonObject(with: data)
            result.snapshot = HTMLAppJSONPath.applyBindings(refresh.bindings, json: json, to: result.snapshot)
            result.lastRefreshAt = Date()
            result.lastError = nil
            result.updatedAt = Date()
            return result
        } catch {
            result.lastError = error.localizedDescription
            result.updatedAt = Date()
            return result
        }
    }
}

