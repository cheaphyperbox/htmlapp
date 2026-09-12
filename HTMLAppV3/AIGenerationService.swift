import Foundation
import SwiftUI

struct AIGenerationOutput {
    var html = ""
    var description = ""
    var iconScript = ""
    var refinedBrief = ""
}

enum AIGenerationError: LocalizedError {
    case notConfigured, invalidEndpoint, missingHTML
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure an AI API URL and model in Settings first."
        case .invalidEndpoint: return "The configured AI API URL is invalid."
        case .missingHTML: return "The AI response did not contain a complete HTML app."
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
    @Published var errorMessage: String?
    @Published var isWorking = false

    private var conversation: [(String, String)] = []
    private var originalPrompt = ""

    func generate(prompt: String) async {
        originalPrompt = prompt
        conversation = []
        await run(request: prompt, existingHTML: nil)
    }

    func revise(change: String) async {
        guard !streamedHTML.isEmpty else { return }
        await run(request: "Revise the current app with these changes:\n\(change)", existingHTML: streamedHTML)
    }

    private func run(request: String, existingHTML: String?) async {
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        isWorking = true
        errorMessage = nil
        phase = "Refining your idea"
        do {
            let queries = try await AIHTMLAgent.planResearch(original: originalPrompt, revision: existingHTML == nil ? nil : request, config: config)
            phase = queries.isEmpty ? "Designing the app" : "Checking public APIs"
            let research = await SafePublicAPIResearch.research(queries: queries)
            phase = "Generating live preview"

            var messages = conversation
            if let existingHTML {
                messages.append(("user", "Current HTML app:\n<htmlapp_existing>\n\(existingHTML)\n</htmlapp_existing>\n\nRequested change:\n\(request)"))
            } else {
                messages.append(("user", request))
            }

            let stream = try await AIProviderClient.stream(config: config, system: AIHTMLAgent.systemPrompt(research: research), messages: messages)
            var full = ""
            for try await piece in stream {
                full += piece
                apply(AIHTMLAgent.parsePartial(full), partial: true)
            }
            let final = AIHTMLAgent.parse(full)
            guard !final.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIGenerationError.missingHTML }
            apply(final, partial: false)
            conversation.append(("user", request))
            conversation.append(("assistant", full))
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Generation stopped"
        }
        isWorking = false
    }

    private func apply(_ output: AIGenerationOutput, partial: Bool) {
        if !output.html.isEmpty { streamedHTML = partial ? HTMLStreamRepair.previewDocument(output.html) : output.html }
        if !output.description.isEmpty { description = output.description }
        if !output.iconScript.isEmpty { iconScript = output.iconScript }
        if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }
    }
}

