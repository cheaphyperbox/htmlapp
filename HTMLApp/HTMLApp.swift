import SwiftUI
import WebKit
import UniformTypeIdentifiers

@main
struct HTMLAppMain: App {
    @StateObject private var store = HTMLAppStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .fullScreenCover(item: $store.runningApp) { app in
                    HTMLRunnerView(app: app)
                        .ignoresSafeArea()
                        .interactiveDismissDisabled(true)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if !$0 { hasCompletedOnboarding = true } }
                )) {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
                        .interactiveDismissDisabled(true)
                }
                .onOpenURL { url in
                    store.openDeepLink(url)
                }
        }
    }
}

struct HTMLAppRecord: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var appDescription: String
    var html: String
    var faviconData: Data?
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var permissionRules: [String: PermissionRule]

    var searchableBodyText: String {
        HTMLMetadata.visibleText(from: html)
    }
}

enum PermissionRule: String, Codable, CaseIterable {
    case ask
    case allow
    case deny
}

@MainActor
final class HTMLAppStore: ObservableObject {
    @Published private(set) var apps: [HTMLAppRecord] = []
    @Published var runningApp: HTMLAppRecord?
    @Published var lastError: String?

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library.json")
        load()
    }

    func add(html: String, description: String) async {
        let id = makeUniqueID()
        let name = HTMLMetadata.title(from: html) ?? "Untitled App"
        let favicon = await HTMLMetadata.faviconData(from: html)
        let now = Date()
        let record = HTMLAppRecord(
            id: id,
            name: name,
            appDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            html: html,
            faviconData: favicon,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: nil,
            permissionRules: [:]
        )
        apps.insert(record, at: 0)
        save()
        await SourceCache.shared.refreshSources(for: record, force: false)
    }

    func update(_ record: HTMLAppRecord, html: String, description: String) async {
        guard let index = apps.firstIndex(where: { $0.id == record.id }) else { return }
        apps[index].html = html
        apps[index].name = HTMLMetadata.title(from: html) ?? record.name
        apps[index].appDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[index].faviconData = await HTMLMetadata.faviconData(from: html) ?? record.faviconData
        apps[index].updatedAt = Date()
        save()
        await SourceCache.shared.refreshSources(for: apps[index], force: false)
    }

    func delete(_ record: HTMLAppRecord) {
        apps.removeAll { $0.id == record.id }
        save()
        SourceCache.shared.removeCache(for: record.id)
    }

    func duplicate(_ record: HTMLAppRecord) {
        var copy = record
        copy.id = makeUniqueID()
        copy.name += " Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastOpenedAt = nil
        apps.insert(copy, at: 0)
        save()
    }

    func launch(_ record: HTMLAppRecord) {
        guard let index = apps.firstIndex(where: { $0.id == record.id }) else { return }
        apps[index].lastOpenedAt = Date()
        save()
        runningApp = apps[index]
    }

    func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "htmlapp",
              url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestedID = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let app = apps.first(where: { $0.id.caseInsensitiveCompare(requestedID) == .orderedSame })
        else {
            lastError = "No saved HTML app matched that link."
            return
        }
        launch(app)
    }

    func rankedResults(for query: String) -> [HTMLAppRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return apps }

        return apps.compactMap { app -> (HTMLAppRecord, Int)? in
            let name = app.name.lowercased()
            let description = app.appDescription.lowercased()
            let body = app.searchableBodyText.lowercased()
            let score: Int
            if name == q { score = 600 }
            else if name.hasPrefix(q) { score = 500 }
            else if name.contains(q) { score = 400 }
            else if description.contains(q) { score = 300 }
            else if body.contains(q) { score = 200 }
            else if app.html.lowercased().contains(q) { score = 100 }
            else { return nil }
            return (app, score)
        }
        .sorted {
            if $0.1 == $1.1 { return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
            return $0.1 > $1.1
        }
        .map(\.0)
    }

    private func makeUniqueID() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        repeat {
            result = String((0..<6).compactMap { _ in characters.randomElement() })
        } while apps.contains(where: { $0.id == result })
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            apps = try JSONDecoder().decode([HTMLAppRecord].self, from: data)
        } catch {
            lastError = "The saved library could not be loaded."
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(apps).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Changes could not be saved."
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: HTMLAppStore
    @State private var query = ""
    @State private var editorMode: EditorMode?
    @State private var showSettings = false
    @State private var deletingApp: HTMLAppRecord?
    @State private var refreshingID: String?

    private var results: [HTMLAppRecord] { store.rankedResults(for: query) }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty {
                    ContentUnavailableView(
                        "No HTML Apps",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        description: Text("Tap + to paste or write an HTML app.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { app in
                        Button {
                            store.launch(app)
                        } label: {
                            HTMLAppRow(app: app, isRefreshing: refreshingID == app.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Update HTML", systemImage: "pencil") { editorMode = .edit(app) }
                            Button("Copy HTML", systemImage: "doc.on.doc") { UIPasteboard.general.string = app.html }
                            Button("Copy ID", systemImage: "number") { UIPasteboard.general.string = app.id }
                            Button("Copy URL Scheme", systemImage: "link") { UIPasteboard.general.string = "htmlapp://open?id=\(app.id)" }
                            Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(app) }
                            Button("Refresh External Sources", systemImage: "arrow.clockwise") {
                                refreshingID = app.id
                                Task {
                                    await SourceCache.shared.refreshSources(for: app, force: true)
                                    await MainActor.run { refreshingID = nil }
                                }
                            }
                            Divider()
                            Button("Delete HTML App", systemImage: "trash", role: .destructive) { deletingApp = app }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("HTMLApp")
            .searchable(text: $query, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { editorMode = .new }
                }
            }
            .sheet(item: $editorMode) { mode in
                HTMLEditorView(mode: mode)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
            }
            .confirmationDialog(
                "Delete this HTML app?",
                isPresented: Binding(get: { deletingApp != nil }, set: { if !$0 { deletingApp = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deletingApp { store.delete(deletingApp) }
                    deletingApp = nil
                }
                Button("Cancel", role: .cancel) { deletingApp = nil }
            } message: {
                Text("Its saved HTML, favicon, settings, and cached sources will be removed.")
            }
            .alert("HTMLApp", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }
}

struct HTMLAppRow: View {
    let app: HTMLAppRecord
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = app.faviconData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .resizable().scaledToFit().padding(10)
                }
            }
            .frame(width: 44, height: 44)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline).lineLimit(1)
                if !app.appDescription.isEmpty {
                    Text(app.appDescription).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(app.id).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            Spacer()
            if isRefreshing { ProgressView() }
            else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}

enum EditorMode: Identifiable {
    case new
    case edit(HTMLAppRecord)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let app): return app.id
        }
    }
}

