import Foundation
import WebKit
import UIKit

@MainActor
enum HTMLRuntimeVerifier {
    static func verify(html: String, timeout: TimeInterval = 10) async -> [String] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ["Runtime: generated HTML was empty."]
        }
        let session = HTMLRuntimeCheckSession(html: html)
        return await session.run(timeout: timeout)
    }
}

@MainActor
private final class HTMLRuntimeCheckSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let html: String
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String], Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false
    private var issues: [String] = []

    init(html: String) {
        self.html = html
        super.init()
    }

    func run(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()

            timeoutTask = Task { [weak self] in
                let nanos = UInt64(max(1, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                self?.finish(extra: ["Runtime: offscreen WebView verification timed out after \(Int(timeout)) seconds."])
            }
        }
    }

    private func start() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: Self.diagnosticsScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: PermissionBridgeScript.source(sensorPolicy: "deny"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: DownloadBridgeScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLNativeAPIScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: HTMLLocalNetworkScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        for name in Self.messageHandlerNames {
            controller.add(self, name: name)
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isHidden = true
        self.webView = webView
        webView.loadHTMLString(html, baseURL: SourceCache.shared.baseURL(appID: "PREVIEW"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.runChecks()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(extra: ["Runtime: WebView navigation failed: \(error.localizedDescription)"])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(extra: ["Runtime: WebView failed to load the generated document: \(error.localizedDescription)"])
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "htmlappRuntimeLog" else {
            return
        }
        if let text = message.body as? String {
            appendIssue(text)
        }
    }

    private func runChecks() async {
        guard let webView else {
            finish(extra: ["Runtime: WebView was unavailable during verification."])
            return
        }

        let phone = await snapshot(webView, width: 390, height: 844)
        if let phone {
            if phone.domNonEmpty == false {
                appendIssue("Runtime: document body rendered empty at 390pt width.")
            }
            if phone.horizontalOverflow {
                appendIssue("Runtime: page has horizontal overflow at 390pt width.")
            }
        } else {
            appendIssue("Runtime: could not inspect the generated DOM at 390pt width.")
        }

        let tablet = await snapshot(webView, width: 820, height: 900)
        if let tablet, tablet.horizontalOverflow {
            appendIssue("Runtime: page has horizontal overflow at 820pt width.")
        }

        _ = try? await evaluate(Self.clickProbeScript, in: webView)
        try? await Task.sleep(nanoseconds: 220_000_000)

        if let recorded = try? await evaluate(
            "JSON.stringify((window.__htmlappRuntimeIssues || []).slice(0, 40))",
            in: webView
        ) as? String,
           let data = recorded.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            values.forEach(appendIssue)
        }

        finish(extra: [])
    }

    private struct Snapshot {
        let domNonEmpty: Bool
        let horizontalOverflow: Bool
    }

    private func snapshot(_ webView: WKWebView, width: CGFloat, height: CGFloat) async -> Snapshot? {
        webView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 90_000_000)

        guard let object = try? await evaluate(
            """
            (() => ({
              domNonEmpty: !!document.body && (
                document.body.children.length > 0 ||
                (document.body.textContent || '').trim().length > 0
              ),
              horizontalOverflow: Math.max(
                document.documentElement?.scrollWidth || 0,
                document.body?.scrollWidth || 0
              ) > ((document.documentElement?.clientWidth || window.innerWidth || 0) + 2)
            }))()
            """,
            in: webView
        ) as? [String: Any] else { return nil }

        return Snapshot(
            domNonEmpty: object["domNonEmpty"] as? Bool ?? false,
            horizontalOverflow: object["horizontalOverflow"] as? Bool ?? false
        )
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private func appendIssue(_ raw: String) {
        let clean = raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !clean.isEmpty, !issues.contains(clean), issues.count < 40 else { return }
        issues.append(clean)
    }

    private func finish(extra: [String]) {
        guard !completed else { return }
        completed = true
        extra.forEach(appendIssue)
        timeoutTask?.cancel()

        if let webView {
            webView.stopLoading()
            let controller = webView.configuration.userContentController
            Self.messageHandlerNames.forEach { controller.removeScriptMessageHandler(forName: $0) }
            webView.navigationDelegate = nil
        }
        webView = nil

        let result = issues
        continuation?.resume(returning: result)
        continuation = nil
    }

    private static let messageHandlerNames = [
        "htmlappRuntimeLog",
        "htmlappLocation",
        "htmlappNotificationPermission",
        "htmlappNotification",
        "htmlappHaptic",
        "htmlappSensorPermission",
        "htmlappDownload",
        "htmlappNative",
        "htmlappNetwork"
    ]

    private static let diagnosticsScript = #"""
    (() => {
      if (window.__htmlappRuntimeDiagnosticsInstalled) return;
      window.__htmlappRuntimeDiagnosticsInstalled = true;
      const issues = [];
      window.__htmlappRuntimeIssues = issues;

      const describe = (value) => {
        try {
          if (value instanceof Error) return value.stack || value.message || String(value);
          if (typeof value === 'string') return value;
          return JSON.stringify(value);
        } catch (_) {
          return String(value);
        }
      };

      const push = (kind, value) => {
        const text = `${kind}: ${describe(value)}`.slice(0, 900);
        if (!issues.includes(text) && issues.length < 40) issues.push(text);
        try { window.webkit?.messageHandlers?.htmlappRuntimeLog?.postMessage(text); } catch (_) {}
      };

      const originalConsoleError = console.error?.bind(console);
      console.error = (...args) => {
        push('console.error', args.map(describe).join(' '));
        if (originalConsoleError) originalConsoleError(...args);
      };

      window.addEventListener('error', (event) => {
        if (event.target && event.target !== window) {
          const target = event.target;
          push('resource error', target.src || target.href || target.tagName || 'unknown resource');
          return;
        }
        push('uncaught error', `${event.message || 'unknown'} ${event.filename || ''}:${event.lineno || 0}:${event.colno || 0}`);
      }, true);

      window.addEventListener('unhandledrejection', (event) => {
        push('unhandled rejection', event.reason || 'unknown promise rejection');
      });

      if (typeof window.fetch === 'function') {
        const nativeFetch = window.fetch.bind(window);
        window.fetch = (...args) => nativeFetch(...args).catch((error) => {
          push('network failure', `${String(args[0] || '')} ${describe(error)}`);
          throw error;
        });
      }

      window.alert = (message) => push('blocking alert invoked', message);
      window.confirm = (message) => { push('blocking confirm invoked', message); return false; };
      window.prompt = (message) => { push('blocking prompt invoked', message); return null; };
    })();
    """#

    private static let clickProbeScript = #"""
    (() => {
      const targets = Array.from(document.querySelectorAll(
        'button, a[href], [role="button"], input[type="button"], input[type="submit"]'
      )).filter((element) => {
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return !element.disabled &&
          rect.width > 0 && rect.height > 0 &&
          style.display !== 'none' &&
          style.visibility !== 'hidden';
      }).slice(0, 60);

      const preventDefault = (event) => event.preventDefault();
      document.addEventListener('click', preventDefault, true);
      for (const target of targets) {
        try {
          target.dispatchEvent(new MouseEvent('click', {
            bubbles: true,
            cancelable: true,
            view: window
          }));
        } catch (error) {
          const text = `click handler threw: ${error?.stack || error?.message || String(error)}`.slice(0, 900);
          if (!window.__htmlappRuntimeIssues.includes(text)) window.__htmlappRuntimeIssues.push(text);
        }
      }
      document.removeEventListener('click', preventDefault, true);
      return targets.length;
    })();
    """#
}
