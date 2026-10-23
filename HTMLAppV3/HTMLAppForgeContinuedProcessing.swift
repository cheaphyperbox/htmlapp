import Foundation
import BackgroundTasks

// Compiled only with the iOS 26 SDK; older Xcode releases keep the existing
// finite UIApplication background task and on-disk Forge checkpoint recovery.
#if compiler(>=6.2)
@available(iOS 26.0, *)
enum HTMLAppForgeContinuedProcessing {
    private static let identifier = "com.mekabrine.htmlapp.forge.processing"
    private static var registered = false
    private static var running = false
    private static var currentTask: BGContinuedProcessingTask?

    static func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let active = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                guard running else {
                    active.setTaskCompleted(success: true)
                    return
                }
                currentTask = active
                active.progress.totalUnitCount = 100
                active.progress.completedUnitCount = 5
                active.expirationHandler = {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("HTMLAppForgeBackgroundExpired"), object: nil)
                        active.setTaskCompleted(success: false)
                        currentTask = nil
                    }
                }
            }
        }
    }

    static func begin(edit: Bool) {
        running = true
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: edit ? "HTMLApp AI edit" : "HTMLApp app generation",
            subtitle: "Generating your app"
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Normal UIApplication background grace and disk recovery remain.
            NSLog("Forge continued processing unavailable: %@", error.localizedDescription)
        }
    }

    static func update(phase: String) {
        currentTask?.updateTitle("HTMLApp Forge", subtitle: String(phase.prefix(80)))
        if let task = currentTask {
            task.progress.completedUnitCount = min(95, task.progress.completedUnitCount + 4)
        }
    }

    static func finish(success: Bool) {
        running = false
        if success { currentTask?.progress.completedUnitCount = 100 }
        currentTask?.setTaskCompleted(success: success)
        currentTask = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}
#endif
