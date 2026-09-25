import Foundation
import SwiftUI

struct AIGenerationOutput {
    var html = ""
    var patch = ""
    var description = ""
    var iconScript = ""
    var refinedBrief = ""
}

enum AIGenerationError: LocalizedError {
    case notConfigured, invalidEndpoint, missingHTML, invalidPatch, missingIcon
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure an AI API URL and model in Settings first."
        case .invalidEndpoint: return "The configured AI API URL is invalid."
        case .missingHTML: return "The AI response did not contain a complete HTML app."
        case .invalidPatch: return "The AI returned a patch that could not be applied safely."
        case .missingIcon: return "The AI could not produce a valid, renderable app icon."
        case .provider(let message): return message
        }
    }
}

@MainActor
final class AIGenerationSession: ObservableObject {
    @Published var phase = "Preparing"
    @Published var streamedHTML = ""
    @Published var refinedBrief = ""
    @Published var description = ""
    @Published var iconScript = ""
    @Published var renderedIconData: Data?
    @Published var verificationReport = ""
    @Published var errorMessage: String?
    @Published var isWorking = false

    private var originalPrompt = ""
    private var lastResearch = ""

    func load(existing app: SavedHTMLApp) {
        originalPrompt = "Maintain and improve the existing HTML app named \(app.name). Preserve its current purpose and working behavior unless the user explicitly asks to change them."
        streamedHTML = app.html
        description = app.summary
        refinedBrief = "Editing \(app.name) with AI. Existing functionality is the starting point and revisions will be applied as patches."
        verificationReport = ""
        phase = "Ready for AI edits"
    }

    func generate(prompt: String, originalUserPrompt: String? = nil) async {
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        originalPrompt = originalUserPrompt ?? prompt
        isWorking = true
        errorMessage = nil
        verificationReport = ""
        do {
            let improved: String
            if AIHTMLAgent.canSkipPreflight(for: prompt) {
                improved = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                refinedBrief = improved
                lastResearch = ""
                phase = "Generating live preview"
            } else {
                phase = "Improving your prompt"
                improved = try await AIHTMLAgent.refinePrompt(prompt, config: config)
                refinedBrief = improved

                phase = "Planning APIs and capabilities"
                let queries = try await AIHTMLAgent.planResearch(original: improved, revision: nil, config: config)
                phase = queries.isEmpty ? "Designing the app" : "Finding useful public APIs"
                lastResearch = await SafePublicAPIResearch.research(queries: queries)
                phase = "Generating live preview"
            }

            let systemPrompt = AIHTMLAgent.systemPrompt(research: lastResearch)
            var full = ""
            do {
                let stream = try await AIProviderClient.stream(
                    config: config,
                    system: systemPrompt,
                    messages: [("user", improved)]
                )
                for try await piece in stream {
                    full += piece
                    apply(AIHTMLAgent.parsePartial(full), partial: true)
                }
            } catch {
                phase = "Retrying generation without streaming"
                full = try await AIProviderClient.complete(
                    config: config,
                    system: systemPrompt,
                    messages: [("user", improved)]
                )
                apply(AIHTMLAgent.parsePartial(full), partial: true)
            }

            var final = AIHTMLAgent.parse(full)
            if final.html.trimmed.isEmpty {
                final = try await recoverIncompleteGeneration(
                    fullResponse: &full,
                    brief: improved,
                    systemPrompt: systemPrompt,
                    config: config
                )
            }
            guard !final.html.trimmed.isEmpty else { throw AIGenerationError.missingHTML }
            apply(final, partial: false)
            try await ensureValidIcon(config: config)
            try await verifyAndRepair(config: config)
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Generation stopped"
        }
        isWorking = false
    }

