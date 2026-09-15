import SwiftUI
import UIKit

@main
struct HTMLAppMain: App {
    @StateObject private var store = AppStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    init() {
        HTMLNotificationCenterDelegate.shared.activate()
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
    var folderName: String?
    var websiteSourceURL: String?
    var websiteFingerprint: String?
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var apps: [SavedHTMLApp] = []
    @Published private(set) var folders: [String] = []
    @Published var runningApp: SavedHTMLApp?
    @Published var pendingSwitchApp: SavedHTMLApp?
    @Published var pendingWebsiteUpdate: SavedHTMLApp?
    @Published var errorMessage: String?
    @Published var notice: String?
    private let libraryURL: URL
    private let folderDefaultsKey = "htmlapp.libraryFolders"

    var orderedApps: [SavedHTMLApp] {
        apps.filter { $0.isFavorite == true } + apps.filter { $0.isFavorite != true }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        libraryURL = base.appendingPathComponent("library.json")
        folders = UserDefaults.standard.stringArray(forKey: folderDefaultsKey) ?? []
        load()
        for folder in apps.compactMap(\.folderName) where !folders.contains(folder) { folders.append(folder) }
        persistFolders()
    }

    func add(html: String, summary: String) async {
        let name = HTMLTools.title(in: html) ?? "Untitled App"
        let icon = await HTMLAppIconTools.savedIcon(html: html, name: name)
        let now = Date()
        let app = SavedHTMLApp(
            id: makeID(), name: name,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html, favicon: icon,
            createdAt: now, updatedAt: now, lastOpenedAt: nil,
            isFavorite: false, folderName: nil,
            websiteSourceURL: nil, websiteFingerprint: nil
        )
        apps.insert(app, at: 0)
        save()
        await SourceCache.shared.refresh(app: app, force: false)
    }

    func addWebsite(urlString: String) async throws {
        guard let url = WebsiteArchiveManager.shared.normalizedURL(urlString) else { throw WebsiteArchiveError.invalidURL }
        let id = makeID()
        let snapshot = try await WebsiteArchiveManager.shared.download(url: url, appID: id)
        try WebsiteArchiveManager.shared.installInitial(snapshot, appID: id)
        let name = HTMLTools.title(in: snapshot.html) ?? url.host ?? "Downloaded Website"
        let icon = await HTMLAppIconTools.savedIcon(html: snapshot.html, name: name)
        let now = Date()
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
            websiteSourceURL: url.absoluteString,
            websiteFingerprint: snapshot.fingerprint
        )
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

    func launch(_ app: SavedHTMLApp) {
        guard var index = apps.firstIndex(where: { $0.id == app.id }) else { return }

        if apps[index].websiteSourceURL != nil,
           let pending = try? WebsiteArchiveManager.shared.activatePending(appID: app.id),
           let pending {
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
              let pending,
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.runningApp = updated }
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

    func createFolder(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folders.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        folders.append(name)
        folders.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        persistFolders()
    }

    func move(_ app: SavedHTMLApp, toFolder folder: String?) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].folderName = folder
        if let folder, !folders.contains(folder) { createFolder(folder) }
        save()
    }

    func deleteFolder(_ folder: String) {
        folders.removeAll { $0 == folder }
        for index in apps.indices where apps[index].folderName == folder { apps[index].folderName = nil }
        persistFolders()
        save()
    }

    func delete(_ app: SavedHTMLApp) {
        apps.removeAll { $0.id == app.id }
        save()
        SourceCache.shared.remove(appID: app.id)
        WebsiteArchiveManager.shared.remove(appID: app.id)
        HTMLPermissionStore.reset(appID: app.id)
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
            // The current downloaded copy remains usable when refresh fails or the device is offline.
        }
    }

    private func replaceRunningApp(with app: SavedHTMLApp) {
        runningApp = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.launch(app)
        }
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

    private func persistFolders() {
        UserDefaults.standard.set(folders, forKey: folderDefaultsKey)
    }
}
