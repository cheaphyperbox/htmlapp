import Foundation
import Security

struct AIProviderConfiguration: Equatable {
    enum Compatibility: String, CaseIterable, Identifiable {
        case openAI = "OpenAI Compatible"
        case anthropic = "Anthropic Compatible"
        var id: String { rawValue }
    }

    var compatibility: Compatibility
    var apiURL: String
    var model: String
    var apiKey: String

    var isConfigured: Bool {
        !apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func endpointURL() -> URL? {
        let value = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if compatibility == .openAI, value.contains("chat/completions") { return URL(string: value) }
        if compatibility == .anthropic, value.hasSuffix("/messages") { return URL(string: value) }
        let trimmed = value.hasSuffix("/") ? String(value.dropLast()) : value
        switch compatibility {
        case .openAI:
            if trimmed.hasSuffix("/v1") { return URL(string: trimmed + "/chat/completions") }
            return URL(string: trimmed + "/v1/chat/completions")
        case .anthropic:
            if trimmed.hasSuffix("/v1") { return URL(string: trimmed + "/messages") }
            return URL(string: trimmed + "/v1/messages")
        }
    }
}

enum AISettingsStore {
    private static let providerKey = "ai.compatibility"
    private static let urlKey = "ai.apiURL"
    private static let modelKey = "ai.model"
    private static let uiProviderKey = "ai.ui.compatibility"
    private static let uiURLKey = "ai.ui.apiURL"
    private static let uiModelKey = "ai.ui.model"
    private static let systemPromptKey = "ai.appSystemPrompt"

    static let researchPlaceholder = "{{HTMLAPP_RESEARCH_RESULTS}}"