    func revise(change: String) async {
        guard !streamedHTML.trimmed.isEmpty else { return }
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        isWorking = true
        errorMessage = nil
        verificationReport = ""
        do {
            phase = "Improving the requested change"
            let improvedChange = try await AIHTMLAgent.refineRevision(change, appBrief: refinedBrief, config: config)

            phase = "Checking APIs for this change"
            let queries = try await AIHTMLAgent.planResearch(original: originalPrompt, revision: improvedChange, config: config)
            let research = await SafePublicAPIResearch.research(queries: queries)
            if !research.isEmpty { lastResearch = research }

            phase = "Patching the app"
            let user = """
Current app:
<htmlapp_existing>
\(streamedHTML)
</htmlapp_existing>

Requested change:
\(improvedChange)
"""
            let response = try await AIProviderClient.complete(
                config: config,
                system: AIHTMLAgent.patchSystemPrompt(research: lastResearch),
                messages: [("user", user)]
            )
            let output = AIHTMLAgent.parse(response)
            if !output.patch.trimmed.isEmpty {
                guard let patched = HTMLPatchApplier.apply(output.patch, to: streamedHTML) else { throw AIGenerationError.invalidPatch }
                streamedHTML = patched
            } else if !output.html.trimmed.isEmpty {
                streamedHTML = output.html
            } else {
                throw AIGenerationError.invalidPatch
            }
            if !output.description.isEmpty { description = output.description }
            if !output.iconScript.isEmpty { iconScript = output.iconScript }
            if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }

            try await ensureValidIcon(config: config)
            try await verifyAndRepair(config: config)
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Edit stopped"
        }
        isWorking = false
    }

    func acceptExternalHTML(_ html: String) {
        streamedHTML = html
        verificationReport = ""
    }

    func verifyCurrent() async {
        let config = AISettingsStore.configuration
        guard config.isConfigured, !streamedHTML.trimmed.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        do {
            try await ensureValidIcon(config: config)
            try await verifyAndRepair(config: config)
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Verification stopped"
        }
        isWorking = false
    }

    private func recoverIncompleteGeneration(
        fullResponse: inout String,
        brief: String,
        systemPrompt: String,
        config: AIProviderConfiguration
    ) async throws -> AIGenerationOutput {
        var partial = AIHTMLAgent.parsePartial(fullResponse)
        guard !partial.html.trimmed.isEmpty else {
            phase = "Repairing AI output"
            let repaired = try await AIHTMLAgent.recoverGeneration(
                response: fullResponse,
                brief: brief,
                research: lastResearch,
                config: config
            )
            return AIHTMLAgent.parse(repaired)
        }

        for _ in 0..<2 {
            phase = "Continuing unfinished generation"
            let continuation = try await AIProviderClient.complete(
                config: config,
                system: systemPrompt,
                messages: [
                    ("user", brief),
                    ("assistant", fullResponse),
                    ("user", """
Your previous response was cut off before the HTMLApp output was complete. Continue exactly from the character where you stopped. Do not restart, repeat earlier sections, or wrap the continuation in Markdown. Finish the remaining HTML/CSS/JavaScript and close </htmlapp_code>.
""")
                ]
            )
            fullResponse += continuation
            partial = AIHTMLAgent.parsePartial(fullResponse)
            apply(partial, partial: true)
            let parsed = AIHTMLAgent.parse(fullResponse)
            if !parsed.html.trimmed.isEmpty { return parsed }
        }

        phase = "Repairing incomplete output"
        let repaired = try await AIHTMLAgent.recoverGeneration(
            response: fullResponse,
            brief: brief,
            research: lastResearch,
            config: config
        )
        let parsed = AIHTMLAgent.parse(repaired)
        if !parsed.html.trimmed.isEmpty { return parsed }
        throw AIGenerationError.missingHTML
    }

    private func ensureValidIcon(config: AIProviderConfiguration) async throws {
        phase = iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generating app icon" : "Checking app icon"

        var candidate = iconScript.trimmingCharacters(in: .whitespacesAndNewlines)
        for attempt in 0..<3 {
            if !candidate.isEmpty, let rendered = await AIIconRenderer.render(script: candidate) {
                iconScript = candidate
                renderedIconData = rendered
                return
            }

            phase = attempt == 0 ? "Generating app icon" : "Repairing app icon"
            candidate = try await AIHTMLAgent.generateIconScript(
                html: streamedHTML,
                originalPrompt: originalPrompt,
                previousScript: candidate,
                config: config
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !candidate.isEmpty, let rendered = await AIIconRenderer.render(script: candidate) {
            iconScript = candidate
            renderedIconData = rendered
            return
        }
        throw AIGenerationError.missingIcon
    }

    private func verifyAndRepair(config: AIProviderConfiguration) async throws {
        phase = "Verifying everything is in place"
        do {
            let response = try await AIHTMLAgent.reviewArtifact(
                html: streamedHTML,
                iconScript: iconScript,
                originalPrompt: originalPrompt,
                config: config
            )
            verificationReport = AIHTMLAgent.verification(from: response)

            let patch = AIHTMLAgent.patch(from: response)
            if !patch.trimmed.isEmpty, let repaired = HTMLPatchApplier.apply(patch, to: streamedHTML) {
                streamedHTML = repaired
                verificationReport += verificationReport.isEmpty ? "Verification repaired the HTML." : "\nVerification repaired the HTML."
            }

            let correctedIcon = AIHTMLAgent.iconScript(from: response).trimmingCharacters(in: .whitespacesAndNewlines)
            if !correctedIcon.isEmpty, correctedIcon != iconScript {
                iconScript = correctedIcon
                renderedIconData = nil
                try await ensureValidIcon(config: config)
                verificationReport += verificationReport.isEmpty ? "Verification repaired the icon." : "\nVerification repaired the icon."
            }
        } catch {
            let localIssues = HTMLQualityChecks.issues(in: streamedHTML)
            verificationReport = localIssues.isEmpty
                ? "Independent verifier was unavailable or timed out. Local structural checks passed."
                : "Independent verifier was unavailable or timed out. Local checks: " + localIssues.joined(separator: " ")
            AIDebugTraceStore.shared.append("VERIFIER FALLBACK", error.localizedDescription)
        }
    }

    private func apply(_ output: AIGenerationOutput, partial: Bool) {
        if !output.html.isEmpty { streamedHTML = partial ? HTMLStreamRepair.previewDocument(output.html) : output.html }
        if !output.description.isEmpty { description = output.description }
        if !output.iconScript.isEmpty { iconScript = output.iconScript }
        if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }
    }
}

