import SwiftUI
import UIKit

@main
struct HTMLAppMain: App {
    @StateObject private var store = AppStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    init() {
        HTMLNotificationCenterDelegate.shared.activate()
        HTMLAppBackgroundCoordinator.shared.register()
        HTMLAppBackgroundCoordinator.shared.schedule()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .fullScreenCover(item: $store.runningApp) { app in
                    WebRunner(app: app)
                        .environmentObject(store)
                        .ignoresSafeArea()
                        .interactiveDismissDisabled(true)
                        .overlay(alignment: .top) {
                            if store.pendingWebsiteUpdate?.id == app.id {
                                WebsiteUpdateBanner(app: app)
                                    .environmentObject(store)
                                    .padding(.top, 12)
                            }
                        }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !onboardingComplete },
                    set: { if !$0 { onboardingComplete = true } }
                )) {
                    OnboardingView(complete: $onboardingComplete)
                        .interactiveDismissDisabled(true)
                }
                .confirmationDialog(
                    "Switch HTML app?",
                    isPresented: Binding(
                        get: { store.pendingSwitchApp != nil },
                        set: { if !$0 { store.pendingSwitchApp = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Switch App") { store.confirmPendingSwitch() }
                    Button("Keep Current App", role: .cancel) { store.pendingSwitchApp = nil }
                } message: {
                    Text("The current HTML app will be unloaded before the linked app opens.")
                }
                .onOpenURL(perform: store.openDeepLink)
                .onReceive(NotificationCenter.default.publisher(for: .htmlAppNotificationOpened)) { notification in
                    if let url = notification.object as? URL {
                        store.openDeepLink(url)
                    }
                }
        }
    }
}

struct WebsiteUpdateBanner: View {
    @EnvironmentObject private var store: AppStore
    let app: SavedHTMLApp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Website Update Ready")
                .font(.headline)
            Text("A newer downloaded copy of \(app.name) is ready.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Next Launch") { store.keepPendingWebsiteUpdateForNextLaunch() }
                    .buttonStyle(.bordered)
                Button("Update Now") { store.applyPendingWebsiteUpdate(app, relaunch: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 8)
        .padding(.horizontal, 16)
    }
}

struct SavedHTMLApp: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var summary: String
    var html: String
    var favicon: Data?
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isFavorite: Bool?
    var folderName: String? // Legacy flat-folder field; migrated into folderID.
    var folderID: String?   // One primary placement. Additional placements are lightweight LibraryAppLink references.
    var websiteSourceURL: String?
    var websiteFingerprint: String?
}

struct LibraryFolder: Identifiable, Codable, Hashable {
    static let defaultTintHex = "#5B9DFF"

    var id: String
    var name: String
    var parentID: String?
    var tintHex: String
    var createdAt: Date
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var apps: [SavedHTMLApp] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published var runningApp: SavedHTMLApp?
    @Published var pendingSwitchApp: SavedHTMLApp?
    @Published var pendingWebsiteUpdate: SavedHTMLApp?
    @Published var errorMessage: String?
    @Published var notice: String?

    private let libraryURL: URL
    private let folderRecordsDefaultsKey = "htmlapp.libraryFolderRecords.v2"
    private let legacyFolderDefaultsKey = "htmlapp.libraryFolders"
    private var pendingInsertionFolderID: String?

    var orderedApps: [SavedHTMLApp] {
        apps.filter { $0.isFavorite == true } + apps.filter { $0.isFavorite != true }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        libraryURL = base.appendingPathComponent("library.json")
        load()
        loadFoldersAndMigrate()
        FolderAppLinkStore.shared.prune(
            validAppIDs: Set(apps.map(\.id)),
            validFolderIDs: Set(folders.map(\.id))
        )
    }

    func prepareNewItemDestination(_ folderID: String?) {
        if let folderID, folders.contains(where: { $0.id == folderID }) {
            pendingInsertionFolderID = folderID
        } else {
            pendingInsertionFolderID = nil
        }
    }

