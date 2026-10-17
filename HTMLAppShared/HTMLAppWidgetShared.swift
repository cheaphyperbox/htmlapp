import Foundation

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

enum HTMLAppWidgetStore {
    private static let key = "htmlapp.shared.widgets.v1"

    private static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: HTMLAppSharedContainer.appGroupID)?
            .appendingPathComponent("htmlapp-widgets-v2.json", isDirectory: false)
    }

    static func all() -> [HTMLAppWidgetDefinition] {
        guard let sharedFile else { return [] }
        // WidgetKit is a separate process. Read directly from the shared file instead
        // of relying on UserDefaults notifications or process-local preference caches.
        if let data = try? Data(contentsOf: sharedFile),
           let values = try? JSONDecoder().decode([HTMLAppWidgetDefinition].self, from: data) {
            return values.sorted { $0.updatedAt > $1.updatedAt }
        }
        // Migrate installations that saved widget definitions using the original
        // App Group UserDefaults storage.
        if let legacy = HTMLAppSharedContainer.defaults.data(forKey: key),
           let values = try? JSONDecoder().decode([HTMLAppWidgetDefinition].self, from: legacy) {
            persist(values)
            return values.sorted { $0.updatedAt > $1.updatedAt }
        }
        return []
    }

    static func definitions(appID: String) -> [HTMLAppWidgetDefinition] {
        all().filter { $0.appID == appID }
    }

    static func definition(compositeID: String) -> HTMLAppWidgetDefinition? {
        all().first { $0.id == compositeID }
    }

    static func preferredDefinition() -> HTMLAppWidgetDefinition? {
        let values = all()
        return values.first(where: { $0.primary }) ?? values.first
    }

    static func save(_ definition: HTMLAppWidgetDefinition) {
        var values = all()
        values.removeAll { $0.id == definition.id }
        var fresh = definition
        fresh.updatedAt = Date()
        if fresh.primary {
            for i in values.indices { values[i].primary = false }
        }
        values.append(fresh)
        persist(values)
    }

    static func setPrimary(compositeID: String) {
        var values = all()
        guard values.contains(where: { $0.id == compositeID }) else { return }
        for i in values.indices { values[i].primary = values[i].id == compositeID }
        persist(values)
    }

    static func replace(appID: String, with definitions: [HTMLAppWidgetDefinition]) {
        var values = all().filter { $0.appID != appID }
        values.append(contentsOf: definitions.map { value in
            var copy = value
            copy.appID = appID
            copy.updatedAt = Date()
            return copy
        })
        persist(values)
    }

    static func remove(appID: String, widgetID: String? = nil) {
        var values = all()
        if let widgetID {
            values.removeAll { $0.appID == appID && $0.widgetID == widgetID }
        } else {
            values.removeAll { $0.appID == appID }
        }
        persist(values)
    }

    private static func persist(_ values: [HTMLAppWidgetDefinition]) {
        guard let sharedFile, let data = try? JSONEncoder().encode(values) else { return }
        // Atomic replacement prevents WidgetKit from observing a partial JSON file.
        do {
            try data.write(to: sharedFile, options: [.atomic])
            // Preserve the legacy copy for compatibility with old installations.
            HTMLAppSharedContainer.defaults.set(data, forKey: key)
        } catch {
            // Never pretend that a failed shared-container write succeeded.
            NSLog("HTMLApp widget shared data write failed: %@", String(describing: error))
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
