import Foundation

struct UIOverhaulResult: Sendable {
    let html: String
    let changedOnlyCSS: Bool
}

enum UIOverhaulService {
    static func polish(html: String, originalPrompt: String) async throws -> UIOverhaulResult {
        let config = AISettingsStore.uiConfiguration
        guard AISettingsStore.isUIOverhaulEnabled else {
            return UIOverhaulResult(html: html, changedOnlyCSS: true)
        }

        let system = """
You are HTMLApp's optional UI refinement model. You receive a finished, functioning, fragile single-file HTML app. Improve only its presentation with the smallest exact patch.

NON-NEGOTIABLE RULES:
- Preserve every feature, API call, event listener, storage key, form field, control action, navigation path, endpoint, widget/background definition, and user-visible capability.
- Do not rewrite or modify any <script> block.
- Prefer CSS-only changes. Markup changes are allowed only when required for presentation and must preserve IDs, classes used by JavaScript, data attributes, form semantics, and DOM relationships.
- Keep safe-area handling, viewport-fit=cover, dark mode, reduced motion, accessibility, 44px touch targets, and iPhone/iPad responsiveness intact or improve them.
- Preserve car display adaptation: html[data-htmlapp-display="car"], window.HTMLAppDisplay, htmlapp:display-change, short-landscape scrolling and --htmlapp-tabbar-height. Use at least 48px targets in car mode, avoid dense detail and oversized headers, and keep primary controls visible above native chrome.
- Do not add frameworks, remote dependencies, fake data, unsupported capabilities, analytics, tracking, or new features.
- Give this app a distinct visual identity rather than automatically using teal/green. Textures, depth, editorial typography or gradients are appropriate when the product supports them. Keep animations tactile and functional, with reduced-motion support.
- If the UI is already strong, return an empty patch rather than rewriting it.

Return only:
<htmlapp_patch>
<<<<<<< SEARCH
exact unique source copied from the existing HTML
=======
replacement source
>>>>>>> REPLACE
</htmlapp_patch>

You may include multiple blocks. A full HTML replacement is not allowed.
"""

        let user = """
User visual taste (optional): \(AISettingsStore.creativeDirection)

Original user request:
<original_prompt>
\(originalPrompt)
</original_prompt>

Finished functioning HTML app:
<htmlapp_existing>
\(html)
</htmlapp_existing>
"""

        let response = try await AIProviderClient.complete(
            config: config,
            system: system,
            messages: [("user", user)],
            timeout: 90,
            maxTokens: 6000,
            retryOnTransient: true
        )

        let patch = AIHTMLAgent.parse(response).patch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !patch.isEmpty else {
            return UIOverhaulResult(html: html, changedOnlyCSS: true)
        }
        guard let polished = HTMLPatchApplier.apply(patch, to: html) else {
            throw AIGenerationError.invalidPatch
        }
        guard scriptBlocks(in: polished) == scriptBlocks(in: html) else {
            throw AIGenerationError.provider("UI Overhaul attempted to modify app behavior, so the visual change was rejected.")
        }

        return UIOverhaulResult(
            html: polished,
            changedOnlyCSS: nonStyleContent(in: polished) == nonStyleContent(in: html)
        )
    }

    private static func scriptBlocks(in html: String) -> [String] {
        matches(#"(?is)<script\b[^>]*>.*?</script>"#, in: html)
    }

    private static func nonStyleContent(in html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<style\b[^>]*>.*?</style>"#) else { return html }
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: "<style></style>"
        )
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}

