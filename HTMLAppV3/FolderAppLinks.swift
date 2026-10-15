import Foundation

/// Lightweight folder placements that point at one canonical SavedHTMLApp record.
/// A copied folder never duplicates HTML, icons, permissions, downloaded website data, or caches.
struct LibraryAppLink: Codable, Hashable, Identifiable {
    var id: String
    var appID: String
    var folderID: String?
}

@MainActor
final class FolderAppLinkStore {
    static let shared = FolderAppLinkStore()

    private let defaultsKey = "htmlapp.libraryAppLinks.v1"
    private var links: [LibraryAppLink] = []

    private init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LibraryAppLink].self, from: data) else { return }
        links = decoded
    }

    func appIDs(in folderID: String?) -> Set<String> {
        Set(links.lazy.filter { $0.folderID == folderID }.map(\.appID))
    }

    func snapshot(appIDs: Set<String>? = nil) -> [LibraryAppLink] {
        guard let appIDs else { return links }
        return links.filter { appIDs.contains($0.appID) }
    }

    func replaceAll(with imported: [LibraryAppLink], canonicalApps: [SavedHTMLApp], folders: [LibraryFolder]) {
        let validApps = Set(canonicalApps.map(\.id))
        let validFolders = Set(folders.map(\.id))
        links = imported.filter {
            validApps.contains($0.appID) && ($0.folderID.map { validFolders.contains($0) } ?? true)
        }
        var seen: Set<String> = []
        links = links.filter {
            seen.insert($0.appID + "\u{1F}" + ($0.folderID ?? "<root>")).inserted
        }
        persist()
    }

    func appendImported(
        _ imported: [LibraryAppLink],
        appIDMap: [String: String],
        folderIDMap: [String: String],
        canonicalApps: [SavedHTMLApp]
    ) {
        for link in imported {
            guard let newAppID = appIDMap[link.appID] else { continue }
            let newFolderID = link.folderID.flatMap { folderIDMap[$0] }
            add(appID: newAppID, folderID: newFolderID, canonicalApps: canonicalApps)
        }
    }

    func contains(appID: String, folderID: String?) -> Bool {
        links.contains { $0.appID == appID && $0.folderID == folderID }
    }

    func add(appID: String, folderID: String?, canonicalApps: [SavedHTMLApp]) {
        guard canonicalApps.contains(where: { $0.id == appID }) else { return }
        if canonicalApps.contains(where: { $0.id == appID && $0.folderID == folderID }) { return }
        guard !contains(appID: appID, folderID: folderID) else { return }
        links.append(LibraryAppLink(id: UUID().uuidString, appID: appID, folderID: folderID))
        persist()
    }

    func remove(appID: String, folderID: String?) {
        let oldCount = links.count
        links.removeAll { $0.appID == appID && $0.folderID == folderID }
        if links.count != oldCount { persist() }
    }

    func removeAll(appID: String) {
        let oldCount = links.count
        links.removeAll { $0.appID == appID }
        if links.count != oldCount { persist() }
    }

    func moveAlias(appID: String, from sourceFolderID: String?, to destinationFolderID: String?, canonicalApps: [SavedHTMLApp]) {
        guard canonicalApps.contains(where: { $0.id == appID }) else { return }
        guard let index = links.firstIndex(where: { $0.appID == appID && $0.folderID == sourceFolderID }) else {
            add(appID: appID, folderID: destinationFolderID, canonicalApps: canonicalApps)
            return
        }

        if canonicalApps.contains(where: { $0.id == appID && $0.folderID == destinationFolderID }) ||
            links.contains(where: { $0.appID == appID && $0.folderID == destinationFolderID }) {
            links.remove(at: index)
        } else {
            links[index].folderID = destinationFolderID
        }
        persist()
    }

    func moveAliases(from sourceFolderID: String, to destinationFolderID: String?, canonicalApps: [SavedHTMLApp]) {
        let movingAppIDs = Set(links.filter { $0.folderID == sourceFolderID }.map(\.appID))
        guard !movingAppIDs.isEmpty else { return }
        links.removeAll { $0.folderID == sourceFolderID }

        for appID in movingAppIDs {
            let alreadyCanonical = canonicalApps.contains { $0.id == appID && $0.folderID == destinationFolderID }
            let alreadyLinked = links.contains { $0.appID == appID && $0.folderID == destinationFolderID }
            if !alreadyCanonical && !alreadyLinked {
                links.append(LibraryAppLink(id: UUID().uuidString, appID: appID, folderID: destinationFolderID))
            }
        }
        persist()
    }

    /// Copies only placement references into the cloned folder tree.
    /// The canonical SavedHTMLApp and every app-owned file remain shared.
    func copyPlacements(folderIDMapping: [String: String], canonicalApps: [SavedHTMLApp]) {
        guard !folderIDMapping.isEmpty else { return }
        let originalLinks = links
        var additions: [(String, String)] = []

        for app in canonicalApps {
            guard let sourceFolderID = app.folderID,
                  let targetFolderID = folderIDMapping[sourceFolderID] else { continue }
            additions.append((app.id, targetFolderID))
        }

        for link in originalLinks {
            guard let sourceFolderID = link.folderID,
                  let targetFolderID = folderIDMapping[sourceFolderID] else { continue }
            additions.append((link.appID, targetFolderID))
        }

        var changed = false
        for (appID, folderID) in additions {
            guard canonicalApps.contains(where: { $0.id == appID }) else { continue }
            let alreadyCanonical = canonicalApps.contains { $0.id == appID && $0.folderID == folderID }
            let alreadyLinked = links.contains { $0.appID == appID && $0.folderID == folderID }
            guard !alreadyCanonical && !alreadyLinked else { continue }
            links.append(LibraryAppLink(id: UUID().uuidString, appID: appID, folderID: folderID))
            changed = true
        }
        if changed { persist() }
    }

    func prune(validAppIDs: Set<String>, validFolderIDs: Set<String>) {
        let oldCount = links.count
        links.removeAll { link in
            !validAppIDs.contains(link.appID) || (link.folderID.map { !validFolderIDs.contains($0) } ?? false)
        }

        var seen: Set<String> = []
        links = links.filter { link in
            let key = link.appID + "\u{1F}" + (link.folderID ?? "<root>")
            return seen.insert(key).inserted
        }
        if links.count != oldCount { persist() }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            UserDefaults.standard.set(try encoder.encode(links), forKey: defaultsKey)
        } catch {
            // The canonical app library remains intact even if a lightweight folder reference cannot be saved.
        }
    }
}
