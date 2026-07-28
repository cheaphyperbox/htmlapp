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
        configuration.allowsInlineMediaPlayback = true

        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: PermissionBridgeScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.add(context.coordinator, name: "htmlappLocation")
        controller.add(context.coordinator, name: "htmlappNotificationPermission")
        controller.add(context.coordinator, name: "htmlappNotification")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.attach(webView)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: appID))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        let controller = uiView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "htmlappLocation")
        controller.removeScriptMessageHandler(forName: "htmlappNotificationPermission")
        controller.removeScriptMessageHandler(forName: "htmlappNotification")
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        let appID: String
        private weak var webView: WKWebView?
        private var nativePermissions: NativePermissionCoordinator?
        private var locationPermissions: HTMLLocationBridge?

        init(appID: String) { self.appID = appID }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            nativePermissions = NativePermissionCoordinator(webView: webView, appID: appID)
            locationPermissions = HTMLLocationBridge(webView: webView, appID: appID)
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
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
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

            default:
                break
            }
        }
    }
}

enum PermissionBridgeScript {
    static let source = #"""
    (() => {
      if (window.__htmlappPermissionBridgeInstalled) return;
      window.__htmlappPermissionBridgeInstalled = true;

      const locationCallbacks = new Map();
      let callbackCounter = 0;
      const makeID = (prefix) => `${prefix}-${Date.now()}-${++callbackCounter}`;

      window.__htmlappLocationSuccess = (id, payload) => {
        const item = locationCallbacks.get(id);
        if (!item) return;
        locationCallbacks.delete(id);
        item.success({
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
      };

      window.__htmlappLocationError = (id, code, message) => {
        const item = locationCallbacks.get(id);
        if (!item) return;
        locationCallbacks.delete(id);
        if (typeof item.error === 'function') item.error({ code, message });
      };

      const geo = {
        getCurrentPosition(success, error, options = {}) {
          const id = makeID('geo');
          locationCallbacks.set(id, { success, error });
          window.webkit.messageHandlers.htmlappLocation.postMessage({
            id,
            highAccuracy: !!options.enableHighAccuracy,
            timeout: Number.isFinite(options.timeout) ? options.timeout : 15000
          });
        },
        watchPosition(success, error, options = {}) {
          const id = makeID('watch');
          locationCallbacks.set(id, { success, error });
          window.webkit.messageHandlers.htmlappLocation.postMessage({
            id,
            highAccuracy: !!options.enableHighAccuracy,
            timeout: Number.isFinite(options.timeout) ? options.timeout : 15000
          });
          return id;
        },
        clearWatch(id) { locationCallbacks.delete(id); }
      };

      try {
        Object.defineProperty(navigator, 'geolocation', { configurable: true, value: geo });
      } catch (_) {}

      const notificationCallbacks = new Map();
      let notificationPermission = 'default';

      window.__htmlappNotificationPermission = (id, value) => {
        notificationPermission = value;
        const callback = notificationCallbacks.get(id);
        if (callback) {
          notificationCallbacks.delete(id);
          callback(value);
        }
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

        window.webkit.messageHandlers.htmlappNotification.postMessage({
          title: this.title,
          body: this.body,
          tag: this.tag,
          silent: this.silent
        });
        setTimeout(() => { if (typeof this.onshow === 'function') this.onshow(); }, 0);
      }

      Object.defineProperty(HTMLAppNotification, 'permission', {
        configurable: true,
        get: () => notificationPermission
      });

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
    """#
}
