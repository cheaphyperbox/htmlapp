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
        MANDATORY VISUAL REFERENCE: Match the chosen mockup layout closely.
        Preserve the SAME colors, typography, font sizes, spacing, padding, corner radii,
        shadows, borders, layout, navigation, icons, component shapes and positions.
        REUSE its CSS custom properties and class structure where practical.
        The initial screen MUST retain the chosen reference's exact content hierarchy:
        same header treatment, dominant visual region, relative positioning of the
        primary action, card ordering, navigation scheme, and surface geometry.
        Treat the selected mockup as the source of truth, not a suggestion.
        Implement features INSIDE this architecture rather than switching to a
        generic dashboard. Prefer faithful layout over decorative novelty.
        If runtime requirements demand extra screens, leave the initial
        mockup composition intact and extend around it.
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
        let isRoute = ["nearest", "mcdonald", "directions", "map", "route", "restaurant"].contains { request.lowercased().contains($0) }
        let destination = request.lowercased().contains("mcdonald") ? "McDonald's" : "nearest place"
        let content: String
        switch variant {
        case 0:
            content = isRoute ? """
            <div class="map"><div class="pin">⌖ You</div><div class="destination">\(destination)</div></div>
            <section class="floating"><small>YOUR NEAREST STOP</small><h2>\(destination)</h2>
            <div class="metrics"><b>— miles</b><b>— min</b></div><button>Find driving route</button>
            <p>Allow location to see the map and directions.</p></section>
            """ : "<div class='map'><h1>\(escaped)</h1></div><section class='floating'><h2>Explore</h2><button>Open workspace</button></section>"
        case 1:
            content = isRoute ? """
            <section class="hero"><small>LET'S GET MOVING</small><h1>Craving \(destination)?</h1>
            <p>One tap to find the nearest location and start your trip.</p><button>Find near me →</button></section>
            <div class="tiles"><div><small>DRIVING DISTANCE</small><h2>— mi</h2></div>
            <div><small>AT 50 MPH</small><h2>— min</h2></div></div>
            <section class="card"><h2>Next turns</h2><p>Your directions appear here.</p></section>
            """ : "<section class='hero'><h1>\(escaped)</h1><button>Get started →</button></section><div class='tiles'><div>My tasks</div><div>Discover</div></div>"
        default:
            content = isRoute ? """
            <header><small>ROUTES / NEARBY</small><h1>Find \(destination)</h1>
            <p>Accurate driving distance and step-by-step directions.</p></header>
            <div class="search">⌖ &nbsp; Locate nearest place →</div>
            <section class="list"><h2>Closest location</h2>
            <div class="item"><b>01</b><div><strong>\(destination)</strong><p>Waiting for location</p></div><span>— mi</span></div>
            <h2>Directions</h2><div class="item"><b>02</b><p>Your first turn will appear here.</p></div>
            <div class="item"><b>03</b><p>Arrival time at 50 mph: —</p></div></section>
            """ : "<header><h1>\(escaped)</h1></header><div class='search'>Search →</div><section class='list'><div class='item'>01 — Your items</div><div class='item'>02 — Actions</div></section>"
        }
        return """
        <!DOCTYPE html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>*{box-sizing:border-box}body{margin:0;padding:16px;font-family:-apple-system,system-ui,sans-serif;
        background:var(--bg);color:var(--ink)}:root{--bg:\(background);--card:\(card);--ink:\(ink);--accent:\(accent)}
        h1{font-size:clamp(28px,6vw,48px);letter-spacing:-.05em;line-height:1.08}h2{font-size:22px}
        small{font-size:12px;letter-spacing:.12em;font-weight:800;opacity:.7}p{line-height:1.5;opacity:.75}
        button,.search{background:var(--accent);color:white;border:0;border-radius:15px;padding:16px;font-weight:800}
        .map{min-height:65vh;position:relative;border-radius:27px;overflow:hidden;background:repeating-linear-gradient(32deg,#d1e2d6 0 25px,#c0d7cf 26px 58px,#ecede3 60px 90px)}
        .map:after{content:"";position:absolute;left:0;right:0;top:42%;height:24px;background:#fafafa;transform:rotate(-14deg)}
        .pin,.destination{position:absolute;z-index:2;background:#122d32;color:white;border-radius:32px;padding:12px;font-weight:800}
        .pin{top:35%;left:10%}.destination{bottom:23%;right:8%}
        .floating{position:relative;margin:-75px 13px 0;padding:24px;background:var(--card);border-radius:28px;box-shadow:0 15px 30px #0002}
        .metrics{display:flex;justify-content:space-between;font-size:25px;margin:20px 0}
        .hero{padding:35px 24px;background:var(--card);border-radius:36px;min-height:380px;display:flex;flex-direction:column;align-items:flex-start;justify-content:center}
        .hero button{margin-top:18px}.tiles{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:14px 0}
        .tiles>div,.card,.list{background:var(--card);border-radius:23px;padding:23px}
        header{padding:25px 0 12px;border-bottom:3px solid var(--accent)}
        .search{margin:20px 0;border-radius:11px}.list{border-radius:9px}
        .item{display:flex;gap:16px;align-items:center;padding:17px 0;border-top:1px solid #8884}
        .item b{color:var(--accent)}.item span{margin-left:auto;font-weight:800}
        </style></head><body><main>\(content)</main></body></html>
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