    func add(html: String, summary: String) async {
        let name = HTMLTools.title(in: html) ?? "Untitled App"
        let icon = await HTMLAppIconTools.savedIcon(html: html, name: name)
        let now = Date()
        let destination = validPendingInsertionFolderID()
        let app = SavedHTMLApp(
            id: makeID(), name: name,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html, favicon: icon,
            createdAt: now, updatedAt: now, lastOpenedAt: nil,
            isFavorite: false, folderName: nil, folderID: destination,
            websiteSourceURL: nil, websiteFingerprint: nil
        )
        pendingInsertionFolderID = nil
        apps.insert(app, at: 0)
        save()
        await SourceCache.shared.refresh(app: app, force: false)
    }

    func addTransferredApp(_ incoming: SavedHTMLApp, portableData: [String: String]? = nil) async {
        if let source = incoming.websiteSourceURL,
           !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (try? await addWebsite(urlString: source)) != nil {
            if let imported = apps.first {
                if let index = apps.firstIndex(where: { $0.id == imported.id }) {
                    apps[index].summary = incoming.summary
                    apps[index].isFavorite = incoming.isFavorite
                    if let favicon = incoming.favicon { apps[index].favicon = favicon }
                    save()
                    if let portableData { HTMLAppPortableDataStore.replace(appID: apps[index].id, values: portableData) }
                }
            }
            notice = "Received \(incoming.name) and refreshed its saved website."
            return
        }

        let now = Date()
        let id = makeID()
        let destination = validPendingInsertionFolderID()
        let icon: Data?
        if let incomingIcon = incoming.favicon {
            icon = incomingIcon
        } else {
            icon = await HTMLAppIconTools.savedIcon(html: incoming.html, name: incoming.name)
        }
        let app = SavedHTMLApp(
            id: id,
            name: incoming.name,
            summary: incoming.summary,
            html: incoming.html,
            favicon: icon,
            createdAt: incoming.createdAt,
            updatedAt: max(incoming.updatedAt, now),
            lastOpenedAt: nil,
            isFavorite: incoming.isFavorite,
            folderName: nil,
            folderID: destination,
            websiteSourceURL: nil,
            websiteFingerprint: nil
        )
        pendingInsertionFolderID = nil
        apps.insert(app, at: 0)
        if let portableData {
            HTMLAppPortableDataStore.replace(appID: id, values: portableData)
        }
        save()
        await SourceCache.shared.refresh(app: app, force: false)
        notice = "Received \(app.name)."
    }

    func addWebsite(urlString: String) async throws {
        guard let url = WebsiteArchiveManager.shared.normalizedURL(urlString) else { throw WebsiteArchiveError.invalidURL }
        let id = makeID()
        let snapshot = try await WebsiteArchiveManager.shared.download(url: url, appID: id)
        try WebsiteArchiveManager.shared.installInitial(snapshot, appID: id)
        let name = HTMLTools.title(in: snapshot.html) ?? url.host ?? "Downloaded Website"
        let icon = await HTMLAppIconTools.savedIcon(html: snapshot.html, name: name)
        let now = Date()
        let destination = validPendingInsertionFolderID()
        let app = SavedHTMLApp(
            id: id,
            name: name,
            summary: "Downloaded from \(url.host ?? url.absoluteString)",
            html: snapshot.html,
            favicon: icon,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: nil,
            isFavorite: false,
            folderName: nil,
            folderID: destination,
            websiteSourceURL: url.absoluteString,
            websiteFingerprint: snapshot.fingerprint
        )
        pendingInsertionFolderID = nil
        apps.insert(app, at: 0)
        save()
        notice = "Downloaded \(name)."
    }

    func update(_ app: SavedHTMLApp, html: String, summary: String) async {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        let name = HTMLTools.title(in: html) ?? app.name
        apps[index].name = name
        apps[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[index].html = html
        apps[index].favicon = await HTMLAppIconTools.savedIcon(html: html, name: name)
        apps[index].updatedAt = Date()
        save()
        await SourceCache.shared.refresh(app: apps[index], force: false)
    }

    func updateWebsiteSource(_ app: SavedHTMLApp, urlString: String) async throws {
        guard let url = WebsiteArchiveManager.shared.normalizedURL(urlString) else { throw WebsiteArchiveError.invalidURL }
        let snapshot = try await WebsiteArchiveManager.shared.download(url: url, appID: app.id)
        try WebsiteArchiveManager.shared.installInitial(snapshot, appID: app.id)
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        let name = HTMLTools.title(in: snapshot.html) ?? url.host ?? app.name
        apps[index].name = name
        apps[index].html = snapshot.html
        apps[index].websiteSourceURL = url.absoluteString
        apps[index].websiteFingerprint = snapshot.fingerprint
        apps[index].favicon = await HTMLAppIconTools.savedIcon(html: snapshot.html, name: name)
        apps[index].updatedAt = Date()
        save()
        notice = "Website source updated."
    }

    func rebuildIcons() async {
        for index in apps.indices {
            apps[index].favicon = await HTMLAppIconTools.savedIcon(html: apps[index].html, name: apps[index].name)
        }
        save()
        notice = "All saved icons were rebuilt."
    }

    func setGeneratedIcon(_ data: Data, for app: SavedHTMLApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].favicon = data
        apps[index].updatedAt = Date()
        save()
        notice = "Updated icon for \(apps[index].name)."
    }

