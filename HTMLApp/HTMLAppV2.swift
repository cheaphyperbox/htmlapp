import SwiftUI
import WebKit

@main
struct HTMLAppMain: App {
    @StateObject private var store = AppStore()
    @AppStorage("onboardingComplete") private var onboardingComplete = false

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
    }

    func add(html: String, summary: String) async {
        let now = Date()
        let app = SavedHTMLApp(
            id: makeID(),
            name: HTMLTools.title(in: html) ?? "Untitled App",
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html,
            favicon: await HTMLTools.favicon(in: html),
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: nil
        )
        apps.insert(app, at: 0)
        save()
        await SourceCache.shared.refresh(app: app, force: false)
    }

    func update(_ app: SavedHTMLApp, html: String, summary: String) async {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].html = html
        apps[index].name = HTMLTools.title(in: html) ?? app.name
        apps[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[index].favicon = await HTMLTools.favicon(in: html) ?? app.favicon
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
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let app = apps.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame })
        else {
            errorMessage = "No saved HTML app matched that URL."
            return
        }
        launch(app)
    }

    func results(for query: String) -> [SavedHTMLApp] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            return $0.1 > $1.1
        }
        .map { $0.0 }
    }

    private func makeID() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var candidate = ""
        repeat {
            candidate = String((0..<6).compactMap { _ in alphabet.randomElement() })
        } while apps.contains(where: { $0.id == candidate })
        return candidate
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
    @State private var searchText = ""
    @State private var editor: EditorMode?
    @State private var showSettings = false
    @State private var pendingDelete: SavedHTMLApp?
    @State private var refreshingID: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty {
                    EmptyState(title: "No HTML Apps", systemImage: "chevron.left.forwardslash.chevron.right", message: "Tap + to paste or write an HTML app.")
                } else if store.results(for: searchText).isEmpty {
                    EmptyState(title: "No Results", systemImage: "magnifyingglass", message: "No saved app matched your search.")
                } else {
                    List(store.results(for: searchText)) { app in
                        Button {
                            store.launch(app)
                        } label: {
                            AppRow(app: app, refreshing: refreshingID == app.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Update HTML") { editor = .edit(app) }
                            Button("Copy HTML") { UIPasteboard.general.string = app.html }
                            Button("Copy ID") { UIPasteboard.general.string = app.id }
                            Button("Copy URL Scheme") { UIPasteboard.general.string = "htmlapp://open?id=\(app.id)" }
                            Button("Duplicate") { store.duplicate(app) }
                            Button("Refresh External Sources") {
                                refreshingID = app.id
                                Task {
                                    await SourceCache.shared.refresh(app: app, force: true)
                                    await MainActor.run { refreshingID = nil }
                                }
                            }
                            Divider()
                            Button("Delete HTML App", role: .destructive) { pendingDelete = app }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("HTMLApp")
            .searchable(text: $searchText, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editor = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add HTML App")
                }
            }
            .sheet(item: $editor) { mode in
                EditorView(mode: mode).environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store)
            }
            .confirmationDialog(
                "Delete this HTML app?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let app = pendingDelete { store.delete(app) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The HTML, metadata, settings, and cached sources will be removed.")
            }
            .alert("HTMLApp", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

struct EmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

struct AppRow: View {
    let app: SavedHTMLApp
    let refreshing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = app.favicon, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .resizable().scaledToFit().padding(10)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline).lineLimit(1)
                if !app.summary.isEmpty {
                    Text(app.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if refreshing { ProgressView() }
            else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}

enum EditorMode: Identifiable {
    case new
    case edit(SavedHTMLApp)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let app): return app.id
        }
    }
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
            _html = State(initialValue: "<!doctype html>\n<html>\n<head>\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>My HTML App</title>\n</head>\n<body>\n  <h1>Hello</h1>\n</body>\n</html>")
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
                    TextField("Optional description", text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("HTML") {
                    TextEditor(text: $html)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 360)
                }
            }
            .navigationTitle(mode.id == "new" ? "Add HTML App" : "Update HTML App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Preview") { previewing = true }.disabled(html.isEmpty)
                    Button("Save") { save() }
                        .disabled(html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .sheet(isPresented: $previewing) {
                NavigationStack {
                    HTMLWebView(html: html, appID: "PREVIEW")
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { previewing = false }
                            }
                        }
                }
            }
            .overlay {
                if saving { ProgressView().controlSize(.large) }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            switch mode {
            case .new:
                await store.add(html: html, summary: summary)
            case .edit(let app):
                await store.update(app, html: html, summary: summary)
            }
            saving = false
            dismiss()
        }
    }
}

struct WebRunner: View {
    let app: SavedHTMLApp

    var body: some View {
        HTMLWebView(html: app.html, appID: app.id)
            .statusBarHidden(true)
    }
}

struct HTMLWebView: UIViewRepresentable {
    let html: String
    let appID: String

    func makeCoordinator() -> Coordinator { Coordinator(appID: appID) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: appID))
        return webView
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
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

final class PermissionPrompt {
    static let shared = PermissionPrompt()
    private init() {}

