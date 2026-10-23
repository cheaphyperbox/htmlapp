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

    /// Standalone HTML avoids fragile JSON-escaping of markup, CSS and scripts.
    /// Each slot gets a fast attempt plus one compact retry. The deterministic
    /// fallback keeps all three distinct choices available if a provider fails.
    static func generateSingle(for request: String, feedback: String = "", index: Int) async throws -> ForgeStyleConcept {
        let config = AISettingsStore.isUIOverhaulEnabled
            ? AISettingsStore.configuration(for: .ui)
            : AISettingsStore.configuration(for: .planner)
        let directions = [
            ("Map First", "Location-first immersive layout", "Dominant map taking most of screen, overlaid route controls and floating destination sheet; minimize card stacks"),
            ("Action First", "Bold guided action layout", "Huge primary locate/search action with playful asymmetric result tiles, strong type and short inline steps; no large map hero"),
            ("List First", "Compact information-first layout", "Dense clear destination list, numbered directions and a small map thumbnail; precision over decoration")
        ]
        let variant = directions[max(0, min(index, directions.count - 1))]
        let user = """
        App idea: \(String(request.prefix(2300)))
        Requested changes: \(String(feedback.prefix(650)))
        Design: \(variant.0) — \(variant.2).
        Every visible element MUST be relevant to the described app.
        For nearby-place apps, show a map/destination, distance, driving time,
        location action, and route steps, arranged according to your layout.
        Never put the entire prompt into the title. No generic "Your Space",
        "Overview", "Make progress your way", "Recent activity" or fake tabs.
        Style \(index + 1) must differ in layout, section order, hierarchy,
        map prominence, button placement and navigation — not merely colors.
        The selected layout archetype is mandatory.
        """
        let system = """
        Return ONLY a complete standalone HTML document starting with <!DOCTYPE html>.
        Build a compact visual mockup, not a functioning app. Include inline CSS
        and realistic labels from the app idea. Keep output under 5000 characters.
        Use responsive mobile-first styling. Design a visually complete
        preview with domain-relevant content, different shapes and hierarchy.
        Three styles share the objective but must not share a template.
        No external resources, external CSS, scripts, JSON, explanation or Markdown.
        No fake iPhone frame, status bar, battery, clock, notch, Dynamic Island
        or home indicator. The iOS host already provides system chrome.
        """
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let raw = try await AIProviderClient.complete(
                    config: config, system: system, messages: [("user", user)],
                    timeout: attempt == 0 ? 45 : 35,
                    maxTokens: attempt == 0 ? 2400 : 1800,
                    retryOnTransient: false
                )
                if let html = extractHTML(raw) {
                    return ForgeStyleConcept(id: index, name: variant.0,
                        summary: variant.1, direction: variant.2, previewHTML: html)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Retry only this failed slot; successful slots are never regenerated.
            }
        }
        try Task.checkCancellation()
        return ForgeStyleConcept(id: index, name: variant.0,
            summary: variant.1 + " (offline preview)",
            direction: variant.2, previewHTML: offlinePreview(request: request, variant: index))
    }

    private static func extractHTML(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept both direct HTML and the older JSON envelope so existing
        // providers/settings continue working without a migration.
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let embedded = json["html"] as? String {
            text = embedded
        }
        guard let begin = text.range(of: "<html", options: .caseInsensitive),
              let end = text.range(of: "</html>", options: .caseInsensitive),
              begin.lowerBound < end.lowerBound else { return nil }
        // Handle leading markdown fences, preamble, and trailing commentary.
        let html = String(text[begin.lowerBound..<end.upperBound])
        guard html.count >= 150, html.count <= 35_000,
              html.range(of: "<body", options: .caseInsensitive) != nil
        else { return nil }
        return "<!DOCTYPE html>\n" + html
    }

    private static func offlinePreview(request: String, variant: Int) -> String {
        let palettes: [(String,String,String,String)] = [
            ("#f7f5f2", "#ffffff", "#272433", "#6755a4"),
            ("#292038", "#493064", "#fff5fd", "#ff7294"),
            ("#111d2d", "#26364c", "#ffffff", "#49b5e8")
        ]
        let (background, card, ink, accent) = palettes[max(0, min(variant, 2))]
        let escaped = String(request.prefix(100))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>:root{--bg:\(background);--card:\(card);--ink:\(ink);--accent:\(accent)}
        *{box-sizing:border-box}body{margin:0;padding:26px 20px;font-family:-apple-system,system-ui,sans-serif;
        color:var(--ink);background:var(--bg)}main{max-width:580px;margin:auto}
        h1{font-size:32px;letter-spacing:-.05em;line-height:1.12}
        .card{background:var(--card);border-radius:\(variant == 1 ? "28" : "16")px;
        padding:22px;margin:18px 0;border:1px solid #8883}
        .button{background:var(--accent);color:white;border:0;border-radius:15px;padding:15px 23px;font-weight:700}
        .muted{opacity:.7;line-height:1.5}.row{display:flex;justify-content:space-between;gap:12px}
        .pill{background:var(--accent);border-radius:999px;padding:8px 13px;color:white}
        </style></head><body><main><p class="muted">YOUR SPACE</p><h1>\(escaped)</h1>
        <div class="card"><div class="row"><strong>Overview</strong><span class="pill">Today</span></div>
        <h2>Make progress your way</h2><p class="muted">Everything in one welcoming place.</p>
        <button class="button">Get started</button></div>
        <div class="card"><strong>Recent activity</strong><p class="muted">Your next steps will appear here.</p></div>
        <nav class="row"><span>Home</span><span>Activity</span><span>Settings</span></nav>
        </main></body></html>
        """
    }

    static func generate(for request: String, feedback: String = "") async throws -> [ForgeStyleConcept] {
        return await withTaskGroup(of: ForgeStyleConcept?.self) { group in
            for index in 0..<3 {
                group.addTask {
                    try? await generateSingle(for: request, feedback: feedback, index: index)
                }
            }
            var results: [ForgeStyleConcept] = []
            for await option in group {
                if let option { results.append(option) }
            }
            return results.sorted { $0.id < $1.id }
        }
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
