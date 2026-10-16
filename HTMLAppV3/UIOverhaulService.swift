import Foundation

enum UIOverhaulService {
    static func polish(html: String, originalPrompt: String) async throws -> String {
        let config = AISettingsStore.uiConfiguration
        guard AISettingsStore.isUIOverhaulEnabled else { return html }

        let system = """
You are HTMLApp's optional UI refinement model. You receive a finished, functioning, fragile single-file HTML app created by another model. Improve only its presentation so it feels like a polished animated mobile iOS application.

NON-NEGOTIABLE RULES:
- Preserve every existing feature, behavior, API call, event listener, storage key, data flow, permission flow, form field, button action, navigation destination, external endpoint, widget definition, background job, and user-visible capability.
- Do not invent facts, live values, fake API results, fake users, fake reviews, fake availability, or unsupported capabilities. Preserve honest loading/error/unavailable states.
- Do not add features. Do not remove features. Do not rename or repurpose controls.
- Do not rewrite working JavaScript unless a tiny change is absolutely required for presentation or animation.
- Treat the HTML as fragile. Make the smallest practical changes.
- Prefer CSS improvements, spacing, typography, hierarchy, safe areas, touch sizing, materials, responsive layout, visual states, and motion.
- SAFE AREA IS MANDATORY: preserve/add viewport-fit=cover and env(safe-area-inset-top/right/bottom/left). The app runs edge-to-edge; interactive content and top chrome must not sit under the notch/Dynamic Island/status bar, bottom controls must clear the Home Indicator, and landscape must respect side cutouts. Do not double-apply an inset.
- Make interactions feel alive like a native mobile app: pressed states, smooth screen transitions, sheets/overlays, tasteful spring-like movement, subtle loading transitions, and feedback that communicates state. Respect prefers-reduced-motion and never animate just for decoration.
- Preserve element IDs, classes used by JavaScript, data attributes, function names, script order, and DOM relationships that behavior may depend on.
- Do not replace real content with placeholders or demo data.
- Do not introduce frameworks, build tools, new remote dependencies, analytics, tracking, private keys, or undocumented endpoints.
- Keep it one self-contained HTML file.
- Do not remove or rewrite HTMLAppNative.widgets/background/appStorage integrations merely because they do not affect foreground visuals.
- Make it feel native on iPhone and iPad: Apple system typography, restrained iOS-style materials, grouped surfaces where appropriate, 44px minimum touch targets, safe-area padding, clear hierarchy, polished light/dark appearance, and strong mobile ergonomics.
- Avoid generic SaaS styling, desktop dashboards, excessive gradients, neon glow, excessive blur, emoji-as-icons, and decorative changes that reduce usability.
- If the UI is already strong, make only conservative refinements.

Return only:
<htmlapp_code>the complete revised HTML document</htmlapp_code>
Do not include Markdown fences or commentary.
"""

        let user = """
Original user request:
<original_prompt>
\(originalPrompt)
</original_prompt>

Finished functioning HTML app to visually refine without changing functionality:
<htmlapp_existing>
\(html)
</htmlapp_existing>
"""

        let response = try await AIProviderClient.complete(
            config: config,
            system: system,
            messages: [("user", user)]
        )

        guard let polished = extractHTML(from: response),
              !polished.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIGenerationError.missingHTML
        }
        return polished
    }

    private static func extractHTML(from text: String) -> String? {
        let open = "<htmlapp_code>"
        let close = "</htmlapp_code>"
        guard let start = text.range(of: open),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
    }
}
