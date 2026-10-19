import Foundation

// Reads declared XML entitlements, not effective sandbox privileges. Container access
// and the extension receipt remain the authoritative runtime tests.
enum HTMLAppSigningGroups {
    static func groups(in bundle: Bundle) -> [String] {
        guard let url = bundle.executableURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return groups(in: data)
    }
    static func groups(in data: Data) -> [String] {
        func word(_ offset: Int, big: Bool = false) -> Int? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let bytes = Array(data[offset..<offset + 4])
            return (big ? bytes : Array(bytes.reversed())).reduce(0) { ($0 << 8) | Int($1) }
        }
        guard word(0) == 0xfeedfacf, let count = word(16), count < 4096,
              let commandsSize = word(20), commandsSize <= data.count - 32 else { return [] }
        var offset = 32
        for _ in 0..<count {
            guard let command = word(offset), let size = word(offset + 4), size >= 8,
                  offset + size <= 32 + commandsSize else { return [] }
            if command == 0x1d {
                guard size >= 16, let start = word(offset + 8), let length = word(offset + 12),
                      start <= data.count, length >= 12, length <= data.count - start,
                      word(start, big: true) == 0xfade0cc0,
                      let total = word(start + 4, big: true), total <= length, total >= 12,
                      let entries = word(start + 8, big: true), entries <= (total - 12) / 8 else { return [] }
                for i in 0..<entries {
                    let index = start + 12 + i * 8
                    guard word(index, big: true) == 5 else { continue }
                    guard let relative = word(index + 4, big: true), relative >= 12 + entries * 8,
                          relative <= total - 8 else { return [] }
                    let blob = start + relative
                    guard word(blob, big: true) == 0xfade7171,
                          let blobSize = word(blob + 4, big: true), blobSize >= 8,
                          blobSize <= total - relative,
                          let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: blob + 8..<blob + blobSize), format: nil) as? [String: Any],
                          let groups = plist["com.apple.security.application-groups"] as? [String] else { return [] }
                    return Array(Set(groups.filter { $0.hasPrefix("group.") && $0.count < 256 })).sorted()
                }
            }
            offset += size
        }
        return [] // DER-only or unknown architectures fail closed.
    }
    static let declared = groups(in: Bundle.main)
    static var common: [String] {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let extensionBundle = Bundle(url: plugins.appendingPathComponent("HTMLAppWidgets.appex")) else { return [] }
        return Array(Set(declared).intersection(groups(in: extensionBundle))).sorted()
    }
}

enum HTMLAppProviderStorage {
    struct Selection: Codable {
        let version: Int
        let group: String
        let date: Date
    }
    static let namespace = "HTMLApp-Widget-Storage-v1"
    static func directory(group: String) -> URL? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return group == HTMLAppSharedContainer.originalGroupID ? root : root.appendingPathComponent(namespace, isDirectory: true)
    }
    static func selected(from selections: [Selection], allowed: [String]) -> String? {
        selections.filter { $0.version == 1 && allowed.contains($0.group) }
            .sorted { $0.date == $1.date ? $0.group < $1.group : $0.date > $1.date }.first?.group
    }
    static var selectedGroup: String {
        let groups = Array(Set(HTMLAppSigningGroups.declared + [HTMLAppSharedContainer.originalGroupID]))
        let markers = groups.compactMap { group -> Selection? in
            guard let root = directory(group: group),
                  let data = try? Data(contentsOf: root.appendingPathComponent("htmlapp-active-group.json")),
                  let selection = try? JSONDecoder().decode(Selection.self, from: data), selection.group == group else { return nil }
            return selection
        }
        return selected(from: markers, allowed: groups) ?? HTMLAppSharedContainer.originalGroupID
    }
    static var originalAvailable: Bool {
        guard directory(group: HTMLAppSharedContainer.originalGroupID) != nil else { return false }
        return HTMLAppSigningGroups.common.contains(HTMLAppSharedContainer.originalGroupID)
    }
    // A signer's profile may authorize a provider-specific group but not our original
    // group. Re-signing or Swift cannot grant that entitlement. Offer an explicit,
    // user-approved compatible group rather than selecting an unusable container.
    static var compatibleGroups: [String] {
        HTMLAppSigningGroups.common.filter {
            $0 != HTMLAppSharedContainer.originalGroupID && directory(group: $0) != nil
        }
    }
    static var recommendedCompatibleGroup: String? {
        let candidates = compatibleGroups
        return candidates.contains(selectedGroup) ? selectedGroup : candidates.first
    }

    static func activate(_ group: String) throws {
        guard HTMLAppSigningGroups.common.contains(group),
              let directory = directory(group: group) else {
            throw HTMLAppWidgetStoreError(code: "group_not_authorized", message: "This group must be present in both signed binaries and accessible to the app. Ask the signer for matching app and extension profiles.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("htmlapp-active-group.json")
        let data = try JSONEncoder().encode(Selection(version: 1, group: group, date: Date()))
        try data.write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try Data(contentsOf: marker) == data, selectedGroup == group else {
            throw HTMLAppWidgetStoreError(code: "group_selection_failed", message: "The group selection could not be verified. Check the device date and signing configuration.")
        }
        // No saved apps or old snapshots are copied into a provider's shared group.
    }
}
