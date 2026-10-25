import Foundation
import Security

/// Task-local so simultaneous normal and QUICK! generations cannot change
/// one another's model selection or leave a global override behind.
enum ForgeRunOptions {
    @TaskLocal static var quick = false
}

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
        if compatibility == .openAI {
            if value.contains("chat/completions") { return URL(string: value) }
            // Gemini OpenAI compatibility uses /v1beta/openai/chat/completions, not /v1/chat/completions.
            if value.hasSuffix("/v1beta/openai") { return URL(string: value + "/chat/completions") }
        }
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

enum AIModelRole: String, CaseIterable, Identifiable {
    case planner
    case coder
    case research
    case ui
    case icon
    case verifier

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planner: return "Prompt Planner"
        case .coder: return "Coding Agent"
        case .research: return "Research Agent"
        case .ui: return "UI Overhaul"
        case .icon: return "Icon & Asset Artist"
        case .verifier: return "QA Verifier"
        }
    }

    var detail: String {
        switch self {
        case .planner: return "Turns rough ideas into a complete product plan and anticipates useful next-step features."
        case .coder: return "Builds and edits the actual HTMLApp."
        case .research: return "Chooses searches/pages and summarizes current web evidence."
        case .ui: return "Optionally performs a conservative visual refinement after the functional build."
        case .icon: return "Designs app icons and generated visual assets using IconScript."
        case .verifier: return "Audits finished apps, proposes exact repairs, and rechecks them before save."
        }
    }
}

enum AISettingsStore {
    private static let providerKey = "ai.compatibility"
    private static let urlKey = "ai.apiURL"
    private static let modelKey = "ai.model"
    private static let quickModelKey = "ai.quickModel"
    private static let plannerModelKey = "ai.role.plannerModel"
    private static let researchModelKey = "ai.role.researchModel"
    private static let uiModelKey = "ai.ui.model"
    private static let iconModelKey = "ai.role.iconModel"
    private static let verifierModelKey = "ai.role.verifierModel"
    private static let systemPromptKey = "ai.appSystemPrompt"
    private static let requestDelayKey = "ai.requestDelaySeconds"

    static let researchPlaceholder = "{{HTMLAPP_RESEARCH_RESULTS}}"

    static let nativeAPIReference = """
HTMLAPP NATIVE API REFERENCE (always available in saved apps):
window.HTMLAppNative exposes Promise-based wrappers for: device.info/keepAwake, clipboard.readText/writeText, haptics.play, share.present, system.open, externalApps.maps/shortcuts, files.pick, contacts.pick/list/create, photos.pick/save, calendar.createEvent/events/updateEvent/deleteEvent, reminders.create/list/update/delete, notifications.schedule/cancel, biometrics.authenticate, secureStorage.set/get/remove, appStorage.get/set/remove/all/clear, widgets.configure/list/remove/reload, background.configure/list/remove/refreshNow, liveActivities.start/update/end/list (iOS 16.2+, user permission), and speech.speak/stop.

The generation pipeline can also inject HTMLAPP DEVICE API CATALOG RESULTS. Those results are the authoritative searchable reference for exact method names, usage examples, return-shape notes, permission expectations, and limitations. Prefer them over remembered assumptions about iOS or Safari. If the catalog says a capability is unavailable, do not invent a bridge for it.

Sensitive methods can reject for cancellation or permission denial. Use only documented methods and feature-detected browser APIs.
"""

