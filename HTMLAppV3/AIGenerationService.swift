import Foundation

struct AIGenerationOutput {
    var html: String
    var description: String
    var iconScript: String
    var refinedBrief: String
}

enum AIGenerationError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case badResponse(String)
    case missingHTML

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure an AI API URL and model in Settings first."
        case .invalidEndpoint: return "The configured AI API URL is invalid."
        case .badResponse(let value): return value
        case .missingHTML: return "The AI response did not contain a complete HTML app."
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
    @Published var rawResponse = ""
    @Published var errorMessage: String?
    @Published var isWorking = false

    private var conversation: [(role: String, content: String)] = []
    private var originalPrompt = ""

    func generate(prompt: String) async {
        originalPrompt = prompt
        conversation = []
        await run(userRequest: prompt, existingHTML: nil)
    }

    func revise(change: String) async {
        guard !streamedHTML.isEmpty else { return }
        let request = "Revise the current HTML app with these changes:\n\(change)"
        await run(userRequest: request, existingHTML: streamedHTML)
    }

    private func run(userRequest: String, existingHTML: String?) async {
        let configuration = AISettingsStore.configuration
        guard configuration.isConfigured else {
            errorMessage = AIGenerationError.notConfigured.localizedDescription
            return
        }

        isWorking = true
        errorMessage = nil
        rawResponse = ""
        phase = "Refining your idea"

        do {
            let researchQueries = try await AIHTMLAgent.planResearch(
                request: originalPrompt,
                revision: existingHTML == nil ? nil : userRequest,
                configuration: configuration
            )

            phase = researchQueries.isEmpty ? "Designing the app" : "Checking public APIs"
            let research = await SafePublicAPIResearch.research(queries: researchQueries)

            phase = "Generating live preview"
            let systemPrompt = AIHTMLAgent.systemPrompt(research: research)
            var messages: [(String, String)] = conversation
            if let existingHTML {
                messages.append(("user", "Current HTML app:\n<htmlapp_existing>\n\(existingHTML)\n</htmlapp_existing>\n\nRequested change:\n\(userRequest)"))
            } else {
                messages.append(("user", userRequest))
            }

            let stream = try await AIProviderClient.stream(
                configuration: configuration,
                system: systemPrompt,
                messages: messages
            )

            var full = ""
            for try await text in stream {
                full += text
                rawResponse = full
                updateParsedState(from: full)
            }

            let final = AIHTMLAgent.parse(full)
            guard !final.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIGenerationError.missingHTML
            }
            streamedHTML = final.html
            description = final.description
            iconScript = final.iconScript
            refinedBrief = final.refinedBrief
            conversation.append(("user", userRequest))
            conversation.append(("assistant", full))
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Generation stopped"
        }
        isWorking = false
    }

    private func updateParsedState(from text: String) {
        let partial = AIHTMLAgent.parsePartial(text)
        if !partial.html.isEmpty { streamedHTML = HTMLStreamRepair.previewDocument(partial.html) }
        if !partial.description.isEmpty { description = partial.description }
        if !partial.iconScript.isEmpty { iconScript = partial.iconScript }
        if !partial.refinedBrief.isEmpty { refinedBrief = partial.refinedBrief }
    }
}

enum AIProviderClient {
    static func complete(configuration: AIProviderConfiguration, system: String, messages: [(String, String)]) async throws -> String {
        var value = ""
        let stream = try await stream(configuration: configuration, system: system, messages: messages, forceStreaming: false)
        for try await chunk in stream { value += chunk }
        return value
    }

