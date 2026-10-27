import Foundation
import Speech
import AVFoundation

/// Foreground-only, explicitly permissioned speech recognition.
@MainActor
final class HTMLAppSpeechRecognition {
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognizer: SFSpeechRecognizer?
    private var callback: ((Result<[String: Any], Error>) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var tapInstalled = false
    private var latestTranscript = ""

    var active: Bool { engine.isRunning }

    func start(locale: String, onResult: @escaping (Result<[String: Any], Error>) -> Void) async throws {
        guard !active else { throw NSError(domain: "HTMLAppSpeech", code: 1) }
        guard locale.count <= 32, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.isAvailable else { throw NSError(domain: "HTMLAppSpeech", code: 2) }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else { throw NSError(domain: "HTMLAppSpeech", code: 3) }
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard granted else { throw NSError(domain: "HTMLAppSpeech", code: 4) }
        try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.recognizer = recognizer
        self.request = request
        self.callback = onResult
        latestTranscript = ""
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    self.callback?(.success(["text": result.bestTranscription.formattedString,
                                             "final": result.isFinal,
                                             "onDevice": request.requiresOnDeviceRecognition]))
                    if result.isFinal { self.stop() }
                } else if let error {
                    self.callback?(.failure(error))
                    self.stop()
                }
            }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled, let self, self.active else { return }
                self.callback?(.success(["text": self.latestTranscript, "final": true, "timedOut": true]))
                self.stop()
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        callback = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
