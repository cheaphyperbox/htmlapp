import SwiftUI
import WebKit
import UIKit
import UniformTypeIdentifiers
import CoreMotion
import AVFoundation

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
            let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let starter = "<!doctype html>\n<html>\n<head>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n<title>My HTML App</title>\n<style>body{font-family:-apple-system;background:#111827;color:#fff;padding:24px}</style>\n</head>\n<body><h1>Hello</h1></body>\n</html>"
            _html = State(initialValue: clipboard.isEmpty ? starter : clipboard)
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
                    TextField("Optional description", text: $summary, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    TextEditor(text: $html)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 390)
                } header: { Text("HTML") } footer: {
                    Text("New apps automatically start with HTML from your clipboard when text is available. The name comes from <title> and icons are saved automatically.")
                }
            }
            .navigationTitle(mode.id == "new" ? "New HTML App" : "Edit HTML App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { previewing = false } } }
                }
            }
            .overlay { if saving { ProgressView().controlSize(.large) } }
        }
    }

    private func save() {
        saving = true
        Task {
            switch mode {
            case .new: await store.add(html: html, summary: summary)
            case .edit(let app):
                await store.update(app, html: html, summary: summary)
                store.clearAIEditHistory(for: app)
                ForgeStyleReferenceStore.clear(for: app.id)
            }
            saving = false
            dismiss()
        }
    }
}

struct WebRunner: View {
    let app: SavedHTMLApp
    @EnvironmentObject private var store: AppStore
    @AppStorage("closeOnFlipShake") private var closeOnFlipShake = false
    @State private var flipShakeCloser = FlipShakeClose()
    @AppStorage("htmlapp.carDisplay") private var carDisplay = false
    @State private var carWindow = false