    func launch(_ app: SavedHTMLApp) {
        guard var index = apps.firstIndex(where: { $0.id == app.id }) else { return }

        if apps[index].websiteSourceURL != nil,
           let pending = try? WebsiteArchiveManager.shared.activatePending(appID: app.id) {
            apps[index].html = pending.html
            apps[index].websiteFingerprint = pending.fingerprint
            apps[index].websiteSourceURL = pending.sourceURL
            apps[index].name = HTMLTools.title(in: pending.html) ?? apps[index].name
            apps[index].updatedAt = Date()
            save()
            index = apps.firstIndex(where: { $0.id == app.id }) ?? index
        }

        apps[index].lastOpenedAt = Date()
        save()
        runningApp = apps[index]

        if apps[index].websiteSourceURL != nil {
            let appID = apps[index].id
            Task { await refreshWebsiteInBackground(appID: appID) }
        }
    }

    func applyPendingWebsiteUpdate(_ app: SavedHTMLApp, relaunch: Bool) {
        guard let pending = try? WebsiteArchiveManager.shared.activatePending(appID: app.id),
              let index = apps.firstIndex(where: { $0.id == app.id }) else {
            pendingWebsiteUpdate = nil
            return
        }
        apps[index].html = pending.html
        apps[index].websiteFingerprint = pending.fingerprint
        apps[index].websiteSourceURL = pending.sourceURL
        apps[index].name = HTMLTools.title(in: pending.html) ?? apps[index].name
        apps[index].updatedAt = Date()
        save()
        let updated = apps[index]
        pendingWebsiteUpdate = nil
        Task {
            if let freshIcon = await HTMLAppIconTools.savedIcon(html: updated.html, name: updated.name),
               let newIndex = apps.firstIndex(where: { $0.id == updated.id }) {
                apps[newIndex].favicon = freshIcon
                save()
            }
        }
        if relaunch, runningApp?.id == updated.id {
            runningApp = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self,
                      let latest = self.apps.first(where: { $0.id == updated.id }) else { return }
                self.runningApp = latest
            }
        }
    }

    func keepPendingWebsiteUpdateForNextLaunch() {
        pendingWebsiteUpdate = nil
        notice = "The downloaded website will update on its next launch."
    }

    func toggleFavorite(_ app: SavedHTMLApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].isFavorite = !(apps[index].isFavorite == true)
        save()
        notice = apps[index].isFavorite == true ? "Pinned \(apps[index].name) to the top." : "Removed \(apps[index].name) from favorites."
    }

    func folder(withID id: String?) -> LibraryFolder? {
        guard let id else { return nil }
        return folders.first(where: { $0.id == id })
    }

    func childFolders(of parentID: String?) -> [LibraryFolder] {
        folders
            .filter { $0.parentID == parentID }
            .sorted { left, right in
                left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    /// Returns canonical app records for this folder. Extra folder appearances are only lightweight links.
    func apps(in folderID: String?) -> [SavedHTMLApp] {
        let linkedIDs = FolderAppLinkStore.shared.appIDs(in: folderID)
        return orderedApps.filter { $0.folderID == folderID || linkedIDs.contains($0.id) }
    }

    func directAppCount(in folderID: String?) -> Int {
        apps(in: folderID).count
    }

    func descendantAppCount(in folderID: String) -> Int {
        let folderIDs = subtreeFolderIDs(startingAt: folderID)
        var appIDs: Set<String> = []
        for id in folderIDs {
            appIDs.formUnion(apps(in: id).map(\.id))
        }
        return appIDs.count
    }

    func subtreeFolderIDs(startingAt folderID: String) -> Set<String> {
        guard folders.contains(where: { $0.id == folderID }) else { return [] }
        var result: Set<String> = [folderID]
        var frontier = [folderID]
        while let current = frontier.popLast() {
            let children = folders.filter { $0.parentID == current }.map(\.id)
            for child in children where !result.contains(child) {
                result.insert(child)
                frontier.append(child)
            }
        }
        return result
    }

    @discardableResult
    func createFolder(_ rawName: String, parentID: String? = nil) -> LibraryFolder? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard parentID == nil || folders.contains(where: { $0.id == parentID }) else {
            errorMessage = "The destination folder no longer exists."
            return nil
        }
        guard !siblingNameExists(name, parentID: parentID) else {
            errorMessage = "A folder named \(name) already exists here."
            return nil
        }
        let folder = LibraryFolder(
            id: UUID().uuidString,
            name: name,
            parentID: parentID,
            tintHex: LibraryFolder.defaultTintHex,
            createdAt: Date()
        )
        folders.append(folder)
        persistFolders()
        return folder
    }

    func renameFolder(_ folder: LibraryFolder, to rawName: String) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !siblingNameExists(name, parentID: folders[index].parentID, excludingID: folder.id) else {
            errorMessage = "A folder named \(name) already exists here."
            return
        }
        folders[index].name = name
        persistFolders()
    }

    func setFolderTint(_ folder: LibraryFolder, hex: String) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].tintHex = hex
        persistFolders()
    }

    func moveFolder(_ folder: LibraryFolder, toParent destinationID: String?) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        guard destinationID == nil || folders.contains(where: { $0.id == destinationID }) else {
            errorMessage = "The destination folder no longer exists."
            return
        }
        let blocked = subtreeFolderIDs(startingAt: folder.id)
        if let destinationID, blocked.contains(destinationID) {
            errorMessage = "A folder cannot be moved inside itself."
            return
        }
        folders[index].name = uniqueFolderName(folders[index].name, parentID: destinationID, excludingID: folder.id)
        folders[index].parentID = destinationID
        persistFolders()
        notice = "Moved \(folders[index].name)."
    }

    /// Duplicates only the folder structure and app references. App-owned storage is never copied.
    func copyFolder(_ folder: LibraryFolder, toParent destinationID: String?) {
        guard folders.contains(where: { $0.id == folder.id }) else { return }
        guard destinationID == nil || folders.contains(where: { $0.id == destinationID }) else {
            errorMessage = "The destination folder no longer exists."
            return
        }
        let sourceIDs = subtreeFolderIDs(startingAt: folder.id)
        if let destinationID, sourceIDs.contains(destinationID) {
            errorMessage = "A folder cannot be copied inside itself."
            return
        }

        let originalFolders = folders
        var mapping: [String: String] = [:]

        func cloneFolderTree(sourceID: String, newParentID: String?, isRoot: Bool) {
            guard let source = originalFolders.first(where: { $0.id == sourceID }) else { return }
            let desiredName = isRoot ? source.name + " Copy" : source.name
            let copied = LibraryFolder(
                id: UUID().uuidString,
                name: uniqueFolderName(desiredName, parentID: newParentID),
                parentID: newParentID,
                tintHex: source.tintHex,
                createdAt: Date()
            )
            folders.append(copied)
            mapping[source.id] = copied.id

            for child in originalFolders
                .filter({ $0.parentID == source.id })
                .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                cloneFolderTree(sourceID: child.id, newParentID: copied.id, isRoot: false)
            }
        }

        cloneFolderTree(sourceID: folder.id, newParentID: destinationID, isRoot: true)
        FolderAppLinkStore.shared.copyPlacements(folderIDMapping: mapping, canonicalApps: apps)
        persistFolders()
        notice = "Copied \(folder.name) using shared app links."
    }

    func deleteFolder(_ folder: LibraryFolder) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        let parentID = folders[folderIndex].parentID

        let childIDs = folders.filter { $0.parentID == folder.id }.map(\.id)
        for childID in childIDs {
            guard let index = folders.firstIndex(where: { $0.id == childID }) else { continue }
            folders[index].name = uniqueFolderName(
                folders[index].name,
                parentID: parentID,
                excludingID: folders[index].id
            )
            folders[index].parentID = parentID
        }

        FolderAppLinkStore.shared.moveAliases(from: folder.id, to: parentID, canonicalApps: apps)
        for index in apps.indices where apps[index].folderID == folder.id {
            apps[index].folderID = parentID
            apps[index].folderName = nil
        }

        folders.removeAll { $0.id == folder.id }
        persistFolders()
        save()
        notice = "Deleted \(folder.name). Its contents were moved up one level."
    }

    /// Moves only the appearance of an app from the folder the user is looking at.
    /// If that appearance is a copied link, the canonical app and all other appearances stay untouched.
    func movePlacement(_ app: SavedHTMLApp, fromFolderID sourceFolderID: String?, toFolderID destinationFolderID: String?) {
        guard destinationFolderID == nil || folders.contains(where: { $0.id == destinationFolderID }) else {
            errorMessage = "The destination folder no longer exists."
            return
        }
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }

        if apps[index].folderID == sourceFolderID {
            FolderAppLinkStore.shared.remove(appID: app.id, folderID: destinationFolderID)
            apps[index].folderID = destinationFolderID
            apps[index].folderName = nil
            save()
        } else {
            FolderAppLinkStore.shared.moveAlias(
                appID: app.id,
                from: sourceFolderID,
                to: destinationFolderID,
                canonicalApps: apps
            )
        }

        notice = destinationFolderID.flatMap { folder(withID: $0)?.name }.map {
            "Moved \(apps[index].name) to \($0)."
        } ?? "Moved \(apps[index].name) to the library."
    }

    /// Compatibility path for callers that move the app's primary placement.
    func move(_ app: SavedHTMLApp, toFolderID folderID: String?) {
        movePlacement(app, fromFolderID: app.folderID, toFolderID: folderID)
    }

    func delete(_ app: SavedHTMLApp) {
        FolderAppLinkStore.shared.removeAll(appID: app.id)
        apps.removeAll { $0.id == app.id }
        save()
        SourceCache.shared.remove(appID: app.id)
        WebsiteArchiveManager.shared.remove(appID: app.id)
        HTMLPermissionStore.reset(appID: app.id)
        HTMLSensorPermissionPolicy.reset(appID: app.id)
        HTMLAppPortableDataStore.clear(appID: app.id)
        HTMLAppWidgetStore.remove(appID: app.id)
        HTMLAppBackgroundJobStore.remove(appID: app.id)
        HTMLAppBackgroundCoordinator.shared.schedule()
    }

    func exportHTML(_ app: SavedHTMLApp) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(OpticalTransferCodec.safeFileName(app.name))
        do {
            try Data(app.html.utf8).write(to: url, options: .atomic)
            SharePresenter.present(items: [url])
        } catch {
            errorMessage = "The HTML file could not be exported."
        }
    }

    func exportPortablePackage(appIDs requestedIDs: Set<String>? = nil) {
        let selected = requestedIDs.map { ids in apps.filter { ids.contains($0.id) } } ?? apps
        guard !selected.isEmpty else {
            errorMessage = "Choose at least one HTMLApp to export."
            return
        }

        let selectedIDs = Set(selected.map(\.id))
        let links = FolderAppLinkStore.shared.snapshot(appIDs: selectedIDs)
        let folders = foldersForPortableExport(apps: selected, links: links)

        do {
            let url = try HTMLAppPackageTransfer.createArchive(
                apps: selected,
                folders: folders,
                links: links
            )
            SharePresenter.present(items: [url])
            notice = selected.count == apps.count
                ? "HTMLApp backup ready to share."
                : "Portable package ready for \(selected.count) app\(selected.count == 1 ? "" : "s")."
        } catch {
            errorMessage = "The HTMLApp package could not be created: \(error.localizedDescription)"
        }
    }

    func importPortablePackage(from url: URL, replaceExisting: Bool) throws {
        let decoded = try HTMLAppPackageTransfer.readArchive(from: url)
        let imported = decoded.bundle

        if replaceExisting {
            for app in apps {
                SourceCache.shared.remove(appID: app.id)
                WebsiteArchiveManager.shared.remove(appID: app.id)
                HTMLPermissionStore.reset(appID: app.id)
                HTMLSensorPermissionPolicy.reset(appID: app.id)
                HTMLAppPortableDataStore.clear(appID: app.id)
            }

            apps = imported.apps
            folders = imported.folders
            FolderAppLinkStore.shared.replaceAll(
                with: imported.links,
                canonicalApps: apps,
                folders: folders
            )

            let identityMap = Dictionary(uniqueKeysWithValues: imported.apps.map { ($0.id, $0.id) })
            try HTMLAppPackageTransfer.restoreCache(decoded.cacheFiles, appIDMap: identityMap)
            restorePortablePermissions(bundle: imported, appIDMap: identityMap)
            restorePortableAppData(bundle: imported, appIDMap: identityMap)
            restorePortableWebsiteState(bundle: imported, appIDMap: identityMap)

            save()
            persistFolders()
            notice = "Restored \(apps.count) HTMLApp\(apps.count == 1 ? "" : "s") from backup."
            return
        }

        var folderIDMap: [String: String] = [:]
        let importedFoldersByID = Dictionary(uniqueKeysWithValues: imported.folders.map { ($0.id, $0) })
        var remainingFolders = imported.folders
        var safety = remainingFolders.count + 2

        while !remainingFolders.isEmpty, safety > 0 {
            safety -= 1
            var progressed = false

            for folder in remainingFolders {
                let canCreate = folder.parentID == nil || folder.parentID.flatMap { folderIDMap[$0] } != nil || importedFoldersByID[folder.parentID ?? ""] == nil
                guard canCreate else { continue }

                let mappedParent = folder.parentID.flatMap { folderIDMap[$0] }
                let newID = UUID().uuidString
                let copied = LibraryFolder(
                    id: newID,
                    name: uniqueFolderName(folder.name, parentID: mappedParent),
                    parentID: mappedParent,
                    tintHex: folder.tintHex,
                    createdAt: folder.createdAt
                )
                folders.append(copied)
                folderIDMap[folder.id] = newID
                remainingFolders.removeAll { $0.id == folder.id }
                progressed = true
            }

            if !progressed { break }
        }

        for folder in remainingFolders {
            let newID = UUID().uuidString
            folders.append(LibraryFolder(
                id: newID,
                name: uniqueFolderName(folder.name, parentID: nil),
                parentID: nil,
                tintHex: folder.tintHex,
                createdAt: folder.createdAt
            ))
            folderIDMap[folder.id] = newID
        }

        var appIDMap: [String: String] = [:]
        var importedApps: [SavedHTMLApp] = []
        for var app in imported.apps {
            let oldID = app.id
            let newID = makeID()
            app.id = newID
            app.folderID = app.folderID.flatMap { folderIDMap[$0] }
            app.folderName = nil
            app.lastOpenedAt = nil
            app.updatedAt = Date()
            appIDMap[oldID] = newID
            importedApps.append(app)
        }

        apps.insert(contentsOf: importedApps, at: 0)
        FolderAppLinkStore.shared.appendImported(
            imported.links,
            appIDMap: appIDMap,
            folderIDMap: folderIDMap,
            canonicalApps: apps
        )
        try HTMLAppPackageTransfer.restoreCache(decoded.cacheFiles, appIDMap: appIDMap)
        restorePortablePermissions(bundle: imported, appIDMap: appIDMap)
        restorePortableAppData(bundle: imported, appIDMap: appIDMap)
        restorePortableWebsiteState(bundle: imported, appIDMap: appIDMap)

        save()
        persistFolders()
        FolderAppLinkStore.shared.prune(
            validAppIDs: Set(apps.map(\.id)),
            validFolderIDs: Set(folders.map(\.id))
        )
        notice = "Imported \(importedApps.count) HTMLApp\(importedApps.count == 1 ? "" : "s") as portable copies."
    }

    func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "htmlapp",
              url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let app = apps.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            errorMessage = "No saved HTML app matched that URL."
            return
        }

        guard let current = runningApp, current.id != app.id else {
            launch(app)
            return
        }

        if UserDefaults.standard.object(forKey: "askBeforeSwitch") as? Bool ?? true {
            pendingSwitchApp = app
        } else {
            replaceRunningApp(with: app)
        }
    }

    func confirmPendingSwitch() {
        guard let app = pendingSwitchApp else { return }
        pendingSwitchApp = nil
        replaceRunningApp(with: app)
    }

    func installWebClip(for app: SavedHTMLApp) {
        WebClipInstaller.shared.install(app: app) { [weak self] result in
            switch result {
            case .success:
                self?.notice = "Profile opened in Safari. Follow the iOS install prompts."
            case .failure(let error):
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func exportProfile(for app: SavedHTMLApp) {
        let data = WebClipProfile.mobileConfigData(for: app)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HTMLApp-\(app.id).mobileconfig")
        do {
            try data.write(to: url, options: .atomic)
            SharePresenter.present(items: [url])
        } catch {
            errorMessage = "The profile could not be exported."
        }
    }

    func results(for query: String) -> [SavedHTMLApp] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ordered = orderedApps
        guard !value.isEmpty else { return ordered }

        return ordered.enumerated().compactMap { offset, app -> (SavedHTMLApp, Int, Int)? in
            let name = app.name.lowercased()
            let score: Int
            if name == value { score = 600 }
            else if name.hasPrefix(value) { score = 500 }
            else if name.contains(value) { score = 400 }
            else if app.summary.lowercased().contains(value) { score = 300 }
            else if HTMLTools.visibleText(in: app.html).lowercased().contains(value) { score = 200 }
            else if app.html.lowercased().contains(value) { score = 100 }
            else { return nil }
            return (app, score, offset)
        }
        .sorted { left, right in
            left.1 == right.1 ? left.2 < right.2 : left.1 > right.1
        }
        .map(\.0)
    }

    private func refreshWebsiteInBackground(appID: String) async {
        guard let index = apps.firstIndex(where: { $0.id == appID }),
              let source = apps[index].websiteSourceURL,
              let url = WebsiteArchiveManager.shared.normalizedURL(source) else { return }
        do {
            let changed = try await WebsiteArchiveManager.shared.stageIfChanged(
                url: url,
                appID: appID,
                currentFingerprint: apps[index].websiteFingerprint
            )
            guard changed, let latestIndex = apps.firstIndex(where: { $0.id == appID }) else { return }
            if UserDefaults.standard.bool(forKey: "autoApplyWebsiteUpdates") {
                applyPendingWebsiteUpdate(apps[latestIndex], relaunch: runningApp?.id == appID)
            } else {
                pendingWebsiteUpdate = apps[latestIndex]
            }
        } catch {
            // Keep the current downloaded copy when offline or refreshing fails.
        }
    }

    private func replaceRunningApp(with app: SavedHTMLApp) {
        runningApp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.launch(app)
        }
    }

    private func foldersForPortableExport(apps selectedApps: [SavedHTMLApp], links: [LibraryAppLink]) -> [LibraryFolder] {
        var needed = Set(selectedApps.compactMap(\.folderID))
        needed.formUnion(links.compactMap(\.folderID))

        var frontier = Array(needed)
        while let id = frontier.popLast() {
            guard let folder = folders.first(where: { $0.id == id }),
                  let parentID = folder.parentID,
                  needed.insert(parentID).inserted else { continue }
            frontier.append(parentID)
        }

        return folders.filter { needed.contains($0.id) }
    }

    private func restorePortablePermissions(bundle: HTMLAppPortableBundle, appIDMap: [String: String]) {
        // A portable package may come from another person/device. Never inherit
        // sensitive sub-app permission grants silently; require fresh consent.
        for newID in appIDMap.values {
            HTMLPermissionStore.reset(appID: newID)
            HTMLSensorPermissionPolicy.reset(appID: newID)
        }
    }


    private func restorePortableAppData(bundle: HTMLAppPortableBundle, appIDMap: [String: String]) {
        guard let appData = bundle.appData else { return }
        for (oldID, values) in appData {
            guard let newID = appIDMap[oldID] else { continue }
            HTMLAppPortableDataStore.replace(appID: newID, values: values)
        }
    }


    private func restorePortableWebsiteState(bundle: HTMLAppPortableBundle, appIDMap: [String: String]) {
        guard let states = bundle.websiteStates else { return }
        for (oldID, state) in states {
            guard let newID = appIDMap[oldID] else { continue }
            WebsiteArchiveManager.shared.restorePortableState(state, appID: newID)
        }
    }

    private func validPendingInsertionFolderID() -> String? {
        guard let pendingInsertionFolderID,
              folders.contains(where: { $0.id == pendingInsertionFolderID }) else { return nil }
        return pendingInsertionFolderID
    }

    private func siblingNameExists(_ name: String, parentID: String?, excludingID: String? = nil) -> Bool {
        folders.contains { folder in
            folder.id != excludingID &&
            folder.parentID == parentID &&
            folder.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func uniqueFolderName(_ desiredName: String, parentID: String?, excludingID: String? = nil) -> String {
        let trimmed = desiredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Folder" : trimmed
        if !siblingNameExists(base, parentID: parentID, excludingID: excludingID) { return base }
        var counter = 2
        while siblingNameExists("\(base) \(counter)", parentID: parentID, excludingID: excludingID) { counter += 1 }
        return "\(base) \(counter)"
    }

    private func makeID() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var value = ""
        repeat { value = String((0..<6).compactMap { _ in alphabet.randomElement() }) }
        while apps.contains(where: { $0.id == value })
        return value
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        do { apps = try JSONDecoder().decode([SavedHTMLApp].self, from: data) }
        catch { errorMessage = "The saved library could not be loaded." }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(apps).write(to: libraryURL, options: .atomic)
        } catch {
            errorMessage = "The library could not be saved."
        }
    }

    private func loadFoldersAndMigrate() {
        if let data = UserDefaults.standard.data(forKey: folderRecordsDefaultsKey),
           let decoded = try? JSONDecoder().decode([LibraryFolder].self, from: data) {
            folders = decoded
        }

        var changed = false
        let legacyStored = UserDefaults.standard.stringArray(forKey: legacyFolderDefaultsKey) ?? []
        var legacyNames = legacyStored
        legacyNames.append(contentsOf: apps.compactMap(\.folderName))

        var rootNameToID: [String: String] = [:]
        for folder in folders where folder.parentID == nil {
            rootNameToID[folder.name.lowercased()] = folder.id
        }

        for rawName in legacyNames {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if rootNameToID[key] == nil {
                let folder = LibraryFolder(
                    id: UUID().uuidString,
                    name: uniqueFolderName(name, parentID: nil),
                    parentID: nil,
                    tintHex: LibraryFolder.defaultTintHex,
                    createdAt: Date()
                )
                folders.append(folder)
                rootNameToID[key] = folder.id
                changed = true
            }
        }

        for index in folders.indices {
            if let parentID = folders[index].parentID,
               parentID == folders[index].id || !folders.contains(where: { $0.id == parentID }) {
                folders[index].parentID = nil
                changed = true
            }
        }

        for index in folders.indices {
            var seen: Set<String> = [folders[index].id]
            var parentID = folders[index].parentID
            while let current = parentID {
                if seen.contains(current) {
                    folders[index].parentID = nil
                    changed = true
                    break
                }
                seen.insert(current)
                parentID = folders.first(where: { $0.id == current })?.parentID
            }
        }

        for index in apps.indices {
            if let folderID = apps[index].folderID,
               folders.contains(where: { $0.id == folderID }) {
                if apps[index].folderName != nil {
                    apps[index].folderName = nil
                    changed = true
                }
                continue
            }

            if let legacy = apps[index].folderName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !legacy.isEmpty {
                let key = legacy.lowercased()
                if let folderID = rootNameToID[key] {
                    apps[index].folderID = folderID
                } else {
                    let folder = LibraryFolder(
                        id: UUID().uuidString,
                        name: uniqueFolderName(legacy, parentID: nil),
                        parentID: nil,
                        tintHex: LibraryFolder.defaultTintHex,
                        createdAt: Date()
                    )
                    folders.append(folder)
                    rootNameToID[key] = folder.id
                    apps[index].folderID = folder.id
                }
                apps[index].folderName = nil
                changed = true
            } else if apps[index].folderID != nil {
                apps[index].folderID = nil
                changed = true
            }
        }

        persistFolders()
        if changed { save() }
        UserDefaults.standard.removeObject(forKey: legacyFolderDefaultsKey)
    }

    private func persistFolders() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(folders)
            UserDefaults.standard.set(data, forKey: folderRecordsDefaultsKey)
        } catch {
            errorMessage = "The folder layout could not be saved."
        }
    }
}
