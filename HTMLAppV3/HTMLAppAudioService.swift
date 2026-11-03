import Foundation
import AVFoundation

/// App-scoped foreground audio recording and playback. File contents remain
/// in the saved app's sandbox and never cross the JSON bridge as base64.
/// Microphone consent is requested only after the host grants permission.
@MainActor
final class HTMLAppAudioService: NSObject, AVAudioRecorderDelegate {
    enum Failure: LocalizedError {
        case denied, busy, invalidFile, failed, nothingToStop

        var errorDescription: String? {
            switch self {
            case .denied: return "Microphone access was denied in iOS Settings."
            case .busy: return "Finish the existing audio operation first."
            case .invalidFile: return "Choose an audio file recorded by this saved app."
            case .failed: return "Audio hardware or recording is currently unavailable."
            case .nothingToStop: return "No audio recording is in progress."
            }
        }
    }

    private let root: URL
    private let onEvent: ([String: Any]) -> Void
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var activeRecordingURL: URL?
    private var lastRecording: URL?

    init(root: URL, onEvent: @escaping ([String: Any]) -> Void) {
        self.root = root.standardizedFileURL
        self.onEvent = onEvent
        super.init()
    }

    func record(maxDuration rawDuration: Double) async throws -> [String: Any] {
        guard recorder == nil else { throw Failure.busy }
        if player != nil { _ = stop() }
        let permitted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard permitted else { throw Failure.denied }
        let duration = max(1, min(300, rawDuration.isFinite ? rawDuration : 60))
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let relative = "native-imports/audio/" + UUID().uuidString + ".m4a"
        let destination = root.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let recorder = try AVAudioRecorder(url: destination, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ])
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: duration) else {
                throw Failure.failed
            }
            self.recorder = recorder
            activeRecordingURL = destination
            lastRecording = nil
            return [
                "recording": true, "url": relative, "maxDuration": duration,
                "mimeType": "audio/mp4"
            ]
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func stopRecording() throws -> [String: Any] {
        guard let recorder, let url = activeRecordingURL else {
            if let lastRecording { return descriptor(for: lastRecording) }
            throw Failure.nothingToStop
        }
        recorder.stop()
        self.recorder = nil
        activeRecordingURL = nil
        lastRecording = url
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
        return descriptor(for: url)
    }

    func cancelRecording() -> [String: Any] {
        let url = activeRecordingURL
        recorder?.stop()
        recorder = nil
        activeRecordingURL = nil
        lastRecording = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
        return ["cancelled": true]
    }

    func levels() -> [String: Any] {
        guard let recorder, recorder.isRecording else {
            return ["recording": false, "levelDB": -160.0]
        }
        recorder.updateMeters()
        return [
            "recording": true,
            "levelDB": Double(recorder.averagePower(forChannel: 0)),
            "peakDB": Double(recorder.peakPower(forChannel: 0)),
            "duration": recorder.currentTime
        ]
    }

    func play(relative: String) throws -> [String: Any] {
        guard recorder == nil else { throw Failure.busy }
        guard let url = appAudioURL(relative) else { throw Failure.invalidFile }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        player?.stop()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.numberOfLoops = 0
        guard audio.prepareToPlay(), audio.play() else { throw Failure.failed }
        player = audio
        return ["playing": true, "duration": audio.duration]
    }

    func pause() -> [String: Any] {
        player?.pause()
        return ["playing": player?.isPlaying ?? false]
    }

    func stop() -> [String: Any] {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
        return ["playing": false]
    }

    func shutdown() {
        _ = cancelRecording()
        _ = stop()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder,
                                                     successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder,
                  let url = self.activeRecordingURL else { return }
            self.recorder = nil
            self.activeRecordingURL = nil
            self.lastRecording = flag ? url : nil
            if !flag { try? FileManager.default.removeItem(at: url) }
            try? AVAudioSession.sharedInstance().setActive(false,
                  options: .notifyOthersOnDeactivation)
            var event: [String: Any] = ["finished": true, "success": flag]
            if flag { event["file"] = self.descriptor(for: url) }
            self.onEvent(event)
        }
    }

    private func descriptor(for url: URL) -> [String: Any] {
        let size = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        let duration = AVURLAsset(url: url).duration.seconds
        return [
            "url": "native-imports/audio/" + url.lastPathComponent,
            "name": url.lastPathComponent,
            "mimeType": "audio/mp4",
            "size": size,
            "duration": duration.isFinite ? duration : 0,
            "recording": false
        ]
    }

    private func appAudioURL(_ relative: String) -> URL? {
        guard relative.hasPrefix("native-imports/audio/"),
              !relative.contains(".."), !relative.contains("%"),
              relative.hasSuffix(".m4a") else { return nil }
        let directory = root.appendingPathComponent("native-imports/audio").standardizedFileURL
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(directory.path + "/"),
              FileManager.default.fileExists(atPath: url.path),
              ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) <= 30_000_000 else {
            return nil
        }
        return url
    }
}
