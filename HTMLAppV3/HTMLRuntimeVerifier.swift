import Foundation
import WebKit
import UIKit

@MainActor
enum HTMLRuntimeVerifier {
    static func verify(html: String, timeout: TimeInterval = 6) async -> [String] {
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
        configuration.mediaTypesRequiringUserActionForPlayback = []

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
            try? await Task.sleep(nanoseconds: 80_000_000)
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

        // Compile each inline classic script without executing it. A syntax error
        // prevents all handlers in that script from registering.
        let scriptErrors = try? await evaluate(Self.inlineScriptSyntaxProbe, in: webView) as? [String]
        if let scriptErrors { scriptErrors.forEach(appendIssue) }

        // Detect tap blockers even when the JavaScript syntax is valid.
        if let blocked = (try? await evaluate(Self.touchabilityProbe, in: webView)) as? [String] {
            blocked.forEach(appendIssue)
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

        // One viewport is the fast default. Tablet checks can be run separately
        // in developer QA rather than blocking every new app generation.

        // Keep this bounded: only safe navigation, not broad destructive UI tests.
        // The dedicated debugging screen can perform more exhaustive checking.
        // Exercise non-destructive navigation in a disposable, nonpersistent runtime.
        // These are smoke tests, not permission to submit forms or mutate user data.
        if let tapped = (try? await evaluate(Self.clickProbeScript, in: webView)) as? [String: Any],
           let count = tapped["tested"] as? Int, count > 0 {
            try? await Task.sleep(nanoseconds: 90_000_000)
            let stillAlive = (try? await evaluate(
                "!!document.body && (document.body.children.length > 0 || (document.body.textContent || '').trim().length > 0)",
                in: webView
            )) as? Bool
            if stillAlive == false {
                appendIssue("Runtime: document became blank after simulated navigation interaction.")
            }
        }

        let recordedValue = try? await evaluate(
            "JSON.stringify((window.__htmlappRuntimeIssues || []).slice(0, 40))",
            in: webView
        )
        if let recorded = recordedValue as? String,
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
        try? await Task.sleep(nanoseconds: 25_000_000)

        let snapshotValue = try? await evaluate(
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
        )
        guard let object = snapshotValue as? [String: Any] else { return nil }

        return Snapshot(
            domNonEmpty: object["domNonEmpty"] as? Bool ?? false,
            horizontalOverflow: object["horizontalOverflow"] as? Bool ?? false
        )
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
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

    private static let touchabilityProbe = #"""
    (() => {
      const issues = [];
      const controls = Array.from(document.querySelectorAll(
        'button, [role="button"], [role="tab"], input, select, textarea, a[href]'
      )).filter(el => {
        const r = el.getBoundingClientRect();
        const css = getComputedStyle(el);
        return r.width >= 18 && r.height >= 18 &&
          css.display !== 'none' && css.visibility !== 'hidden' &&
          !el.disabled && !el.closest('[hidden], [inert]');
      }).slice(0, 35);
      let noPointer = 0, covered = 0;
      for (const el of controls) {
        if (getComputedStyle(el).pointerEvents === 'none') {
          noPointer++;
          continue;
        }
        const r = el.getBoundingClientRect();
        const cx = Math.max(1, Math.min(innerWidth - 1, r.left + r.width / 2));
        const cy = Math.max(1, Math.min(innerHeight - 1, r.top + r.height / 2));
        if (cy < 0 || cy >= innerHeight || cx < 0 || cx >= innerWidth) continue;
        const hit = document.elementFromPoint(cx, cy);
        if (hit && hit !== el && !el.contains(hit) && !hit.contains(el)) covered++;
      }
      if (noPointer >= Math.max(2, Math.ceil(controls.length / 2))) {
        issues.push('Runtime tapability: most visible controls have pointer-events disabled (' +
          noPointer + '/' + controls.length + ').');
      }
      if (covered >= Math.max(3, Math.ceil(controls.length * 0.6))) {
        issues.push('Runtime tapability: ' + covered + ' visible controls are covered by another element. Inspect overlays/z-index.');
      }
      return issues;
    })()
    """#

    private static let inlineScriptSyntaxProbe = #"""
    (() => {
      const found = [];
      for (const [i, el] of Array.from(document.scripts).entries()) {
        if (el.src || el.type === 'module' ||
            (el.type && !/^(text\/javascript|application\/javascript)$/i.test(el.type))) continue;
        const source = el.textContent || '';
        if (!source.trim()) continue;
        try {
          // Function constructor parses only; does not run app code.
          new Function(source);
        } catch (error) {
          found.push('JavaScript syntax in inline script ' + (i + 1) + ': ' +
            String(error?.message || error).slice(0, 250) +
            '. Fix this before release; unparsed scripts leave buttons unresponsive.');
        }
      }
      const buttons = document.querySelectorAll('button,[role="button"],[role="tab"]').length;
      if (found.length && buttons) {
        found.push('JavaScript did not compile; ' + buttons + ' controls may be unresponsive.');
      }
      return found;
    })()
    """#

    private static let clickProbeScript = #"""
    (() => {
      // Only try small safe navigation/toggle affordances. Never press save,
      // delete, purchase, submit, permission or external actions during QA.
      const safe = /\b(tab|menu|open|close|view|show|next|back|settings|details|more|filter)\b/i;
      const forbidden = /\b(delete|remove|reset|clear|pay|buy|purchase|send|share|upload|download|save|submit|connect|record|start|stop|log ?out|sign ?out)\b/i;
      const controls = Array.from(document.querySelectorAll(
        'button:not([type="submit"]),[role="tab"],[role="button"],input[type="checkbox"]'
      )).filter((element) => {
        const label = [element.getAttribute('aria-label'), element.textContent,
          element.getAttribute('title')].filter(Boolean).join(' ').trim().slice(0, 140);
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return !element.disabled && !element.closest('form') &&
          rect.width > 0 && rect.height > 0 &&
          style.visibility !== 'hidden' && style.display !== 'none' &&
          safe.test(label) && !forbidden.test(label);
      }).slice(0, 5);
      let tested = 0;
      const preventNavigation = (event) => {
        const link = event.target?.closest?.('a');
        if (link) event.preventDefault();
      };
      document.addEventListener('click', preventNavigation, true);
      for (const control of controls) {
        try {
          control.dispatchEvent(new MouseEvent('click', {
            bubbles: true, cancelable: true, view: window
          }));
          tested++;
        } catch (error) {
          const text = 'navigation click threw: ' + String(error?.message || error).slice(0, 260);
          window.__htmlappRuntimeIssues?.push(text);
        }
      }
      document.removeEventListener('click', preventNavigation, true);
      return { tested };
    })();

    """#
}
