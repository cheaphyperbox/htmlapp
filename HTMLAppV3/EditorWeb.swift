import SwiftUI
import WebKit
import UIKit

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
            _html = State(initialValue: "<!doctype html>\n<html>\n<head>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>My HTML App</title>\n<style>body{font-family:-apple-system;background:#111827;color:#fff;padding:24px}</style>\n</head>\n<body><h1>Hello</h1></body>\n</html>")
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
                    Text("The name comes from <title>. A favicon is saved as a PNG; otherwise an icon is generated from the first initial and detected page colors.")
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
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = UserDefaults.standard.object(forKey: "allowJavaScript") as? Bool ?? true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: appID))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate {
        let appID: String
        init(appID: String) { self.appID = appID }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            PermissionPrompt.shared.ask(appID: appID, type: type, completion: decisionHandler)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
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
            guard appID != "PREVIEW",
                  let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
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
            let alert = UIAlertController(title: "Permission Request",
                message: "HTML app \(appID) wants access to the \(permission).",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Don’t Allow", style: .cancel) { _ in completion(.deny) })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in completion(.grant) })
            root.present(alert, animated: true)
        }
    }
}