enum AIProviderClient {
    static func complete(config: AIProviderConfiguration, system: String, messages: [(String, String)]) async throws -> String {
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
        guard let endpoint = config.endpointURL() else { throw AIGenerationError.invalidEndpoint }
        var request = makeRequest(config: config, endpoint: endpoint)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(config: config, system: system, messages: messages, stream: true))
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw AIGenerationError.provider("The AI provider returned an HTTP error.")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let text = streamedText(object, type: config.compatibility), !text.isEmpty { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
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
Create one self-contained standards-compliant HTML file: semantic HTML, all CSS in <style>, all JavaScript in <script>, inline SVG icons, no framework or build step. It must feel like a premium native iOS 26 product: restrained Liquid Glass mainly for navigation, controls, sheets and overlays; native-feeling navigation; clear hierarchy; Apple-like spacing; spring motion; safe areas; adaptive phone/tablet layouts; light and dark appearance; loading, empty, error and offline states; accessible 44px touch targets; no dead controls. Avoid generic SaaS dashboards, excessive blur/glow/gradients, Material-style UI, emoji icons and browser alert() for routine feedback. Permission-requiring APIs may only activate after an explicit user gesture. Use realistic local fallback data when remote data fails.
"""

    static let iconGuide = """
Inside <icon_script>, output only a static drawing script. Commands: SIZE width height; BG color; RECT x y width height color; CIRCLE center_x center_y radius color; LINE x1 y1 x2 y2 thickness color; TRIANGLE x1 y1 x2 y2 x3 y3 color; optional FILL_LINEAR, FILL_RADIAL, FILL_TEXTURE immediately before a shape. Use absolute coordinates and CSS/HEX colors, draw back-to-front, and never use ANIM, GROUP or FPS.
"""

    static func planResearch(original: String, revision: String?, config: AIProviderConfiguration) async throws -> [String] {
        let system = "Return zero to four concise safe public-API search queries, each inside <query>. Research only if live data materially helps. Prefer no-auth APIs, then documented free tiers. Never search age-restricted, dangerous, gambling, weapon, intoxicant, explicit, or malware-acquisition categories. If none is needed, return <research></research>."
        let user = revision.map { "Original: \(original)\nRevision: \($0)" } ?? original
        let text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
        let values = tagValues("query", in: text)
        return Array(values.prefix(upTo: min(4, values.count)))
    }

    static func systemPrompt(research: String) -> String {
        """
You are HTMLApp's fast app-building agent. Refine the request into a concise implementation brief, then build the app. Do not reveal hidden chain-of-thought; <thinking> is only a short user-facing requirements/design brief.

Return exactly these sections with no Markdown fences:
<thinking>concise refined brief</thinking>
<description>one sentence describing the finished app</description>
<icon_script>static icon drawing script</icon_script>
<htmlapp_code><!DOCTYPE html>...complete app...</htmlapp_code>

DESIGN RULES:
\(designGuide)

ICON RULES:
\(iconGuide)

HTMLAPP DEVICE APIS:
Use navigator.vibrate(...) only after explicit user interaction for haptic feedback. Geolocation supports getCurrentPosition and continuously refreshed watchPosition while the app is open. For motion/gyro/compass experiences, request DeviceMotionEvent.requestPermission() or DeviceOrientationEvent.requestPermission() from a user gesture before listening for devicemotion/deviceorientation. Compass heading is also exposed as window.htmlappCompassHeading and the htmlappcompass custom event. Notifications use the standard Notification.requestPermission() and new Notification(...) flow.

API ROUTING:
Prefer Auth=None, then documented free tiers. OAuth only when account access is essential. Endpoint placeholders are not literal URLs. Never embed private keys in generated HTML. Restricted API categories are excluded. Include local fallback data.

RESEARCH RESULTS:
\(research.isEmpty ? "No external API research was needed." : research)
"""
    }

    static func parse(_ text: String) -> AIGenerationOutput {
        AIGenerationOutput(html: tagValue("htmlapp_code", in: text), description: tagValue("description", in: text).trimmed, iconScript: tagValue("icon_script", in: text).trimmed, refinedBrief: tagValue("thinking", in: text).trimmed)
    }

    static func parsePartial(_ text: String) -> AIGenerationOutput {
        AIGenerationOutput(html: partialTag("htmlapp_code", in: text), description: partialTag("description", in: text).trimmed, iconScript: partialTag("icon_script", in: text).trimmed, refinedBrief: partialTag("thinking", in: text).trimmed)
    }

    private static func tagValues(_ tag: String, in text: String) -> [String] {
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

    private static func tagValue(_ tag: String, in text: String) -> String { tagValues(tag, in: text).first ?? "" }
    private static func partialTag(_ tag: String, in text: String) -> String {
        let open = "<\(tag)>"; let close = "</\(tag)>"
        guard let start = text.range(of: open) else { return "" }
        let tail = text[start.upperBound...]
        if let end = tail.range(of: close) { return String(tail[..<end.lowerBound]) }
        return String(tail)
    }
}

enum SafePublicAPIResearch {
    private static let catalogURL = URL(string: "https://raw.githubusercontent.com/public-apis/public-apis/master/README.md")!
    private static let excluded = ["gambling", "betting", "casino", "alcohol", "beer", "wine", "weapon", "firearm", "drug", "porn", "adult", "malware"]

    static func research(queries: [String]) async -> String {
        guard !queries.isEmpty else { return "" }
        guard let (data, _) = try? await URLSession.shared.data(from: catalogURL), let catalog = String(data: data, encoding: .utf8) else {
            return "The public API catalog is unavailable. Build the app with robust local fallback data."
        }
        var output: [String] = []
        for query in queries where safe(query) {
            let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let matches = catalog.split(separator: "\n").map(String.init).filter { row in
                guard row.hasPrefix("|") else { return false }
                let lower = row.lowercased()
                return !excluded.contains(where: { lower.contains($0) }) && terms.contains(where: { lower.contains($0) })
            }
            let rows = Array(matches.prefix(upTo: min(8, matches.count)))
            if !rows.isEmpty { output.append("Query: \(query)\n" + rows.joined(separator: "\n")) }
        }
        return output.joined(separator: "\n\n")
    }

    private static func safe(_ query: String) -> Bool {
        let lower = query.lowercased()
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
