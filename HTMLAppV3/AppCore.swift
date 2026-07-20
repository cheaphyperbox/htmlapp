import SwiftUI
import UIKit

@main
struct HTMLAppMain: App {
    @StateObject private var store = AppStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .fullScreenCover(item: $store.runningApp) { app in
                    WebRunner(app: app).ignoresSafeArea().interactiveDismissDisabled(true)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !onboardingComplete },
                    set: { if !$0 { onboardingComplete = true } }
                )) {
                    OnboardingView(complete: $onboardingComplete).interactiveDismissDisabled(true)
                }
                .onOpenURL(perform: store.openDeepLink)
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
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var apps: [SavedHTMLApp] = []
    @Published var runningApp: SavedHTMLApp?
    @Published var errorMessage: String?
    @Published var notice: String?
    private let libraryURL: URL

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
        let app = SavedHTMLApp(id: makeID(), name: name,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html, favicon: icon, createdAt: now, updatedAt: now, lastOpenedAt: nil)
        apps.insert(app, at: 0)
        save()
        await SourceCache.shared.refresh(app: app, force: false)
    }

    func update(_ app: SavedHTMLApp, html: String, summary: String) async {
        guard let i = apps.firstIndex(where: { $0.id == app.id }) else { return }
        let name = HTMLTools.title(in: html) ?? app.name
        apps[i].name = name
        apps[i].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[i].html = html
        apps[i].favicon = await HTMLAppIconTools.savedIcon(html: html, name: name)
        apps[i].updatedAt = Date()
        save()
        await SourceCache.shared.refresh(app: apps[i], force: false)
    }

    func rebuildIcons() async {
        for i in apps.indices {
            apps[i].favicon = await HTMLAppIconTools.savedIcon(html: apps[i].html, name: apps[i].name)
        }
        save()
        notice = "All saved icons were rebuilt."
    }

    func launch(_ app: SavedHTMLApp) {
        guard let i = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[i].lastOpenedAt = Date()
        save()
        runningApp = apps[i]
    }

    func duplicate(_ app: SavedHTMLApp) {
        var copy = app
        copy.id = makeID()
        copy.name += " Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastOpenedAt = nil
        apps.insert(copy, at: 0)
        save()
    }

    func delete(_ app: SavedHTMLApp) {
        apps.removeAll { $0.id == app.id }
        save()
        SourceCache.shared.remove(appID: app.id)
    }

    func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "htmlapp", url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let app = apps.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            errorMessage = "No saved HTML app matched that URL."
            return
        }
        launch(app)
    }

    func results(for query: String) -> [SavedHTMLApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.compactMap { app -> (SavedHTMLApp, Int)? in
            let name = app.name.lowercased()
            if name == q { return (app, 600) }
            if name.hasPrefix(q) { return (app, 500) }
            if name.contains(q) { return (app, 400) }
            if app.summary.lowercased().contains(q) { return (app, 300) }
            if HTMLTools.visibleText(in: app.html).lowercased().contains(q) { return (app, 200) }
            if app.html.lowercased().contains(q) { return (app, 100) }
            return nil
        }.sorted {
            $0.1 == $1.1 ? $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending : $0.1 > $1.1
        }.map { $0.0 }
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
        } catch { errorMessage = "The library could not be saved." }
    }
}
