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
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var apps: [SavedHTMLApp] = []
    @Published var runningApp: SavedHTMLApp?
    @Published var pendingSwitchApp: SavedHTMLApp?
    @Published var errorMessage: String?
    @Published var notice: String?
    private let libraryURL: URL

    var orderedApps: [SavedHTMLApp] {
        apps.filter { $0.isFavorite == true } + apps.filter { $0.isFavorite != true }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        libraryURL = base.appendingPathComponent("library.json")
        load()
    }

    func add(html: String, summary: String) async {
        let name = HTMLTools.title(in: html) ?? "Untitled App"
        let icon = await HTMLAppIconTools.savedIcon(html: html, name: name)
        let now = Date()
        let app = SavedHTMLApp(
            id: makeID(),
            name: name,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html,
            favicon: icon,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: nil,
            isFavorite: false
        )
        apps.insert(app, at: 0)
        save()
        await SourceCache.shared.refresh(app: app, force: false)
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

    func rebuildIcons() async {
        for index in apps.indices {
            apps[index].favicon = await HTMLAppIconTools.savedIcon(html: apps[index].html, name: apps[index].name)
        }
        save()
        notice = "All saved icons were rebuilt."
    }

    func launch(_ app: SavedHTMLApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].lastOpenedAt = Date()
        save()
        runningApp = apps[index]
    }

    func toggleFavorite(_ app: SavedHTMLApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].isFavorite = !(apps[index].isFavorite == true)
        save()
        notice = apps[index].isFavorite == true ? "Pinned \(apps[index].name) to the top." : "Removed \(apps[index].name) from favorites."
    }

    func delete(_ app: SavedHTMLApp) {
        apps.removeAll { $0.id == app.id }
        save()
        SourceCache.shared.remove(appID: app.id)
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
}