    func ask(appID: String, type: WKMediaCaptureType, completion: @escaping (WKPermissionDecision) -> Void) {
        DispatchQueue.main.async {
            guard appID != "PREVIEW",
                  let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else {
                completion(.deny)
                return
            }

            let permission: String
            switch type {
            case .camera: permission = "camera"
            case .microphone: permission = "microphone"
            case .cameraAndMicrophone: permission = "camera and microphone"
            @unknown default: permission = "media capture"
            }

            let alert = UIAlertController(
                title: "Permission Request",
                message: "HTML app \(appID) wants access to the \(permission).",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in completion(.deny) })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in completion(.grant) })
            root.topPresentedController.present(alert, animated: true)
        }
    }
}

private extension UIViewController {
    var topPresentedController: UIViewController {
        if let presentedViewController { return presentedViewController.topPresentedController }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topPresentedController ?? navigation
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topPresentedController ?? tab
        }
        return self
    }
}

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0

    private let pages = [
        ("HTMLApp", "chevron.left.forwardslash.chevron.right", "Save HTML as user-facing apps and launch them in a full-screen viewer."),
        ("Private Library", "externaldrive", "Each saved app receives a unique six-character ID and stays in your on-device library."),
        ("Permission Controls", "hand.raised", "Sensitive access requires iOS approval and an additional prompt for the requesting HTML app."),
        ("Deep Links", "link", "Open a saved app using htmlapp://open?id=123456.")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: pages[page].1).font(.system(size: 62))
            Text(pages[page].0).font(.largeTitle.bold())
            Text(pages[page].2)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
            Spacer()
            Button(page == pages.count - 1 ? "Start Using HTMLApp" : "Continue") {
                if page == pages.count - 1 { complete = true }
                else { withAnimation { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 30)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("sourceRefreshDays") private var sourceRefreshDays = 3
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    Button("Refresh All External Sources") {
                        refreshing = true
                        Task {
                            for app in store.apps {
                                await SourceCache.shared.refresh(app: app, force: true)
                            }
                            refreshing = false
                        }
                    }
                    .disabled(refreshing || store.apps.isEmpty)
                    Button("Clear All Source Caches", role: .destructive) {
                        SourceCache.shared.clearAll()
                    }
                }
                Section("Caching") {
                    Stepper("Refresh after \(sourceRefreshDays) days", value: $sourceRefreshDays, in: 1...30)
                    Text("If refreshing fails or the device is offline, the previous cached copy is preserved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Onboarding") {
                    Button("Show Onboarding Again") {
                        onboardingComplete = false
                        dismiss()
                    }
                }
                Section("About") {
                    LabeledContent("Minimum iOS", value: "16.0")
                    Text("Only import HTML and JavaScript you trust. Review every permission prompt carefully.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if refreshing { ProgressView() }
            }
        }
    }
}

enum HTMLTools {
    static func title(in html: String) -> String? {
        capture("<title[^>]*>(.*?)</title>", text: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    static func visibleText(in html: String) -> String {
        html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func favicon(in html: String) async -> Data? {
        let patterns = [
            "<link[^>]+rel=[\\\"'][^\\\"']*(?:icon|apple-touch-icon)[^\\\"']*[\\\"'][^>]+href=[\\\"']([^\\\"']+)[\\\"']",
            "<link[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]+rel=[\\\"'][^\\\"']*(?:icon|apple-touch-icon)[^\\\"']*[\\\"']"
        ]
        guard let value = patterns.compactMap({ capture($0, text: html) }).first else { return nil }
        if value.hasPrefix("data:image"), let comma = value.firstIndex(of: ",") {
            return Data(base64Encoded: String(value[value.index(after: comma)...]))
        }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    static func externalURLs(in html: String) -> [URL] {
        let patterns = [
            "(?:src|href)=[\\\"'](https?://[^\\\"']+)[\\\"']",
            "url\\([\\\"']?(https?://[^)\\\"']+)[\\\"']?\\)"
        ]
        var urls = Set<URL>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1,
                      let matchRange = Range(match.range(at: 1), in: html),
                      let url = URL(string: String(html[matchRange]))
                else { continue }
                urls.insert(url)
            }
        }
        return Array(urls)
    }

    private static func capture(_ pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
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
        let configuredDays = UserDefaults.standard.integer(forKey: "sourceRefreshDays")
        let days = configuredDays == 0 ? 3 : configuredDays
        let maximumAge = TimeInterval(days * 86_400)

        for url in HTMLTools.externalURLs(in: app.html) {
            let destination = folder.appendingPathComponent(filename(for: url))
            if !force,
               let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < maximumAge {
                continue
            }

            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("HTMLApp/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { continue }
                try data.write(to: destination, options: .atomic)
            } catch {
                // Preserve the previous cache when offline or when a refresh fails.
            }
        }
    }

    nonisolated func remove(appID: String) {
        try? FileManager.default.removeItem(at: baseURL(appID: appID))
    }

    nonisolated func clearAll() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func filename(for url: URL) -> String {
        let hash = url.absoluteString.utf8.reduce(UInt64(1469598103934665603)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        let ext = url.pathExtension.isEmpty ? "resource" : url.pathExtension
        return String(hash, radix: 16) + "." + ext
    }
}
