import Foundation
import SwiftUI
import WebKit

struct ForgeStyleConcept: Identifiable, Equatable, Codable, Sendable {
    let id: Int
    let name: String
    let summary: String
    let direction: String
    let previewHTML: String

    static func designTokens(_ html: String) -> String {
        // Compact style summary doubles as a cheap consistency check after generation.
        let patterns = [#"--[a-zA-Z0-9-]+\s*:\s*[^;}]{1,90}"#,
                        #"font-family\s*:\s*[^;}]{1,100}"#,
                        #"border-radius\s*:\s*[^;}]{1,55}"#]
        let ns = html as NSString
        var found: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).prefix(24) {
                let value = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !found.contains(value) { found.append(value) }
            }
        }
        return found.prefix(36).joined(separator: "; ")
    }

    var visualTokenDeclarations: [String] {
        let regex = try? NSRegularExpression(pattern: #"--[a-zA-Z0-9-]+\s*:\s*([^;}]+)"#)
        let ns = previewHTML as NSString
        return (regex?.matches(in: previewHTML, range: NSRange(location: 0, length: ns.length)) ?? [])
            .prefix(16).map { ns.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var buildInstruction: String {
        """
        VISUAL STYLE CHOSEN BY THE USER
        Name: \(name)
        Impression: \(summary)
        Design specification: \(direction)
        MANDATORY VISUAL REFERENCE: Match this mockup nearly pixel-for-pixel.
        Preserve the SAME colors, typography, font sizes, spacing, padding, corner radii,
        shadows, borders, layout, navigation, icons, component shapes and positions.
        REUSE its CSS custom properties and class structure where practical.
        Only introduce new elements for real features and responsive layouts, in
        precisely the same design language. Replace demo data with real working data.
        Do NOT redesign this mockup or replace it with a generic layout.
        EXTRACTED STYLE TOKENS:
        \(Self.designTokens(previewHTML))

        AUTHORITATIVE MOCKUP HTML:
        <selected_mockup_html>
        \(previewHTML)
        </selected_mockup_html>
        This is a nonfunctional sketch: implement actual working controls/persistence.
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

    /// Generate one independent sketch so malformed output does not discard peers.
    static func generateSingle(for request: String, feedback: String = "", index: Int) async throws -> ForgeStyleConcept {
        let config = AISettingsStore.isUIOverhaulEnabled
            ? AISettingsStore.configuration(for: .ui)
            : AISettingsStore.configuration(for: .planner)
        let system = """
        You design ONE compact phone UI style sketch, not a complete app.
        Return a JSON object with string keys name, summary, direction, html.
        The html value is self-contained HTML with inline CSS; no outside URLs or APIs.
        Keep HTML below 9000 characters. Include <html>, <head> and </html>.
        Use a deliberately distinct direction numbered \(index + 1) of 3:
        1 = quiet editorial, 2 = playful vivid, 3 = utilitarian high-contrast.
        Never include a fake phone status bar, 9:41 clock, notch, Dynamic Island, battery, signal indicators, iPhone frame or home indicator. The real iOS host provides its own chrome.\n        Escape all quotes and newlines correctly. No Markdown fences.
        """
        let user = "APP IDEA: \(String(request.prefix(2800)))\nFEEDBACK: \(String(feedback.prefix(900)))"
        let raw = try await AIProviderClient.complete(
            config: config, system: system, messages: [("user", user)],
            timeout: 90, maxTokens: 4200, retryOnTransient: true
        )
        try Task.checkCancellation()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"),
              let bytes = String(trimmed[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        else { throw PreviewError.invalidResponse }
        let html = (json["html"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard html.range(of: "<html", options: .caseInsensitive) != nil,
              html.range(of: "</html>", options: .caseInsensitive) != nil,
              html.count <= 35_000 else { throw PreviewError.invalidResponse }
        return ForgeStyleConcept(
            id: index,
            name: String((json["name"] as? String ?? "Style \(index + 1)").prefix(48)),
            summary: String((json["summary"] as? String ?? "Alternate visual direction").prefix(240)),
            direction: String((json["direction"] as? String ?? "Create a distinctive, usable interface.").prefix(1600)),
            previewHTML: html
        )
    }

    static func generate(for request: String, feedback: String = "") async throws -> [ForgeStyleConcept] {
        var previews: [ForgeStyleConcept] = []
        for index in 0..<3 {
            if let result = try? await generateSingle(for: request, feedback: feedback, index: index) {
                previews.append(result)
            }
        }
        guard !previews.isEmpty else { throw PreviewError.invalidResponse }
        return previews
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
        if let head = document.range(of: #"<head\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
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
