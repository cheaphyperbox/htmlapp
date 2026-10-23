import SwiftUI
import Speech
import AVFoundation

@MainActor
final class ForgeDictation: ObservableObject {
    @Published var recording = false
    @Published var requestingPermission = false
    @Published var transcribingOffline = false
    @Published var transcript = ""
    @Published var status = "Dictate your idea. Review the text before generating."
    private let engine = AVAudioEngine()
    private var offlineRecorder: AVAudioRecorder?
    private var offlineURL: URL?
    private var offlineMode = false
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var tapped = false
    private var timeout: Task<Void, Never>?

    func start() async {
        guard !recording, !requestingPermission else { return }
        if UserDefaults.standard.string(forKey: "htmlapp.dictationEngine") == "whisper" {
            await startOffline()
            return
        }
        requestingPermission = true
        defer { requestingPermission = false }
        let attempt = generation
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == attempt, !Task.isCancelled else { return }
        guard permission == .authorized else { status = "Enable Speech Recognition for HTMLApp in Settings, or type your idea."; return }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == attempt, !Task.isCancelled else { return }
        guard microphone else { status = "Enable Microphone for HTMLApp in Settings, or type your idea."; return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            status = "Speech recognition is unavailable for this language or connection. You can still type."; return
        }
        stop()
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            transcript = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain: "Dictation", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone input is available."]) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            let generation = self.generation
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == generation else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                        self.status = error == nil ? "Dictation finished. Review your idea." : "Dictation stopped. Your transcribed text is kept; you can edit it."
                    }
                }
            }
            engine.prepare()
            try engine.start()
            recording = true
            status = recognizer.supportsOnDeviceRecognition ? "Listening on device…" : "Listening using Apple speech recognition. Audio may be sent to Apple."
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 55_000_000_000)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch { stop(); status = error.localizedDescription }
    }
    private func startOffline() async {
        requestingPermission = true
        defer { requestingPermission = false }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else {
            status = "Allow Microphone for HTMLApp in iOS Settings. Whisper needs no Apple Speech permission."
            return
        }
        do {
            stop()
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default, options: .duckOthers)
            try audio.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("htmlapp-dictation-" + UUID().uuidString + ".wav")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false
            ])
            guard recorder.record() else {
                throw NSError(domain: "Dictation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not record microphone audio."])
            }
            offlineURL = url
            offlineRecorder = recorder
            offlineMode = true
            transcript = ""
            recording = true
            status = "Recording for Whisper… Release to transcribe offline."
        } catch {
            status = "Offline recording could not start: " + error.localizedDescription
            stop()
        }
    }

    func cancel() {
        // Explicit cancellation discards a captured recording instead of
        // launching an expensive Whisper decode outside the drop target.
        if offlineMode {
            offlineRecorder?.stop()
            offlineRecorder = nil
            offlineMode = false
            recording = false
            if let offlineURL { try? FileManager.default.removeItem(at: offlineURL) }
            offlineURL = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        stop()
    }

    func stop() {
        if offlineMode {
            offlineRecorder?.stop()
            offlineRecorder = nil
            offlineMode = false
            recording = false
            let url = offlineURL
            offlineURL = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            guard let url else { return }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            guard bytes > 1024 else {
                status = "No microphone audio was recorded. Check microphone access and hold the mic longer."
                try? FileManager.default.removeItem(at: url)
                return
            }
            status = "Recorded \(bytes / 1024) KB. Loading Whisper and transcribing offline…"
            transcribingOffline = true
            Task {
                defer {
                    transcribingOffline = false
                    try? FileManager.default.removeItem(at: url)
                }
                do {
                    let result = try await HTMLAppOfflineSpeech.shared.transcribe(fileURL: url)
                    transcript = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    status = transcript.isEmpty ? "No speech detected. Try again or type instead." : "Whisper transcription is ready."
                } catch {
                    status = "Whisper unavailable: " + error.localizedDescription
                }
            }
            return
        }
        generation = UUID()
        if recording { status = "Dictation stopped. Review your text before generating." }
        timeout?.cancel(); timeout = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