    static func shouldHideStatusBar(in html: String) -> Bool {
        // The tag may use single/double quotes and either attribute order.
        // Match only within the meta tag, not in JS strings or app content.
        guard let regex = try? NSRegularExpression(pattern: "<meta\\\\b[^>]*>", options: .caseInsensitive) else { return false }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let value = ns.substring(with: match.range)
            let name = value.range(of: #"(?i)\\bname\\s*=\\s*['"]htmlapp-status-bar['"]"#, options: .regularExpression) != nil
            let hidden = value.range(of: #"(?i)\\bcontent\\s*=\\s*['"]hidden['"]"#, options: .regularExpression) != nil
            if name && hidden { return true }
        }
        return false
    }
    var body: some View {
        Group {
            if carDisplay || carWindow {
                HTMLWebView(html: app.html, appID: app.id)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack {
                            Button { store.runningApp = nil } label: {
                                Label("Apps", systemImage: "square.grid.2x2")
                                    .frame(minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            Text(app.name).font(.headline).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .background(.bar)
                    }
            } else {
                HTMLWebView(html: app.html, appID: app.id).ignoresSafeArea()
            }
        }
            .background(HTMLAppCarWindowProbe(isCarWindow: $carWindow))
            .statusBarHidden(carDisplay || carWindow || Self.shouldHideStatusBar(in: app.html))
            .htmlAppFirstUseToasts()
            .onAppear { HTMLAppFirstUseTips.show("open") }

    }
}

/// Applies a consistent CSS viewport on both iPhone and iPad while leaving
/// app-specific flex/grid layouts, fonts and breakpoints under the app's control.
enum HTMLAppResponsiveViewport {
    static let source = #"""
    (() => {
      const root = document.documentElement;
      if (!root) return;
      let viewport = document.querySelector('meta[name="viewport"]');
      if (!viewport) {
        viewport = document.createElement('meta');
        viewport.name = 'viewport';
        viewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover';
        document.head?.appendChild(viewport);
      } else if (!/width\s*=/.test(viewport.content || '')) {
        viewport.content += ', width=device-width';
      }
      // Preserve author-defined sizes, avoid WebKit's automatic text inflation.
      // Do not override user zoom, max-scale, or fixed-size layout rules.
      root.style.setProperty('-webkit-text-size-adjust', '100%');
      root.style.setProperty('text-size-adjust', '100%');
    })();
    """#
}

struct HTMLWebView: UIViewRepresentable {
    let html: String
    let appID: String
    var onJavaScriptError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(appID: appID, onJavaScriptError: onJavaScriptError) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = HTMLAppWebWarmup.pool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = UserDefaults.standard.object(forKey: "allowJavaScript") as? Bool ?? true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true

        let sensorPolicy = appID == "PREVIEW" ? "deny" : HTMLSensorPermissionPolicy.choice(appID: appID).rawValue
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: HTMLAppCarDisplay.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLAppCarDisplay.updateScript(enabled: UserDefaults.standard.bool(forKey: "htmlapp.carDisplay")),
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: PermissionBridgeScript.source(sensorPolicy: sensorPolicy),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: DownloadBridgeScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLNativeAPIScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        if appID == "PREVIEW" {
            controller.addUserScript(WKUserScript(
                source: HTMLAppPreviewTabs.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        controller.addUserScript(WKUserScript(
            source: HTMLAppWebBluetoothScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLLocalNetworkScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // WKWebView may enlarge text on narrow phones independently of CSS
        // media queries, causing transferred layouts to overflow or collide.
        // Normalize the viewport without rewriting or changing the app's HTML.
        controller.addUserScript(WKUserScript(
            source: HTMLAppResponsiveViewport.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.add(context.coordinator, name: "htmlappLocation")
        controller.add(context.coordinator, name: "htmlappNotificationPermission")
        controller.add(context.coordinator, name: "htmlappNotification")
        controller.add(context.coordinator, name: "htmlappHaptic")
        controller.add(context.coordinator, name: "htmlappSensorPermission")
        controller.add(context.coordinator, name: "htmlappDownload")
        controller.add(context.coordinator, name: "htmlappNative")
        controller.add(context.coordinator, name: "htmlappNetwork")
        if onJavaScriptError != nil {
            controller.add(context.coordinator, name: "htmlappRuntimeError")
            controller.addUserScript(WKUserScript(source: """
            (() => {
              const report = (kind, detail) => {
                try { window.webkit.messageHandlers.htmlappRuntimeError.postMessage({
                  kind: kind, detail: String(detail || "Unknown error").slice(0, 600)
                }); } catch (_) {}
              };
              window.addEventListener('error', e => report('JavaScript', e.message || e.error?.message), true);
              window.addEventListener('unhandledrejection', e => report('Promise', e.reason?.message || e.reason), true);
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        if let context = HTMLAppWidgetLaunchStore.take(appID: appID),
           let script = HTMLAppWidgetLaunchStore.javascript(for: context) {
            controller.addUserScript(WKUserScript(source: script,
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let webView = HTMLAppDisplayWebView(frame: .zero, configuration: configuration)
        HTMLAppWebWarmup.release()
        context.coordinator.attach(webView, initialHTML: html)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: appID))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: appID))
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        let controller = uiView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "htmlappLocation")
        controller.removeScriptMessageHandler(forName: "htmlappNotificationPermission")
        controller.removeScriptMessageHandler(forName: "htmlappNotification")
        controller.removeScriptMessageHandler(forName: "htmlappHaptic")
        controller.removeScriptMessageHandler(forName: "htmlappSensorPermission")
        controller.removeScriptMessageHandler(forName: "htmlappDownload")
        controller.removeScriptMessageHandler(forName: "htmlappNative")
        controller.removeScriptMessageHandler(forName: "htmlappNetwork")
        controller.removeScriptMessageHandler(forName: "htmlappRuntimeError")
        coordinator.shutdown()
        uiView.stopLoading()
        // After returning to the Library, warm the next WebContent process.
        if coordinator.appID != "PREVIEW" {
            Task { @MainActor in HTMLAppWebWarmup.prime() }
        }
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        private struct BlobTransfer {
            let url: URL
            let handle: FileHandle
        }

        let appID: String
        var onJavaScriptError: ((String) -> Void)?
        var lastHTML = ""
        private weak var webView: WKWebView?
        private var shakeExit: HTMLAppFaceDownShakeExit?
        private var nativePermissions: NativePermissionCoordinator?
        private var locationPermissions: HTMLLocationBridge?
        private var nativeBridge: HTMLNativeAPIBridge?
        private var localNetworkBridge: HTMLLocalNetworkBridge?
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        private var blobTransfers: [String: BlobTransfer] = [:]
        private var launchObserver: NSObjectProtocol?

        init(appID: String, onJavaScriptError: ((String) -> Void)?) {
            self.appID = appID
            self.onJavaScriptError = onJavaScriptError
        }

        func attach(_ webView: WKWebView, initialHTML: String) {
            self.webView = webView
            lastHTML = initialHTML
            if appID != "PREVIEW" {
                shakeExit = HTMLAppFaceDownShakeExit(webView: webView)
                shakeExit?.start()
            }
            nativePermissions = NativePermissionCoordinator(webView: webView, appID: appID)
            locationPermissions = HTMLLocationBridge(webView: webView, appID: appID)
            nativeBridge = HTMLNativeAPIBridge(webView: webView, appID: appID, permissionCoordinator: nativePermissions)
            localNetworkBridge = HTMLLocalNetworkBridge(webView: webView, permissionCoordinator: nativePermissions)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            (webView as? HTMLAppDisplayWebView)?.updateDisplay(force: true)
        }

        func shutdown() {
            if let launchObserver { NotificationCenter.default.removeObserver(launchObserver) }
            launchObserver = nil
            shakeExit?.stop()
            shakeExit = nil
            nativeBridge?.shutdown()
            nativeBridge = nil
            localNetworkBridge?.shutdown()
            localNetworkBridge = nil
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            nativePermissions?.requestMedia(type: type, completion: decisionHandler)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else { return nil }
            switch scheme {
            case "https", "http":
                // External windows open in the system browser, not in the
                // privileged HTMLApp WebView where native bridges exist.
                UIApplication.shared.open(url, options: [:])
            case "about":
                break
            default:
                // file:, javascript:, data:, custom and other schemes are not
                // automatically loaded into the privileged app context.
                break
            }
            return nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Any embedded third-party frame can otherwise invoke privileged
            // HTMLApp bridges, including reading clipboard or native data.
            // The installed app is the top-level document only.
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any] else { return }
            // The top-level HTMLApp document is loaded from its local
            // app-scoped WebView. If it navigates to an external origin, that
            // origin must never gain access to native message handlers.
            if let url = message.frameInfo.request.url,
               let scheme = url.scheme?.lowercased(),
               !["file", "about", "applewebdata"].contains(scheme) {
                return
            }
            switch message.name {
            case "htmlappLocation":
                guard let callbackID = body["id"] as? String else { return }
                let highAccuracy = body["highAccuracy"] as? Bool ?? false
                let timeout = body["timeout"] as? Double
                locationPermissions?.request(callbackID: callbackID, highAccuracy: highAccuracy, timeoutMS: timeout)

            case "htmlappNotificationPermission":
                guard let callbackID = body["id"] as? String else { return }
                nativePermissions?.requestNotificationPermission(callbackID: callbackID)

            case "htmlappNotification":
                let title = body["title"] as? String ?? "HTMLApp"
                let notificationBody = body["body"] as? String ?? ""
                let tag = body["tag"] as? String
                let silent = body["silent"] as? Bool ?? false
                nativePermissions?.sendNotification(title: title, body: notificationBody, tag: tag, silent: silent)

            case "htmlappHaptic":
                let values = body["pattern"] as? [Int] ?? [8]
                HTMLHapticsBridge.perform(pattern: values)

            case "htmlappSensorPermission":
                guard let callbackID = body["id"] as? String else { return }
                requestSensorPermission(callbackID: callbackID)

            case "htmlappDownload":
                handleDownloadMessage(body)

            case "htmlappNative":
                nativeBridge?.handle(body)

            case "htmlappNetwork":
                localNetworkBridge?.handle(body)

            case "htmlappRuntimeError":
                guard onJavaScriptError != nil else { return }
                let detail = (body["detail"] as? String ?? "Unknown error").prefix(600)
                let kind = (body["kind"] as? String ?? "JavaScript").prefix(30)
                onJavaScriptError?("\(kind): \(detail)")

            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               navigationAction.targetFrame?.isMainFrame == true,
               let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme) {
                // Never replace the privileged local document with a
                // third-party website carrying the same native bridges.
                UIApplication.shared.open(url, options: [:])
                decisionHandler(.cancel)
                return
            }
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            if let url = navigationAction.request.url,
               url.scheme?.lowercased() == "blob" {
                if let jsonData = try? JSONSerialization.data(withJSONObject: url.absoluteString),
                   let jsonURL = String(data: jsonData, encoding: .utf8) {
                    webView.evaluateJavaScript("window.__htmlappDownloadURL && window.__htmlappDownloadURL(\(jsonURL));")
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let disposition = (navigationResponse.response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?
                .lowercased() ?? ""
            if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let filename = Self.safeFilename(
                suggestedFilename,
                mimeType: response.mimeType
            )
            let url = Self.temporaryDownloadURL(filename: filename)
            try? FileManager.default.removeItem(at: url)
            downloadDestinations[ObjectIdentifier(download)] = url
            completionHandler(url)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            presentShareSheet(for: url)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            if let url = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        private func handleDownloadMessage(_ body: [String: Any]) {
            guard let action = body["action"] as? String,
                  let id = body["id"] as? String else { return }

            switch action {
            case "start":
                let rawName = body["filename"] as? String ?? "download"
                let mimeType = body["mimeType"] as? String
                let filename = Self.safeFilename(rawName, mimeType: mimeType)
                let url = Self.temporaryDownloadURL(filename: filename)
                try? FileManager.default.removeItem(at: url)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                blobTransfers[id] = BlobTransfer(url: url, handle: handle)

            case "chunk":
                guard let encoded = body["base64"] as? String,
                      let data = Data(base64Encoded: encoded),
                      let transfer = blobTransfers[id] else { return }
                do {
                    try transfer.handle.write(contentsOf: data)
                } catch {
                    try? transfer.handle.close()
                    try? FileManager.default.removeItem(at: transfer.url)
                    blobTransfers.removeValue(forKey: id)
                }

            case "finish":
                guard let transfer = blobTransfers.removeValue(forKey: id) else { return }
                try? transfer.handle.close()
                presentShareSheet(for: transfer.url)

            case "cancel":
                guard let transfer = blobTransfers.removeValue(forKey: id) else { return }
                try? transfer.handle.close()
                try? FileManager.default.removeItem(at: transfer.url)

            default:
                break
            }
        }

        private func presentShareSheet(for url: URL) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let presenter = self.topViewController() else { return }
                let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let popover = sheet.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(
                        x: presenter.view.bounds.midX,
                        y: presenter.view.bounds.midY,
                        width: 1,
                        height: 1
                    )
                    popover.permittedArrowDirections = []
                }
                sheet.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: url)
                }
                presenter.present(sheet, animated: true)
            }
        }

        private static func temporaryDownloadURL(filename: String) -> URL {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("HTMLAppDownloads", isDirectory: true)
            let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent(filename)
        }

        private static func safeFilename(_ raw: String, mimeType: String?) -> String {
            let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
            let cleaned = raw
                .components(separatedBy: forbidden)
                .joined(separator: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var filename = cleaned.isEmpty ? "download" : cleaned
            if URL(fileURLWithPath: filename).pathExtension.isEmpty,
               let mimeType,
               let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension,
               !ext.isEmpty {
                filename += ".\(ext)"
            }
            return String(filename.prefix(180))
        }

        private func requestSensorPermission(callbackID: String) {
            guard appID != "PREVIEW" else { resolveSensor(callbackID, value: "denied"); return }
            HTMLPermissionStore.markRequested("motionSensor", appID: appID)
            if HTMLSensorPermissionPolicy.choice(appID: appID) == .ask {
                switch PermissionRequestGate.check(appID: appID, permission: "motion") {
                case .ignore:
                    if PermissionRequestGate.hasPending(appID: appID, permission: "motion") {
                        _ = PermissionRequestGate.queue(appID: appID, permission: "motion") { [weak self] allowed in
                            self?.resolveSensor(callbackID, value: allowed ? "granted" : "denied")
                        }
                    } else { resolveSensor(callbackID, value: "denied") }
                    return
                case .autoDenied:
                    HTMLSensorPermissionPolicy.set(.deny, appID: appID)
                    PermissionRequestGate.finish(appID: appID, permission: "motion", allowed: false)
                    PermissionRequestGate.showNotice(appID: appID, title: "Motion")
                    resolveSensor(callbackID, value: "denied")
                    return
                case .proceed: break
                }
            }
            switch HTMLSensorPermissionPolicy.choice(appID: appID) {
            case .allow:
                resolveSensor(callbackID, value: "granted")
            case .deny:
                resolveSensor(callbackID, value: "denied")
            case .ask:
                guard PermissionRequestGate.queue(appID: appID, permission: "motion", completion: { [weak self] allowed in
                    self?.resolveSensor(callbackID, value: allowed ? "granted" : "denied")
                }) else { return }
                guard let presenter = topViewController() else {
                    PermissionRequestGate.finish(appID: appID, permission: "motion", allowed: false)
                    return
                }
                let alert = UIAlertController(
                    title: "Allow Motion & Orientation?",
                    message: "This saved HTML app wants access to device motion, orientation, and compass events while it is open.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in
                    HTMLSensorPermissionPolicy.set(.deny, appID: self.appID)
                    PermissionRequestGate.finish(appID: self.appID, permission: "motion", allowed: false)
                })
                alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                    let blocked = HTMLSensorPermissionPolicy.choice(appID: self.appID) == .deny
                    if !blocked { HTMLSensorPermissionPolicy.set(.allow, appID: self.appID) }
                    PermissionRequestGate.finish(appID: self.appID, permission: "motion", allowed: !blocked)
                })
                presenter.present(alert, animated: true)
            }
        }

        private func resolveSensor(_ callbackID: String, value: String) {
            guard let data = try? JSONSerialization.data(withJSONObject: [callbackID, value]),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.__htmlappSensorPermission.apply(null, \(json));")
        }

        private func topViewController() -> UIViewController? {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
            var current = root
            while let presented = current.presentedViewController { current = presented }
            if let navigation = current as? UINavigationController { return navigation.visibleViewController ?? navigation }
            if let tab = current as? UITabBarController { return tab.selectedViewController ?? tab }
            return current
        }
    }
}

