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

    /// Compact reference for the first coding pass. The complete mockup
    /// remains available for the existing fidelity repair if needed.
    var compactBuildInstruction: String {
        let html = previewHTML as NSString
        let regex = try? NSRegularExpression(
            pattern: #"<(header|section|main|div|button|h1|h2)\b[^>]*>"#,
            options: .caseInsensitive
        )
        let structure = (regex?.matches(in: previewHTML,
                                        range: NSRange(location: 0, length: html.length)) ?? [])
            .prefix(25).map { html.substring(with: $0.range) }
            .joined(separator: " → ")
        return """
        SELECTED STYLE: \(name) — \(summary)
        Design: \(direction)
        REQUIRED: Match the chosen look's initial hierarchy, dominant visual region,
        action placement, card ordering, background, contrast, typography, shape,
        border radius and navigation pattern. Implement functioning controls.
        EXACT STYLE TOKENS:
        \(Self.designTokens(previewHTML))
        CSS VARIABLE DECLARATIONS:
        \(visualTokenDeclarations.joined(separator: "; "))
        ORDERED STRUCTURE:
        \(structure)
        Use these as a strict visual contract, not a generic layout suggestion.
        """
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
            "The AI did not return complete style HTML. Check your style model and retry."
        }
    }

    /// Standalone HTML avoids fragile JSON-escaping of markup, CSS and scripts.
    /// Each slot requests a complete document and retries with the coder model
    /// if necessary. Incomplete provider output is reported, not substituted.
    static func generateSingle(for request: String, feedback: String = "", index: Int,
                               appearance: String = "light", regeneration: Int = 0) async throws -> ForgeStyleConcept {
        let preferredConfig = AISettingsStore.isUIOverhaulEnabled
            ? AISettingsStore.configuration(for: .ui)
            : AISettingsStore.configuration(for: .planner)
        // The regular coder model retries incomplete specialist output;
        // no locally drawn replacement is ever returned.
        let recoveryConfig = AISettingsStore.configuration(for: .coder)
        // Broad audience directions leave composition and visual identity to the AI.
        let directions: [(String, String, String)] = [
            ("Modern", "Modern / professional", "Modern and professional. Choose the visual identity, layout, palette, typography and interactions freely to suit this product."),
            ("Technical", "Technical / detailed", "Technical and detailed. Choose how to organize depth, precision and useful information freely to suit this product."),
            ("Kiddy", "Kiddy / easy-to-use", "Kiddy and easy to use. Choose an approachable, friendly experience with clear language and simple interactions freely to suit this product.")
        ]
        let slot = max(0, index % 3)
        let variant = directions[slot]
        let freeform = index >= 3
        let user = """
        App idea: \(String(request.prefix(2300)))
        Requested changes: \(String(feedback.prefix(650)))
        \(freeform ? "Choose your own entirely original visual style, layout, interaction pattern and design language. Do not follow any predefined aesthetic or archetype." : "General direction: \(variant.1). \(variant.2) No mandatory composition, palette or aesthetic.")
        Style regeneration round: \(regeneration). Invent a completely new visual identity, section organization and interaction pattern on each round.
        System appearance: \(appearance). Design in this light/dark mode unless the user explicitly requested another mode.
        Every visible element MUST be relevant to the described app.
        Invent a concrete brand name, realistic starter records, and a meaningful
        primary screen for THIS product. A workout tracker needs workout sets,
        timers and training history; a task manager needs actual task rows;
        a location app needs a map and useful distances. Never use arbitrary
        placeholder sections such as 'My tasks' for unrelated products.
        Never put the entire prompt into the title. No generic "Your Space",
        "Overview", "Make progress your way", "Recent activity" or fake tabs.
        Style \(slot + 1) must differ in layout, section order, hierarchy,
        map prominence, button placement and navigation — not merely colors.
        \(freeform ? "The AI must invent the design freely; no style presets." : "The direction guides the audience and feel only; invent the design freely.")
        """
        let system = """
        Return ONLY a complete standalone HTML document starting with <!DOCTYPE html>.
        Build a compact visual mockup, not a functioning app. Include inline CSS
        and realistic labels from the app idea. Aim for 2000–3200 characters.
        Finish the entire document, including </body></html>, before adding
        decoration. Do not spend output on planning or reasoning text.
        Use responsive mobile-first styling. Design a visually complete
        preview with domain-relevant content, different shapes and hierarchy.
        Three styles share the objective but must not share a template.
        Choose any composition that fits this product; avoid generic filler and copied templates.
        \(freeform ? "Invent a new composition without presets." : "Use the broad direction as guidance only; no prescribed layout, shapes, colors or navigation.")
        Also adapt to short landscape car displays: keep key content legible,
        controls at least 48px and secondary content vertically scrollable.
        Car display compatibility is not native CarPlay template support.
        No external resources, external CSS, scripts, JSON, explanation or Markdown.
        No fake iPhone frame, status bar, battery, clock, notch, Dynamic Island
        or home indicator. The iOS host already provides system chrome.
        Honor the user's explicit theme request. Otherwise prefer \(appearance) appearance.
        Use matching background, cards and text contrast; do not force a dark
        theme in a light-mode system or vice versa.
        """
        for attempt in 0..<(ForgeRunOptions.quick ? 1 : 2) {
            try Task.checkCancellation()
            let config = attempt == 0 ? preferredConfig : recoveryConfig
            do {
                let raw = try await AIProviderClient.complete(
                    config: config, system: system, messages: [("user", user)],
                    timeout: ForgeRunOptions.quick ? 55 : (attempt == 0 ? 75 : 90),
                    maxTokens: ForgeRunOptions.quick ? 6500 : (attempt == 0 ? 8500 : 12000),
                    retryOnTransient: false
                )
                if let html = extractHTML(raw) {
                    return ForgeStyleConcept(id: index, name: freeform ? "AI Look \(index + 1)" : variant.0,
                        summary: freeform ? "Original AI-designed concept" : variant.1,
                        direction: freeform ? "Unrestricted creative direction" : variant.2, previewHTML: html)
                }
                let detail = "Look \(index + 1), attempt \(attempt + 1), model \(config.model): incomplete HTML (\(raw.count) characters)."
                await MainActor.run {
                    AIDebugTraceStore.shared.append("STYLE MOCKUP", detail)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let detail = "Look \(index + 1), attempt \(attempt + 1), model \(config.model): \(error.localizedDescription)"
                await MainActor.run {
                    AIDebugTraceStore.shared.append("STYLE MOCKUP", detail)
                }
            }
        }
        try Task.checkCancellation()
        throw PreviewError.invalidResponse
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

