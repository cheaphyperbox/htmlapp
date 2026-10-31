import SwiftUI
import UIKit
import WidgetKit

@main
struct HTMLAppMain: App {
    @UIApplicationDelegateAdaptor(HTMLAppBackgroundURLSessionDelegate.self) private var backgroundURLDelegate
    @StateObject private var store = AppStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("htmlapp.lastOpenedVersion") private var lastOpenedVersion = ""
    @AppStorage("htmlapp.previousOpenedVersion") private var previousOpenedVersion = ""
    @AppStorage("htmlapp.lastSeenBuild") private var lastSeenBuild = ""
    @State private var presentingWhatsNew = false
    @State private var detectedPreviousVersion: String?
    @State private var checkedVersionThisLaunch = false
    @State private var deferredExternalURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if let diagnosis = HTMLAppProviderStorage.repairPreviouslyApprovedGroup() {
            NSLog("HTMLApp widget signing status: %@", diagnosis)
        }
        if #available(iOS 16.2, *) {
            HTMLAppSiriShortcuts.updateAppShortcutParameters()
        }
        HTMLNotificationCenterDelegate.shared.activate()
        if #available(iOS 16.2, *) {
            Task { await HTMLAppForgeActivityService.recoverStale() }
        }
        HTMLAppBackgroundCoordinator.shared.register()
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            HTMLAppForgeContinuedProcessing.register()
        }
        #endif
        HTMLAppBackgroundCoordinator.shared.schedule()
        ForgeBackgroundUpload.shared.reconnectIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            HTMLAppDisplayRoot()
                .environmentObject(store)
                .fullScreenCover(item: $store.runningApp) { app in
                    WebRunner(app: app)
                        .environmentObject(store)
                        .interactiveDismissDisabled(true)
                        .onChange(of: store.pendingSwitchApp?.id) { id in
                            if id != nil { HTMLAppFirstUseTips.show("switch") }
                        }
                        .alert("Switch HTML app?", isPresented: Binding(
                            get: { store.pendingSwitchApp != nil },
                            set: { if !$0 { store.pendingSwitchApp = nil } }
                        )) {
                            Button("Switch App") { store.confirmPendingSwitch() }
                            Button("Keep Current App", role: .cancel) { store.pendingSwitchApp = nil }
                        } message: {
                            Text("Switch to the other app? Your current app will close only after you choose Switch App.")
                        }
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
                .fullScreenCover(isPresented: $presentingWhatsNew, onDismiss: {
                    recordVersionSeen()
                    if let url = deferredExternalURL {
                        deferredExternalURL = nil
                        store.openDeepLink(url)
                    }
                }) {
                    HTMLAppWhatsNewView(previousVersion: detectedPreviousVersion) {
                        presentingWhatsNew = false
                    }
                    .interactiveDismissDisabled(true)
                }
                .onAppear(perform: checkVersionOnLaunch)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HTMLApp.FaceDownShakeExit"))) { _ in
                    // The runner is a SwiftUI full-screen cover, not a UIKit
                    // controller that can reliably be dismissed via responders.
                    store.runningApp = nil
                }
                .task { await store.syncICloud() }
                .onReceive(NotificationCenter.default.publisher(for: HTMLAppPortableDataStore.localDataChanged)) { _ in
                    if HTMLAppICloudPreferences.includeData { store.requestICloudSync() }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { store.requestICloudSync() }
                }
                .onChange(of: onboardingComplete) { finished in
                    guard finished else { return }
                    checkedVersionThisLaunch = false
                    checkVersionOnLaunch()
                }
                .sheet(item: $store.pendingWebClipGuideApp) { app in
                    HTMLAppHomeScreenGuide(
                        appName: app.name, appID: app.id, profileURL: store.pendingWebClipProfileURL,
                        openInSafari: { store.openWebClipProfileInSafari(for: app) },
                        exportProfile: { store.exportProfile(for: app) }
                    )
                }
                .alert("Library recovery needed", isPresented: $store.showLibraryRecoveryAlert) {
                    Button("Keep Library Protected", role: .cancel) {
                        store.showLibraryRecoveryAlert = false
                    }
                    if store.libraryCorruptCopyName != nil {
                        Button("Start Empty Library", role: .destructive) {
                            store.allowNewLibraryAfterRecoveryCopy()
                        }
                    }
                } message: {
                    Text("HTMLApp couldn't read your saved apps. It preserved the damaged file rather than deleting it. Starting empty will not restore those apps. Use Keep Library Protected until you've recovered your data.")
                }
                .onOpenURL { url in
                    // A cold Lock Screen launch can race the What's New cover.
                    // Route once that cover is fully dismissed on older iOS.
                    if presentingWhatsNew && url.scheme?.lowercased() == "htmlapp" &&
                        ["voice-create", "import"].contains(url.host?.lowercased() ?? "") {
                        deferredExternalURL = url
                        presentingWhatsNew = false
                    } else {
                        store.openDeepLink(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .htmlAppNotificationOpened)) { notification in
                    if let url = notification.object as? URL {
                        store.openDeepLink(url)
                    }
                }
        }
    }

    private var installedBuildFingerprint: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? HTMLAppReleaseNotes.installedVersion
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "\(version)-\(build)"
    }

    private func checkVersionOnLaunch() {
        guard onboardingComplete, !checkedVersionThisLaunch else { return }
        checkedVersionThisLaunch = true
        let installed = HTMLAppReleaseNotes.installedVersion
        guard installed != "Unknown" else { return }
        let fingerprint = installedBuildFingerprint
        // A new build can contain new changes without a marketing version bump.
        // Present release notes on first install and on each distinct build.
        guard lastSeenBuild != fingerprint || lastOpenedVersion != installed else { return }
        detectedPreviousVersion = lastOpenedVersion.isEmpty ? nil : lastOpenedVersion
        presentingWhatsNew = true
    }

    private func recordVersionSeen() {
        let installed = HTMLAppReleaseNotes.installedVersion
        guard installed != "Unknown" else { return }
        if !lastOpenedVersion.isEmpty && installed != lastOpenedVersion {
            previousOpenedVersion = lastOpenedVersion
        }
        lastOpenedVersion = installed
        lastSeenBuild = installedBuildFingerprint
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

struct SavedHTMLApp: Identifiable, Codable, Hashable, Sendable {
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

struct LibraryFolder: Identifiable, Codable, Hashable, Sendable {
    static let defaultTintHex = "#5B9DFF"

    var id: String
    var name: String
    var parentID: String?
    var tintHex: String
    var createdAt: Date
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var voiceCreateRequest = 0
    @Published private(set) var remoteHTMLImportRequest: URL?
    @Published private(set) var apps: [SavedHTMLApp] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published var runningApp: SavedHTMLApp?
    @Published var pendingSwitchApp: SavedHTMLApp?
    @Published var pendingWebClipGuideApp: SavedHTMLApp?
    @Published var pendingWebClipProfileURL: URL?
    @Published var pendingWebsiteUpdate: SavedHTMLApp?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var libraryLoadBlocked = false
    @Published var showLibraryRecoveryAlert = false
    @Published private(set) var libraryCorruptCopyName: String?

    private let libraryURL: URL
    private let folderRecordsDefaultsKey = "htmlapp.libraryFolderRecords.v2"
    private let legacyFolderDefaultsKey = "htmlapp.libraryFolders"
    private var pendingInsertionFolderID: String?
    private var deferredLaunchSave: Task<Void, Never>?

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
        if !libraryLoadBlocked {
            FolderAppLinkStore.shared.prune(
                validAppIDs: Set(apps.map(\.id)),
                validFolderIDs: Set(folders.map(\.id))
            )
        }
    }

    /// Pull remote changes without deleting local apps. iCloud absence never
    /// clears or blocks the local Library.
    func syncICloud() async {
        guard HTMLAppICloudPreferences.enabled, !libraryLoadBlocked else { return }
        let snapshot = apps
        let portable = HTMLAppICloudPreferences.includeData
            ? Dictionary(uniqueKeysWithValues: apps.map { ($0.id, HTMLAppPortableDataStore.all(appID: $0.id)) })
            : [:]
        let incoming = await HTMLAppICloudSync.shared.exchange(localApps: snapshot, localFolders: folders, localData: portable, localDeleted: HTMLAppICloudPreferences.deleted)
        guard HTMLAppICloudPreferences.enabled, !libraryLoadBlocked else { return }
        var changed = false
        var foldersChanged = false
        for cloud in incoming.folders where !folders.contains(where: { $0.id == cloud.id }) {
            folders.append(cloud)
            foldersChanged = true
        }
        if foldersChanged { persistFolders() }
        var deleted = HTMLAppICloudPreferences.deleted
        for (id, time) in incoming.deleted {
            deleted[id] = max(deleted[id] ?? 0, time)
        }
        HTMLAppICloudPreferences.deleted = deleted
        let oldCount = apps.count
        apps.removeAll { item in (deleted[item.id] ?? 0) > item.updatedAt.timeIntervalSince1970 }
        if apps.count != oldCount { changed = true }
        for cloud in incoming.apps {
            guard (deleted[cloud.id] ?? 0) <= cloud.updatedAt.timeIntervalSince1970 else { continue }
            if let index = apps.firstIndex(where: { $0.id == cloud.id }) {
                if cloud.updatedAt > apps[index].updatedAt {
                    apps[index] = cloud
                    changed = true
                }
            } else {
                var imported = cloud
                if let folderID = imported.folderID, !folders.contains(where: { $0.id == folderID }) {
                    imported.folderID = nil
                }
                apps.append(imported)
                changed = true
            }
        }
        for (id, values) in incoming.data where HTMLAppICloudPreferences.includeData {
            // No cross-app access: only the matching saved app owns its store.
            guard apps.contains(where: { $0.id == id }) else { continue }
            HTMLAppPortableDataStore.replace(appID: id, values: values)
        }
        if changed { save() }
    }

    func requestICloudSync() {
        guard HTMLAppICloudPreferences.enabled else { return }
        Task { await syncICloud() }
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
        Task(priority: .utility) { await SourceCache.shared.refresh(app: app, force: false) }
    }

    func addTransferredApp(
        _ incoming: SavedHTMLApp,
        portableData: [String: String]? = nil,
        widgets: [HTMLAppWidgetDefinition]? = nil,
        backgroundJobs: [HTMLAppBackgroundFetchJob]? = nil
    ) async {
        if let source = incoming.websiteSourceURL,
           !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (try? await addWebsite(urlString: source)) != nil {
            if let imported = apps.first,
               let index = apps.firstIndex(where: { $0.id == imported.id }) {
                apps[index].summary = incoming.summary
                apps[index].isFavorite = incoming.isFavorite
                if let favicon = incoming.favicon { apps[index].favicon = favicon }
                save()
                if let portableData {
                    HTMLAppPortableDataStore.replace(appID: apps[index].id, values: portableData)
                }
                installTransferredIntegrations(
                    appID: apps[index].id,
                    widgets: widgets,
                    backgroundJobs: backgroundJobs
                )
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
        installTransferredIntegrations(appID: id, widgets: widgets, backgroundJobs: backgroundJobs)
        save()
        Task(priority: .utility) { await SourceCache.shared.refresh(app: app, force: false) }
        notice = "Received \(app.name)."
    }

    func installTransferredIntegrations(
        appID: String,
        widgets: [HTMLAppWidgetDefinition]?,
        backgroundJobs: [HTMLAppBackgroundFetchJob]?
    ) {
        if let widgets {
            HTMLAppWidgetStore.replace(appID: appID, with: widgets)
        }
        if let backgroundJobs {
            HTMLAppBackgroundJobStore.replace(appID: appID, with: backgroundJobs)
        }
        if widgets != nil {
            WidgetCenter.shared.reloadAllTimelines()
        }
        if backgroundJobs != nil {
            HTMLAppBackgroundCoordinator.shared.schedule()
        }
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

    // Full-source checkpoints are stored separately from library.json. This
    // intentionally survives app restarts and does not modify app user data.
    struct AIEditCheckpoint: Codable, Identifiable {
        var id: UUID
        var created: Date
        var html: String
        var summary: String
        var note: String
    }

    private func editHistoryURL(for id: String) -> URL {
        let safeID = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let folder = libraryURL.deletingLastPathComponent().appendingPathComponent("AIEditHistory", isDirectory: true)
        return folder.appendingPathComponent(safeID + ".json")
    }

    func editHistory(for app: SavedHTMLApp) -> [AIEditCheckpoint] {
        guard let data = try? Data(contentsOf: editHistoryURL(for: app.id)),
              let records = try? JSONDecoder().decode([AIEditCheckpoint].self, from: data) else { return [] }
        return records
    }

    func updateFromAI(_ app: SavedHTMLApp, html: String, summary: String, note: String) async {
        guard let current = apps.first(where: { $0.id == app.id }), current.html != html else {
            await update(app, html: html, summary: summary)
            return
        }
        var history = editHistory(for: app)
        history.append(AIEditCheckpoint(id: UUID(), created: Date(), html: current.html,
                                        summary: current.summary, note: note))
        let url = editHistoryURL(for: app.id)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Could not save the previous edit version. The AI edit was not applied."
            return
        }
        await update(app, html: html, summary: summary)
    }

    func restoreAIEdit(_ app: SavedHTMLApp, checkpointID: UUID) async {
        guard let current = apps.first(where: { $0.id == app.id }) else { return }
        var history = editHistory(for: app)
        guard let chosen = history.first(where: { $0.id == checkpointID }) else { return }
        history.append(AIEditCheckpoint(id: UUID(), created: Date(), html: current.html,
                                        summary: current.summary, note: "Before restore"))
        let url = editHistoryURL(for: app.id)
        do {
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
        } catch {
            errorMessage = "Could not preserve current version; restore canceled."
            return
        }
        await update(current, html: chosen.html, summary: chosen.summary)
        notice = "Restored earlier HTML version."
    }

    func clearAIEditHistory(for app: SavedHTMLApp) {
        let url = editHistoryURL(for: app.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { errorMessage = "Could not clear old AI edit history." }
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
        let updated = apps[index]
        Task(priority: .utility) { await SourceCache.shared.refresh(app: updated, force: false) }
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
        // Loading an app must not synchronously re-encode, validate and
        // backup the entire library before its WebView can appear.
        runningApp = apps[index]
        deferredLaunchSave?.cancel()
        deferredLaunchSave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 700_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.save()
        }

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
        HTMLAppICloudPreferences.markDeleted(app.id)
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
        let safeName = HTMLFileName.safe(app.name)
        let fileName = safeName.lowercased().hasSuffix(".html") ? safeName : safeName + ".html"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        do {
            try Data(app.html.utf8).write(to: url, options: .atomic)
            SharePresenter.present(items: [url])
        } catch {
            errorMessage = "The HTML file could not be exported."
        }
    }

    func createNearbyPackage(appIDs: Set<String>) throws -> URL {
        let selected = apps.filter { appIDs.contains($0.id) }.map { original in
            var clean = original
            clean.lastOpenedAt = nil
            clean.isFavorite = nil
            return clean
        }
        guard !selected.isEmpty else { throw HTMLAppPackageError.invalidArchive }
        let links = FolderAppLinkStore.shared.snapshot(appIDs: Set(selected.map(\.id)))
        let url = try HTMLAppPackageTransfer.createArchive(apps: selected, folders: foldersForPortableExport(apps: selected, links: links), links: links, includePersonalData: false)
        let unique = FileManager.default.temporaryDirectory.appendingPathComponent("Nearby-Send-\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: url, to: unique)
        return unique
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

    func importPortablePackage(from url: URL, replaceExisting: Bool, includePersonalData: Bool = true) throws {
        let decoded = try HTMLAppPackageTransfer.readArchive(from: url)
        let imported = decoded.bundle

        if replaceExisting {
            for app in apps {
                SourceCache.shared.remove(appID: app.id)
                WebsiteArchiveManager.shared.remove(appID: app.id)
                HTMLPermissionStore.reset(appID: app.id)
                HTMLSensorPermissionPolicy.reset(appID: app.id)
                HTMLAppPortableDataStore.clear(appID: app.id)
                HTMLAppWidgetStore.remove(appID: app.id)
                HTMLAppBackgroundJobStore.remove(appID: app.id)
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
            restoreGeneratedIntegrations(bundle: imported, appIDMap: identityMap)

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
        if includePersonalData {
            try HTMLAppPackageTransfer.restoreCache(decoded.cacheFiles, appIDMap: appIDMap)
            restorePortablePermissions(bundle: imported, appIDMap: appIDMap)
            restorePortableAppData(bundle: imported, appIDMap: appIDMap)
            restorePortableWebsiteState(bundle: imported, appIDMap: appIDMap)
            restoreGeneratedIntegrations(bundle: imported, appIDMap: appIDMap)
        }

        save()
        persistFolders()
        FolderAppLinkStore.shared.prune(
            validAppIDs: Set(apps.map(\.id)),
            validFolderIDs: Set(folders.map(\.id))
        )
        notice = "Imported \(importedApps.count) HTMLApp\(importedApps.count == 1 ? "" : "s") as portable copies."
    }

    func openDeepLink(_ url: URL) {
        if url.scheme?.lowercased() == "htmlapp",
           url.host?.lowercased() == "forge" {
            // The Live Activity is a return-to-app action. Existing Forge
            // presentations remain open; startup recovery handles a killed job.
            return
        }
        if url.scheme?.lowercased() == "htmlapp",
           url.host?.lowercased() == "voice-create" {
            UserDefaults.standard.set(true, forKey: "htmlapp.voiceCreatePending")
            voiceCreateRequest += 1
            NotificationCenter.default.post(name: Notification.Name("HTMLAppVoiceCreateRequested"), object: nil)
            return
        }
        if url.scheme?.lowercased() == "htmlapp",
           url.host?.lowercased() == "import" {
            do {
                remoteHTMLImportRequest = try RemoteHTMLImport.sourceURL(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }
        guard url.scheme?.lowercased() == "htmlapp",
              url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let app = apps.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            errorMessage = "No saved HTML app matched that URL."
            return
        }

        HTMLAppWidgetLaunchStore.receive(url: url, appID: app.id)
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

    func takeRemoteHTMLImportRequest() -> URL? {
        defer { remoteHTMLImportRequest = nil }
        return remoteHTMLImportRequest
    }

    func confirmPendingSwitch() {
        guard let app = pendingSwitchApp else { return }
        pendingSwitchApp = nil
        replaceRunningApp(with: app)
    }

    func installWebClip(for app: SavedHTMLApp) {
        // Display instructions immediately; the ephemeral loopback listener
        // must start when Safari is opened, not while the user reads the guide.
        pendingWebClipProfileURL = nil
        pendingWebClipGuideApp = app
    }

    func openWebClipProfileInSafari(for app: SavedHTMLApp) {
        LocalProfileDownload.shared.start(profile: WebClipProfile.mobileConfigData(for: app)) { [weak self] result in
            switch result {
            case .success(let url):
                self?.pendingWebClipProfileURL = url
                UIApplication.shared.open(url)
            case .failure(let error):
                self?.errorMessage = "Could not prepare the Home Screen profile: \(error.localizedDescription)"
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
        // Keep the existing full-screen presentation alive until the new
        // app has been selected. Replacing the identifiable item in place
        // prevents a transient dismiss from canceling the switch dialog.
        launch(app)
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


    private func restoreGeneratedIntegrations(bundle: HTMLAppPortableBundle, appIDMap: [String: String]) {
        for (oldID, newID) in appIDMap {
            if let definitions = bundle.widgetDefinitions?.filter({ $0.appID == oldID }) {
                HTMLAppWidgetStore.replace(appID: newID, with: definitions)
            } else {
                HTMLAppWidgetStore.remove(appID: newID)
            }

            if let jobs = bundle.backgroundJobs?.filter({ $0.appID == oldID }) {
                HTMLAppBackgroundJobStore.replace(appID: newID, with: jobs)
            } else {
                HTMLAppBackgroundJobStore.remove(appID: newID)
            }
        }

        HTMLAppBackgroundCoordinator.shared.schedule()
        WidgetCenter.shared.reloadAllTimelines()
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

    private var libraryBackupURL: URL {
        libraryURL.appendingPathExtension("bak")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            if let fallback = try? Data(contentsOf: libraryBackupURL),
               let recovered = try? JSONDecoder().decode([SavedHTMLApp].self, from: fallback) {
                apps = recovered
                try? fallback.write(to: libraryURL, options: .atomic)
            }
            return
        }
        do {
            let data = try Data(contentsOf: libraryURL)
            apps = try JSONDecoder().decode([SavedHTMLApp].self, from: data)
        } catch {
            // Preserve exact damaged bytes before attempting any recovery.
            let stamp = Int(Date().timeIntervalSince1970)
            let name = "library.corrupt-\(stamp).json"
            let archive = libraryURL.deletingLastPathComponent().appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: libraryURL, to: archive)
                libraryCorruptCopyName = name
            } catch {
                libraryLoadBlocked = true
                showLibraryRecoveryAlert = true
                errorMessage = "Your Library couldn't be read or safely copied. Saving is blocked to protect your apps."
                return
            }
            if let backup = try? Data(contentsOf: libraryBackupURL),
               let recovered = try? JSONDecoder().decode([SavedHTMLApp].self, from: backup) {
                apps = recovered
                do {
                    try backup.write(to: libraryURL, options: .atomic)
                    notice = "Library recovered from its last valid backup. The damaged original was preserved as \(name)."
                } catch {
                    libraryLoadBlocked = true
                    showLibraryRecoveryAlert = true
                    errorMessage = "A backup was found, but restoration failed. Saving is blocked; your Library files are preserved."
                }
            } else {
                libraryLoadBlocked = true
                showLibraryRecoveryAlert = true
                errorMessage = "Your Library couldn't be read. Its damaged data was saved as \(name). Saving is blocked until you choose how to recover."
            }
        }
    }

    /// Never overwrite an unreadable library simply because the in-memory
    /// array is empty. The user must explicitly acknowledge this recovery risk.
    func allowNewLibraryAfterRecoveryCopy() {
        guard libraryLoadBlocked, libraryCorruptCopyName != nil else { return }
        do {
            try FileManager.default.removeItem(at: libraryURL)
        } catch {
            errorMessage = "The damaged Library couldn't be moved out of the way. Saving remains blocked."
            return
        }
        libraryLoadBlocked = false
        showLibraryRecoveryAlert = false
        notice = "Starting a fresh Library. Your original library copy remains available for recovery."
        save()
    }

    private func save() {
        guard !libraryLoadBlocked else {
            errorMessage = "Library changes weren't saved because recovery is required. Your existing files remain untouched."
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let result = try encoder.encode(apps)
            // Keep one known-good previous snapshot, not an empty failed load.
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                let previous = try Data(contentsOf: libraryURL)
                _ = try JSONDecoder().decode([SavedHTMLApp].self, from: previous)
                try previous.write(to: libraryBackupURL, options: .atomic)
            }
            try result.write(to: libraryURL, options: .atomic)
            requestICloudSync()
        } catch {
            errorMessage = "The library couldn't be saved. Existing data and its backup were kept."
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

