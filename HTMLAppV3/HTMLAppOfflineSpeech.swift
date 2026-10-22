import Foundation
import AVFoundation
import WhisperKit

/// Shared offline recognizer. The model is downloaded by WhisperKit the first
/// time a transcription runs and retained in its managed model directory.
@MainActor
final class HTMLAppOfflineSpeech {
    static let shared = HTMLAppOfflineSpeech()
    private var whisper: WhisperKit?
    private init() {}

    func transcribe(fileURL: URL) async throws -> String {
        if whisper == nil {
            whisper = try await WhisperKit()
        }
        guard let result = try await whisper?.transcribe(audioPath: fileURL.path) else {
            throw NSError(domain: "HTMLAppWhisper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No transcription was returned."])
        }
        return result.map(\.text).joined(separator: " ")
    }
}
