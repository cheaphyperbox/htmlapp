import Foundation

/// A compact, value-free model of the saved app. It never stores the user's
/// records, secrets, full source, HTML input values, or AI transcripts.
struct ForgeSemanticAppModel: Codable {
    var version: Int = 1
    var purpose: String
    var components: [String]
    var storageKeys: [String]
    var databaseCollections: [String]
    var nativeMethods: [String]
    var acceptance: [String]
    var recentEdits: [String] = []

    static func build(html: String, purpose: String) -> ForgeSemanticAppModel {
        let source = String(html.prefix(1_000_000))
        let ids = captures(#"\bid\s*=\s*["']([^"']+)["']"#, source)
        let semantic = captures(#"data-forge-id\s*=\s*["']([^"']+)["']"#, source)
            + captures(#"data-screen\s*=\s*["']([^"']+)["']"#, source)
            + captures(#"data-view\s*=\s*["']([^"']+)["']"#, source)
        let appKeys = captures(#"(?:localStorage|sessionStorage)\.(?:setItem|getItem|removeItem)\(\s*["']([^"']+)["']"#, source)
            + captures(#"HTMLAppNative\.appStorage\.(?:get|set|remove)\(\s*["']([^"']+)["']"#, source)
        let collections = captures(#"HTMLAppNative\.db\.(?:put|get|query|delete|search|count)\(\s*["']([^"']+)["']"#, source)
        let methods = captures(#"\bHTMLAppNative\.([A-Za-z][A-Za-z0-9]*\.[A-Za-z][A-Za-z0-9]*)\s*\("#, source)
        var acceptance = [
            "Primary screens and navigation remain usable",
            "Page never horizontally scrolls except intentional marked components",
            "Page does not pinch/double-tap zoom; readable text still reflows",
            "Existing saved records must survive edits"
        ]
        if !appKeys.isEmpty || !collections.isEmpty {
            acceptance.append("Stored data survives a relaunch and a schema change uses a migration")
        }
        if !methods.isEmpty {
            acceptance.append("Native APIs are feature-detected and handle denial, cancellation and unsupported devices")
        }
        return ForgeSemanticAppModel(
            purpose: String(purpose.prefix(360)),
            components: unique(ids + semantic, limit: 100),
            storageKeys: unique(appKeys, limit: 50),
            databaseCollections: unique(collections, limit: 30),
            nativeMethods: unique(methods, limit: 90),
            acceptance: acceptance
        )
    }

    private static func captures(_ pattern: String, _ source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).prefix(150).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: source) else { return nil }
            let value = String(source[captured])
            return value.count <= 120 ? value : nil
        }
    }

    private static func unique(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values.filter { seen.insert($0).inserted }.prefix(limit))
    }

    var summary: String {
        """
        Purpose: \(purpose)
        Semantic components/DOM IDs: \(components.prefix(35).joined(separator: ", "))
        Durable storage keys (preserve exactly): \(storageKeys.joined(separator: ", "))
        Database collections (preserve exactly): \(databaseCollections.joined(separator: ", "))
        Existing native integrations: \(nativeMethods.joined(separator: ", "))
        Previous semantic edits: \(recentEdits.suffix(6).joined(separator: " | "))
        """
    }
}

enum ForgeSemanticAppModelStore {
    private static func url(for appID: String) -> URL? {
        let safe = appID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        guard !safe.isEmpty,
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("ForgeSemanticModels", isDirectory: true)
            .appendingPathComponent(safe + ".json")
    }

    static func load(for appID: String) -> ForgeSemanticAppModel? {
        guard let path = url(for: appID),
              let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(ForgeSemanticAppModel.self, from: data)
    }

    static func save(for appID: String, html: String, purpose: String, editNote: String = "") {
        guard let path = url(for: appID) else { return }
        var model = ForgeSemanticAppModel.build(html: html, purpose: purpose)
        let previous = load(for: appID)?.recentEdits ?? []
        let note = editNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = previous + (note.isEmpty ? [] : [String(note.prefix(220))])
        model.recentEdits = Array(history.suffix(12))
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(model).write(to: path, options: .atomic)
        } catch {
            // The model is advisory metadata; never block a user data save.
        }
    }
}

enum ForgeEditScope: String {
    case appearance
    case component
    case behavior
    case dataModel
    case nativeCapability
    case architecture
    case bugFix
    case performance
}

struct ForgeEditContract {
    let literalRequest: String
    let intent: String
    let scope: ForgeEditScope
    let goals: [String]
    let nonGoals: [String]
    let targets: [String]
    let recommendedCapabilities: [String]
    let acceptance: [String]
    let model: ForgeSemanticAppModel
    let taste: String

    static func make(request: String, model: ForgeSemanticAppModel, taste: String) -> ForgeEditContract {
        let lower = request.lowercased()
        func has(_ terms: [String]) -> Bool { terms.contains { lower.contains($0) } }
        var goals: [String] = []
        var capabilities: [String] = []
        var intent = "Implement only the requested change, choosing reversible ordinary product expectations."
        var scope: ForgeEditScope = .component

        if has(["clean", "simple", "minimal", "tidy", "declutter", "less busy"]) {
            scope = .appearance
            intent = "Improve visual hierarchy and reduce unnecessary UI noise without removing existing features."
            goals += ["Use consistent spacing, clearer priorities and fewer competing surfaces", "Move secondary options into accessible secondary UI"]
        } else if has(["apple-like", "apple like", "more native", "ios-like", "ios style"]) {
            scope = .appearance
            intent = "Make the existing app feel more like a native iOS application."
            goals += ["Respect safe areas, system-inspired type, meaningful sheets and touch feedback", "Use native tabs where documented and appropriate; preserve route IDs"]
        } else if has(["modern", "premium", "polish", "prettier"]) {
            scope = .appearance
            intent = "Polish the current visual identity without changing business logic."
            goals += ["Improve type hierarchy, color contrast, motion, spacing and interaction states"]
        }
        if has(["faster", "laggy", "slow", "performance"]) {
            scope = .performance
            goals += ["Avoid unnecessary rerenders and timers", "Keep existing behavior and measure impact"]
        }
        if has(["fix", "broken", "crash", "doesn't work", "bug"]) {
            scope = .bugFix
            goals += ["Identify the failing execution path", "Preserve unrelated behavior and add regression coverage"]
        }
        if has(["remind", "notification", "alert me later"]) {
            scope = .nativeCapability
            capabilities += ["notifications.schedule", "notifications.cancel"]
            goals += ["Use documented native scheduled notifications, not setTimeout as background scheduling", "Handle permission denial and cancellation"]
        }
        if has(["home screen", "widget"]) {
            scope = .nativeCapability
            capabilities += ["widgets.configure", "widgets.reload"]
        }
        if has(["bluetooth", "ble", "gatt"]) {
            scope = .nativeCapability
            capabilities += ["bluetooth.scan", "bluetooth.gattRead"]
        }
        if has(["database", "storage schema", "data model", "migrate"]) {
            scope = .dataModel
            goals += ["Provide a backward-compatible migration and preserve existing records"]
        }
        if has(["redo entire app", "rebuild from scratch", "change architecture"]) {
            scope = .architecture
        }
        if goals.isEmpty { goals = ["Make the requested behavior work end-to-end", "Keep loading, empty, error, offline and permission states honest"] }
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        let targets = model.components.filter { id in
            let normalized = id.replacingOccurrences(of: #"([a-z0-9])([A-Z])"#,
                                                      with: "$1 $2", options: .regularExpression)
                .lowercased()
            let parts = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            return parts.contains { words.contains($0) }
        }
        let nonGoals = [
            "Do not remove or rename existing storage keys, collections, component IDs, routes or permissions without an explicit migration",
            "Do not redesign unrelated screens or replace the whole HTML file for a local change",
            "Do not invent native APIs, network endpoints, entitlements, or simulated successful results",
            "Do not introduce page-level horizontal scrolling, pinch zoom or input-focus zoom"
        ]
        return ForgeEditContract(literalRequest: request,
                                 intent: intent, scope: scope, goals: goals,
                                 nonGoals: nonGoals, targets: Array(targets.prefix(5)),
                                 recommendedCapabilities: capabilities,
                                 acceptance: model.acceptance, model: model, taste: taste)
    }

    var implementationBrief: String {
        """
        AUTHORITATIVE USER REQUEST: \(literalRequest)
        INTERPRETED INTENT (reversible, not permission to remove features): \(intent)
        EDIT SCOPE: \(scope.rawValue)
        TARGET COMPONENTS (when confidently matched): \(targets.joined(separator: ", "))
        GOALS:
        \(goals.map { "- " + $0 }.joined(separator: "\n"))
        NON-GOALS / INVARIANTS:
        \(nonGoals.map { "- " + $0 }.joined(separator: "\n"))
        EXISTING APP STRUCTURE:
        \(model.summary)
        DOCUMENTED CAPABILITY CANDIDATES (verify catalog and runtime):
        \(recommendedCapabilities.joined(separator: ", "))
        RETAINED ACCEPTANCE:
        \(acceptance.map { "- " + $0 }.joined(separator: "\n"))
        PROJECT STYLE PREFERENCES (only when opted in):
        \(taste)
        Apply the smallest safe patch. If schema changes are essential, implement migrations. Test new and existing workflows.
        """
    }
}
