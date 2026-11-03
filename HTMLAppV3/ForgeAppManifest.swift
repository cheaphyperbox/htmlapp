import Foundation

/// Versioned, value-free product contract for generated apps. Do not store
/// source HTML, AI transcripts, user records, credentials or network payloads.
struct ForgeAppManifest: Codable {
    var manifestVersion: Int = 1
    var purpose: String
    var screens: [String]
    var components: [String]
    var routes: [String]
    var storageKeys: [String]
    var databaseCollections: [String]
    var storageSchemaVersion: Int
    var nativeCapabilities: [String]
    var permissions: [String]
    var networkDomains: [String]
    var designTokens: [String]
    var acceptanceCriteria: [String]
    var editHistory: [ForgeManifestEditRecord] = []

    static func build(html: String, model: ForgeSemanticAppModel) -> ForgeAppManifest {
        let methods = Array(Set(model.nativeMethods)).sorted()
        let permissions = Array(Set(methods.compactMap { permissionName($0) } +
                                    (methods.contains("video.capture") ? ["microphone"] : []))).sorted()
        let domains = networkHosts(in: html)
        return ForgeAppManifest(
            purpose: String(model.purpose.prefix(360)),
            screens: (model.screenIDs ?? []).prefix(40).map { $0 },
            components: model.components.prefix(100).map { $0 },
            routes: (model.routeIDs ?? []).prefix(40).map { $0 },
            storageKeys: model.storageKeys.prefix(100).map { $0 },
            databaseCollections: model.databaseCollections.prefix(60).map { $0 },
            storageSchemaVersion: 1,
            nativeCapabilities: methods,
            permissions: permissions,
            networkDomains: domains,
            designTokens: (model.designTokens ?? []).prefix(60).map { $0 },
            acceptanceCriteria: model.acceptance.prefix(35).map { $0 }
        )
    }

    var planningSummary: String {
        """
        APP MANIFEST v\(manifestVersion)
        Purpose: \(purpose)
        Screens: \(screens.joined(separator: ", "))
        Routes: \(routes.joined(separator: ", "))
        Semantic components: \(components.prefix(45).joined(separator: ", "))
        Protected storage keys: \(storageKeys.joined(separator: ", "))
        Protected DB collections: \(databaseCollections.joined(separator: ", "))
        Current schema version: \(storageSchemaVersion)
        Native capabilities: \(nativeCapabilities.joined(separator: ", "))
        Device permissions: \(permissions.joined(separator: ", "))
        Network hosts: \(networkDomains.joined(separator: ", "))
        Design tokens: \(designTokens.prefix(35).joined(separator: ", "))
        Required regression checks: \(acceptanceCriteria.joined(separator: " | "))
        Recent accepted changes: \(editHistory.suffix(6).map(\.note).joined(separator: " | "))
        The manifest is metadata, not permission to add new capabilities or change existing data.
        """
    }

    static func permissionName(_ method: String) -> String? {
        let group = String(method.split(separator: ".").first ?? "")
        switch group {
        case "camera", "video": return "camera"
        case "audio": return method == "audio.record" ? "microphone" : nil
        case "health", "nfc", "contacts", "calendar", "reminders", "bluetooth",
             "motion", "notifications", "biometrics", "ai", "spotlight",
             "network", "clipboard", "files", "liveActivities": return group
        case "photos": return "photoLibrary"
        case "push": return "notifications"
        case "location": return method == "location.roadSpeedLimit" ? "roadData" : "location"
        case "documents": return "files"
        case "externalApps", "system": return "externalApps"
        default: return nil
        }
    }

    private static func networkHosts(in html: String) -> [String] {
        let source = String(html.prefix(1_000_000))
        // This is an advisory disclosure, not an enforcement allowlist. The
        // separate native networking gate still asks before each DNS host.
        guard let regex = try? NSRegularExpression(
            pattern: #"https://([A-Za-z0-9.-]{1,253})(?=[^A-Za-z0-9.-]|$)"#,
            options: .caseInsensitive
        ) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, range: range).prefix(100)
        var domains = Set<String>()
        for match in matches {
            guard let value = Range(match.range(at: 1), in: source) else { continue }
            let host = String(source[value]).lowercased()
            guard host.contains("."), !host.hasSuffix(".local"),
                  host != "localhost", !host.hasSuffix(".internal") else { continue }
            domains.insert(host)
        }
        return Array(domains).sorted().prefix(40).map { $0 }
    }
}

struct ForgeManifestEditRecord: Codable {
    let note: String
    let componentsAdded: [String]
    let componentsRemoved: [String]
    let capabilitiesAdded: [String]
    let capabilitiesRemoved: [String]
}

enum ForgeAppManifestStore {
    private static func path(for appID: String) -> URL? {
        guard !appID.isEmpty,
              appID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
                    .contains($0)
              }),
              let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
              ).first else { return nil }
        return appSupport.appendingPathComponent("ForgeAppManifests", isDirectory: true)
            .appendingPathComponent(appID + ".json")
    }

    static func remove(for appID: String) {
        if let url = path(for: appID) { try? FileManager.default.removeItem(at: url) }
    }

    static func load(for appID: String) -> ForgeAppManifest? {
        guard let url = path(for: appID), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(ForgeAppManifest.self, from: data)
    }

    static func save(for appID: String, html: String, model: ForgeSemanticAppModel,
                     note: String = "") {
        guard let url = path(for: appID) else { return }
        let previous = load(for: appID)
        var next = ForgeAppManifest.build(html: html, model: model)
        // Keep previous acceptance criteria even if an edit removes the
        // screen/handler that originally justified them. This makes
        // regressions visible instead of erasing the test specification.
        if let previous {
            next.acceptanceCriteria = Array(Set(previous.acceptanceCriteria +
                                               next.acceptanceCriteria)).sorted().prefix(40).map { $0 }
            next.storageSchemaVersion = max(1, previous.storageSchemaVersion)
            next.editHistory = previous.editHistory
        }
        let cleanNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        if !cleanNote.isEmpty {
            next.editHistory.append(ForgeManifestEditRecord(
                note: cleanNote,
                componentsAdded: Array(Set(next.components)
                    .subtracting(previous?.components ?? [])).sorted().prefix(20).map { $0 },
                componentsRemoved: Array(Set(previous?.components ?? [])
                    .subtracting(next.components)).sorted().prefix(20).map { $0 },
                capabilitiesAdded: Array(Set(next.nativeCapabilities)
                    .subtracting(previous?.nativeCapabilities ?? [])).sorted(),
                capabilitiesRemoved: Array(Set(previous?.nativeCapabilities ?? [])
                    .subtracting(next.nativeCapabilities)).sorted()
            ))
            next.editHistory = Array(next.editHistory.suffix(20))
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
        } catch {
            // The metadata cache must never prevent saving real app data.
        }
    }

    static func updateStorageVersion(for appID: String, to version: Int) {
        guard (1...1000).contains(version), let url = path(for: appID),
              var value = load(for: appID) else { return }
        value.storageSchemaVersion = max(version, value.storageSchemaVersion)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