struct HTMLEditorView: View {
    @EnvironmentObject private var store: HTMLAppStore
    @Environment(\.dismiss) private var dismiss
    let mode: EditorMode
    @State private var html: String
    @State private var description: String
    @State private var saving = false
    @State private var showPreview = false

    init(mode: EditorMode) {
        self.mode = mode
        switch mode {
        case .new:
            _html = State(initialValue: "<!doctype html>\n<html>\n<head>\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>My HTML App</title>\n</head>\n<body>\n  <h1>Hello</h1>\n</body>\n</html>")
            _description = State(initialValue: "")
        case .edit(let app):
            _html = State(initialValue: app.html)
            _description = State(initialValue: app.appDescription)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("Optional description", text: $description, axis: .vertical)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Preview") { showPreview = true }.disabled(html.isEmpty)
                    Button("Save") { save() }.disabled(html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .sheet(isPresented: $showPreview) {
                NavigationStack {
                    HTMLWebView(html: html, appID: "PREVIEW")
                        .navigationTitle("Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { showPreview = false } }
                }
            }
            .overlay { if saving { ProgressView().controlSize(.large) } }
        }
    }

    private func save() {
        saving = true
        Task {
            switch mode {
            case .new:
                await store.add(html: html, description: description)
            case .edit(let app):
                await store.update(app, html: html, description: description)
            }
            saving = false
            dismiss()
        }
    }
}

struct HTMLRunnerView: View {
    let app: HTMLAppRecord

    var body: some View {
        HTMLWebView(html: app.html, appID: app.id)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}

struct HTMLWebView: UIViewRepresentable {
    let html: String
    let appID: String

    func makeCoordinator() -> Coordinator { Coordinator(appID: appID) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.uiDelegate = context.coordinator
        view.navigationDelegate = context.coordinator
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        view.isInspectable = false
        view.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(for: appID))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let appID: String
        init(appID: String) { self.appID = appID }

        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let key: String
            switch type {
            case .camera: key = "camera"
            case .microphone: key = "microphone"
            case .cameraAndMicrophone: key = "cameraAndMicrophone"
            @unknown default: key = "media"
            }
            PermissionCenter.shared.request(appID: appID, permission: key, decisionHandler: decisionHandler)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}

final class PermissionCenter {
    static let shared = PermissionCenter()
    private init() {}

    func request(appID: String, permission: String, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        DispatchQueue.main.async {
            guard appID != "PREVIEW",
                  let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let presenter = scene.keyWindow?.rootViewController?.topPresenter
            else {
                decisionHandler(.deny)
                return
            }

            let alert = UIAlertController(
                title: "Permission Request",
                message: "HTML app \(appID) wants access to \(permission). This decision currently applies for this session.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in decisionHandler(.deny) })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in decisionHandler(.grant) })
            presenter.present(alert, animated: true)
        }
    }
}

private extension UIViewController {
    var topPresenter: UIViewController {
        if let presentedViewController { return presentedViewController.topPresenter }
        if let navigation = self as? UINavigationController { return navigation.visibleViewController?.topPresenter ?? navigation }
        if let tab = self as? UITabBarController { return tab.selectedViewController?.topPresenter ?? tab }
        return self
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("HTMLApp", "chevron.left.forwardslash.chevron.right", "Save HTML as user-facing apps and launch each one in a full-screen viewer."),
        ("Local Library", "externaldrive", "Every saved app receives a unique six-character ID and remains available in your private on-device library."),
        ("Permissions", "hand.raised", "Camera, microphone, location, and other sensitive capabilities require both iOS permission and approval for the requesting HTML app."),
        ("Deep Links", "link", "Open a saved app using htmlapp://open?id=123456. You can copy the exact link from its context menu.")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: pages[page].1).font(.system(size: 64)).symbolRenderingMode(.hierarchical)
            Text(pages[page].0).font(.largeTitle.bold())
            Text(pages[page].2).font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 30)
            Spacer()
            Button(page == pages.count - 1 ? "Start Using HTMLApp" : "Continue") {
                if page == pages.count - 1 { isComplete = true }
                else { withAnimation { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 30)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: HTMLAppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("refreshAfterDays") private var refreshAfterDays = 3
    @State private var clearing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    Button("Refresh All External Sources") {
                        clearing = true
                        Task {
                            for app in store.apps { await SourceCache.shared.refreshSources(for: app, force: true) }
                            clearing = false
                        }
                    }
                    .disabled(clearing || store.apps.isEmpty)
                    Button("Clear All Source Caches", role: .destructive) { SourceCache.shared.clearAll() }
                }
                Section("Caching") {
                    Stepper("Refresh after \(refreshAfterDays) days", value: $refreshAfterDays, in: 1...30)
                    Text("Cached static sources remain usable when an update fails or the device is offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Onboarding") {
                    Button("Show Onboarding Again") {
                        hasCompletedOnboarding = false
                        dismiss()
                    }
                }
                Section("About") {
                    LabeledContent("App", value: "HTMLApp")
                    LabeledContent("Minimum iOS", value: "16.0")
                    Text("Arbitrary HTML and JavaScript can be unsafe. Only import code you trust and review permission prompts carefully.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .overlay { if clearing { ProgressView() } }
        }
    }
}

enum HTMLMetadata {
    static func title(from html: String) -> String? {
        firstCapture(pattern: "<title[^>]*>(.*?)</title>", in: html)?
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    static func visibleText(from html: String) -> String {
        html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func faviconData(from html: String) async -> Data? {
        guard let href = firstCapture(pattern: "<link[^>]+rel=[\\\"'][^\\\"']*(?:icon|apple-touch-icon)[^\\\"']*[\\\"'][^>]+href=[\\\"']([^\\\"']+)[\\\"']", in: html)
                ?? firstCapture(pattern: "<link[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]+rel=[\\\"'][^\\\"']*(?:icon|apple-touch-icon)[^\\\"']*[\\\"']", in: html)
        else { return nil }

        if href.hasPrefix("data:image"), let comma = href.firstIndex(of: ",") {
            let payload = String(href[href.index(after: comma)...])
            return Data(base64Encoded: payload)
        }
        guard let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    static func externalURLs(from html: String) -> [URL] {
        let patterns = [
            "(?:src|href)=[\\\"'](https?://[^\\\"']+)[\\\"']",
            "url\\([\\\"']?(https?://[^)\\\"']+)[\\\"']?\\)"
        ]
        var values = Set<URL>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1, let swiftRange = Range(match.range(at: 1), in: html), let url = URL(string: String(html[swiftRange])) else { continue }
                values.insert(url)
            }
        }
        return Array(values)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

actor SourceCache {
    static let shared = SourceCache()
    private let root: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    nonisolated func baseURL(for appID: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("HTMLApp/SourceCache/\(appID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func refreshSources(for app: HTMLAppRecord, force: Bool) async {
        let directory = root.appendingPathComponent(app.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let maxAge = TimeInterval(UserDefaults.standard.integer(forKey: "refreshAfterDays").nonZero(or: 3) * 86_400)

        for url in HTMLMetadata.externalURLs(from: app.html) {
            let name = stableFilename(for: url)
            let destination = directory.appendingPathComponent(name)
            if !force,
               let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < maxAge { continue }

            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("HTMLApp/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { continue }
                try data.write(to: destination, options: .atomic)
            } catch {
                // Keep the previous cached file when offline or when refresh fails.
            }
        }
    }

    nonisolated func removeCache(for appID: String) {
        try? FileManager.default.removeItem(at: baseURL(for: appID))
    }

    nonisolated func clearAll() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func stableFilename(for url: URL) -> String {
        let bytes = Array(url.absoluteString.utf8)
        let hash = bytes.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let ext = url.pathExtension.isEmpty ? "resource" : url.pathExtension
        return String(hash, radix: 16) + "." + ext
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
