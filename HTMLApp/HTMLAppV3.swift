import SwiftUI
import WebKit
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
    private let libraryURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        libraryURL = base.appendingPathComponent("library.json")
        load()
        Task { await repairMissingIcons() }
    }

    func add(html: String, summary: String) async {
        let name = HTMLTools.title(in: html) ?? "Untitled App"
        let now = Date()
        let app = SavedHTMLApp(
            id: makeID(), name: name,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html,
            favicon: await HTMLAppIconTools.savedIcon(html: html, name: name),
            createdAt: now, updatedAt: now, lastOpenedAt: nil
        )
        apps.insert(app, at: 0)
        save()
        await SourceCache.shared.refresh(app: app, force: false)
    }

    func update(_ app: SavedHTMLApp, html: String, summary: String) async {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        let name = HTMLTools.title(in: html) ?? app.name
        apps[index].html = html
        apps[index].name = name
        apps[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[index].favicon = await HTMLAppIconTools.savedIcon(html: html, name: name)
        apps[index].updatedAt = Date()
        save()
        await SourceCache.shared.refresh(app: apps[index], force: false)
    }

    func delete(_ app: SavedHTMLApp) {
        apps.removeAll { $0.id == app.id }
        save()
        SourceCache.shared.remove(appID: app.id)
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

    func launch(_ app: SavedHTMLApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].lastOpenedAt = Date()
        save()
        runningApp = apps[index]
    }

    func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "htmlapp",
              url.host?.lowercased() == "open",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              let app = apps.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else {
            errorMessage = "No saved HTML app matched that link."
            return
        }
        launch(app)
    }

    func results(for raw: String) -> [SavedHTMLApp] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.compactMap { app -> (SavedHTMLApp, Int)? in
            let name = app.name.lowercased()
            let summary = app.summary.lowercased()
            let body = HTMLTools.visibleText(in: app.html).lowercased()
            if name == query { return (app, 600) }
            if name.hasPrefix(query) { return (app, 500) }
            if name.contains(query) { return (app, 400) }
            if summary.contains(query) { return (app, 300) }
            if body.contains(query) { return (app, 200) }
            if app.html.lowercased().contains(query) { return (app, 100) }
            return nil
        }
        .sorted { $0.1 == $1.1 ? $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending : $0.1 > $1.1 }
        .map(\.0)
    }

    func installWebClip(for app: SavedHTMLApp) {
        do {
            let url = try WebClipProfile.dataURL(for: app)
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if !opened {
                    self?.errorMessage = "iOS did not open the profile installer. Use Export .mobileconfig and open the exported file instead."
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportProfile(for app: SavedHTMLApp) {
        let data = Data(WebClipProfile.mobileConfig(for: app).utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HTMLApp-\(app.id).mobileconfig")
        do {
            try data.write(to: url, options: .atomic)
            SharePresenter.present(items: [url])
        } catch {
            errorMessage = "The profile could not be exported."
        }
    }

    func clearLibrary() {
        apps.removeAll()
        save()
        SourceCache.shared.clearAll()
    }

    private func repairMissingIcons() async {
        var changed = false
        for index in apps.indices where apps[index].favicon == nil || UIImage(data: apps[index].favicon ?? Data()) == nil {
            apps[index].favicon = await HTMLAppIconTools.savedIcon(html: apps[index].html, name: apps[index].name)
            changed = true
        }
        if changed { save() }
    }

    private func makeID() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var value = ""
        repeat {
            value = String((0..<6).compactMap { _ in alphabet.randomElement() })
        } while apps.contains(where: { $0.id == value })
        return value
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        do {
            apps = try JSONDecoder().decode([SavedHTMLApp].self, from: data)
        } catch {
            errorMessage = "The saved library could not be loaded."
        }
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

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @AppStorage("showAppIDs") private var showAppIDs = true
    @State private var searchText = ""
    @State private var editor: EditorMode?
    @State private var showSettings = false
    @State private var pendingDelete: SavedHTMLApp?
    @State private var refreshingID: String?

    private var results: [SavedHTMLApp] { store.results(for: searchText) }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty {
                    WelcomeLibraryCard { editor = .new }
                } else if results.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No Results").font(.title2.bold())
                        Text("Try a name, description, or text from the HTML app.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(30)
                } else if libraryLayout == "grid" {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                            ForEach(results) { appCard($0) }
                        }.padding()
                    }
                } else {
                    List(results) { appCard($0).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)) }
                        .listStyle(.plain)
                }
            }
            .navigationTitle("HTMLApp")
            .searchable(text: $searchText, prompt: "Search your HTML apps")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editor = .new } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .sheet(item: $editor) { EditorView(mode: $0).environmentObject(store) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "this app")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { if let app = pendingDelete { store.delete(app) }; pendingDelete = nil }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Its HTML, icon, metadata, and cached sources will be removed.")
            }
            .alert("HTMLApp", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func appCard(_ app: SavedHTMLApp) -> some View {
        Button { store.launch(app) } label: {
            HStack(spacing: 13) {
                AppIconView(app: app, size: libraryLayout == "grid" ? 54 : 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.headline).lineLimit(1)
                    if !app.summary.isEmpty {
                        Text(app.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if showAppIDs {
                        Label(app.id, systemImage: "number").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 2)
                if refreshingID == app.id { ProgressView() }
                else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { appMenu(app) }
    }

    @ViewBuilder
    private func appMenu(_ app: SavedHTMLApp) -> some View {
        Button { store.installWebClip(for: app) } label: {
            Label("Install Home Screen Web Clip", systemImage: "square.and.arrow.down")
        }
        Button { store.exportProfile(for: app) } label: {
            Label("Export .mobileconfig", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button { editor = .edit(app) } label: { Label("Update HTML", systemImage: "pencil") }
        Button { UIPasteboard.general.string = app.html } label: { Label("Copy HTML", systemImage: "doc.on.doc") }
        Button { UIPasteboard.general.string = app.id } label: { Label("Copy ID", systemImage: "number") }
        Button { UIPasteboard.general.string = "htmlapp://open?id=\(app.id)" } label: { Label("Copy URL Scheme", systemImage: "link") }
        Button { store.duplicate(app) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button {
            refreshingID = app.id
            Task {
                await SourceCache.shared.refresh(app: app, force: true)
                refreshingID = nil
            }
        } label: {
            Label("Refresh External Sources", systemImage: "arrow.clockwise")
        }
        Divider()
        Button(role: .destructive) { pendingDelete = app } label: { Label("Delete HTML App", systemImage: "trash") }
    }
}

struct WelcomeLibraryCard: View {
    let add: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "app.badge.checkmark").font(.system(size: 64)).symbolRenderingMode(.hierarchical)
            Text("Turn HTML into apps").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("Paste HTML, save it locally, launch it full screen, and add a matching Web Clip to your Home Screen.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action: add) { Label("Create Your First HTML App", systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(32)
    }
}

struct AppIconView: View {
    let app: SavedHTMLApp
    let size: CGFloat
    var body: some View {
        Group {
            if let image = UIImage(data: app.resolvedIconData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(.primary.opacity(0.08)))
    }
}

enum EditorMode: Identifiable {
    case new
    case edit(SavedHTMLApp)
    var id: String { switch self { case .new: return "new"; case .edit(let app): return app.id } }
}

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let mode: EditorMode
    @State private var html: String
    @State private var summary: String
    @State private var previewing = false
    @State private var saving = false

    init(mode: EditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _html = State(initialValue: "<!doctype html>\n<html>\n<head>\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>My HTML App</title>\n  <style>body{font-family:-apple-system;background:#111827;color:#fff;padding:24px}</style>\n</head>\n<body>\n  <h1>Hello</h1>\n</body>\n</html>")
            _summary = State(initialValue: "")
        case .edit(let app):
            _html = State(initialValue: app.html)
            _summary = State(initialValue: app.summary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("What does this app do?", text: $summary, axis: .vertical).lineLimit(2...4)
                    Text("Descriptions improve search results.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("HTML Source") {
                    TextEditor(text: $html)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 380)
                }
            }
            .navigationTitle(mode.id == "new" ? "New HTML App" : "Edit HTML App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Preview") { previewing = true }.disabled(html.isEmpty)
                    Button("Save") { save() }.fontWeight(.semibold)
                        .disabled(html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .sheet(isPresented: $previewing) {
                NavigationStack {
                    HTMLWebView(html: html, appID: "PREVIEW")
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { previewing = false } }
                }
            }
            .overlay {
                if saving {
                    ProgressView("Saving icon and app…")
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            switch mode {
            case .new: await store.add(html: html, summary: summary)
            case .edit(let app): await store.update(app, html: html, summary: summary)
            }
            saving = false
            dismiss()
        }
    }
}

struct WebRunner: View {
    let app: SavedHTMLApp
    var body: some View { HTMLWebView(html: app.html, appID: app.id).statusBarHidden(true) }
}

struct HTMLWebView: UIViewRepresentable {
    let html: String
    let appID: String
    func makeCoordinator() -> Coordinator { Coordinator(appID: appID) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = context.coordinator
        view.navigationDelegate = context.coordinator
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        view.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: appID))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let appID: String
        init(appID: String) { self.appID = appID }
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            PermissionPrompt.shared.ask(appID: appID, type: type, completion: decisionHandler)
        }
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}

final class PermissionPrompt {
    static let shared = PermissionPrompt()
    private init() {}
    func ask(appID: String, type: WKMediaCaptureType, completion: @escaping (WKPermissionDecision) -> Void) {
        DispatchQueue.main.async {
            guard appID != "PREVIEW", let root = UIApplication.shared.keyRoot else { completion(.deny); return }
            let permission = type == .camera ? "camera" : type == .microphone ? "microphone" : "camera and microphone"
            let alert = UIAlertController(title: "Permission Request", message: "HTML app \(appID) wants access to the \(permission).", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in completion(.deny) })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in completion(.grant) })
            root.topPresentedController.present(alert, animated: true)
        }
    }
}

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0
    private let pages = [
        ("Welcome to HTMLApp", "rectangle.stack.badge.plus", "Save HTML as simple, user-facing apps on your iPhone.", "Tap the + button in the library to begin."),
        ("Create and preview", "chevron.left.forwardslash.chevron.right", "Paste or write HTML, add a searchable description, and preview before saving.", "HTMLApp reads the <title> and saves the page icon automatically."),
        ("Launch from Home Screen", "apps.iphone", "Hold an app and choose Install Home Screen Web Clip.", "iOS opens a profile installer. Review it, tap Install, and enter your passcode if requested."),
        ("Use deep links", "link", "Each app gets a unique six-character ID and htmlapp:// link.", "A Web Clip uses that link to open the correct saved app immediately."),
        ("Permissions stay controlled", "hand.raised.fill", "Camera and microphone requests receive an extra prompt identifying the saved app.", "Only import HTML and JavaScript you trust.")
    ]

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                if page > 0 { Button("Back") { withAnimation { page -= 1 } } }
                Spacer()
                Text("\(page + 1) of \(pages.count)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }.padding(.horizontal)
            ProgressView(value: Double(page + 1), total: Double(pages.count)).padding(.horizontal)
            Spacer()
            Image(systemName: pages[page].1).font(.system(size: 68)).symbolRenderingMode(.hierarchical)
            Text(pages[page].0).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(pages[page].2).font(.title3).multilineTextAlignment(.center)
            Text(pages[page].3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
            Button(page == pages.count - 1 ? "Open My Library" : "Continue") {
                if page == pages.count - 1 { complete = true }
                else { withAnimation { page += 1 } }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            if page < pages.count - 1 { Button("Skip Tutorial") { complete = true }.foregroundStyle(.secondary) }
        }.padding(.vertical, 24)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("sourceRefreshDays") private var sourceRefreshDays = 3
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @AppStorage("showAppIDs") private var showAppIDs = true
    @AppStorage("webClipFullScreen") private var webClipFullScreen = true
    @AppStorage("webClipPrecomposed") private var webClipPrecomposed = false
    @State private var refreshing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library Appearance") {
                    Picker("Layout", selection: $libraryLayout) {
                        Text("List").tag("list")
                        Text("Grid").tag("grid")
                    }.pickerStyle(.segmented)
                    Toggle("Show six-character IDs", isOn: $showAppIDs)
                }
                Section("Home Screen Web Clips") {
                    Toggle("Open full screen", isOn: $webClipFullScreen)
                    Toggle("Use precomposed icons", isOn: $webClipPrecomposed)
                    Text("Web Clip profiles use each app’s saved PNG icon and open htmlapp:// links.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("External Source Cache") {
                    Stepper("Refresh after \(sourceRefreshDays) days", value: $sourceRefreshDays, in: 1...30)
                    Button {
                        refreshing = true
                        Task {
                            for app in store.apps { await SourceCache.shared.refresh(app: app, force: true) }
                            refreshing = false
                        }
                    } label: { Label("Refresh All Sources", systemImage: "arrow.clockwise") }
                    .disabled(refreshing || store.apps.isEmpty)
                    Button(role: .destructive) { SourceCache.shared.clearAll() } label: { Label("Clear Source Cache", systemImage: "trash") }
                    Text("Older cached copies remain available when a refresh fails or the device is offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy and Permissions") {
                    Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                        Label("Open iOS App Permissions", systemImage: "hand.raised")
                    }
                    Text("HTMLApp adds a per-app prompt before WebKit camera or microphone access. iOS system permission still applies to HTMLApp as a whole.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Tutorial") {
                    Button { onboardingComplete = false; dismiss() } label: { Label("Replay Onboarding Tutorial", systemImage: "graduationcap") }
                }
                Section("Storage") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    Button("Delete Entire Library", role: .destructive) { confirmClear = true }.disabled(store.apps.isEmpty)
                }
                Section("About") {
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("URL scheme", value: "htmlapp://")
                    Text("Only import code you trust.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay {
                if refreshing { ProgressView("Refreshing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
            }
            .confirmationDialog("Delete every saved HTML app?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete Entire Library", role: .destructive) { store.clearLibrary() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This cannot be undone.") }
        }
    }
}

enum HTMLTools {
    static func title(in html: String) -> String? {
        capture("<title[^>]*>(.*?)</title>", text: html)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
    static func visibleText(in html: String) -> String {
        html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func externalURLs(in html: String) -> [URL] {
        let patterns = [
            "(?:src|href)=[\\\"'](https?://[^\\\"']+)[\\\"']",
            "url\\([\\\"']?(https?://[^)\\\"']+)[\\\"']?\\)"
        ]
        var urls = Set<URL>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: html),
                   let url = URL(string: String(html[range])) { urls.insert(url) }
            }
        }
        return Array(urls)
    }
    private static func capture(_ pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

actor SourceCache {
    static let shared = SourceCache()
    private let root: URL

    private init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    nonisolated func baseURL(appID: String) -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache/\(appID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func refresh(app: SavedHTMLApp, force: Bool) async {
        let folder = root.appendingPathComponent(app.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configured = UserDefaults.standard.integer(forKey: "sourceRefreshDays")
        let days = configured == 0 ? 3 : configured
        for url in HTMLTools.externalURLs(in: app.html) {
            let destination = folder.appendingPathComponent(filename(for: url))
            if !force,
               let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < Double(days * 86400) { continue }
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("HTMLApp/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { continue }
                try data.write(to: destination, options: .atomic)
            } catch {}
        }
    }

    nonisolated func remove(appID: String) { try? FileManager.default.removeItem(at: baseURL(appID: appID)) }
    nonisolated func clearAll() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    private func filename(for url: URL) -> String {
        let hash = url.absoluteString.utf8.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return String(hash, radix: 16) + "." + (url.pathExtension.isEmpty ? "resource" : url.pathExtension)
    }
}

enum SharePresenter {
    static func present(items: [Any]) {
        guard let root = UIApplication.shared.keyRoot else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        }
        root.topPresentedController.present(controller, animated: true)
    }
}

private extension UIApplication {
    var keyRoot: UIViewController? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    }
}

private extension UIViewController {
    var topPresentedController: UIViewController {
        if let presentedViewController { return presentedViewController.topPresentedController }
        if let nav = self as? UINavigationController { return nav.visibleViewController?.topPresentedController ?? nav }
        if let tab = self as? UITabBarController { return tab.selectedViewController?.topPresentedController ?? tab }
        return self
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