    static let defaultSystemPrompt = ForgeProductContract.rules + "\n\n" + """
You are HTMLApp Forge, a product engineer and creative director. Deliver a finished, reliable app on the first pass, not a demo.

PRODUCT: Build the user's core workflow from start to finish; anticipate no more than two genuinely useful adjacent conveniences. Implement persistent state, form validation, undo/recovery when appropriate, error/empty/offline states, and real handlers for every control. Examine every navigation path, modal, mutation, state update, storage read/write, and async failure before output. Do not claim unperformed testing or guarantee perfection. Keep the code self-contained, maintainable, accessible and secure.

SCOPE AND CODE SAFETY: For a straightforward offline app, prefer 1–2 excellent screens instead of four tabs, oversized histories, settings panels, and dozens of optional features. Keep the initial HTML and JavaScript compact and easy to validate. Do not compress event handlers, markup construction, and nested template literals into huge one-line expressions. Every inline <script> must be valid, independently parseable JavaScript; broken syntax disables all actions. Ensure the initial boot and event registration execute even when native permissions are denied.

DESIGN: Invent this product's identity rather than repeat a template. Pick a distinct palette, typography, information hierarchy, shapes, surfaces, icon metaphor, and motion language to suit its purpose. Do not default to green/teal, checkmarks, identical rounded cards, or a generic "modern iOS" skin. A rich, editorial, tactile, colorful, quiet, classic or minimalist direction can all be right depending on the app. Interpret the user's optional visual taste flexibly; their taste is not a fixed layout or color requirement. Support light/dark contrast and Dynamic Type where practical.

MOTION: Normal interactive controls should feel like polished iOS apps. If a tab bar is used, the current-tab highlight should subtly squish on press, stretch toward the destination, and settle elastically into the selected tab with smooth easing (about 180–300ms). Buttons respond promptly with press-scale feedback; sheets, menus and popovers ease in and out with gentle transform/opacity transitions and natural overshoot only where appropriate. Use CSS transitions/keyframes with reliable touch/pointer behavior, and honor prefers-reduced-motion. Never animate just for decoration.

RUNTIME: Return one complete semantic HTML document with embedded CSS/JS, <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"> and correct iPhone/iPad safe areas. Design and test mentally for narrow iPhone (320–390 CSS px), regular iPhone (390–430 CSS px), and iPad (768–1024 CSS px). Never use hardcoded pixel positions or viewport-proportional font sizes that enlarge controls disproportionately between phones and tablets; use clamp(), rem, flex/grid minmax(), max-width, and media queries. Floating create buttons must clear the tab bar, content and bottom safe-area on all sizes; touch controls must remain reachable and never overlap or stretch.  Use documented HTMLAppNative interfaces when available, portable appStorage for valuable user data, and user-consented permissions. Do not invent device bridges, external API behavior, credentials, or fake live content. Ensure scrolling, keyboard, bottom navigation, focus, and overlays work on small phones and iPad.

ICON: Supply a bespoke, clear iOS-style IconScript with SIZE 1024 1024 and opaque BG. Prefer one recognizable product-specific symbol, tasteful layers, and a distinct palette. Avoid dense illustration, unnecessary detailing, repeated flat tickmarks or generic discs. The icon specialist may replace the draft.

PROGRESS: Insert 3–6 HTMLAPP_PROGRESS HTML comments at meaningful boundaries, each with a concise human-readable status. Saved HTML strips these comments.

OUTPUT ONLY, in this order, without Markdown fences:
<build_summary>Eight concise lines: Intent, Core loop, Structure, Data & state, Capabilities, Edge cases, Experience, Validation.</build_summary>
<description>A one-sentence product summary.</description>
<icon_script>Complete supported IconScript drawing.</icon_script>
<asset_scripts>Optional original assets, otherwise empty.</asset_scripts>
<htmlapp_code><!DOCTYPE html>...complete self-contained app...</htmlapp_code>

Before finishing, recheck all primary user actions, persistence, state updates, closures, errors, color contrast, reduced motion, and responsiveness. Repair clear defects internally before returning.

RESEARCH RESULTS
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
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey) }
    }

    static var quickModel: String {
        get { UserDefaults.standard.string(forKey: quickModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: quickModelKey) }
    }

    static var plannerModel: String {
        get { UserDefaults.standard.string(forKey: plannerModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? model }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: plannerModelKey) }
    }

    static var researchModel: String {
        get { UserDefaults.standard.string(forKey: researchModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? plannerModel }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: researchModelKey) }
    }

    static var uiModel: String {
        get { UserDefaults.standard.string(forKey: uiModelKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: uiModelKey) }
    }

    static var iconModel: String {
        get { UserDefaults.standard.string(forKey: iconModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? model }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: iconModelKey) }
    }

    static var verifierModel: String {
        get { UserDefaults.standard.string(forKey: verifierModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? model }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: verifierModelKey) }
    }

    static var apiKey: String {
        get { KeychainValueStore.read(account: "ai-api-key") ?? "" }
        set {
            if newValue.isEmpty { KeychainValueStore.delete(account: "ai-api-key") }
            else { KeychainValueStore.write(newValue, account: "ai-api-key") }
        }
    }

    static func model(for role: AIModelRole) -> String {
        switch role {
        case .planner: return plannerModel
        case .coder: return model
        case .research: return researchModel
        case .ui: return uiModel.isEmpty ? model : uiModel
        case .icon: return iconModel
        case .verifier: return verifierModel
        }
    }

    static func usesSpecialistProvider(for role: AIModelRole) -> Bool {
        if ForgeRunOptions.quick && !quickModel.isEmpty { return false }
        return UserDefaults.standard.bool(forKey: "ai.specialist.\(role.rawValue).enabled")
    }

    static func setSpecialistProvider(_ enabled: Bool, for role: AIModelRole) {
        UserDefaults.standard.set(enabled, forKey: "ai.specialist.\(role.rawValue).enabled")
    }

    static func specialistConfiguration(for role: AIModelRole) -> AIProviderConfiguration {
        let prefix = "ai.specialist.\(role.rawValue)"
        return AIProviderConfiguration(
            compatibility: AIProviderConfiguration.Compatibility(rawValue: UserDefaults.standard.string(forKey: prefix + ".format") ?? "") ?? compatibility,
            apiURL: UserDefaults.standard.string(forKey: prefix + ".url") ?? apiURL,
            model: UserDefaults.standard.string(forKey: prefix + ".model") ?? model(for: role),
            apiKey: KeychainValueStore.read(account: prefix + ".key") ?? ""
        )
    }

    static func saveSpecialistConfiguration(_ config: AIProviderConfiguration, for role: AIModelRole) {
        let prefix = "ai.specialist.\(role.rawValue)"
        UserDefaults.standard.set(config.compatibility.rawValue, forKey: prefix + ".format")
        UserDefaults.standard.set(config.apiURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: prefix + ".url")
        UserDefaults.standard.set(config.model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: prefix + ".model")
        if config.apiKey.isEmpty { KeychainValueStore.delete(account: prefix + ".key") }
        else { KeychainValueStore.write(config.apiKey, account: prefix + ".key") }
    }

    static func configuration(for role: AIModelRole) -> AIProviderConfiguration {
        if ForgeRunOptions.quick && !quickModel.isEmpty {
            return AIProviderConfiguration(compatibility: compatibility, apiURL: apiURL,
                                           model: quickModel, apiKey: apiKey)
        }
        if usesSpecialistProvider(for: role) { return specialistConfiguration(for: role) }
        return AIProviderConfiguration(
            compatibility: compatibility,
            apiURL: apiURL,
            model: model(for: role),
            apiKey: apiKey
        )
    }

    static var appearancePreference: String {
        get { UserDefaults.standard.string(forKey: "ai.appearancePreference") ?? "" }
        set { UserDefaults.standard.set(String(newValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)), forKey: "ai.appearancePreference") }
    }

    static var creativeDirection: String {
        let preference = appearancePreference
        return preference.isEmpty ? "Choose a distinct style for this product without generic template defaults."
            : "Optional user aesthetic preference (interpret flexibly): \(preference)"
    }

    static var configuration: AIProviderConfiguration {
        configuration(for: .coder)
    }

    static var requestDelaySeconds: Double {
        get {
            if UserDefaults.standard.object(forKey: requestDelayKey) == nil { return 0 }
            return max(0, min(60, UserDefaults.standard.double(forKey: requestDelayKey)))
        }
        set {
            UserDefaults.standard.set(max(0, min(60, newValue)), forKey: requestDelayKey)
        }
    }

    // Legacy prompt overrides must never replace the maintained built-in
    // agent contract. The old UserDefaults key is ignored and cleaned up.
    static var systemPrompt: String {
        get { defaultSystemPrompt }
        set { UserDefaults.standard.removeObject(forKey: systemPromptKey) }
    }

    static var isUsingCustomSystemPrompt: Bool { false }

    static func restoreDefaultSystemPrompt() {
        UserDefaults.standard.removeObject(forKey: systemPromptKey)
    }

    static func resolvedSystemPrompt(research: String) -> String {
        let evidence = research.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No additional device-capability or public-API research was needed."
            : research
        let prompt = systemPrompt + "\n\nUSER VISUAL TASTE\n" + creativeDirection
        let resolved: String
        if prompt.contains(researchPlaceholder) {
            resolved = prompt.replacingOccurrences(of: researchPlaceholder, with: evidence)
        } else {
            resolved = prompt + "\n\nRESEARCH RESULTS\n" + evidence
        }
        if resolved.contains("window.HTMLAppNative") { return resolved }
        return resolved + "\n\n" + nativeAPIReference
    }

    // Legacy aliases remain so older settings state and call sites migrate cleanly.
    // All task models now use one provider, base URL, and Keychain API key.
    static var uiCompatibility: AIProviderConfiguration.Compatibility {
        get { compatibility }
        set { compatibility = newValue }
    }

    static var uiAPIURL: String {
        get { apiURL }
        set { apiURL = newValue }
    }

    static var uiAPIKey: String {
        get { apiKey }
        set { apiKey = newValue }
    }

    static var uiConfiguration: AIProviderConfiguration {
        configuration(for: .ui)
    }

    static var isUIOverhaulEnabled: Bool {
        (usesSpecialistProvider(for: .ui) || !uiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && uiConfiguration.isConfigured
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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


enum ForgeQuickClassifier {
    /// The user can override this recommendation with the QUICK! toggle.
    /// Failures and timeouts never silently select the lower-quality path.
    @MainActor
    static func decide(for prompt: String) async -> (fast: Bool, reason: String) {
        let text = prompt.lowercased()
        let complexity = ["multi-feature", "multiple screens", "dashboard", "calendar",
                          "bluetooth", "camera", "share with", "production", "polished",
                          "detailed design", "native api", "real-time", "realtime"]
        if complexity.contains(where: text.contains) {
            return (false, "Complex app: polished generation")
        }
        let simple = ["quick prototype", "simple timer", "just a", "basic counter",
                      "quickly make", "simple calculator", "rough prototype"]
        if simple.contains(where: text.contains) {
            return (true, "Simple request: fast generation")
        }
        guard !AISettingsStore.quickModel.isEmpty else {
            return (false, "No fast model is configured")
        }
        let config = ForgeRunOptions.$quick.withValue(true) {
            AISettingsStore.configuration(for: .planner)
        }
        do {
            let raw = try await AIProviderClient.complete(
                config: config,
                system: """
                Choose the generation quality tier for this HTML app request.
                Reply as JSON only: {"mode":"fast"|"polished","reason":"short explanation"}.
                fast: small, simple, urgent, throwaway prototype with 1-2 features.
                polished: shared, design-intensive, multi-screen, native capabilities,
                complex state or production usage. If unsure, select polished.
                """,
                messages: [("user", String(prompt.prefix(850)))],
                timeout: 6, maxTokens: 80, retryOnTransient: false
            )
            guard let first = raw.firstIndex(of: "{"), let last = raw.lastIndex(of: "}"),
                  let data = String(raw[first...last]).data(using: .utf8),
                  let response = try JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return (false, "Automatic classifier returned no decision") }
            return (response["mode"] == "fast",
                    String((response["reason"] ?? "Automatic assessment").prefix(90)))
        } catch {
            return (false, "Classifier unavailable: polished generation")
        }
    }
}
