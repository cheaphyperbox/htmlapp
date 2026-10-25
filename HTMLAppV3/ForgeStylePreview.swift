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
    private struct PreviewSeed: Decodable {
        let brand: String
        let headline: String
        let action: String
        let records: [String]
        let accent: String
    }

    static func enrichedOptions(for request: String, appearance: String) async -> [ForgeStyleConcept]? {
        let config = ForgeRunOptions.$quick.withValue(true) {
            AISettingsStore.configuration(for: .planner)
        }
        guard config.isConfigured else { return nil }
        do {
            let raw = try await AIProviderClient.complete(
                config: config,
                system: """
                Return ONE small JSON object only: {"brand":"short name","headline":"short product-specific headline","action":"primary action","records":["realistic example 1","example 2","example 3"],"accent":"#RRGGBB"}.
                Identify the real product from the request. All content must be specific to its purpose. No explanations or markdown.
                """,
                messages: [("user", String(request.prefix(750)))],
                timeout: 12, maxTokens: 900, retryOnTransient: false
            )
            guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"),
                  open < close, let data = String(raw[open...close]).data(using: .utf8),
                  let seed = try? JSONDecoder().decode(PreviewSeed.self, from: data),
                  (2...34).contains(seed.brand.count), (5...90).contains(seed.headline.count),
                  (2...35).contains(seed.action.count),
                  seed.records.count >= 3,
                  seed.records.prefix(3).allSatisfy({ (2...55).contains($0.count) }),
                  seed.accent.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil
            else { return nil }
            return instantOptions(for: request, appearance: appearance, seed: seed)
        } catch {
            // Local styles remain available; enrichment failure is nonblocking.
            return nil
        }
    }

    enum PreviewError: LocalizedError {
        case invalidResponse
        var errorDescription: String? {
            "The AI could not make usable style previews. You can retry or build the full app directly."
        }
    }

    private static func instantOptions(for request: String, appearance: String, seed: PreviewSeed) -> [ForgeStyleConcept] {
        options(for: request, appearance: appearance, seed: seed)
    }

    static func instantOptions(for request: String, appearance: String) -> [ForgeStyleConcept] {
        options(for: request, appearance: appearance, seed: nil)
    }

    private static func options(for request: String, appearance: String, seed: PreviewSeed?) -> [ForgeStyleConcept] {
        let directions = [
            ("Immersive", "Large visual-first product layout", "Dominant product-specific visual or data feature, with overlaid contextual controls and an anchored action sheet"),
            ("Action First", "Bold guided action layout", "Big functional call-to-action, expressive type and asymmetrical summary tiles, with a clear next step"),
            ("Dashboard", "Compact information-first layout", "Realistic domain-specific metrics, a short ordered list or activity feed, and compact controls")
        ]
        return directions.enumerated().map { index, variant in
            ForgeStyleConcept(id: index, name: variant.0, summary: variant.1,
                              direction: variant.2,
                              previewHTML: offlinePreview(request: request, variant: index, appearance: appearance, seed: seed))
        }
    }

    /// Standalone HTML avoids fragile JSON-escaping of markup, CSS and scripts.
    /// Each slot gets a fast attempt plus one compact retry. The deterministic
    /// fallback keeps all three distinct choices available if a provider fails.
    static func generateSingle(for request: String, feedback: String = "", index: Int,
                               appearance: String = "light") async throws -> ForgeStyleConcept {
        let preferredConfig = AISettingsStore.isUIOverhaulEnabled
            ? AISettingsStore.configuration(for: .ui)
            : AISettingsStore.configuration(for: .planner)
        // A specialist that produces only a fragment must not permanently
        // force every style onto the offline fallback. The regular app model
        // is a useful second chance when the UI specialist runs out of tokens.
        let recoveryConfig = AISettingsStore.configuration(for: .coder)
        let directions = [
            ("Immersive", "Large visual-first product layout", "Dominant product-specific visual or data feature, with overlaid contextual controls and an anchored action sheet"),
            ("Action First", "Bold guided action layout", "Big functional call-to-action, expressive type and asymmetrical summary tiles, with a clear next step"),
            ("Dashboard", "Compact information-first layout", "Realistic domain-specific metrics, a short ordered list or activity feed, and compact controls")
        ]
        let variant = directions[max(0, min(index, directions.count - 1))]
        let user = """
        App idea: \(String(request.prefix(2300)))
        Requested changes: \(String(feedback.prefix(650)))
        Design: \(variant.0) — \(variant.2).
        System appearance: \(appearance). Design in this light/dark mode unless the user explicitly requested another mode.
        Every visible element MUST be relevant to the described app.
        Invent a concrete brand name, realistic starter records, and a meaningful
        primary screen for THIS product. A workout tracker needs workout sets,
        timers and training history; a task manager needs actual task rows;
        a location app needs a map and useful distances. Never use arbitrary
        placeholder sections such as 'My tasks' for unrelated products.
        Never put the entire prompt into the title. No generic "Your Space",
        "Overview", "Make progress your way", "Recent activity" or fake tabs.
        Style \(index + 1) must differ in layout, section order, hierarchy,
        map prominence, button placement and navigation — not merely colors.
        The selected layout archetype is mandatory.
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
        No external resources, external CSS, scripts, JSON, explanation or Markdown.
        No fake iPhone frame, status bar, battery, clock, notch, Dynamic Island
        or home indicator. The iOS host already provides system chrome.
        Honor the user's explicit theme request. Otherwise prefer \(appearance) appearance.
        Use matching background, cards and text contrast; do not force a dark
        theme in a light-mode system or vice versa.
        """
        for attempt in 0..<(ForgeRunOptions.quick ? 1 : 2) {
            try Task.checkCancellation()
            do {
                let config = attempt == 0 ? preferredConfig : recoveryConfig
                let raw = try await AIProviderClient.complete(
                    config: config, system: system, messages: [("user", user)],
                    timeout: ForgeRunOptions.quick ? 55 : (attempt == 0 ? 75 : 90),
                    // Reasoning-capable OpenAI-compatible models may spend
                    // most of max_tokens internally. Small limits yielded
                    // only 190–270 visible characters on iOS 16.2.
                    maxTokens: ForgeRunOptions.quick ? 6500 : (attempt == 0 ? 8500 : 12000),
                    retryOnTransient: false
                )
                if let html = extractHTML(raw) {
                    return ForgeStyleConcept(id: index, name: variant.0,
                        summary: variant.1, direction: variant.2, previewHTML: html)
                }
                await MainActor.run {
                    AIDebugTraceStore.shared.append("STYLE MOCKUP",
                        "Look \(index + 1) attempt \(attempt + 1) from \(config.model) returned \(raw.count) characters but no usable standalone HTML. \(attempt == 0 && !ForgeRunOptions.quick ? "Retrying with the main app model and a larger completion budget." : "")")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = "Look \(index + 1) attempt \(attempt + 1) failed: \(error.localizedDescription)"
                await MainActor.run { AIDebugTraceStore.shared.append("STYLE MOCKUP", message) }
            }
        }
        try Task.checkCancellation()
        await MainActor.run {
            AIDebugTraceStore.shared.append("STYLE MOCKUP",
                "Look \(index + 1) used a locally generated domain-specific sketch after provider output was unavailable.")
        }
        return ForgeStyleConcept(id: index, name: variant.0,
            summary: variant.1 + " (offline preview)",
            direction: variant.2, previewHTML: offlinePreview(request: request, variant: index, appearance: appearance, seed: nil))
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

    private static func offlinePreview(request: String, variant: Int, appearance: String, seed: PreviewSeed?) -> String {
        let query = request.lowercased()
        let dark = query.contains("dark mode") || query.contains("dark theme") ||
            (!query.contains("light mode") && !query.contains("light theme") && appearance == "dark")
        let palettes: [(String, String, String, String)] = dark
            ? [("#121b20", "#223037", "#f4f6ef", "#96dbc5"),
               ("#21182c", "#392649", "#fff3fb", "#fa86bb"),
               ("#0d1b2a", "#1b3245", "#f1f8ff", "#73c8f0")]
            : [("#f5f7f2", "#ffffff", "#18342d", "#278e76"),
               ("#faf2f7", "#ffffff", "#38253a", "#c04784"),
               ("#edf4f8", "#ffffff", "#183447", "#187aa7")]
        let (background, card, ink, accent) = palettes[max(0, min(variant, 2))]
        let brand: String
        let eyebrow: String
        let headline: String
        let action: String
        let first: String
        let second: String
        let third: String
        let metric: String
        if ["workout", "fitness", "gym", "exercise", "lifting", "reps"].contains(where: query.contains) {
            brand = "Route Rep"; eyebrow = "YOUR TRAINING"; headline = "Ready for your next set?"
            action = "Start workout"; first = "Upper-body strength"; second = "4 exercises planned"
            third = "Last session · 32 min"; metric = "12 workouts this month"
        } else if ["route", "map", "nearest", "directions", "restaurant", "location"].contains(where: query.contains) {
            brand = "NearPath"; eyebrow = "PLACES NEAR YOU"; headline = "Your next stop, sorted."
            action = "Find nearest"; first = "Closest destination"; second = "Driving route"
            third = "Estimated arrival"; metric = "Location needed"
        } else if ["calculator", "arithmetic", "maths", "math"].contains(where: query.contains) {
            brand = "Sumline"; eyebrow = "CALCULATOR"; headline = "Calculate anything."
            action = "Calculate"; first = "12 × 8 = 96"; second = "240 ÷ 6 = 40"
            third = "18 + 24 = 42"; metric = "0"
        } else if ["habit", "routine", "streak"].contains(where: query.contains) {
            brand = "Ritual"; eyebrow = "TODAY'S RHYTHM"; headline = "Keep your streak alive."
            action = "Mark habit done"; first = "Morning stretch"; second = "Read for 15 minutes"
            third = "Drink water"; metric = "6-day streak"
        } else if ["todo", "to-do", "task", "planner", "homework"].contains(where: query.contains) {
            brand = "Focus List"; eyebrow = "TODAY'S PLAN"; headline = "Make today feel lighter."
            action = "Add a task"; first = "Finish top priority"; second = "Review upcoming work"
            third = "Plan tomorrow"; metric = "3 tasks to focus on"
        } else if ["budget", "expense", "money", "finance"].contains(where: query.contains) {
            brand = "Pocket Ledger"; eyebrow = "YOUR MONEY"; headline = "Know where it goes."
            action = "Add expense"; first = "Today's purchases"; second = "Monthly budget"
            third = "Savings goal"; metric = "Spending snapshot"
        } else if ["recipe", "food", "meal", "cook"].contains(where: query.contains) {
            brand = "Fresh Table"; eyebrow = "YOUR KITCHEN"; headline = "Make something good."
            action = "Find a recipe"; first = "Weeknight favorites"; second = "Shopping list"
            third = "Meals for this week"; metric = "12 saved recipes"
        } else {
            let words = request.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).filter { !["make", "build", "create", "an", "a", "app", "for", "with", "the", "i", "want"].contains($0.lowercased()) }
            let topic = words.prefix(3).joined(separator: " ")
            brand = topic.isEmpty ? "My Workspace" : String(topic.prefix(35)).capitalized
            eyebrow = "YOUR WORKSPACE"; headline = "Everything in one place."
            action = "Get started"; first = "Recent activity"; second = "Your saved items"
            third = "Quick actions"; metric = "Your daily overview"
        }
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let title = escaped(seed?.brand ?? brand), label = escaped(eyebrow)
        let hero = escaped(seed?.headline ?? headline)
        let cta = escaped(seed?.action ?? action)
        let row1 = escaped(seed?.records[0] ?? first)
        let row2 = escaped(seed?.records[1] ?? second)
        let row3 = escaped(seed?.records[2] ?? third), stat = escaped(metric)
        let overrideAccent = seed?.accent ?? accent
        var content: String
        switch variant {
        case 0:
            content = """
            <div class="feature"><span class="eyebrow">\(label)</span><h1>\(hero)</h1>
            <div class="feature-art"><span class="ring"></span><span class="ring small"></span>
            <span class="chart-bars"><i></i><i></i><i></i><i></i></span></div></div>
            <section class="floating"><small>\(title.uppercased())</small><h2>\(stat)</h2>
            <p>\(row1) · \(row2)</p><button>\(cta) →</button></section>
            """
        case 1:
            content = """
            <section class="hero"><small>\(label)</small><h1>\(hero)</h1>
            <p>\(stat)</p><button>\(cta) →</button></section>
            <div class="tiles"><div><small>UP NEXT</small><strong>\(row1)</strong></div>
            <div><small>PROGRESS</small><strong>\(row2)</strong></div></div>
            <section class="card"><h2>\(title)</h2><p>\(row3)</p></section>
            """
        default:
            content = """
            <header><small>\(label)</small><h1>\(title)</h1><p>\(stat)</p></header>
            <div class="search">＋ &nbsp; \(cta)</div>
            <section class="list"><h2>Today's overview</h2>
            <div class="item"><b>01</b><div><strong>\(row1)</strong><p>Ready to go</p></div></div>
            <div class="item"><b>02</b><div><strong>\(row2)</strong><p>Next on your list</p></div></div>
            <div class="item"><b>03</b><div><strong>\(row3)</strong><p>Keep it moving</p></div></div></section>
            """
        }
        if ["calculator", "arithmetic", "maths", "math"].contains(where: query.contains) {
            switch variant {
            case 0:
                content = """
                <div class="feature calc-layout">
                <small>\(title.uppercased()) / STANDARD</small>
                <p class="calc-formula">480 ÷ 8</p><h1 class="calc-result">60</h1>
                <div class="calc-keypad">
                <span class="function">AC</span><span class="function">±</span><span class="function">%</span><span class="operator">÷</span>
                <span>7</span><span>8</span><span>9</span><span class="operator">×</span>
                <span>4</span><span>5</span><span>6</span><span class="operator">−</span>
                <span>1</span><span>2</span><span>3</span><span class="operator">+</span>
                <span class="zero">0</span><span>.</span><span class="operator">=</span>
                </div></div>
                <section class="floating calc-memory"><small>LAST ANSWER</small>
                <h2>\(row1)</h2><p>Saved in your calculation history</p></section>
                """
            case 1:
                content = """
                <section class="hero calc-hero">
                <small>\(title.uppercased()) / QUICK MATH</small><p class="calc-formula">24 × 6</p>
                <h1 class="calc-result">144</h1>
                <button>New calculation →</button></section>
                <div class="tiles"><div><small>PREVIOUS</small><strong>\(row1)</strong></div>
                <div><small>MEMORY</small><strong>\(row2)</strong></div></div>
                <section class="card"><small>OPERATIONS</small>
                <div class="calc-operations"><span>+</span><span>−</span><span>×</span><span>÷</span></div></section>
                """
            default:
                content = """
                <header><small>\(title.uppercased()) / SCIENTIFIC</small>
                <h1>Calculator</h1><p>Standard • History • Memory</p></header>
                <div class="search calc-sum">120 + 43 <b>= 163</b></div>
                <section class="list"><h2>Calculation history</h2>
                <div class="item"><b>01</b><div><strong>\(row1)</strong><p>Most recent</p></div></div>
                <div class="item"><b>02</b><div><strong>\(row2)</strong><p>Earlier today</p></div></div>
                <div class="item"><b>03</b><div><strong>\(row3)</strong><p>Yesterday</p></div></div></section>
                <div class="calc-operations bottom"><span>sin</span><span>cos</span><span>√</span><span>π</span></div>
                """
            }
        }
        return """
        <!DOCTYPE html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="color-scheme" content="\(dark ? "dark" : "light")">
        <style>*{box-sizing:border-box}body{margin:0;padding:16px;font-family:-apple-system,system-ui,sans-serif;
        background:var(--bg);color:var(--ink)}:root{--bg:\(background);--card:\(card);--ink:\(ink);--accent:\(overrideAccent)}
        h1{font-size:clamp(29px,6vw,46px);letter-spacing:-.045em;line-height:1.09}
        h2{font-size:22px;margin:5px 0 13px}small,.eyebrow{font-size:11px;letter-spacing:.15em;font-weight:800;opacity:.75}
        p{line-height:1.45;opacity:.75}button,.search{background:var(--accent);color:white;border:0;border-radius:16px;padding:16px;font-weight:800}
        .feature{min-height:67vh;position:relative;border-radius:30px;overflow:hidden;padding:28px;color:var(--ink);
        background:linear-gradient(155deg,var(--card),var(--bg))}
        .feature h1{position:relative;z-index:2;max-width:290px}
        .feature-art{position:absolute;inset:25% 0 0;background:repeating-linear-gradient(138deg,transparent 0 46px,var(--accent) 48px 53px,transparent 55px 112px);opacity:.38}
        .ring{position:absolute;width:190px;height:190px;border:16px solid var(--accent);border-radius:50%;right:-30px;bottom:45px}
        .ring.small{width:100px;height:100px;border-width:9px;left:25px;bottom:115px}
        .chart-bars{display:flex;align-items:end;gap:12px;position:absolute;bottom:20px;left:25%;height:90px}
        .chart-bars i{display:block;width:18px;height:40%;border-radius:10px;background:var(--accent)}
        .chart-bars i:nth-child(2){height:75%}.chart-bars i:nth-child(3){height:52%}.chart-bars i:nth-child(4){height:100%}
        .floating{position:relative;margin:-85px 10px 0;padding:24px;background:var(--card);border-radius:28px;box-shadow:0 12px 30px #0002}
        .floating button{width:100%;margin-top:8px}.hero{padding:35px 27px;background:var(--card);border-radius:36px;min-height:390px;
        display:flex;flex-direction:column;align-items:flex-start;justify-content:center}
        .hero button{margin-top:16px}.tiles{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:14px 0}
        .tiles>div,.card,.list{background:var(--card);border-radius:24px;padding:21px}
        .tiles strong{display:block;margin-top:13px;font-size:18px}.card{margin-top:12px}
        header{padding:25px 0 12px;border-bottom:3px solid var(--accent)}
        .search{margin:20px 0;border-radius:13px}.list{border-radius:16px}
        .item{display:flex;gap:17px;align-items:center;padding:17px 0;border-top:1px solid #8884}
        .item b{color:var(--accent)}.item p{margin:4px 0;font-size:13px}
        .calc-layout{padding:28px 18px 120px;min-height:780px}.calc-formula{text-align:right;font-size:25px;opacity:.66;margin:40px 3px 2px}
        .calc-result{text-align:right;font-size:72px;font-weight:300;letter-spacing:-.06em;margin:0 3px 18px}
        .calc-keypad{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin-top:20px}
        .calc-keypad span{display:grid;place-items:center;height:60px;border-radius:50px;background:var(--bg);font-size:24px}
        .calc-keypad .function{background:var(--accent);color:var(--bg)}
        .calc-keypad .operator{background:var(--accent);color:var(--bg);font-weight:700}
        .calc-keypad .zero{grid-column:span 2;justify-content:start;padding-left:24px}
        .calc-memory{margin-top:-110px}.calc-memory h2{font-size:27px}
        .calc-hero{min-height:400px;background:var(--accent);color:var(--bg);justify-content:end}
        .calc-hero .calc-formula{margin:18px 0 0;opacity:.8}.calc-hero h1{font-size:80px}
        .calc-hero button{background:var(--bg);color:var(--ink)}
        .calc-operations{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:15px}
        .calc-operations span{background:var(--bg);padding:17px 4px;border-radius:14px;text-align:center;font-size:22px}
        .calc-operations.bottom{margin-top:15px}.calc-sum{display:flex;justify-content:space-between;gap:10px}
        .calc-sum b{white-space:nowrap}
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
