import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Small, permission-gated generated-app inference. Never reaches any cloud AI
/// provider; use it only for short interactions that fit Apple's on-device model.
enum HTMLAppLocalAgent {
    enum LocalError: LocalizedError {
        case unavailable(String), invalidResult, invalidInput, thermal
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .invalidResult: return "The on-device model did not produce the requested response format."
            case .invalidInput: return "Local model prompts must be short and nonempty."
            case .thermal: return "Local inference is paused because the device is overheating."
            }
        }
    }

    static var availabilityMessage: String? { HTMLAppOfflineForge.availabilityMessage }

    static func complete(prompt: String, system: String, json: Bool) async throws -> [String: Any] {
        guard let reason = availabilityMessage else {
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  prompt.utf8.count <= 4000, system.utf8.count <= 1200 else {
                throw LocalError.invalidInput
            }
            guard ProcessInfo.processInfo.thermalState != .critical else {
                throw LocalError.thermal
            }
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return try await infer(prompt: prompt, system: system, json: json)
            }
            #endif
            throw LocalError.unavailable("Foundation Models is unavailable in this build.")
        }
        throw LocalError.unavailable(reason)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func infer(prompt: String, system: String, json: Bool) async throws -> [String: Any] {
        try Task.checkCancellation()
        let instruction = system + (json ?
            "\nRespond with one JSON object or array only. Do not use Markdown." : "")
        let session = LanguageModelSession(instructions: instruction)
        let response = try await session.respond(to: prompt)
        try Task.checkCancellation()
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalError.invalidResult }
        if json {
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  object is [String: Any] || object is [Any] else {
                throw LocalError.invalidResult
            }
            return ["text": text, "format": "json"]
        }
        return ["text": text, "format": "text"]
    }
    #endif
}
