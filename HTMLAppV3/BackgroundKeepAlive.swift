import AVFoundation
import Foundation

/// Best-effort experimental background audio during a user-started Forge run.
/// iOS may still suspend the app; background tasks are the supported fallback.
@MainActor
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var installed = false
    private(set) var isRunning = false

    func start() {
        guard UserDefaults.standard.bool(forKey: "generationMusic.silentKeepAlive"), !isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100),
                  let channel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = 44100
            channel.initialize(repeating: 0, count: 44100)
            if !installed {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                installed = true
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            try engine.start()
            player.play()
            isRunning = true
        } catch {
            AIDebugTraceStore.shared.append("FORGE AUDIO", error.localizedDescription)
        }
    }

    func stop() {
        guard installed else { return }
        player.stop()
        engine.stop()
        engine.detach(player)
        installed = false
        isRunning = false
        if !GenerationMusic.shared.isPlaying {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }
}
