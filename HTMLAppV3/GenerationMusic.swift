import Foundation
import SwiftUI
import AVFoundation
import CryptoKit
import MediaPlayer

enum GenerationMusicSettings {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "generationMusic.enabled") }
    static var url: String { UserDefaults.standard.string(forKey: "generationMusic.url") ?? "" }
    static var volume: Float {
        guard UserDefaults.standard.object(forKey: "generationMusic.volume") != nil else { return 0.6 }
        return Float(min(1, max(0, UserDefaults.standard.double(forKey: "generationMusic.volume"))))
    }

    static func validatedURL(_ input: String) -> URL? {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if components.scheme?.lowercased() == "https" { return url }
        guard components.scheme?.lowercased() == "http" else { return nil }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        let private172 = parts.count == 4 && parts[0] == 172 && (16...31).contains(parts[1])
        let private192 = parts.count == 4 && parts[0] == 192 && parts[1] == 168
        let private10 = parts.count == 4 && parts[0] == 10
        return host.hasSuffix(".local") || host == "localhost" || private172 || private192 || private10 ? url : nil
    }
}

@MainActor
final class GenerationMusic: ObservableObject {
    static let shared = GenerationMusic()
    static let playbackPausedNotification = Notification.Name("HTMLApp.GenerationMusicPaused")
    @Published private(set) var status = "Ready"
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreview = false
    @Published private(set) var isGenerationActive = false

    private var player: AVAudioPlayer?
    private var loadTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var remoteStopToken: Any?
    private var remotePlayToken: Any?
    private var remotePauseToken: Any?
    private var generationWanted = false
    private var requestID = UUID()

    private init() {}

    func start() {
        stopPreview()
        guard GenerationMusicSettings.enabled else { return }
        generationWanted = true
        isGenerationActive = true
        begin(preview: false)
    }

    func preview() {
        guard !generationWanted else { return }
        begin(preview: true)
    }

    func togglePreview() {
        if isPreview { stopPreview() } else { preview() }
    }

    func applyVolume() {
        player?.volume = GenerationMusicSettings.volume
    }

