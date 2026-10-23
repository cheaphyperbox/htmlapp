import Foundation

enum HTMLAppPortableDataStore {
    static let localDataChanged = Notification.Name("HTMLAppPortableDataChanged")
    private static let queue = DispatchQueue(label: "com.mekabrine.htmlapp.portable-data")
    private static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
            .appendingPathComponent("PortableAppData", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func get(appID: String, key: String) -> String? {
        queue.sync { load(appID: appID)[key] }
    }

    static func set(appID: String, key: String, value: String) {
        queue.sync {
            var values = load(appID: appID)
            values[key] = value
            persist(values, appID: appID)
        }
        HTMLAppWidgetStore.updateFromPortableData(appID: appID, key: key, value: value)
        HTMLAppWidgetReloadCoordinator.request()
        NotificationCenter.default.post(name: localDataChanged, object: nil)
    }

    static func remove(appID: String, key: String) {
        queue.sync {
            var values = load(appID: appID)
            values.removeValue(forKey: key)
            persist(values, appID: appID)
        }
        HTMLAppWidgetStore.updateFromPortableData(appID: appID, key: key, value: nil)
        HTMLAppWidgetReloadCoordinator.request()
        NotificationCenter.default.post(name: localDataChanged, object: nil)
    }

    static func all(appID: String) -> [String: String] {
        queue.sync { load(appID: appID) }
    }

    static func replace(appID: String, values: [String: String]) {
        let removed = Set(all(appID: appID).keys).subtracting(values.keys)
        queue.sync { persist(values, appID: appID) }
        for key in removed {
            HTMLAppWidgetStore.updateFromPortableData(appID: appID, key: key, value: nil)
        }
        for (key, value) in values {
            HTMLAppWidgetStore.updateFromPortableData(appID: appID, key: key, value: value)
        }
        HTMLAppWidgetReloadCoordinator.request()
    }

    static func clear(appID: String) {
        let keys = Array(all(appID: appID).keys)
        queue.sync { try? FileManager.default.removeItem(at: fileURL(appID: appID)) }
        for key in keys {
            HTMLAppWidgetStore.updateFromPortableData(appID: appID, key: key, value: nil)
        }
        HTMLAppWidgetReloadCoordinator.request()
    }

    private static func load(appID: String) -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL(appID: appID)),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private static func persist(_ values: [String: String], appID: String) {
        let destination = fileURL(appID: appID)
        if values.isEmpty {
            try? FileManager.default.removeItem(at: destination)
            return
        }
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: destination, options: .atomic)
    }

    static func fileURL(appID: String) -> URL {
        let safe = appID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return root.appendingPathComponent(safe.isEmpty ? "invalid" : safe).appendingPathExtension("json")
    }
}
