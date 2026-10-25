import Foundation
import UIKit
import UserNotifications

/// Keeps one file-backed model request running through iOS suspension.
/// Foreground coding uses the existing streaming client; the background
/// response is persisted for safe foreground verification and icon rendering.
final class ForgeBackgroundUpload: NSObject, URLSessionDataDelegate {
    static let shared = ForgeBackgroundUpload()

    static let finishedNotification = Notification.Name("HTMLAppForgeBackgroundUploadFinished")
    private static let sessionIdentifier = "com.mekabrine.htmlapp.forge.background-upload"
    private static let pendingKey = "forge.backgroundUpload.pending"
    private static let formatKey = "forge.backgroundUpload.compatibility"
    private static let bodyFileKey = "forge.backgroundUpload.bodyFile"

    private var session: URLSession?
    private var responseBuffers: [Int: Data] = [:]
    private var eventsCompletion: (() -> Void)?

    private override init() { super.init() }

    /// Access from the app's main thread (including scene lifecycle hooks).
    var isActive: Bool { UserDefaults.standard.bool(forKey: Self.pendingKey) }

    private func attachSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 1200
        let created = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        session = created
        return created
    }

    func reconnectIfNeeded() {
        guard isActive else { return }
        let attached = attachSession()
        attached.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                if tasks.isEmpty {
                    self.completeWithoutResult("The background request ended before returning an app.")
                }
            }
        }
    }

    func reconnect(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.sessionIdentifier else {
            completionHandler()
            return
        }
        eventsCompletion = completionHandler
        _ = attachSession()
    }

    /// Returns false for unsupported/non-HTTPS providers. Failure to start a
    /// transfer leaves the normal foreground checkpoint recovery available.
    @discardableResult
    func start(config: AIProviderConfiguration, system: String,
               messages: [(String, String)], edit: Bool) -> Bool {
        guard !isActive, config.isConfigured else { return false }
        do {
            let (request, file) = try AIProviderClient.backgroundUploadRequest(
                config: config, system: system, messages: messages)
            let defaults = UserDefaults.standard
            defaults.set(config.compatibility.rawValue, forKey: Self.formatKey)
            defaults.set(file.path, forKey: Self.bodyFileKey)
            defaults.set(true, forKey: Self.pendingKey)
            let task = attachSession().uploadTask(with: request, fromFile: file)
            task.taskDescription = edit ? "HTMLApp AI edit" : "HTMLApp generation"
            task.resume()
            Task { @MainActor in AIDebugTraceStore.shared.append(
                "BACKGROUND FORGE",
                "A file-backed provider request was started. The completed result will be reviewed in HTMLApp.") }
            return true
        } catch {
            Task { @MainActor in AIDebugTraceStore.shared.append(
                "BACKGROUND FORGE", "Could not start background generation: " + error.localizedDescription) }
            return false
        }
    }

    func cancel() {
        let attached = session
        attached?.getAllTasks { tasks in
            for task in tasks { task.cancel() }
        }
        clearPending()
        Task { @MainActor in GenerationMusic.shared.stop() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseBuffers[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let body = responseBuffers.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard isActive else { return }
        if let error {
            completeWithoutResult("The background AI request failed: " + error.localizedDescription)
            return
        }
        guard let response = task.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            completeWithoutResult("The background AI request was not accepted by the provider.")
            return
        }
        let selected = UserDefaults.standard.string(forKey: Self.formatKey) ?? ""
        let format = AIProviderConfiguration.Compatibility(rawValue: selected) ?? .openAI
        guard let text = AIProviderClient.backgroundResponseText(body, type: format),
              let draft = ForgeDraftCheckpointStore.load() else {
            completeWithoutResult("The provider did not return a usable background result.")
            return
        }

        let result = AIHTMLAgent.parse(text)
        let reconstructed: String?
        if !result.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reconstructed = result.html
        } else if !result.patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reconstructed = HTMLPatchApplier.apply(result.patch, to: draft.html)
        } else {
            reconstructed = nil
        }
        guard let html = reconstructed,
              html.localizedCaseInsensitiveContains("</html>") else {
            completeWithoutResult("The provider's background response was incomplete. Your earlier draft remains available.")
            return
        }

        var updated = draft
        updated.html = html
        updated.savedAt = Date()
        updated.streamedByteCount = html.utf8.count
        updated.description = result.description.isEmpty ? draft.description : result.description
        updated.refinedBrief = result.refinedBrief.isEmpty ? draft.refinedBrief : result.refinedBrief
        updated.iconScript = result.iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AIHTMLAgent.fallbackIconScript(html: html, originalPrompt: draft.originalPrompt)
            : result.iconScript
        updated.phase = "Background result received"
        ForgeDraftCheckpointStore.save(updated)
        clearPending()
        Task { @MainActor in AIDebugTraceStore.shared.append(
            "BACKGROUND FORGE", "A complete background response was saved for foreground review.") }
        NotificationCenter.default.post(name: Self.finishedNotification, object: nil)
        Task { @MainActor in
            GenerationMusic.shared.stop()
            Self.notifyReady()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if let completion = eventsCompletion {
            eventsCompletion = nil
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func completeWithoutResult(_ message: String) {
        if var checkpoint = ForgeDraftCheckpointStore.load() {
            checkpoint.phase = "Background request failed"
            checkpoint.savedAt = Date()
            ForgeDraftCheckpointStore.save(checkpoint)
        }
        clearPending()
        Task { @MainActor in AIDebugTraceStore.shared.append("BACKGROUND FORGE", message) }
        NotificationCenter.default.post(name: Self.finishedNotification, object: nil)
        Task { @MainActor in GenerationMusic.shared.stop() }
    }

    private func clearPending() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: Self.bodyFileKey) {
            try? FileManager.default.removeItem(atPath: path)
        }
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.formatKey)
        defaults.removeObject(forKey: Self.bodyFileKey)
    }

    @MainActor
    private static func notifyReady() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "HTMLApp"
            content.body = "Your app is ready to review."
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

/// Receives completed URLSession events after iOS relaunches HTMLApp.
final class HTMLAppBackgroundURLSessionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        ForgeBackgroundUpload.shared.reconnect(
            identifier: identifier, completionHandler: completionHandler)
    }
}