    func prefetch() {
        // Changing the Settings URL must not cancel an active generation track.
        guard !generationWanted else { return }
        guard let url = GenerationMusicSettings.validatedURL(GenerationMusicSettings.url) else {
            fail("Enter a valid audio file URL.")
            return
        }
        let identifier = UUID()
        requestID = identifier
        loadTask?.cancel()
        status = "Loading…"
        loadTask = Task {
            do {
                _ = try await Self.cachedAudio(from: url)
                guard !Task.isCancelled, requestID == identifier else { return }
                status = "Ready"
            } catch is CancellationError {
            } catch {
                guard requestID == identifier else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func begin(preview: Bool) {
        guard let url = GenerationMusicSettings.validatedURL(GenerationMusicSettings.url) else {
            fail("Enter a valid audio file URL.")
            return
        }
        let identifier = UUID()
        requestID = identifier
        loadTask?.cancel()
        player?.stop()
        player = nil
        isPlaying = false
        isPreview = preview
        if !preview { generationWanted = true }
        status = "Loading…"
        // A locally cached track can begin synchronously, before the user
        // locks the display or iOS suspends network download callbacks.
        if let cached = Self.existingCachedAudio(from: url) {
            do {
                try activateAndPlay(cached)
                return
            } catch {
                fail(error.localizedDescription)
            }
        }
        loadTask = Task {
            // Yield to let the caller close the microphone audio session first.
            await Task.yield()
            do {
                let file = try await Self.cachedAudio(from: url)
                // Give Forge dictation's session teardown time to finish
                // before activating music; the preview remains immediate.
                if !preview { try await Task.sleep(nanoseconds: 150_000_000) }
                try Task.checkCancellation()
                guard requestID == identifier, (preview ? isPreview : generationWanted) else { return }
                try activateAndPlay(file)
            } catch is CancellationError {
            } catch {
                guard requestID == identifier else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func activateAndPlay(_ file: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        let audio = try AVAudioPlayer(contentsOf: file)
        audio.numberOfLoops = -1
        audio.prepareToPlay()
        audio.volume = GenerationMusicSettings.volume
        guard audio.play() else { throw NSError(domain: "GenerationMusic", code: 1, userInfo: [NSLocalizedDescriptionKey: "The audio could not start playing."]) }
        player = audio
        isPlaying = true
        status = "Playing"
        observeAudioSession()
        configureNowPlaying()
    }

    private func configureNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Generation Music",
            MPMediaItemPropertyArtist: "HTMLApp",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0
        ]
        let controls = MPRemoteCommandCenter.shared()
        controls.stopCommand.isEnabled = true
        controls.playCommand.isEnabled = true
        controls.pauseCommand.isEnabled = true
        if remoteStopToken == nil {
            remoteStopToken = controls.stopCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.stop() }
                return .success
            }
        }
        if remotePauseToken == nil {
            remotePauseToken = controls.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.pause() }
                return .success
            }
        }
        if remotePlayToken == nil {
            remotePlayToken = controls.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.resume() }
                return .success
            }
        }
    }

    private func observeAudioSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if type == AVAudioSession.InterruptionType.ended.rawValue {
                    let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                        self.resume()
                    } else {
                        self.pause()
                    }
                } else if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.isPlaying = false
                    self.updatePlaybackRate(0)
                    if self.generationWanted {
                        NotificationCenter.default.post(name: Self.playbackPausedNotification, object: nil)
                    }
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                           object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                if rawReason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self.pause()
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
        })
    }

    private func pause() {
        guard player != nil else { return }
        player?.pause()
        isPlaying = false
        status = "Paused"
        updatePlaybackRate(0)
        if generationWanted {
            NotificationCenter.default.post(name: Self.playbackPausedNotification, object: nil)
        }
    }

    private func updatePlaybackRate(_ rate: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func resume() {
        guard generationWanted || isPreview else { return }
        if let player {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                if player.play() { isPlaying = true; status = "Playing"; updatePlaybackRate(1); return }
            } catch { }
        }
        begin(preview: isPreview)
    }

    func stopPreview() {
        guard isPreview && !generationWanted else { return }
        stop()
    }

    func stop() {
        let hadMusicSession = generationWanted || isPreview || player != nil || loadTask != nil
        generationWanted = false
        isGenerationActive = false
        isPreview = false
        requestID = UUID()
        loadTask?.cancel()
        loadTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        let controls = MPRemoteCommandCenter.shared()
        if let remoteStopToken { controls.stopCommand.removeTarget(remoteStopToken) }
        if let remotePlayToken { controls.playCommand.removeTarget(remotePlayToken) }
        if let remotePauseToken { controls.pauseCommand.removeTarget(remotePauseToken) }
        remoteStopToken = nil
        remotePlayToken = nil
        remotePauseToken = nil
        controls.stopCommand.isEnabled = false
        controls.playCommand.isEnabled = false
        controls.pauseCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if hadMusicSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                AIDebugTraceStore.shared.append("GENERATION MUSIC", "Audio session deactivation was unavailable.")
            }
        }
        status = "Ready"
    }

    private func fail(_ detail: String) {
        isPlaying = false
        status = detail
        AIDebugTraceStore.shared.append("GENERATION MUSIC", detail)
    }

    nonisolated private static func cacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GenerationMusic", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated private static func existingCachedAudio(from url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        let ext = ["mp3", "m4a", "wav", "aac", "caf"].contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "mp3"
        guard let directory = try? cacheDirectory() else { return nil }
        let file = directory.appendingPathComponent(key + "." + ext)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    nonisolated private static func cachedAudio(from url: URL) async throws -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        let ext = ["mp3", "m4a", "wav", "aac", "caf"].contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "mp3"
        let directory = try cacheDirectory()
        let destination = directory.appendingPathComponent(key + "." + ext)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "GenerationMusic", code: 2, userInfo: [NSLocalizedDescriptionKey: "The audio download failed. Check the URL."])
        }
        let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 && size <= 80 * 1024 * 1024 else {
            throw NSError(domain: "GenerationMusic", code: 3, userInfo: [NSLocalizedDescriptionKey: "The audio file must be smaller than 80 MB."])
        }
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file != destination { try? FileManager.default.removeItem(at: file) }
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return destination
    }
}
