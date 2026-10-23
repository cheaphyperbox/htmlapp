import Foundation

/// Optional iCloud Documents mirroring. Local Library and portable data remain
/// authoritative while iCloud is disabled or unavailable.
enum HTMLAppICloudPreferences {
    static let appsKey = "htmlapp.icloud.syncApps"
    static let dataKey = "htmlapp.icloud.syncData"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: appsKey) }
    static var includeData: Bool { enabled && UserDefaults.standard.bool(forKey: dataKey) }
}

actor HTMLAppICloudSync {
    static let shared = HTMLAppICloudSync()
    private let fm = FileManager.default
    private var syncing = false

    struct Incoming: Sendable {
        var apps: [SavedHTMLApp] = []
        var data: [String: [String: String]] = [:]
    }

    /// FileManager's ubiquity lookup can block: never call on the main actor.
    private func folder() -> URL? {
        guard let container = fm.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let folder = container.appendingPathComponent("Documents/HTMLAppSync", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func read(_ url: URL) -> Data? {
        if fm.isUbiquitousItem(at: url) { try? fm.startDownloadingUbiquitousItem(at: url) }
        var result: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
            result = try? Data(contentsOf: coordinated)
        }
        return result
    }

    private func write(_ data: Data, at url: URL) {
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &error) { coordinated in
            try? data.write(to: coordinated, options: .atomic)
        }
    }

    func exchange(localApps: [SavedHTMLApp], localData: [String: [String: String]]) -> Incoming {
        guard HTMLAppICloudPreferences.enabled, !syncing, let root = folder() else { return Incoming() }
        syncing = true
        defer { syncing = false }
        let appRoot = root.appendingPathComponent("Apps", isDirectory: true)
        let dataRoot = root.appendingPathComponent("Data", isDirectory: true)
        try? fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
        if HTMLAppICloudPreferences.includeData {
            try? fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        var incoming = Incoming()
        var remote: [String: SavedHTMLApp] = [:]
        for url in (try? fm.contentsOfDirectory(at: appRoot, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            if let bytes = read(url), let app = try? JSONDecoder().decode(SavedHTMLApp.self, from: bytes) {
                remote[app.id] = app
            }
        }
        for app in localApps {
            if let cloud = remote.removeValue(forKey: app.id), cloud.updatedAt > app.updatedAt {
                incoming.apps.append(cloud)
            } else if let bytes = try? encoder.encode(app) {
                // Do not overwrite newer remote app versions with stale local data.
                write(bytes, at: appRoot.appendingPathComponent(app.id + ".json"))
            }
        }
        incoming.apps.append(contentsOf: remote.values)

        if HTMLAppICloudPreferences.includeData {
            // Preserve per-app data independently and never mirror permissions,
            // tokens, app-specific Keychain items, or OS authorization decisions.
            let ids = Set(localApps.map(\.id)).union(incoming.apps.map(\.id))
            for id in ids {
                let url = dataRoot.appendingPathComponent(id + ".json")
                let values = localData[id] ?? [:]
                let localURL = HTMLAppPortableDataStore.fileURL(appID: id)
                let localDate = (try? fm.attributesOfItem(atPath: localURL.path)[.modificationDate]) as? Date ?? .distantPast
                let cloudDate = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date ?? .distantPast
                if cloudDate > localDate, let bytes = read(url),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: bytes) {
                    incoming.data[id] = decoded
                } else if !values.isEmpty, let bytes = try? encoder.encode(values) {
                    write(bytes, at: url)
                }
            }
        }
        return incoming
    }
}
