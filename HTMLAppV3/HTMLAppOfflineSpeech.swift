import Foundation
import AVFoundation
import WhisperKit

/// Shared offline recognizer. The model is downloaded by WhisperKit the first
/// time a transcription runs and retained in its managed model directory.
@MainActor
final class HTMLAppOfflineSpeech {
    static let shared = HTMLAppOfflineSpeech()
    private var whisper: WhisperKit?
    private var loadingTask: Task<WhisperKit, Error>?
    private init() {}

    func preloadIfSelected() {
        guard UserDefaults.standard.string(forKey: "htmlapp.dictationEngine") == "whisper" else { return }
        guard whisper == nil, loadingTask == nil else { return }
        loadingTask = Task { try await WhisperKit() }
    }

    private func preparedModel() async throws -> WhisperKit {
        if let whisper { return whisper }
        if loadingTask == nil { loadingTask = Task { try await WhisperKit() } }
        guard let task = loadingTask else { throw NSError(domain: "HTMLAppWhisper", code: 2) }
        do {
            let model = try await task.value
            whisper = model
            loadingTask = nil
            return model
        } catch {
            loadingTask = nil
            throw error
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        let model = try await preparedModel()
        let result = try await model.transcribe(audioPath: fileURL.path)
        guard !result.isEmpty else {
            throw NSError(domain: "HTMLAppWhisper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No transcription was returned."])
        }
        return result.map(\.text).joined(separator: " ")
    }
}