actor AIRequestGate {
    static let shared = AIRequestGate()
    private var lastRequestAt = Date.distantPast

    func waitIfNeeded() async {
        let minimum = AISettingsStore.requestDelaySeconds
        guard minimum > 0 else {
            lastRequestAt = Date()
            return
        }
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        let remaining = minimum - elapsed
        if remaining > 0 {
            let nanoseconds = UInt64((remaining * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        lastRequestAt = Date()
    }
}

actor AIStreamActivity {
    private var lastContentAt = Date()
    private var finished = false

    func markContent() {
        lastContentAt = Date()
    }

    func markFinished() {
        finished = true
    }

    func shouldTimeout(after seconds: TimeInterval) -> Bool {
        !finished && Date().timeIntervalSince(lastContentAt) >= seconds
    }
}

enum AIProviderClient {
    static func complete(config: AIProviderConfiguration, system: String, messages: [(String, String)]) async throws -> String {
        await AIRequestGate.shared.waitIfNeeded()
        guard let endpoint = config.endpointURL() else { throw AIGenerationError.invalidEndpoint }
        var request = makeRequest(config: config, endpoint: endpoint)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(config: config, system: system, messages: messages, stream: false))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIGenerationError.provider("The AI provider returned invalid JSON.") }
        switch config.compatibility {
        case .openAI:
            if let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String { return text }
        case .anthropic:
            if let blocks = object["content"] as? [[String: Any]] { return blocks.compactMap { $0["text"] as? String }.joined() }
        }
        throw AIGenerationError.provider("The AI provider response did not contain text.")
    }

    static func stream(config: AIProviderConfiguration, system: String, messages: [(String, String)]) async throws -> AsyncThrowingStream<String, Error> {
        await AIRequestGate.shared.waitIfNeeded()
        guard let endpoint = config.endpointURL() else { throw AIGenerationError.invalidEndpoint }
        var request = makeRequest(config: config, endpoint: endpoint)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(config: config, system: system, messages: messages, stream: true))
        return AsyncThrowingStream { continuation in
            let activity = AIStreamActivity()

            let worker = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw AIGenerationError.provider("The AI provider returned an HTTP error.")
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let text = streamedText(object, type: config.compatibility), !text.isEmpty {
                            await activity.markContent()
                            continuation.yield(text)
                        }
                    }
                    await activity.markFinished()
                    continuation.finish()
                } catch {
                    await activity.markFinished()
                    continuation.finish(throwing: error)
                }
            }

            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if Task.isCancelled { break }
                    if await activity.shouldTimeout(after: 25) {
                        continuation.finish(throwing: AIGenerationError.provider("AI streaming stalled for 25 seconds. Retrying without streaming."))
                        worker.cancel()
                        break
                    }
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                watchdog.cancel()
            }
        }
    }

    private static func makeRequest(config: AIProviderConfiguration, endpoint: URL) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch config.compatibility {
        case .openAI:
            if !config.apiKey.isEmpty { request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            if !config.apiKey.isEmpty { request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        return request
    }

    private static func requestBody(config: AIProviderConfiguration, system: String, messages: [(String, String)], stream: Bool) -> [String: Any] {
        switch config.compatibility {
        case .openAI:
            var list: [[String: String]] = [["role": "system", "content": system]]
            list.append(contentsOf: messages.map { ["role": $0.0, "content": $0.1] })
            return ["model": config.model, "messages": list, "stream": stream]
        case .anthropic:
            let list: [[String: String]] = messages.map { ["role": $0.0 == "assistant" ? "assistant" : "user", "content": $0.1] }
            return ["model": config.model, "max_tokens": 32000, "system": system, "messages": list, "stream": stream]
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let detail = String(decoding: data.prefix(1500), as: UTF8.self)
        throw AIGenerationError.provider("AI provider error \(http.statusCode): \(detail)")
    }

    private static func streamedText(_ object: [String: Any], type: AIProviderConfiguration.Compatibility) -> String? {
        switch type {
        case .openAI:
            guard let choices = object["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        case .anthropic:
            guard object["type"] as? String == "content_block_delta", let delta = object["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
    }
}

enum AIHTMLAgent {
    static let designGuide = """
Build one self-contained standards-compliant HTML file with semantic HTML, all CSS in <style>, all JavaScript in <script>, inline SVG icons, and no build step. It must behave like a real mobile app rather than a static webpage: clear screen hierarchy, native-feeling navigation, pressed states, sheets/overlays where appropriate, smooth animated transitions, spring-like motion, tasteful micro-interactions, and haptic feedback after user gestures when it improves the experience. Motion must communicate state and navigation, respect prefers-reduced-motion, and never block usability.

Aim for a premium iPhone/iPad experience: Apple system typography, safe areas, responsive layouts, 44px minimum touch targets, polished light/dark appearance, loading/empty/error/offline states, keyboard-friendly forms, and no dead controls. Use restrained iOS-style materials for navigation, controls, sheets and overlays. Avoid generic SaaS dashboards, excessive blur/glow/gradients, Material-style UI, emoji icons, browser alert() for routine feedback, and desktop-first layouts.

Never invent facts, live values, people, accounts, reviews, measurements, availability, prices, API responses, endpoints, or capabilities unless the user explicitly asks for fictional/demo/sample content. Do not silently pass fabricated sample data off as real data. If real data or a capability is needed, use the researched documented API when available. If you are unsure whether something can be done, prefer a documented API solution found in the research rather than pretending it works. If no suitable API exists, make the limitation clear in the app and offer honest user-entered/local functionality instead of fake live data.

Permission-requiring APIs may only activate after an explicit user gesture. Never embed private API keys or secrets in generated HTML.
"""

    static let iconGuide = """
Inside <icon_script>, output only a static drawing script. Commands: SIZE width height; BG color; RECT x y width height color; CIRCLE center_x center_y radius color; LINE x1 y1 x2 y2 thickness color; TRIANGLE x1 y1 x2 y2 x3 y3 color; optional FILL_LINEAR, FILL_RADIAL, FILL_TEXTURE immediately before a shape. Use absolute coordinates and CSS/HEX colors, draw back-to-front, and never use ANIM, GROUP or FPS.
"""

    static func canSkipPreflight(for prompt: String) -> Bool {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 160 else { return false }
        let lower = value.lowercased()
        let remoteSignals = [
            "api", "website", "web site", "url", "current", "live", "latest", "weather",
            "news", "stock", "crypto", "price", "map", "location", "restaurant", "flight",
            "sports", "score", "search the web", "internet", "online", "remote", "database",
            "login", "account", "oauth", "server", "fetch", "download"
        ]
        return !remoteSignals.contains(where: { lower.contains($0) })
    }

    static func refinePrompt(_ prompt: String, config: AIProviderConfiguration) async throws -> String {
        let system = """
Turn the user's app idea into a stronger, concise implementation brief. Preserve the user's intent and do not add unsupported requirements. Clarify likely screens, interactions, data needs, mobile behavior, animation/motion, empty/loading/error states, and what must be real versus local. Do not invent data or APIs. Return only <brief>...</brief>.
"""
        let text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", prompt)])
        return value("brief", in: text).trimmed.isEmpty ? prompt : value("brief", in: text).trimmed
    }

    static func refineRevision(_ change: String, appBrief: String, config: AIProviderConfiguration) async throws -> String {
        let system = "Return a precise patch request that preserves everything not explicitly changed. Resolve ambiguity conservatively. Include mobile animation/state implications when relevant. Never invent facts or fake live data. Return only <brief>...</brief>."
        let text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", "Current brief: \(appBrief)\nRequested change: \(change)")])
        return value("brief", in: text).trimmed.isEmpty ? change : value("brief", in: text).trimmed
    }

    static func planResearch(original: String, revision: String?, config: AIProviderConfiguration) async throws -> [String] {
        let system = """
Return zero to six concise public-API discovery queries, each inside <query>. Search whenever the requested app or revision needs real-world/live/current data, a remote capability, or a capability you are not confident can be implemented locally. If unsure whether a capability exists, search rather than making it up. Prefer documented no-auth APIs, then documented free tiers. Never search age-restricted, dangerous, gambling, weapon, intoxicant, explicit, or malware-acquisition categories. If the app truly needs no external data or service, return no queries.
"""
        let user = revision.map { "App: \(original)\nRevision: \($0)" } ?? original
        let text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
        let values = values("query", in: text)
        return Array(values.prefix(upTo: min(6, values.count)))
    }

    static func systemPrompt(research: String) -> String {
        AISettingsStore.resolvedSystemPrompt(research: research)
    }

    static func patchSystemPrompt(research: String) -> String {
        """
You are HTMLApp's code-editing agent. Edit the existing single-file HTML app with the smallest safe patch that satisfies the requested change. Preserve all unrelated behavior, IDs, storage keys, API integrations, permissions, navigation and working code. Prefer patching over rewriting.

Return these sections with no Markdown fences:
<thinking>short updated implementation plan</thinking>
<description>updated one-sentence description if materially changed, otherwise repeat the current purpose</description>
<icon_script>updated icon script only if the app identity changed; otherwise leave empty</icon_script>
<htmlapp_patch>
<<<<<<< SEARCH
exact text copied from the existing HTML
=======
replacement text
>>>>>>> REPLACE
</htmlapp_patch>

You may include multiple SEARCH/REPLACE blocks. SEARCH text must match exactly and should be as small and unique as practical. If an exact safe patch is genuinely impossible, return a complete <htmlapp_code> document instead.

RULES:
\(designGuide)
Keep or improve native-feeling animation and mobile interactions. Do not fabricate facts, APIs, live data or capabilities. If the revision depends on something uncertain, use the documented research below; if no credible API is available, implement an honest local/limited state rather than fake data.

RESEARCH RESULTS:
\(research.isEmpty ? "No new external API research was needed or no suitable public API was found." : research)
"""
    }

    static func generateIconScript(
        html: String,
        originalPrompt: String,
        previousScript: String,
        config: AIProviderConfiguration
    ) async throws -> String {
        let system = """
Create a valid HTMLApp icon drawing script for the supplied app. The icon is mandatory and must visually match the app's purpose and visual language. Return only <icon_script>...</icon_script>. Use only these commands: SIZE, BG, RECT, CIRCLE, LINE, TRIANGLE, FILL_LINEAR, FILL_RADIAL, FILL_TEXTURE. Use absolute coordinates and CSS/HEX colors. Never use ANIM, GROUP, FPS, Markdown, SVG, HTML, or explanatory text.
"""
        let user = """
USER'S ORIGINAL PROMPT:
(originalPrompt)

APP HTML:
(html)

PREVIOUS ICON SCRIPT, IF ANY:
(previousScript.isEmpty ? "None. Generate a new icon." : previousScript)
"""
        let response = try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
        return value("icon_script", in: response)
    }

    static func reviewArtifact(
        html: String,
        iconScript: String,
        originalPrompt: String,
        config: AIProviderConfiguration
    ) async throws -> String {
        let system = """
You are a fresh final artifact verifier. You have no access to any previous AI conversation, research, planning, or generation context. Judge only the three artifacts supplied by the user: their original prompt, the finished HTML app, and its icon drawing script.

Check whether the HTML substantially fulfills the original prompt, is structurally complete, and has obvious source-level functional errors. Check whether the icon is valid in concept and appropriately represents the same app. Do not redesign working code merely for preference. If a concrete HTML defect prevents the request from being fulfilled, return a minimal exact SEARCH/REPLACE patch. If the icon is missing, malformed, or mismatched, return a complete replacement icon script.

Return only:
<verification>brief result</verification>
<htmlapp_patch>optional exact SEARCH/REPLACE blocks</htmlapp_patch>
<icon_script>optional complete replacement icon script</icon_script>
"""
        let user = """
ORIGINAL PROMPT:
(originalPrompt)

HTML:
<htmlapp_existing>
(html)
</htmlapp_existing>

ICON:
<icon_script_existing>
(iconScript)
</icon_script_existing>
"""
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
    }

    static func review(html: String, originalPrompt: String, research: String, localIssues: [String], config: AIProviderConfiguration) async throws -> String {
        let system = """
You are HTMLApp's final QA reviewer. Review the complete HTML/CSS/JavaScript source for likely functional defects and mobile UI quality problems. Check that controls have actions, navigation and state transitions make sense, APIs are not fabricated, error/loading/empty states are honest, permissions require gestures, touch targets are usable, light/dark layouts are coherent, and motion makes the app feel alive without being distracting. Also check for obvious syntax/DOM-reference problems.

Do not claim you visually rendered or device-tested anything you cannot actually observe. Do not invent failures. If you find a concrete issue, return a minimal exact SEARCH/REPLACE patch. If no concrete source-level issue is found, leave <htmlapp_patch> empty.

Return only:
<verification>brief QA summary including what was checked and any limitations</verification>
<htmlapp_patch>optional SEARCH/REPLACE blocks</htmlapp_patch>
"""
        let user = """
Original request/intent:
\(originalPrompt)

Local static checks:
\(localIssues.isEmpty ? "No local structural warnings." : localIssues.joined(separator: "\n"))

Relevant API research:
\(research.isEmpty ? "None." : research)

HTML to review:
<htmlapp_existing>
\(html)
</htmlapp_existing>
"""
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
    }

    static func recoverGeneration(
        response: String,
        brief: String,
        research: String,
        config: AIProviderConfiguration
    ) async throws -> String {
        let system = """
You are HTMLApp's recovery editor. The previous app-generation response was truncated or malformed. Reconstruct it into one complete, valid HTMLApp response while preserving all useful work already present. Fix unclosed HTML/CSS/JavaScript, missing required sections, duplicated cutoff text, and obvious source errors. Do not invent APIs or data. Return exactly:
<thinking>concise implementation plan</thinking>
<description>one sentence</description>
<icon_script>static icon drawing script</icon_script>
<htmlapp_code><!DOCTYPE html>...one complete self-contained app...</htmlapp_code>
No Markdown fences and no text outside those sections.
"""
        let user = """
Original brief:
(brief)

Research evidence:
(research.isEmpty ? "None." : research)

Interrupted/malformed response:
<interrupted_response>
(response)
</interrupted_response>
"""
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
    }

    static func parse(_ text: String) -> AIGenerationOutput {
        AIGenerationOutput(
            html: value("htmlapp_code", in: text),
            patch: value("htmlapp_patch", in: text),
            description: value("description", in: text).trimmed,
            iconScript: value("icon_script", in: text).trimmed,
            refinedBrief: value("thinking", in: text).trimmed
        )
    }

    static func parsePartial(_ text: String) -> AIGenerationOutput {
        AIGenerationOutput(
            html: partial("htmlapp_code", in: text),
            patch: partial("htmlapp_patch", in: text),
            description: partial("description", in: text).trimmed,
            iconScript: partial("icon_script", in: text).trimmed,
            refinedBrief: partial("thinking", in: text).trimmed
        )
    }

    static func verification(from text: String) -> String { value("verification", in: text).trimmed }
    static func patch(from text: String) -> String { value("htmlapp_patch", in: text) }
    static func iconScript(from text: String) -> String { value("icon_script", in: text) }

    private static func values(_ tag: String, in text: String) -> [String] {
        var result: [String] = []
        var remaining = text[...]
        let open = "<\(tag)>"; let close = "</\(tag)>"
        while let start = remaining.range(of: open) {
            let tail = remaining[start.upperBound...]
            guard let end = tail.range(of: close) else { break }
            result.append(String(tail[..<end.lowerBound]).trimmed)
            remaining = tail[end.upperBound...]
        }
        return result
    }

    private static func value(_ tag: String, in text: String) -> String { values(tag, in: text).first ?? "" }
    private static func partial(_ tag: String, in text: String) -> String {
        let open = "<\(tag)>"; let close = "</\(tag)>"
        guard let start = text.range(of: open) else { return "" }
        let tail = text[start.upperBound...]
        if let end = tail.range(of: close) { return String(tail[..<end.lowerBound]) }
        return String(tail)
    }
}

enum HTMLPatchApplier {
    static func apply(_ patch: String, to source: String) -> String? {
        let searchMarker = "<<<<<<< SEARCH"
        let splitMarker = "======="
        let replaceMarker = ">>>>>>> REPLACE"
        var result = source
        var cursor = patch[...]
        var applied = 0

        while let searchStart = cursor.range(of: searchMarker) {
            let afterSearchMarker = cursor[searchStart.upperBound...]
            guard let divider = afterSearchMarker.range(of: splitMarker) else { return nil }
            let rawSearch = String(afterSearchMarker[..<divider.lowerBound]).trimmingCharacters(in: .newlines)
            let afterDivider = afterSearchMarker[divider.upperBound...]
            guard let replaceEnd = afterDivider.range(of: replaceMarker) else { return nil }
            let rawReplacement = String(afterDivider[..<replaceEnd.lowerBound]).trimmingCharacters(in: .newlines)
            guard !rawSearch.isEmpty, let range = result.range(of: rawSearch) else { return nil }
            result.replaceSubrange(range, with: rawReplacement)
            applied += 1
            cursor = afterDivider[replaceEnd.upperBound...]
        }
        return applied > 0 ? result : nil
    }
}

enum HTMLQualityChecks {
    static func issues(in html: String) -> [String] {
        let lower = html.lowercased()
        var issues: [String] = []
        if !lower.contains("<!doctype html") { issues.append("Missing <!DOCTYPE html>.") }
        if !lower.contains("name=\"viewport\"") && !lower.contains("name='viewport'") { issues.append("Missing mobile viewport metadata.") }
        if count("<script", in: lower) != count("</script>", in: lower) { issues.append("Unbalanced <script> tags.") }
        if count("<style", in: lower) != count("</style>", in: lower) { issues.append("Unbalanced <style> tags.") }
        if lower.contains("alert(") { issues.append("Uses browser alert(); routine feedback should use in-app UI.") }
        if lower.contains("example.com") || lower.contains("your_api_key") || lower.contains("api-key-here") { issues.append("Contains a likely placeholder endpoint or key.") }
        return issues
    }

    private static func count(_ needle: String, in haystack: String) -> Int { haystack.components(separatedBy: needle).count - 1 }
}

enum SafePublicAPIResearch {
    private static let publicAPIsURL = URL(string: "https://raw.githubusercontent.com/public-apis/public-apis/master/README.md")!
    private static let APIsGuruURL = URL(string: "https://api.apis.guru/v2/list.json")!
    private static let excluded = ["gambling", "betting", "casino", "alcohol", "beer", "wine", "weapon", "firearm", "drug", "porn", "adult", "malware"]

    static func research(queries: [String]) async -> String {
        guard !queries.isEmpty else { return "" }
        async let publicCatalog = fetchText(publicAPIsURL)
        async let guruData = fetchData(APIsGuruURL)
        let catalog = await publicCatalog
        let guru = await guruData
        var output: [String] = []

        for query in queries where safe(query) {
            let terms = searchTerms(query)
            var matches: [String] = []

            if let catalog {
                let rows = catalog.split(separator: "\n").map(String.init).filter { row in
                    guard row.hasPrefix("|") else { return false }
                    let lower = row.lowercased()
                    return safe(lower) && terms.contains(where: { lower.contains($0) })
                }
                matches.append(contentsOf: rows.prefix(6))
            }

            if let guru,
               let object = try? JSONSerialization.jsonObject(with: guru) as? [String: Any] {
                for (name, raw) in object where matches.count < 10 {
                    guard let service = raw as? [String: Any] else { continue }
                    let lower = (name + " " + String(describing: service)).lowercased()
                    guard safe(lower), terms.contains(where: { lower.contains($0) }) else { continue }
                    var line = "APIs.guru: \(name)"
                    if let preferred = service["preferred"] as? String,
                       let versions = service["versions"] as? [String: Any],
                       let version = versions[preferred] as? [String: Any] {
                        if let info = version["info"] as? [String: Any], let title = info["title"] as? String { line += " — \(title)" }
                        if let swagger = version["swaggerUrl"] as? String { line += " — OpenAPI: \(swagger)" }
                    }
                    matches.append(line)
                }
            }

            if matches.isEmpty {
                output.append("Query: \(query)\nNo matching documented public API was found in the checked catalogs. Do not invent one.")
            } else {
                output.append("Query: \(query)\n" + matches.joined(separator: "\n"))
            }
        }
        return output.joined(separator: "\n\n")
    }

    private static func fetchText(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func fetchData(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }

    private static func searchTerms(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
    }

    private static func safe(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !excluded.contains(where: { lower.contains($0) })
    }
}

enum HTMLStreamRepair {
    static func previewDocument(_ fragment: String) -> String {
        var html = fragment
        let lower = html.lowercased()
        if !lower.contains("<!doctype") && !lower.contains("<html") {
            html = "<!DOCTYPE html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\"></head><body>" + html
        }
        if count("<script", html) > count("</script>", html) { html += "\n</script>" }
        if count("<style", html) > count("</style>", html) { html += "\n</style>" }
        if count("<head", html) > count("</head>", html) { html += "\n</head>" }
        if count("<body", html) > count("</body>", html) { html += "\n</body>" }
        if count("<html", html) > count("</html>", html) { html += "\n</html>" }
        return html
    }
    private static func count(_ needle: String, _ haystack: String) -> Int { haystack.lowercased().components(separatedBy: needle).count - 1 }
}

enum AIIconRenderer {
    static func render(script: String) async -> Data? {
        let code = script.trimmed
        guard !code.isEmpty, let url = URL(string: "https://mekapc.hostish.site/api/image") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])
        guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
        return data
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