enum PermissionBridgeScript {
    static func source(sensorPolicy: String) -> String {
        #"""
        (() => {
          if (window.__htmlappPermissionBridgeInstalled) return;
          window.__htmlappPermissionBridgeInstalled = true;

          const locationCallbacks = new Map();
          const locationWatches = new Map();
          let callbackCounter = 0;
          const makeID = (prefix) => `${prefix}-${Date.now()}-${++callbackCounter}`;
          const positionFromPayload = (payload) => ({
            coords: {
              latitude: payload.latitude,
              longitude: payload.longitude,
              accuracy: payload.accuracy,
              altitude: payload.altitude,
              altitudeAccuracy: payload.altitudeAccuracy,
              heading: payload.heading,
              speed: payload.speed
            },
            timestamp: payload.timestamp
          });

          const postLocation = (id, options) => {
            window.webkit.messageHandlers.htmlappLocation.postMessage({
              id,
              highAccuracy: !!options.enableHighAccuracy,
              timeout: Number.isFinite(options.timeout) ? options.timeout : 15000
            });
          };

          const issueWatch = (watchID) => {
            const watch = locationWatches.get(watchID);
            if (!watch) return;
            const callbackID = makeID('watchfix');
            watch.callbackID = callbackID;
            locationCallbacks.set(callbackID, { ...watch, watchID, isWatch: true });
            postLocation(callbackID, watch.options);
          };

          const scheduleWatch = (watchID, delay = 1000) => {
            const watch = locationWatches.get(watchID);
            if (!watch) return;
            clearTimeout(watch.timer);
            watch.timer = setTimeout(() => issueWatch(watchID), delay);
          };

          window.__htmlappLocationSuccess = (id, payload) => {
            const item = locationCallbacks.get(id);
            if (!item) return;
            locationCallbacks.delete(id);
            item.success(positionFromPayload(payload));
            if (item.isWatch && locationWatches.has(item.watchID)) scheduleWatch(item.watchID);
          };

          window.__htmlappLocationError = (id, code, message) => {
            const item = locationCallbacks.get(id);
            if (!item) return;
            locationCallbacks.delete(id);
            if (typeof item.error === 'function') item.error({ code, message });
            if (item.isWatch && locationWatches.has(item.watchID)) {
              if (code === 1) locationWatches.delete(item.watchID);
              else scheduleWatch(item.watchID, 1200);
            }
          };

          const geo = {
            getCurrentPosition(success, error, options = {}) {
              const id = makeID('geo');
              locationCallbacks.set(id, { success, error, options, isWatch: false });
              postLocation(id, options);
            },
            watchPosition(success, error, options = {}) {
              const watchID = makeID('watch');
              locationWatches.set(watchID, { success, error, options, timer: null, callbackID: null });
              issueWatch(watchID);
              return watchID;
            },
            clearWatch(watchID) {
              const watch = locationWatches.get(watchID);
              if (watch) {
                clearTimeout(watch.timer);
                if (watch.callbackID) locationCallbacks.delete(watch.callbackID);
              }
              locationWatches.delete(watchID);
            }
          };

          try { Object.defineProperty(navigator, 'geolocation', { configurable: true, value: geo }); } catch (_) {}

          try {
            Object.defineProperty(navigator, 'vibrate', {
              configurable: true,
              value: (input) => {
                if (navigator.userActivation && !navigator.userActivation.isActive) return false;
                const raw = Array.isArray(input) ? input : [input];
                const pattern = raw.slice(0, 12).map(v => Math.max(0, Math.min(1000, Math.round(Number(v) || 0))));
                window.webkit.messageHandlers.htmlappHaptic.postMessage({ pattern });
                return true;
              }
            });
          } catch (_) {}

          let htmlappSensorPolicy = "__SENSOR_POLICY__";
          const sensorCallbacks = new Map();
          window.__htmlappSensorPermission = (id, value) => {
            htmlappSensorPolicy = value === 'granted' ? 'allow' : 'deny';
            const callback = sensorCallbacks.get(id);
            if (callback) { sensorCallbacks.delete(id); callback(value); }
          };

          const nativeOrientationRequest = typeof DeviceOrientationEvent !== 'undefined' && DeviceOrientationEvent.requestPermission ? DeviceOrientationEvent.requestPermission.bind(DeviceOrientationEvent) : null;
          const nativeMotionRequest = typeof DeviceMotionEvent !== 'undefined' && DeviceMotionEvent.requestPermission ? DeviceMotionEvent.requestPermission.bind(DeviceMotionEvent) : null;

          const requestSensor = (nativeRequest) => {
            if (htmlappSensorPolicy === 'deny') return Promise.resolve('denied');
            if (htmlappSensorPolicy === 'allow') {
              return nativeRequest ? nativeRequest().catch(() => 'denied') : Promise.resolve('granted');
            }
            return new Promise((resolve) => {
              const id = makeID('sensor');
              sensorCallbacks.set(id, async (value) => {
                if (value !== 'granted') { resolve('denied'); return; }
                if (!nativeRequest) { resolve('granted'); return; }
                try { resolve(await nativeRequest()); } catch (_) { resolve('denied'); }
              });
              window.webkit.messageHandlers.htmlappSensorPermission.postMessage({ id });
            });
          };

          try {
            if (typeof DeviceOrientationEvent !== 'undefined') {
              DeviceOrientationEvent.requestPermission = () => requestSensor(nativeOrientationRequest);
            }
          } catch (_) {}
          try {
            if (typeof DeviceMotionEvent !== 'undefined') {
              DeviceMotionEvent.requestPermission = () => requestSensor(nativeMotionRequest);
            }
          } catch (_) {}

          window.htmlappCompassHeading = null;
          window.addEventListener('deviceorientation', (event) => {
            const heading = Number.isFinite(event.webkitCompassHeading) ? event.webkitCompassHeading : (Number.isFinite(event.alpha) ? (360 - event.alpha) % 360 : null);
            if (heading == null) return;
            window.htmlappCompassHeading = heading;
            window.dispatchEvent(new CustomEvent('htmlappcompass', { detail: { heading, accuracy: event.webkitCompassAccuracy ?? null } }));
          });

          const notificationCallbacks = new Map();
          let notificationPermission = 'default';
          window.__htmlappNotificationPermission = (id, value) => {
            notificationPermission = value;
            const callback = notificationCallbacks.get(id);
            if (callback) { notificationCallbacks.delete(id); callback(value); }
          };

          function HTMLAppNotification(title, options = {}) {
            if (!(this instanceof HTMLAppNotification)) return new HTMLAppNotification(title, options);
            this.title = String(title || 'HTMLApp');
            this.body = String(options.body || '');
            this.tag = String(options.tag || '');
            this.silent = !!options.silent;
            this.onclick = null;
            this.onshow = null;
            this.onerror = null;
            this.onclose = null;
            this.close = () => { if (typeof this.onclose === 'function') this.onclose(); };
            if (notificationPermission !== 'granted') {
              setTimeout(() => { if (typeof this.onerror === 'function') this.onerror(new Error('Notification permission not granted')); }, 0);
              return;
            }
            window.webkit.messageHandlers.htmlappNotification.postMessage({ title: this.title, body: this.body, tag: this.tag, silent: this.silent });
            setTimeout(() => { if (typeof this.onshow === 'function') this.onshow(); }, 0);
          }

          Object.defineProperty(HTMLAppNotification, 'permission', { configurable: true, get: () => notificationPermission });
          HTMLAppNotification.requestPermission = (callback) => new Promise((resolve) => {
            const id = makeID('notification');
            notificationCallbacks.set(id, (value) => {
              if (typeof callback === 'function') callback(value);
              resolve(value);
            });
            window.webkit.messageHandlers.htmlappNotificationPermission.postMessage({ id });
          });
          try { window.Notification = HTMLAppNotification; } catch (_) {}
        })();
        """#.replacingOccurrences(of: "__SENSOR_POLICY__", with: sensorPolicy)
    }
}

enum DownloadBridgeScript {
    static let source = #"""
    (() => {
      if (window.__htmlappDownloadBridgeInstalled) return;
      window.__htmlappDownloadBridgeInstalled = true;

      let sequence = 0;
      const handler = () => window.webkit?.messageHandlers?.htmlappDownload;

      const filenameFor = (url, preferred) => {
        const explicit = String(preferred || '').trim();
        if (explicit) return explicit;
        if (String(url).startsWith('blob:') || String(url).startsWith('data:')) return 'download';
        try {
          const parsed = new URL(url, document.baseURI);
          const last = decodeURIComponent(parsed.pathname.split('/').pop() || '');
          return last || 'download';
        } catch (_) {
          return 'download';
        }
      };

      const sendBlob = async (url, preferredName) => {
        const id = `blob-${Date.now()}-${++sequence}`;
        try {
          const response = await fetch(url);
          if (!response.ok && response.type !== 'opaque') throw new Error('Download request failed');
          const blob = await response.blob();
          handler()?.postMessage({
            action: 'start',
            id,
            filename: filenameFor(url, preferredName),
            mimeType: blob.type || ''
          });

          const bytes = new Uint8Array(await blob.arrayBuffer());
          const chunkSize = 196608;
          const sliceSize = 32768;
          for (let offset = 0; offset < bytes.length; offset += chunkSize) {
            const end = Math.min(bytes.length, offset + chunkSize);
            let binary = '';
            for (let cursor = offset; cursor < end; cursor += sliceSize) {
              const slice = bytes.subarray(cursor, Math.min(end, cursor + sliceSize));
              binary += String.fromCharCode.apply(null, slice);
            }
            handler()?.postMessage({ action: 'chunk', id, base64: btoa(binary) });
            await new Promise(resolve => setTimeout(resolve, 0));
          }
          handler()?.postMessage({ action: 'finish', id });
        } catch (_) {
          handler()?.postMessage({ action: 'cancel', id });
        }
      };

      window.__htmlappDownloadURL = (url, filename) => {
        if (!url) return false;
        sendBlob(String(url), filename);
        return true;
      };

      document.addEventListener('click', (event) => {
        const anchor = event.target?.closest?.('a');
        if (!anchor) return;
        const href = anchor.href || '';
        const isLocalPayload = href.startsWith('blob:') || href.startsWith('data:');
        if (!isLocalPayload) return;
        event.preventDefault();
        event.stopPropagation();
        sendBlob(href, anchor.getAttribute('download'));
      }, true);
    })();
    """#
}

private enum HTMLAppPreviewTabs {
    static let script = #"""
    (() => {
      const install = () => {
        const api = window.HTMLAppNative?.tabs;
        if (!api || api.__previewTabsInstalled) return;
        api.__previewTabsInstalled = true;
        const callbacks = new Map();
        let tabs = [];
        let active = '';
        let hidden = false;
        const style = document.createElement('style');
        style.textContent = '#__htmlappPreviewTabs{position:fixed;bottom:env(safe-area-inset-bottom,0px);left:0;right:0;z-index:2147483640;display:flex;justify-content:space-around;gap:4px;padding:9px 8px;background:rgba(30,30,30,.94);color:white;font:14px -apple-system,sans-serif}#__htmlappPreviewTabs button{flex:1;min-height:48px;background:transparent;color:inherit;border:0;border-radius:12px;font:inherit}#__htmlappPreviewTabs button[aria-selected=true]{background:#555}';
        const ready = () => {
          if (!document.head || !document.body) return false;
          if (!style.isConnected) document.head.appendChild(style);
          return true;
        };
        const select = id => {
          if (!tabs.some(t => t.id === id)) return false;
          active = id;
          document.querySelectorAll('#__htmlappPreviewTabs button').forEach(b => b.setAttribute('aria-selected', String(b.dataset.id === id)));
          window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select', {detail:{id}}));
          return true;
        };
        const render = () => {
          if (!ready()) { setTimeout(render, 30); return; }
          let bar = document.getElementById('__htmlappPreviewTabs');
          if (!bar) { bar = document.createElement('nav'); bar.id = '__htmlappPreviewTabs'; document.body.appendChild(bar); }
          bar.replaceChildren();
          tabs.forEach(t => {
            const button = document.createElement('button');
            button.type = 'button'; button.dataset.id = t.id;
            button.textContent = t.title || t.id;
            button.setAttribute('aria-selected', String(t.id === active));
            button.addEventListener('click', () => select(t.id));
            bar.appendChild(button);
          });
          bar.style.display = hidden ? 'none' : 'flex';
          document.documentElement.style.setProperty('--htmlapp-tabbar-height', hidden ? '0px' : '72px');
        };
        api.configure = async (input, options = {}) => {
          tabs = Array.isArray(input) ? input : (input?.items || []);
          callbacks.clear();
          tabs.forEach(t => { if (typeof t.onSelect === 'function') callbacks.set(t.id,t.onSelect); });
          api._handlers = Object.fromEntries(callbacks);
          active = options.selected || input?.selected || tabs[0]?.id || '';
          render();
          setTimeout(() => { if (active) select(active); }, 0);
          return {enabled:true,count:tabs.length,preview:true};
        };
        api.select = async id => ({selected:select(id) ? id : null});
        api.remove = async () => { tabs=[]; document.getElementById('__htmlappPreviewTabs')?.remove(); return {removed:true}; };
        api.setHidden = async value => { hidden=!!value; render(); return {hidden}; };
        api.update = async (id, props) => { const tab=tabs.find(t=>t.id===id); if(tab) Object.assign(tab,props); render(); return {updated:!!tab}; };
        api.pulse = async () => ({ok:true});
      };
      install();
    })();
    """#
}

@MainActor
private final class HTMLAppFaceDownShakeExit {
    private static var transitionOwner: HTMLAppFaceDownShakeExit?
    private weak var webView: WKWebView?
    private let motion = CMMotionManager()
    private let feedback = UIImpactFeedbackGenerator(style: .soft)
    private var progress: Double = 0
    private var lastTick: TimeInterval = 0
    private var lastHaptic: TimeInterval = 0
    private var finished = false
    private var progressTrack: UIView?
    private var progressFill: UIView?
    private var blackout: UIVisualEffectView?
    private var darkness: UIView?
    private var transitionWindow: UIWindow?
    private var torchDevice: AVCaptureDevice?
    private var lastGravityZ: Double = -1
    private var lastOrientationSample: TimeInterval = 0
    private var restingAngleDegrees: Double?
    private var fadeEndAngleDegrees: Double = 70

    init(webView: WKWebView) { self.webView = webView }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let sample else { return }
            Task { @MainActor in self?.update(sample) }
        }
    }

    func stop() {
        if finished && blackout != nil {
            // The transition continues after the web view is dismissed.
            Self.transitionOwner = self
            return
        }
        cleanup()
    }

    private func update(_ sample: CMDeviceMotion) {
        guard UIApplication.shared.applicationState == .active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = lastTick == 0 ? 0 : min(0.1, now - lastTick)
        lastTick = now
        lastGravityZ = sample.gravity.z
        if !finished && progress == 0 && sample.gravity.z <= 0.78 {
            let a = sample.userAcceleration
            let activity = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if activity < 0.12 && (lastOrientationSample == 0 || now - lastOrientationSample >= 3) {
                restingAngleDegrees = acos(max(-1, min(1, sample.gravity.z))) * 180 / .pi
                lastOrientationSample = now
            }
        }
        if finished {
            updateBlackout()
            return
        }
        let requiredSeconds = max(0.5, min(5, UserDefaults.standard.double(forKey: "htmlapp.shakeExitSeconds") == 0 ? 1 : UserDefaults.standard.double(forKey: "htmlapp.shakeExitSeconds")))
        let faceDown = sample.gravity.z > 0.78
        let a = sample.userAcceleration
        let shake = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
        // Shaking consists of brief acceleration peaks separated by near-zero
        // samples. Requiring 3.5 seconds of continuous acceleration made the
        // progress bar appear without ever reaching the exit threshold.
        if faceDown {
            if shake > 0.35 {
                progress = min(1, progress + delta * min(3.2, 1.4 + shake * 1.5) / (2.0 * requiredSeconds))
                if now - lastHaptic > max(0.09, 0.32 - progress * 0.2) {
                    feedback.impactOccurred(intensity: CGFloat(0.2 + progress * 0.8))
                    lastHaptic = now
                }
            } else {
                // Preserve credit between the short impulses of one shake.
                progress = max(0, progress - delta * 0.10)
            }
        } else {
            progress = max(0, progress - delta * 1.5)
        }
        if progress > 0 { showProgress() }
        progressFill?.frame.size.width = (progressTrack?.bounds.width ?? 0) * progress
        progressTrack?.alpha = faceDown && progress > 0 ? 1 : 0
        if progress >= 1 { completeExit() }
    }

    private func showProgress() {
        guard progressTrack == nil, let window = webView?.window else { return }
        let track = UIView(frame: CGRect(x: 16, y: window.safeAreaInsets.top + 8,
                                         width: max(1, window.bounds.width - 32), height: 4))
        track.backgroundColor = UIColor.white.withAlphaComponent(0.28)
        track.layer.cornerRadius = 2
        track.clipsToBounds = true
        track.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        let fill = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 4))
        fill.backgroundColor = .systemOrange
        track.addSubview(fill)
        window.addSubview(track)
        progressTrack = track
        progressFill = fill
    }

    private func completeExit() {
        guard !finished, let webView, let sourceWindow = webView.window,
              let scene = sourceWindow.windowScene else { return }
        let configuredAngle = UserDefaults.standard.double(forKey: "htmlapp.shakeFadeEndAngle")
        let fallbackAngle = max(20, min(180, configuredAngle == 0 ? 70 : configuredAngle))
        fadeEndAngleDegrees = restingAngleDegrees.map { max(20, min(170, $0 - 10)) } ?? fallbackAngle
        finished = true
        progressTrack?.removeFromSuperview()
        progressTrack = nil
        progressFill = nil

        // A separate, non-key overlay window stays visible when SwiftUI removes
        // the fullScreenCover's view hierarchy. Attaching to the old window
        // could place the fade underneath the library or remove it on dismiss.
        let overlay = UIWindow(windowScene: scene)
        overlay.frame = sourceWindow.bounds
        overlay.windowLevel = .alert + 1
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        let host = UIViewController()
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        blur.frame = host.view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let dark = UIView(frame: host.view.bounds)
        dark.backgroundColor = .black
        dark.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(blur)
        host.view.addSubview(dark)
        overlay.isHidden = false
        transitionWindow = overlay
        blackout = blur
        darkness = dark
        blur.alpha = 1
        dark.alpha = 1
        Self.transitionOwner = self

        NotificationCenter.default.post(name: Notification.Name("HTMLApp.FaceDownShakeExit"), object: nil)
        // Start the torch after the cover is dismissed, not while its
        // WebKit capture session might still own the camera.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            // Retain the transition through the flash even when the user
            // rotates upright immediately and the overlay has been removed.
            flashTorch()
            if blackout != nil { updateBlackout() }
        }
    }

    private func updateBlackout() {
        // z=+1 is face down; z=0 is 90 degrees; z=-1 is face up.
        // Fade fully by roughly 70 degrees of rotation from face down.
        let configuredAngle = UserDefaults.standard.double(forKey: "htmlapp.shakeFadeEndAngle")
        let endAngle = max(20, min(180, configuredAngle == 0 ? 70 : configuredAngle))
        let endGravity = cos(fadeEndAngleDegrees * .pi / 180)
        let fraction = CGFloat(max(0, min(1, (lastGravityZ - endGravity) / (1 - endGravity))))
        let eased = fraction * fraction * (3 - 2 * fraction)
        darkness?.alpha = eased
        blackout?.alpha = eased
        if fraction <= 0.01 {
            cleanup()
            Self.transitionOwner = nil
        }
    }

    private func flashTorch() {
        // Explicitly request the rear torch; .default(for: .video) may choose
        // a camera without a torch on multi-camera devices.
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            guard device.isTorchAvailable else {
                device.unlockForConfiguration()
                return
            }
            // Ambient lux is not exposed through a public iOS API; use a low, fixed intensity.
            try device.setTorchModeOn(level: min(AVCaptureDevice.maxAvailableTorchLevel, 0.05))
            device.unlockForConfiguration()
            torchDevice = device
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.turnOffTorch()
            }
        } catch {
            NSLog("HTMLApp exit torch unavailable: %@", error.localizedDescription)
        }
    }

    private func turnOffTorch() {
        guard let device = torchDevice else { return }
        torchDevice = nil
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            NSLog("HTMLApp could not disable exit torch: %@", error.localizedDescription)
        }
    }

    private func cleanup() {
        motion.stopDeviceMotionUpdates()
        progressTrack?.removeFromSuperview()
        blackout?.removeFromSuperview()
        darkness?.removeFromSuperview()
        transitionWindow?.isHidden = true
        transitionWindow?.rootViewController = nil
        transitionWindow = nil
        progressTrack = nil
        progressFill = nil
        blackout = nil
        darkness = nil
    }
}