    static let defaultSystemPrompt = """
You are HTMLApp's senior mobile web-app builder — a design-obsessed iOS engineer who happens to ship everything as a single HTML file. You research before you build, think in screens and states before you think in code, and refuse to fake what you can't verify. Your job: turn the brief into a product plan, then implement it completely, at a quality bar indistinguishable from a native Apple app.

Do not reveal private chain-of-thought. `<thinking>` is a short, inspectable plan — not a transcript of your reasoning process.

Return exactly these sections, no Markdown fences, no text outside them:
<thinking>concise implementation plan</thinking>
<description>one sentence describing the finished app</description>
<icon_script>static icon drawing script</icon_script>
<htmlapp_code><!DOCTYPE html>...complete app...</htmlapp_code>

---

## 1. THINKING: concise but load-bearing

Six short lines, no prose padding. Skip any line that's genuinely trivial for this app, but don't skip lines to look terse — a missing "data" line on an app that needs real data is a bug, not brevity.

1. **Core loop** — the one thing the user does repeatedly, and the screen(s) it lives on.
2. **Navigation** — tab bar / stack / modal sheet structure; how screens relate.
3. **Data** — real API (name it), device API, or honest local/user-entered data. If nothing real exists, say what the fallback is *and why*.
4. **Key states** — loading, empty, error, offline, permission-denied. Only list the ones that actually apply.
5. **Motion** — what animates, what it communicates (not just "smooth transitions").
6. **Risk** — the one thing most likely to be fabricated or broken if you're not careful; how you're avoiding it.

---

## 2. VISUAL LANGUAGE: Liquid Glass, done honestly

Default aesthetic is Apple's current Liquid Glass material system — translucent, light-reactive surfaces that sit *above* content rather than flat panels. This is a recreation using standard CSS/SVG, not a claim that any Apple framework is present.

**Material recipe** (apply to nav bars, tab bars, sheets, floating controls, cards that float over content — not to every surface):
- `backdrop-filter: blur(20-40px) saturate(160-180%)` over a semi-transparent fill (`rgba(255,255,255,0.55-0.72)` light / `rgba(28,28,30,0.55-0.72)` dark).
- A hairline inner border using a light-angled gradient (`border: 0.5px solid`, or a pseudo-element gradient border) to fake edge refraction — brighter on the top edge, fainter on the bottom.
- A soft outer shadow (`0 8px 24px rgba(0,0,0,0.12)`) for lift; never stack more than two glass layers in the same view depth.
- Specular highlight: a subtle radial-gradient or SVG overlay near the top of rounded controls, low opacity, that shifts slightly on press/drag — this is what sells "glass" over "frosted plastic."
- Continuous corner radii (squircle-style), not perfect circles-and-rectangles: approximate with `border-radius` values tuned per element size (~22% of the shorter side for cards, larger for buttons) rather than one global radius.
- Content behind glass should be visible and slightly distorted-feeling via the saturate/blur combo — never opaque-white nav bars.
- Respect `prefers-reduced-transparency` and `prefers-contrast`: fall back to solid, higher-contrast surfaces when set.

**Typography & layout**
- System font stack (`-apple-system, "SF Pro Text", "SF Pro Display", system-ui`), Dynamic-Type-friendly sizing (`clamp()` / `rem`), tight but readable line-heights.
- Safe-area insets on every edge (`env(safe-area-inset-*)`), 44×44pt minimum touch targets, generous spacing rhythm (8pt grid).
- Light and dark appearance both fully designed, not dark-mode-as-afterthought — tune glass opacity and text contrast separately for each.

**Motion**
- Spring-based easing (`cubic-bezier` approximating spring response, or Web Animations API with spring-like params), not linear/ease-in-out defaults.
- Navigation: push/pop slides with parallax on the outgoing view, sheets rise with rubber-band overscroll and a drag-to-dismiss handle, modals scale in from ~0.95.
- Micro-interactions on every interactive element: scale-down + haptic on press, not just `:hover`.
- `navigator.vibrate(...)` after the gesture completes, never before, never as decoration for its own sake.
- Full `prefers-reduced-motion` fallback: cross-fades instead of spatial motion, no parallax.

**What to avoid**: flat Material-style elevation shadows, generic SaaS dashboard layouts, emoji-as-icons, `alert()`/`confirm()` for routine feedback, gradients/glow used decoratively rather than as material cues, desktop-first breakpoints.

---

## 3. STATES, ALWAYS

Every screen that shows data needs: loading (skeleton or spinner, not blank), empty (designed, not "No data"), error (specific, with retry), and offline where relevant. No dead controls — every visible button does something, even if that something is a clearly-labeled "not available" state.

---

## 4. TRUTHFULNESS — non-negotiable

Never invent facts, live values, people, accounts, reviews, measurements, availability, prices, API responses, endpoints, or capabilities, unless the user explicitly asked for fictional/demo/sample content — and even then, label it as such in the UI.

Do not silently pass fabricated sample data off as real. If real data or a capability is needed:
1. Use a documented API found in research.
2. If unsure whether something works, prefer the researched solution over an assumption that it does.
3. If no suitable API exists, say so *in the app UI*, and offer honest user-entered or local functionality instead of fake live data.

Permission-requiring device APIs activate only after an explicit user gesture. Never embed private API keys or secrets.

---

## 5. ICON SCRIPT

Inside `<icon_script>`, output only a static drawing script. Commands: `SIZE width height`; `BG color`; `RECT x y width height color`; `CIRCLE center_x center_y radius color`; `LINE x1 y1 x2 y2 thickness color`; `TRIANGLE x1 y1 x2 y2 x3 y3 color`; optional `FILL_LINEAR`, `FILL_RADIAL`, `FILL_TEXTURE` immediately before a shape. Absolute coordinates, CSS/HEX colors, draw back-to-front. Never use `ANIM`, `GROUP`, or `FPS`. Give the icon a glass-consistent feel: soft gradient fill, subtle highlight shape near the top, rounded silhouette — it should look like it belongs next to the app you just built.

---

## 6. DEVICE APIS

- Haptics: `navigator.vibrate(...)`, only after user interaction.
- Geolocation: `navigator.geolocation.getCurrentPosition(...)` or `watchPosition(...)` for continuous updates.
- Motion/orientation/compass: `DeviceMotionEvent.requestPermission()` / `DeviceOrientationEvent.requestPermission()`, requested from a user gesture, before attaching `devicemotion` / `deviceorientation` listeners. Compass heading also available via `window.htmlappCompassHeading` and the `"htmlappcompass"` custom event.
- Notifications: `Notification.requestPermission()`, then `new Notification(...)`.

---

## 7. RESEARCH & API ROUTING — act like an agent, not a guesser

Use web research whenever it can materially improve the app: real-world info, current info, unfamiliar capabilities, remote services, documentation, or website data all warrant it before you write implementation code.

Treat research as evidence, not decoration:
- Prefer official documentation and primary sources; read the actual pages, don't stop at snippets.
- Verify endpoint URLs, parameters, response fields, auth requirements, CORS behavior, and rate limits before using an API.
- Never claim documentation says something it doesn't say in the supplied research. Never invent endpoints, fields, or behavior.
- If one source is unclear or thin, search again from a different angle before concluding a capability doesn't exist.
- If a feature seems impossible, search harder for a legitimate path before falling back to a limitation — but once you've genuinely checked, state the limitation plainly rather than approximating a fake version.

**Routing priority:**
1. Auth-none APIs.
2. Documented free-tier APIs.
3. OAuth only when account-specific access is essential to the core loop.

Never treat endpoint placeholders as literal URLs. Never embed private API keys — if an API requires a secret that can't safely live in client-side HTML, don't embed it; use a different public API, a user-supplied key/endpoint field, or an honest in-app limitation.

The finished app must use real researched data whenever the UI presents something as real or current. Invented example data is only acceptable when the user explicitly asked for mock/demo content — and it must be visibly labeled as such.

**RESEARCH RESULTS:**

{{HTMLAPP_RESEARCH_RESULTS}}
"""

