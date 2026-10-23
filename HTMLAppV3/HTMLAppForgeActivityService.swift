import Foundation
import ActivityKit

/// Host-owned Forge progress, separate from activities created by saved HTML apps.
@MainActor
@available(iOS 16.2, *)
enum HTMLAppForgeActivityService {
    static let warning = "Do not leave HTMLApp or turn off your phone for more than 20 seconds at a time for now."
    private static var activeJob: String?

    static func recoverStale() async {
        for activity in Activity<HTMLAppForgeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activeJob = nil
    }

    static func start(job: String, edit: Bool, phase: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Don't leave duplicate activities if a new job replaces an old job.
        await recoverStale()
        do {
            let activity = try Activity<HTMLAppForgeActivityAttributes>.request(
                attributes: HTMLAppForgeActivityAttributes(jobID: job, isEdit: edit),
                content: ActivityContent(state: .init(phase: phase, progress: 0.05), staleDate: nil),
                pushType: nil
            )
            activeJob = activity.attributes.jobID
        } catch {
            // Live Activities can be disabled or throttled; never interrupt Forge.
            NSLog("HTMLApp Forge Live Activity unavailable: %@", error.localizedDescription)
        }
    }

    static func update(job: String, phase: String) async {
        guard activeJob == job,
              let activity = Activity<HTMLAppForgeActivityAttributes>.activities.first(where: { $0.attributes.jobID == job })
        else { return }
        let phases = ["Preparing", "Planning", "Designing", "Generating", "Patching",
                      "Repairing", "Checking", "Polishing", "Ready"]
        let ordinal = phases.firstIndex(where: { phase.localizedCaseInsensitiveContains($0) }) ?? 2
        let approximate = min(0.95, Double(ordinal + 1) / Double(phases.count))
        await activity.update(ActivityContent(
            state: .init(phase: String(phase.prefix(85)), progress: approximate), staleDate: nil
        ))
    }

    static func finish(job: String) async {
        guard activeJob == job else { return }
        activeJob = nil
        for activity in Activity<HTMLAppForgeActivityAttributes>.activities where activity.attributes.jobID == job {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