    static func stream(configuration: AIProviderConfiguration, system: String, messages: [(String, String)], forceStreaming: Bool = true) async throws -> AsyncThrowingStream<String, Error> {
        guard let endpoint = configuration.endpointURL() else { throw AIGenerationError.invalidEndpoint }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch configuration.compatibility {
        case .openAI:
            if !configuration.apiKey.isEmpty { request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization") }
            var encodedMessages: [[String: String]] = [["role": "system", "content": system]]
            encodedMessages.append(contentsOf: messages.map { ["role": $0.0, "content": $0.1] })
            body = [
                "model": configuration.model,
                "messages": encodedMessages,
                "stream": forceStreaming
            ]
        case .anthropic:
            if !configuration.apiKey.isEmpty { request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": configuration.model,
                "max_tokens": 32000,
                "system": system,
                "messages": messages.map { ["role": $0.0 == "assistant" ? "assistant" : "user", "content": $0.1] },
                "stream": forceStreaming
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if !forceStreaming {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let text = try parseWholeResponse(data: data, compatibility: configuration.compatibility)
            return AsyncThrowingStream { continuation in
                continuation.yield(text)
                continuation.finish()
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw AIGenerationError.badResponse("The AI provider returned an HTTP error.")
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let delta = streamText(from: object, compatibility: configuration.compatibility), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data.prefix(1500), encoding: .utf8) ?? ""
            throw AIGenerationError.badResponse("AI provider error \(http.statusCode): \(detail)")
        }
    }

    private static func parseWholeResponse(data: Data, compatibility: AIProviderConfiguration.Compatibility) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIGenerationError.badResponse("The AI provider returned invalid JSON.")
        }
        switch compatibility {
        case .openAI:
            if let choices = object["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let text = message["content"] as? String { return text }
        case .anthropic:
            if let content = object["content"] as? [[String: Any]] {
                return content.compactMap { $0["text"] as? String }.joined()
            }
        }
        throw AIGenerationError.badResponse("The AI provider response did not contain text.")
    }

    private static func streamText(from object: [String: Any], compatibility: AIProviderConfiguration.Compatibility) -> String? {
        switch compatibility {
        case .openAI:
            guard let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return delta["content"] as? String
        case .anthropic:
            guard object["type"] as? String == "content_block_delta",
                  let delta = object["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
    }
}

enum AIHTMLAgent {
    static let designGuide = """
Build one self-contained, standards-compliant HTML file with semantic HTML, all CSS in <style>, all JavaScript in <script>, and inline SVG icons. It should feel like a premium native iOS 26 app translated to the web: restrained Liquid Glass used mainly for navigation/controls/sheets, strong hierarchy, large-title navigation, Apple-like spacing, spring motion, safe-area support, adaptive phone/tablet layouts, light and dark themes, polished loading/empty/error states, 44pt touch targets, accessibility, and no dead controls. Avoid generic SaaS dashboards, excessive gradients/glow/blur, Material-style UI, emoji icons, generic browser alerts, and permission prompts on page load. Browser APIs that require permission must only activate after a user gesture. Use local fallback data for remote APIs and handle offline/rate-limit failures gracefully.
"""

    static let iconGuide = """
For the app icon, output a static drawing script only inside <icon_script>. The drawing language supports: SIZE width height; BG color; RECT x y width height color; CIRCLE center_x center_y radius color; LINE x1 y1 x2 y2 thickness color; TRIANGLE x1 y1 x2 y2 x3 y3 color; and optional FILL_LINEAR, FILL_RADIAL, or FILL_TEXTURE immediately before a shape. Use absolute coordinates, draw back-to-front, CSS/HEX colors, and never use ANIM, GROUP, or FPS. The script will be POSTed as JSON {"code":"..."} to the configured image renderer.
"""

    static func planResearch(request: String, revision: String?, configuration: AIProviderConfiguration) async throws -> [String] {
        let system = """
You are a fast planning agent for a single-file HTML app generator. Return only zero to four concise public-API search queries, one per <query> tag. Use research only when live data materially improves the requested app. Do not search for age-restricted, dangerous, gambling, weapon, intoxicant, explicit, or malware-acquisition content. Prefer APIs with no authentication, then documented free tiers. If no research is needed, return <research></research>.
"""
        let user = revision.map { "Original request: \(request)\nRevision: \($0)" } ?? request
        let result = try await AIProviderClient.complete(configuration: configuration, system: system, messages: [("user", user)])
        return tagValues("query", in: result).prefix(4).map { String($0) }
    }

    static func systemPrompt(research: String) -> String {
        """
You are HTMLApp's app-building agent. Complete the task quickly and produce a production-quality single-file HTML app.

First refine the user's idea into a concise implementation brief inside <thinking>. This is a short requirements/design brief, not hidden chain-of-thought. Then output a user-facing one-sentence app description in <description>. Then output an icon drawing script in <icon_script>. Finally output the complete app in <htmlapp_code>.

Required output structure:
<thinking>concise refined requirements</thinking>
<description>one sentence</description>
<icon_script>static drawing script</icon_script>
<htmlapp_code><!DOCTYPE html>...</htmlapp_code>

Do not wrap the response in Markdown fences. Do not put commentary outside these tags.

DESIGN INSTRUCTIONS:
\(designGuide)

ICON INSTRUCTIONS:
\(iconGuide)

PUBLIC API RESEARCH:
The catalog routing policy is: prefer Auth=None, then APIs with a documented free tier; only use OAuth when account access is essential; endpoint placeholders are not literal URLs; verify current documentation. Restricted categories are intentionally excluded from research.
\(research.isEmpty ? "No external API research was needed." : research)

When using an API, include robust fallback data. Never expose secrets in generated HTML. If an API requires a private key and no safe demo fallback exists, choose another source.
"""
    }

    static func parse(_ text: String) -> AIGenerationOutput {
        AIGenerationOutput(
            html: tagValue("htmlapp_code", in: text),
            description: tagValue("description", in: text).trimmingCharacters(in: .whitespacesAndNewlines),
            iconScript: tagValue("icon_script", in: text).trimmingCharacters(in: .whitespacesAndNewlines),
            refinedBrief: tagValue("thinking", in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parsePartial(_ text: String) -> AIGenerationOutput {
        AIGenerationOutput(
            html: partialTagValue("htmlapp_code", in: text),
            description: partialTagValue("description", in: text).trimmingCharacters(in: .whitespacesAndNewlines),
            iconScript: partialTagValue("icon_script", in: text).trimmingCharacters(in: .whitespacesAndNewlines),
            refinedBrief: partialTagValue("thinking", in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func tagValues(_ tag: String, in text: String) -> [String] {
        var values: [String] = []
        var remainder = text[...]
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        while let start = remainder.range(of: open) {
            let after = remainder[start.upperBound...]
            guard let end = after.range(of: close) else { break }
            values.append(String(after[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            remainder = after[end.upperBound...]
        }
        return values
    }

    private static func tagValue(_ tag: String, in text: String) -> String { tagValues(tag, in: text).first ?? "" }

    private static func partialTagValue(_ tag: String, in text: String) -> String {
        let open = "<\(tag)>"
        guard let start = text.range(of: open) else { return "" }
        let after = text[start.upperBound...]
        let close = "</\(tag)>"
        if let end = after.range(of: close) { return String(after[..<end.lowerBound]) }
        return String(after)
    }
}

enum SafePublicAPIResearch {
    private static let source = URL(string: "https://raw.githubusercontent.com/public-apis/public-apis/master/README.md")!
    private static let blockedTerms = ["gambling", "betting", "casino", "alcohol", "beer", "wine", "weapon", "gun", "firearm", "drug", "porn", "adult", "malware"]

    static func research(queries: [String]) async -> String {
        guard !queries.isEmpty else { return "" }
        guard let (data, _) = try? await URLSession.shared.data(from: source),
              let catalog = String(data: data, encoding: .utf8) else { return "Public API catalog could not be reached; use local fallback data." }

        var sections: [String] = []
        for query in queries where isSafe(query) {
            let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let rows = catalog.split(separator: "\n").map(String.init).filter { line in
                guard line.hasPrefix("|") else { return false }
                let lower = line.lowercased()
                guard !blockedTerms.contains(where: { lower.contains($0) }) else { return false }
                return terms.contains(where: { lower.contains($0) })
            }.prefix(8)
            if !rows.isEmpty {
                sections.append("Query: \(query)\n" + rows.joined(separator: "\n"))
            }
        }
        return sections.joined(separator: "\n\n")
    }

    private static func isSafe(_ query: String) -> Bool {
        let lower = query.lowercased()
        return !blockedTerms.contains(where: { lower.contains($0) })
    }
}

enum HTMLStreamRepair {
    static func previewDocument(_ fragment: String) -> String {
        var html = fragment
        let lower = html.lowercased()
        if !lower.contains("<!doctype") && !lower.contains("<html") {
            html = "<!DOCTYPE html><html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\"></head><body>" + html
        }
        if count("<script", in: html) > count("</script>", in: html) { html += "\n</script>" }
        if count("<style", in: html) > count("</style>", in: html) { html += "\n</style>" }
        if count("<head", in: html) > count("</head>", in: html) { html += "\n</head>" }
        if count("<body", in: html) > count("</body>", in: html) { html += "\n</body>" }
        if count("<html", in: html) > count("</html>", in: html) { html += "\n</html>" }
        return html
    }

    private static func count(_ needle: String, in value: String) -> Int {
        value.lowercased().components(separatedBy: needle).count - 1
    }
}

enum AIIconRenderer {
    static let endpoint = URL(string: "https://mekapc.hostish.site/api/image")!

    static func render(script: String) async -> Data? {
        let cleaned = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": cleaned])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else { return nil }
        return data
    }
}
