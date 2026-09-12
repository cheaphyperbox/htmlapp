import Foundation

enum UIOverhaulService {
    static func polish(html: String, originalPrompt: String) async throws -> String {
        let config = AISettingsStore.uiConfiguration
        guard AISettingsStore.isUIOverhaulEnabled else { return html }

        let system = """
You are HTMLApp's optional UI-only refinement model. You receive a finished, functioning, fragile single-file HTML app created by another model. Improve only its presentation so it feels more like a polished mobile iOS application.

NON-NEGOTIABLE RULES:
- Preserve every existing feature, behavior, API call, event listener, storage key, data flow, permission flow, form field, button action, navigation destination, external endpoint, and user-visible capability.
- Do not add features. Do not remove features. Do not rename or repurpose controls.
- Do not rewrite working JavaScript unless a tiny change is absolutely required for presentation.
- Treat the HTML as fragile. Make the smallest practical changes.
- Prefer CSS improvements, spacing, typography, hierarchy, safe areas, touch sizing, materials, responsive layout, and visual states.
- Preserve element IDs, classes used by JavaScript, data attributes, function names, script order, and DOM relationships that behavior may depend on.
- Do not replace real content with placeholders.
- Do not introduce frameworks, build tools, new remote dependencies, analytics, tracking, or private keys.
- Keep it one self-contained HTML file.
- Make it feel native on iPhone: Apple system typography, restrained iOS-style materials, grouped surfaces where appropriate, 44px minimum touch targets, safe-area padding, clear hierarchy, polished light/dark appearance, subtle spring-like motion, and good mobile ergonomics.
- Avoid generic SaaS styling, desktop dashboards, excessive gradients, neon glow, excessive blur, and decorative changes that reduce usability.
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