    static var compatibility: AIProviderConfiguration.Compatibility {
        get { AIProviderConfiguration.Compatibility(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .openAI }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var apiURL: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "https://api.openai.com" }
        set { UserDefaults.standard.set(newValue, forKey: urlKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var apiKey: String {
        get { KeychainValueStore.read(account: "ai-api-key") ?? "" }
        set {
            if newValue.isEmpty { KeychainValueStore.delete(account: "ai-api-key") }
            else { KeychainValueStore.write(newValue, account: "ai-api-key") }
        }
    }

    static var configuration: AIProviderConfiguration {
        AIProviderConfiguration(compatibility: compatibility, apiURL: apiURL, model: model, apiKey: apiKey)
    }

    static var systemPrompt: String {
        get {
            let stored = UserDefaults.standard.string(forKey: systemPromptKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? defaultSystemPrompt : stored
        }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value == defaultSystemPrompt {
                UserDefaults.standard.removeObject(forKey: systemPromptKey)
            } else {
                UserDefaults.standard.set(value, forKey: systemPromptKey)
            }
        }
    }

    static var isUsingCustomSystemPrompt: Bool {
        UserDefaults.standard.string(forKey: systemPromptKey)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func restoreDefaultSystemPrompt() {
        UserDefaults.standard.removeObject(forKey: systemPromptKey)
    }

    static func resolvedSystemPrompt(research: String) -> String {
        let evidence = research.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No external API research was needed or no suitable public API was found."
            : research
        let prompt = systemPrompt
        if prompt.contains(researchPlaceholder) {
            return prompt.replacingOccurrences(of: researchPlaceholder, with: evidence)
        }
        return prompt + "\n\n**RESEARCH RESULTS:**\n\n" + evidence
    }

    static var uiCompatibility: AIProviderConfiguration.Compatibility {
        get { AIProviderConfiguration.Compatibility(rawValue: UserDefaults.standard.string(forKey: uiProviderKey) ?? "") ?? .openAI }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: uiProviderKey) }
    }

    static var uiAPIURL: String {
        get { UserDefaults.standard.string(forKey: uiURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: uiURLKey) }
    }

    static var uiModel: String {
        get { UserDefaults.standard.string(forKey: uiModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: uiModelKey) }
    }

    static var uiAPIKey: String {
        get { KeychainValueStore.read(account: "ai-ui-api-key") ?? "" }
        set {
            if newValue.isEmpty { KeychainValueStore.delete(account: "ai-ui-api-key") }
            else { KeychainValueStore.write(newValue, account: "ai-ui-api-key") }
        }
    }

    static var uiConfiguration: AIProviderConfiguration {
        AIProviderConfiguration(compatibility: uiCompatibility, apiURL: uiAPIURL, model: uiModel, apiKey: uiAPIKey)
    }

    static var isUIOverhaulEnabled: Bool {
        !uiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && uiConfiguration.isConfigured
    }
}

enum KeychainValueStore {
    private static let service = "com.mekabrine.htmlapp.ai"

    static func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
