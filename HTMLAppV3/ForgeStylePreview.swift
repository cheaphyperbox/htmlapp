import Foundation
import SwiftUI
import WebKit

struct ForgeStyleConcept: Identifiable, Equatable {
    let id: Int
    let name: String
    let summary: String
    let direction: String
    let previewHTML: String

    var buildInstruction: String {
        """
        VISUAL STYLE CHOSEN BY THE USER
        Name: \(name)
        Impression: \(summary)
        Design specification: \(direction)
        Preserve the chosen preview's visual identity, layout principles, palette, typography, and interaction character.
        The preview was deliberately a nonfunctional sketch. Build a complete real application with working controls, real persistence and robust states; never copy dummy content as real data.
        """
    }
}

enum ForgeStylePreviewService {
    enum PreviewError: LocalizedError {
        case invalidResponse
        var errorDescription: String? {
            "The AI could not make usable style previews. You can retry or build the full app directly."
        }
    }

    /// A single small request produces three alternate, deliberately shallow HTML sketches.
    static func generate(for request: String) async throws -> [ForgeStyleConcept] {
        let config = AISettingsStore.isUIOverhaulEnabled
            ? AISettingsStore.configuration(for: .ui)
            : AISettingsStore.configuration(for: .planner)
        let system = """
        You are a mobile app art director producing QUICK INTERACTIVE STYLE MOCKUPS, not functioning applications.
        Return ONLY one valid JSON object with a "styles" array of exactly THREE different style options.
        Each style object has four string fields:
        "name": 1–3 word evocative design name;
        "summary": one sentence of what differentiates this visual direction;
        "direction": 90–170 words of actionable visual specifications covering palette (give approximate hex colors), typography, layout, surfaces, primary navigation, interactive motion, and icon direction. Describe the visual identity so another AI can build the FULL app from it;
        "html": a self-contained <!DOCTYPE html><html> ... </html> miniature UI sketch with inline CSS and at most tiny vanilla JavaScript.
        
        The three sketches must look MEANINGFULLY DIFFERENT, not recolored copies. Choose distinct themes, compositions, hierarchy, and visual density based on the app's purpose. Respect the user's optional visual taste, but do not force every app to look the same.
        Sketches show one believable phone-sized screen each, at most 2–3 small interactive elements (e.g. a tab selector, simple toggle, or popup), with clearly visible press and easing transitions, and concise illustrative placeholder copy. They are NOT feature-complete, and should not pretend to fetch data, request device access or persist anything.
        Use absolutely NO network requests, remote fonts, images, iframes, CDNs, storage, permissions, native APIs, alerts, trackers, or external links. Use only inlined CSS/JS and simple SVG/CSS shapes if useful.
        Include viewport meta, body width responsiveness, safe-area spacing, and prefers-reduced-motion handling. Target about 500–900 words TOTAL across all three HTML sketches, compact CSS, no giant code or functional algorithms.
        No Markdown fences or commentary. Output parseable JSON strings; escape newlines and quotation marks properly.
        """
        let user = "APP IDEA:\n\(String(request.prefix(3500)))\n\nVISUAL PREFERENCE:\n\(AISettingsStore.creativeDirection)"
        let raw = try await AIProviderClient.complete(
            config: config,
            system: system,
            messages: [("user", user)],
            timeout: 90,
            maxTokens: 7200,
            retryOnTransient: false
        )
        try Task.checkCancellation()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end,
              let bytes = String(trimmed[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let entries = json["styles"] as? [[String: Any]] else {
            throw PreviewError.invalidResponse
        }
        var styles: [ForgeStyleConcept] = []
        for entry in entries.prefix(3) {
            let name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = (entry["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let direction = (entry["direction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let html = (entry["html"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !direction.isEmpty,
                  name.count <= 65, direction.count <= 1600,
                  html.count <= 35_000,
                  html.range(of: "<html", options: .caseInsensitive) != nil,
                  html.range(of: "<head", options: .caseInsensitive) != nil,
                  html.range(of: "</html>", options: .caseInsensitive) != nil
            else { continue }
            styles.append(.init(id: styles.count, name: String(name.prefix(48)),
                                summary: String(summary.prefix(240)),
                                direction: direction, previewHTML: html))
        }
        guard styles.count >= 2 else { throw PreviewError.invalidResponse }
        return styles
    }
}

/// A dedicated nonpersistent, unbridged WebView. Generated sketch code cannot
/// call HTMLAppNative and the CSP blocks network, frames and external resources.
struct ForgeStyleSketchView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor.systemBackground
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        let csp = """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'; object-src 'none'">
        """
        var document = html
        if let head = document.range(of: #"<head\\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            document.replaceSubrange(head, with: String(document[head]) + csp)
        }
        view.loadHTMLString(document, baseURL: nil)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The top-level loadHTMLString navigation remains allowed.
            let isInternal = navigationAction.request.url?.scheme == "about"
            decisionHandler(isInternal ? .allow : .cancel)
        }
    }
}
