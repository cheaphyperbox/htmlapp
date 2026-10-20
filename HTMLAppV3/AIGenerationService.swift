import Foundation
import SwiftUI

struct AIGeneratedAsset: Equatable {
    var name: String
    var script: String
}

struct AIGenerationOutput {
    var html = ""
    var patch = ""
    var description = ""
    var iconScript = ""
    var assetScripts: [AIGeneratedAsset] = []
    var refinedBrief = ""
}

struct AIResearchPlan {
    var publicQueries: [String] = []
    var deviceQueries: [String] = []

    var isEmpty: Bool {
        publicQueries.isEmpty && deviceQueries.isEmpty
    }
}

struct AIPlanningResult {
    var brief: String
    var research: AIResearchPlan
}

enum AIGenerationError: LocalizedError {
    case notConfigured, invalidEndpoint, missingHTML, invalidPatch, missingIcon
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure an AI API URL and model in Settings first."
        case .invalidEndpoint: return "The configured AI API URL is invalid."
        case .missingHTML: return "The AI response did not contain a complete HTML app."
        case .invalidPatch: return "The AI returned a patch that could not be applied safely."
        case .missingIcon: return "The AI could not produce a valid, renderable app icon."
        case .provider(let message): return message
        }
    }
}

struct AIProviderRequestError: LocalizedError {
    let statusCode: Int?
    let message: String
    let retryable: Bool
    let retryAfter: TimeInterval?

    var errorDescription: String? { message }
}

@MainActor
final class AIGenerationSession: ObservableObject {
    @Published var activity: [String] = []
    @Published var progressNote = "Getting the workspace ready."
    @Published var phase = "Preparing" {
        didSet {
            if oldValue != phase {
                activity.append(phase)
                if activity.count > 40 { activity.removeFirst() }
                progressNote = Self.defaultProgressNote(for: phase)
            }
        }
    }
    @Published var streamedHTML = ""
    @Published var refinedBrief = ""
    @Published var description = ""
    @Published var iconScript = ""
    @Published var renderedIconData: Data?
    @Published var verificationReport = ""
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published var streamedByteCount = 0

    private var originalPrompt = ""
    private var lastResearch = ""
    private var editingExistingApp = false

    private static func defaultProgressNote(for phase: String) -> String {
        switch phase {
        case "Preparing": return "Getting the workspace ready."
        case "Improving your prompt": return "Turning your request into a concrete product brief without adding unrelated scope."
        case "Planning APIs and capabilities": return "Checking which parts should stay local and which need verified device or web capabilities."
        case "Designing the app": return "Choosing the core workflow, data model, and responsive navigation before coding."
        case "Checking device and web APIs": return "Verifying HTMLApp capabilities and external data sources before depending on them."
        case "Checking device capabilities": return "Matching the requested features to HTMLApp's documented native and browser capabilities."
        case "Finding useful public APIs": return "Looking for no-key data sources, then verifying documentation before integration."
        case "Using web research": return "Applying the research evidence to the implementation without extrapolating beyond it."
        case "Planning web research": return "Deciding what current facts or API documentation actually need to be checked."
        case "Generating live preview": return "Writing the real HTML, CSS, state, persistence, and interactions now."
        case "Retrying generation without streaming": return "The live stream stopped, so I’m finishing the same build with a non-streaming request."
        case "Continuing unfinished generation": return "Continuing exactly where the generated app was cut off instead of restarting it."
        case "Repairing AI output", "Repairing incomplete output": return "Recovering the incomplete response while preserving the finished parts."
        case "Improving the requested change": return "Reducing the edit request to the smallest coherent change that preserves existing behavior."
        case "Checking APIs for this change": return "Verifying whether this edit needs new runtime capabilities or external data."
        case "Preparing focused patch": return "Skipping unnecessary capability research and going straight to the local code change."
        case "Patching the app": return "Applying a focused code patch and preserving unrelated storage, navigation, and behavior."
        case "Generating app icon", "Designing final app icon": return "Designing a simple app-specific icon that stays readable at Home Screen size."
        case "Checking app icon", "Repairing app icon": return "Rendering the icon locally and fixing it if the script is invalid or too detailed."
        case "Reviewing source (not running device tests)": return "Auditing controls, persistence, async failures, safe areas, accessibility, and unsupported assumptions."
        case "Rechecking repaired app": return "Rechecking the repaired source for regressions before presenting it."
        case "Polishing the interface": return "Refining the visual hierarchy without changing the app’s working product model."
        case "Ready to review": return "The generated source is ready for you to try on-device and review."
        case "Generation stopped", "Edit stopped", "Verification stopped": return "The current operation stopped; completed source has been preserved where possible."
        default: return "Working on the current build stage."
        }
    }

    private func publishModelProgress(_ raw: String) {
        let clean = raw.replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != progressNote else { return }
        progressNote = String(clean.prefix(160))
        let event = "AI: \(progressNote)"
        if activity.last != event {
            activity.append(event)
            if activity.count > 40 { activity.removeFirst() }
        }
    }

    func load(existing app: SavedHTMLApp) {
        editingExistingApp = true
        originalPrompt = "Maintain and improve the existing HTML app named \(app.name). Preserve its current purpose and working behavior unless the user explicitly asks to change them."
        streamedHTML = app.html
        description = app.summary
        renderedIconData = app.favicon
        refinedBrief = "Editing \(app.name) with AI. Existing functionality is the starting point and revisions will be applied as patches."
        verificationReport = ""
        phase = "Ready for AI edits"
    }

    func generate(prompt: String, originalUserPrompt: String? = nil, researchReport: String = "") async {
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        editingExistingApp = false
        originalPrompt = originalUserPrompt ?? prompt
        isWorking = true
        errorMessage = nil
        verificationReport = ""
        do {
            let suppliedResearch = researchReport.trimmingCharacters(in: .whitespacesAndNewlines)
            let improved: String
            if AIHTMLAgent.canSkipPreflight(for: prompt) {
                improved = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                refinedBrief = improved
                lastResearch = suppliedResearch
                phase = "Generating live preview"
            } else {
                phase = "Designing the app"
                let planning = try await AIHTMLAgent.planPrompt(
                    prompt,
                    config: AISettingsStore.configuration(for: .planner)
                )
                improved = planning.brief
                refinedBrief = improved
                let plan = planning.research

                let deviceResearch = HTMLAppDeviceAPIResearch.research(queries: plan.deviceQueries)
                AIDebugTraceStore.shared.append(
                    "DEVICE API RESEARCH",
                    deviceResearch.isEmpty ? "No internal device capability research was needed." : deviceResearch
                )
                let publicResearch: String
                if suppliedResearch.isEmpty {
                    if plan.isEmpty {
                        phase = "Designing the app"
                    } else if !plan.deviceQueries.isEmpty && !plan.publicQueries.isEmpty {
                        phase = "Checking device and web APIs"
                    } else if !plan.deviceQueries.isEmpty {
                        phase = "Checking device capabilities"
                    } else {
                        phase = "Finding useful public APIs"
                    }
                    publicResearch = await SafePublicAPIResearch.research(queries: plan.publicQueries)
                } else {
                    phase = plan.deviceQueries.isEmpty ? "Using web research" : "Checking device capabilities"
                    publicResearch = ""
                }

                lastResearch = [deviceResearch, suppliedResearch, publicResearch]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                phase = "Generating live preview"
            }

            let systemPrompt = AIHTMLAgent.systemPrompt(research: lastResearch)
            var full = ""
            var recoveredFromStream: AIGenerationOutput?
            var receivedBytes = 0
            var lastPreviewBytes = 0
            var lastPreviewAt = Date.distantPast
            var lastProgressAt = Date.distantPast
            var progressTail = ""
            do {
                let stream = try await AIProviderClient.stream(
                    config: config,
                    system: systemPrompt,
                    messages: [("user", improved)]
                )
                for try await piece in stream {
                    try Task.checkCancellation()
                    full += piece
                    receivedBytes += piece.utf8.count
                    progressTail += piece
                    if progressTail.utf8.count > 12_000 {
                        progressTail = String(progressTail.suffix(8_000))
                    }

                    let now = Date()
                    if now.timeIntervalSince(lastProgressAt) >= 0.2 {
                        streamedByteCount = receivedBytes
                        if let note = AIHTMLAgent.streamingProgress(in: progressTail) {
                            publishModelProgress(note)
                        }
                        lastProgressAt = now
                    }

                    // Parsing and reloading a WKWebView on every small chunk made
                    // long generations increasingly expensive. Keep the last good
                    // preview and refresh only at coarse, stable checkpoints.
                    if receivedBytes - lastPreviewBytes >= 30_000,
                       now.timeIntervalSince(lastPreviewAt) >= 2.5 {
                        let partial = AIHTMLAgent.parsePartial(full)
                        if HTMLStreamRepair.isSafeForLivePreview(partial.html) {
                            apply(partial, partial: true)
                            lastPreviewBytes = receivedBytes
                            lastPreviewAt = now
                        }
                    }
                }
                streamedByteCount = receivedBytes
                let partial = AIHTMLAgent.parsePartial(full)
                if HTMLStreamRepair.isSafeForLivePreview(partial.html) {
                    apply(partial, partial: true)
                }
            } catch {
                try Task.checkCancellation()
                if full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    phase = "Retrying generation without streaming"
                    full = try await AIProviderClient.complete(
                        config: config,
                        system: systemPrompt,
                        messages: [("user", improved)]
                    )
                    apply(AIHTMLAgent.parsePartial(full), partial: true)
                } else {
                    // Preserve useful streamed output. Continue from the cutoff instead
                    // of discarding it and paying for a full non-streaming restart.
                    recoveredFromStream = try await recoverIncompleteGeneration(
                        fullResponse: &full,
                        brief: improved,
                        systemPrompt: systemPrompt,
                        config: config
                    )
                }
            }

            var final = recoveredFromStream ?? AIHTMLAgent.parse(full)
            if final.html.trimmed.isEmpty {
                final = try await recoverIncompleteGeneration(
                    fullResponse: &full,
                    brief: improved,
                    systemPrompt: systemPrompt,
                    config: config
                )
            }
            guard !final.html.trimmed.isEmpty else { throw AIGenerationError.missingHTML }
            apply(final, partial: false)
            let finalAssets = await refineGeneratedAssets(final.assetScripts)
            await installGeneratedAssets(finalAssets)
            try await ensureValidIcon(
                config: AISettingsStore.configuration(for: .icon),
                forceRegenerate: false
            )
            try await verifyAndRepair(config: config)
            try Task.checkCancellation()
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Generation stopped"
        }
        isWorking = false
    }

    func revise(change: String, researchReport: String = "") async {
        guard !streamedHTML.trimmed.isEmpty else { return }
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        isWorking = true
        errorMessage = nil
        verificationReport = ""
        do {
            let cleanChange = change.trimmingCharacters(in: .whitespacesAndNewlines)
            let canApplyDirectly = cleanChange.count <= 280 && !AIHTMLAgent.needsCapabilityResearch(for: cleanChange)
            let improvedChange: String
            if canApplyDirectly {
                phase = "Preparing focused patch"
                improvedChange = cleanChange
                AIDebugTraceStore.shared.append(
                    "CHANGE PLANNER",
                    "Skipped because this is a concise local edit; the patching model can apply it directly without another AI planning round trip."
                )
            } else {
                phase = "Improving the requested change"
                improvedChange = try await AIHTMLAgent.refineRevision(change, appBrief: refinedBrief, config: AISettingsStore.configuration(for: .planner))
            }

            let suppliedResearch = researchReport.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldPlanResearch = !suppliedResearch.isEmpty || AIHTMLAgent.needsCapabilityResearch(for: change)
            let plan: AIResearchPlan
            if shouldPlanResearch {
                phase = "Checking APIs for this change"
                plan = try await AIHTMLAgent.planResearch(original: originalPrompt, revision: improvedChange, config: AISettingsStore.configuration(for: .planner))
            } else {
                phase = "Preparing focused patch"
                plan = AIResearchPlan()
                AIDebugTraceStore.shared.append(
                    "RESEARCH PLANNER",
                    "Skipped because this edit is local UI/behavior work and does not introduce a new device or web capability."
                )
            }
            let deviceResearch = HTMLAppDeviceAPIResearch.research(queries: plan.deviceQueries)
            AIDebugTraceStore.shared.append(
                "DEVICE API RESEARCH",
                deviceResearch.isEmpty ? "No new internal device capability research was needed for this edit." : deviceResearch
            )
            let publicResearch: String
            if suppliedResearch.isEmpty, !plan.publicQueries.isEmpty {
                publicResearch = await SafePublicAPIResearch.research(queries: plan.publicQueries)
            } else {
                publicResearch = ""
            }
            let research = [deviceResearch, suppliedResearch, publicResearch]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            if !research.isEmpty { lastResearch = research }

            phase = "Patching the app"
            let user = """
Current app:
<htmlapp_existing>
\(streamedHTML)
</htmlapp_existing>

Requested change:
\(improvedChange)
"""
            let response = try await AIProviderClient.complete(
                config: config,
                system: AIHTMLAgent.patchSystemPrompt(research: lastResearch),
                messages: [("user", user)]
            )
            let initialOutput = AIHTMLAgent.parse(response)
            let output = try await applyEditOutputWithRecovery(
                initialOutput,
                requestedChange: improvedChange,
                config: config
            )
            if !output.description.isEmpty { description = output.description }
            if !output.iconScript.isEmpty { iconScript = output.iconScript }
            if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }
            let revisedAssets = await refineGeneratedAssets(output.assetScripts)
            await installGeneratedAssets(revisedAssets)

            if !output.iconScript.isEmpty || !editingExistingApp {
                try await ensureValidIcon(
                    config: AISettingsStore.configuration(for: .icon),
                    forceRegenerate: false
                )
            }
            try await verifyAndRepair(config: config)
            try Task.checkCancellation()
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Edit stopped"
        }
        isWorking = false
    }

    private func applyEditOutputWithRecovery(
        _ initialOutput: AIGenerationOutput,
        requestedChange: String,
        config: AIProviderConfiguration
    ) async throws -> AIGenerationOutput {
        func apply(_ output: AIGenerationOutput) -> HTMLPatchApplication {
            if !output.patch.trimmed.isEmpty {
                return HTMLPatchApplier.applyDetailed(output.patch, to: streamedHTML)
            }
            if !output.html.trimmed.isEmpty {
                return HTMLPatchApplication(html: output.html, failureReason: nil, contextSnippet: "")
            }
            return HTMLPatchApplication(
                html: nil,
                failureReason: "The model returned neither a patch nor a replacement HTML document.",
                contextSnippet: String(streamedHTML.prefix(2200))
            )
        }

        var output = initialOutput
        var application = apply(output)
        if let html = application.html {
            streamedHTML = html
            return output
        }

        let firstFailure = application.failureReason ?? "The patch could not be applied safely."
        AIDebugTraceStore.shared.append("PATCH RECOVERY", firstFailure)

        phase = "Repairing AI output"
        let retryUser = """
The patch below could not be applied safely.

FAILURE:
\(firstFailure)

RELEVANT CURRENT SOURCE:
<source_snippet>
\(application.contextSnippet)
</source_snippet>

FAILED PATCH:
<htmlapp_patch>
\(output.patch)
</htmlapp_patch>

REQUESTED CHANGE:
\(requestedChange)

Return a corrected, minimal <htmlapp_patch> whose SEARCH blocks each match exactly once in the current source. Do not use Markdown fences. Do not change unrelated behavior.
"""
        let retryResponse = try await AIProviderClient.complete(
            config: config,
            system: AIHTMLAgent.patchSystemPrompt(research: lastResearch),
            messages: [("user", retryUser)],
            timeout: 120,
            maxTokens: 8000,
            retryOnTransient: true
        )
        output = AIHTMLAgent.parse(retryResponse)
        application = apply(output)
        if let html = application.html {
            streamedHTML = html
            return output
        }

        let secondFailure = application.failureReason ?? "The corrected patch still could not be applied safely."
        AIDebugTraceStore.shared.append("PATCH FULL REPLACEMENT", secondFailure)

        phase = "Repairing incomplete output"
        let replacementUser = """
Two focused patch attempts failed, so return a complete replacement document for this existing app.

CURRENT APP:
<htmlapp_existing>
\(streamedHTML)
</htmlapp_existing>

REQUESTED CHANGE:
\(requestedChange)

LAST PATCH FAILURE:
\(secondFailure)

Preserve all unrelated features, storage keys, APIs, navigation, data schemas, permissions, widgets/background definitions, and working behavior. Apply only the requested change. Return the normal HTMLApp response format with one complete <htmlapp_code> document and no Markdown fences.
"""
        let replacementResponse = try await AIProviderClient.complete(
            config: config,
            system: AIHTMLAgent.systemPrompt(research: lastResearch),
            messages: [("user", replacementUser)],
            timeout: 180,
            maxTokens: 16000,
            retryOnTransient: true
        )
        let replacementOutput = AIHTMLAgent.parse(replacementResponse)
        guard !replacementOutput.html.trimmed.isEmpty else { throw AIGenerationError.invalidPatch }
        streamedHTML = replacementOutput.html
        return replacementOutput
    }

    func acceptExternalHTML(_ html: String) {
        streamedHTML = html
        verificationReport = ""
    }

    func verifyCurrent() async {
        let config = AISettingsStore.configuration
        guard config.isConfigured, !streamedHTML.trimmed.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        do {
            if !editingExistingApp || !iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await ensureValidIcon(config: config)
            }
            try await verifyAndRepair(config: config)
            try Task.checkCancellation()
            phase = "Ready to review"
        } catch {
            errorMessage = error.localizedDescription
            phase = "Verification stopped"
        }
        isWorking = false
    }

    private func recoverIncompleteGeneration(
        fullResponse: inout String,
        brief: String,
        systemPrompt: String,
        config: AIProviderConfiguration
    ) async throws -> AIGenerationOutput {
        var partial = AIHTMLAgent.parsePartial(fullResponse)
        guard !partial.html.trimmed.isEmpty else {
            phase = "Repairing AI output"
            let repaired = try await AIHTMLAgent.recoverGeneration(
                response: fullResponse,
                brief: brief,
                research: lastResearch,
                config: config
            )
            return AIHTMLAgent.parse(repaired)
        }

        for _ in 0..<2 {
            phase = "Continuing unfinished generation"
            let continuation = try await AIProviderClient.complete(
                config: config,
                system: systemPrompt,
                messages: [
                    ("user", brief),
                    ("assistant", fullResponse),
                    ("user", """
Your previous response was cut off before the HTMLApp output was complete. Continue exactly from the character where you stopped. Do not restart, repeat earlier sections, or wrap the continuation in Markdown. Finish the remaining HTML/CSS/JavaScript and close </htmlapp_code>.
""")
                ]
            )
            fullResponse += continuation
            partial = AIHTMLAgent.parsePartial(fullResponse)
            apply(partial, partial: true)
            let parsed = AIHTMLAgent.parse(fullResponse)
            if !parsed.html.trimmed.isEmpty { return parsed }
        }

        phase = "Repairing incomplete output"
        let repaired = try await AIHTMLAgent.recoverGeneration(
            response: fullResponse,
            brief: brief,
            research: lastResearch,
            config: config
        )
        let parsed = AIHTMLAgent.parse(repaired)
        if !parsed.html.trimmed.isEmpty { return parsed }
        throw AIGenerationError.missingHTML
    }

    private func ensureValidIcon(
        config: AIProviderConfiguration,
        forceRegenerate: Bool = false
    ) async throws {
        phase = iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Generating app icon" : "Checking app icon"

        var candidate = iconScript.trimmingCharacters(in: .whitespacesAndNewlines)
        var repairReason: String?
        var lastError: Error?

        if forceRegenerate {
            phase = "Designing final app icon"
            do {
                let designed = try await AIHTMLAgent.generateIconScript(
                    html: streamedHTML,
                    originalPrompt: originalPrompt,
                    previousScript: candidate,
                    repairReason: "Create the final shipping icon. Treat any existing script only as a draft; simplify or replace it so the selected Icon & Asset model owns the final App Store-style concept.",
                    config: config
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !designed.isEmpty { candidate = designed }
            } catch {
                lastError = error
                AIDebugTraceStore.shared.append("ICON ARTIST", "The dedicated icon pass failed; validating the coding-agent draft instead. \(error.localizedDescription)")
            }
        }

        for attempt in 0..<3 {
            if !candidate.isEmpty {
                if let rendered = await AIIconRenderer.render(script: candidate) {
                    if let qualityIssue = AIHTMLAgent.iconQualityIssue(candidate) {
                        repairReason = qualityIssue
                        AIDebugTraceStore.shared.append("ICON QUALITY", "Attempt \(attempt + 1) rendered, but was rejected: \(qualityIssue)")
                    } else {
                        iconScript = candidate
                        renderedIconData = rendered
                        AIDebugTraceStore.shared.append("ICON RENDER", "Rendered and passed icon-quality checks on attempt \(attempt + 1).")
                        return
                    }
                } else {
                    repairReason = "The previous icon script did not render successfully in HTMLApp. Repair or replace it using only the supported icon commands."
                    AIDebugTraceStore.shared.append("ICON RENDER", "Local render failed on attempt \(attempt + 1). Asking the AI to repair the script.")
                }
            }

            phase = candidate.isEmpty ? "Generating app icon" : "Repairing app icon"
            do {
                candidate = try await AIHTMLAgent.generateIconScript(
                    html: streamedHTML,
                    originalPrompt: originalPrompt,
                    previousScript: candidate,
                    repairReason: repairReason,
                    config: config
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty {
                    repairReason = "The previous response omitted the mandatory <icon_script>. Return a complete replacement icon script."
                }
            } catch {
                lastError = error
                repairReason = "The previous icon-generation request failed: \(error.localizedDescription). Return only a compact valid icon script."
                AIDebugTraceStore.shared.append("ICON GENERATION RETRY", "Attempt \(attempt + 1) failed: \(error.localizedDescription)")
            }
        }

        if !candidate.isEmpty, let rendered = await AIIconRenderer.render(script: candidate) {
            iconScript = candidate
            renderedIconData = rendered
            AIDebugTraceStore.shared.append("ICON RENDER", "Rendered locally after the final repair attempt.")
            return
        }

        let fallback = AIHTMLAgent.fallbackIconScript(html: streamedHTML, originalPrompt: originalPrompt)
        if let rendered = await AIIconRenderer.render(script: fallback) {
            iconScript = fallback
            renderedIconData = rendered
            AIDebugTraceStore.shared.append("ICON FALLBACK", "The provider could not produce a usable icon, so HTMLApp created a local purpose-aware fallback instead of blocking the app.")
            return
        }

        if let lastError { throw lastError }
        throw AIGenerationError.missingIcon
    }

    private func verifyAndRepair(config: AIProviderConfiguration) async throws {
        verificationReport = ""
        do {
            var changedOnPreviousPass = false

            for pass in 1...2 {
                try Task.checkCancellation()
                phase = pass == 1 ? "Reviewing source (not running device tests)" : "Rechecking repaired app"
                let localIssues = HTMLQualityChecks.issues(in: streamedHTML)
                let response = try await AIHTMLAgent.reviewArtifact(
                    html: streamedHTML,
                    iconScript: iconScript,
                    originalPrompt: originalPrompt,
                    research: lastResearch,
                    localIssues: localIssues,
                    pass: pass,
                    config: AISettingsStore.configuration(for: .verifier)
                )

                let summary = AIHTMLAgent.verification(from: response)
                if !summary.isEmpty {
                    verificationReport += verificationReport.isEmpty
                        ? "Pass \(pass): \(summary)"
                        : "\nPass \(pass): \(summary)"
                }

                var changedThisPass = false
                let patch = AIHTMLAgent.patch(from: response)
                if !patch.trimmed.isEmpty {
                    let beforeRepair = streamedHTML
                    let verifierOutput = AIHTMLAgent.parse(response)
                    _ = try await applyEditOutputWithRecovery(
                        verifierOutput,
                        requestedChange: "Repair only the concrete verifier findings from pass \(pass): \(summary)",
                        config: AISettingsStore.configuration(for: .verifier)
                    )
                    if streamedHTML != beforeRepair {
                        changedThisPass = true
                        verificationReport += "\nPass \(pass) repaired the HTML."
                    }
                }

                let correctedIcon = AIHTMLAgent.iconScript(from: response).trimmingCharacters(in: .whitespacesAndNewlines)
                if !correctedIcon.isEmpty, correctedIcon != iconScript {
                    iconScript = correctedIcon
                    renderedIconData = nil
                    try await ensureValidIcon(config: config)
                    changedThisPass = true
                    verificationReport += "\nPass \(pass) repaired the icon."
                }

                changedOnPreviousPass = changedThisPass
                if !changedThisPass { break }
            }

            let remainingLocalIssues = HTMLQualityChecks.issues(in: streamedHTML)
            if remainingLocalIssues.isEmpty {
                verificationReport += verificationReport.isEmpty
                    ? "Local structural checks passed."
                    : "\nLocal structural checks passed."
            } else {
                verificationReport += "\nRemaining local checks: " + remainingLocalIssues.joined(separator: " ")
            }

            if changedOnPreviousPass {
                AIDebugTraceStore.shared.append("VERIFIER", "The second verifier pass made a repair; local structural checks were run again afterward.")
            }
        } catch {
            let localIssues = HTMLQualityChecks.issues(in: streamedHTML)
            verificationReport = localIssues.isEmpty
                ? "Independent verifier was unavailable or timed out. Local structural checks passed."
                : "Independent verifier was unavailable or timed out. Local checks: " + localIssues.joined(separator: " ")
            AIDebugTraceStore.shared.append("VERIFIER FALLBACK", error.localizedDescription)
        }
    }

    private func refineGeneratedAssets(_ assets: [AIGeneratedAsset]) async -> [AIGeneratedAsset] {
        guard !assets.isEmpty else { return [] }
        phase = "Refining generated artwork"
        do {
            let refined = try await AIHTMLAgent.refineAssetScripts(
                html: streamedHTML,
                originalPrompt: originalPrompt,
                drafts: assets,
                config: AISettingsStore.configuration(for: .icon)
            )
            return refined.isEmpty ? assets : refined
        } catch {
            AIDebugTraceStore.shared.append("ASSET ARTIST", "The dedicated asset-art pass failed; using the coding-agent artwork drafts. \(error.localizedDescription)")
            return assets
        }
    }

    private func installGeneratedAssets(_ assets: [AIGeneratedAsset]) async {
        guard !assets.isEmpty else { return }
        var installed = 0
        var html = streamedHTML

        for asset in assets.prefix(6) {
            let cleanName = AIHTMLAgent.safeAssetName(asset.name)
            guard !cleanName.isEmpty,
                  let png = await AIIconRenderer.render(script: asset.script) else {
                AIDebugTraceStore.shared.append("ASSET RENDER", "Skipped an asset because its name or IconScript was invalid.")
                continue
            }
            let token = "{{HTMLAPP_ASSET:\(cleanName)}}"
            guard html.contains(token) else {
                AIDebugTraceStore.shared.append("ASSET RENDER", "Rendered \(cleanName), but no matching token was present in the generated HTML.")
                continue
            }
            let dataURL = "data:image/png;base64," + png.base64EncodedString()
            html = html.replacingOccurrences(of: token, with: dataURL)
            installed += 1
        }

        streamedHTML = html
        if installed > 0 {
            AIDebugTraceStore.shared.append("GENERATED ASSETS", "Rendered and embedded \(installed) portable PNG asset(s) directly into the HTMLApp.")
        }
    }

    private func apply(_ output: AIGenerationOutput, partial: Bool) {
        if !output.html.isEmpty { streamedHTML = partial ? HTMLStreamRepair.previewDocument(output.html) : output.html }
        if !output.description.isEmpty { description = output.description }
        if !output.iconScript.isEmpty { iconScript = output.iconScript }
        if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }
    }
}

actor AIRequestGate {
    static let shared = AIRequestGate()
    private var nextAllowedAt = Date.distantPast

    func waitIfNeeded() async {
        let minimum = AISettingsStore.requestDelaySeconds
        let now = Date()
        guard minimum > 0 else {
            nextAllowedAt = now
            return
        }

        // Reserve this caller's slot before sleeping. Actor methods are re-entrant
        // across awaits, so updating after sleep lets concurrent callers pass together.
        let allowedAt = max(now, nextAllowedAt)
        nextAllowedAt = allowedAt.addingTimeInterval(minimum)
        let remaining = allowedAt.timeIntervalSince(now)
        if remaining > 0 {
            let nanoseconds = UInt64((remaining * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }
}

actor AIStreamActivity {
    private var lastContentAt = Date()
    private var finished = false

    func markContent() {
        lastContentAt = Date()
    }

    func markFinished() {
        finished = true
    }

    func shouldTimeout(after seconds: TimeInterval) -> Bool {
        !finished && Date().timeIntervalSince(lastContentAt) >= seconds
    }
}

enum AIProviderClient {
    static func complete(
        config: AIProviderConfiguration,
        system: String,
        messages: [(String, String)],
        timeout: TimeInterval = 300,
        maxTokens: Int? = nil,
        retryOnTransient: Bool = true
    ) async throws -> String {
        guard let endpoint = config.endpointURL() else { throw AIGenerationError.invalidEndpoint }
        await logRequest(kind: "COMPLETE", config: config, endpoint: endpoint, system: system, messages: messages)

        var lastError: Error?
        var tokenParameterOverride: String?
        let maximumAttempts = retryOnTransient ? 3 : 1
        for attempt in 1...maximumAttempts {
            await AIRequestGate.shared.waitIfNeeded()
            do {
                var request = makeRequest(config: config, endpoint: endpoint, timeout: timeout)
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: requestBody(
                        config: config,
                        system: system,
                        messages: messages,
                        stream: false,
                        maxTokens: maxTokens,
                        tokenParameterOverride: tokenParameterOverride
                    )
                )
                let (data, response) = try await URLSession.shared.data(for: request)
                try validate(response, data: data)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw AIGenerationError.provider("The AI provider returned invalid JSON.")
                }

                let text = responseText(object, type: config.compatibility)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    let shape = responseShape(object)
                    throw AIGenerationError.provider("The AI provider returned a successful response without usable text (\(shape)).")
                }
                await MainActor.run { AIDebugTraceStore.shared.append("AI RESPONSE", text) }
                return text
            } catch {
                lastError = error

                if config.compatibility == .openAI,
                   maxTokens != nil,
                   tokenParameterOverride == nil,
                   let providerError = error as? AIProviderRequestError,
                   providerError.statusCode == 400,
                   shouldRetryWithMaxCompletionTokens(providerError.message) {
                    tokenParameterOverride = "max_completion_tokens"
                    await MainActor.run {
                        AIDebugTraceStore.shared.append(
                            "AI REQUEST PARAMETER FALLBACK",
                            "Provider rejected max_tokens; retrying with max_completion_tokens."
                        )
                    }
                    continue
                }

                let retry = retryInfo(for: error)
                let willRetry = attempt < maximumAttempts && retry.retryable
                let delay = willRetry ? retryDelay(forAttempt: attempt, retryAfter: retry.retryAfter) : 0
                await MainActor.run {
                    AIDebugTraceStore.shared.append(
                        willRetry ? "AI REQUEST RETRY" : "AI REQUEST ERROR",
                        willRetry
                            ? "Attempt \(attempt) of \(maximumAttempts) failed: \(error.localizedDescription)\nRetrying in \(String(format: "%.1f", delay)) seconds."
                            : error.localizedDescription
                    )
                }
                if willRetry {
                    try Task.checkCancellation()
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        throw lastError ?? AIGenerationError.provider("The AI request failed.")
    }

    static func stream(config: AIProviderConfiguration, system: String, messages: [(String, String)], maxTokens: Int? = nil) async throws -> AsyncThrowingStream<String, Error> {
        await AIRequestGate.shared.waitIfNeeded()
        guard let endpoint = config.endpointURL() else { throw AIGenerationError.invalidEndpoint }
        await logRequest(kind: "STREAM", config: config, endpoint: endpoint, system: system, messages: messages)
        var request = makeRequest(config: config, endpoint: endpoint, timeout: 300)
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(config: config, system: system, messages: messages, stream: true, maxTokens: maxTokens))
        return AsyncThrowingStream { continuation in
            let activity = AIStreamActivity()

            let worker = Task {
                var rawResponse = ""
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIProviderRequestError(statusCode: nil, message: "The AI provider returned an invalid HTTP response.", retryable: true, retryAfter: nil)
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line + "\n"
                            if detail.utf8.count >= 1500 { break }
                        }
                        let trimmed = String(detail.prefix(1500)).trimmingCharacters(in: .whitespacesAndNewlines)
                        throw providerHTTPError(http, detail: trimmed)
                    }

                    var wasTruncated = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        await activity.markContent()
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let streamError = streamError(from: object, type: config.compatibility) {
                            throw streamError
                        }
                        if streamWasTruncated(object, type: config.compatibility) {
                            wasTruncated = true
                        }
                        if let text = streamedText(object, type: config.compatibility), !text.isEmpty {
                            await activity.markContent()
                            rawResponse += text
                            continuation.yield(text)
                        }
                    }
                    guard !rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AIProviderRequestError(statusCode: nil, message: "The AI stream completed without text.", retryable: true, retryAfter: nil)
                    }
                    if wasTruncated {
                        throw AIProviderRequestError(statusCode: nil, message: "The AI stream reached the provider output-token limit.", retryable: false, retryAfter: nil)
                    }
                    await activity.markFinished()
                    let completedResponse = rawResponse
                    await MainActor.run { AIDebugTraceStore.shared.append("AI STREAM RESPONSE", completedResponse) }
                    continuation.finish()
                } catch {
                    await activity.markFinished()
                    let partialResponse = rawResponse
                    let errorText = error.localizedDescription
                    await MainActor.run {
                        AIDebugTraceStore.shared.append("AI STREAM ERROR", errorText + "\nPartial response:\n" + partialResponse)
                    }
                    continuation.finish(throwing: error)
                }
            }

            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if Task.isCancelled { break }
                    if await activity.shouldTimeout(after: 120) {
                        continuation.finish(throwing: AIGenerationError.provider("AI streaming stalled for 120 seconds. Continuing from any partial output."))
                        worker.cancel()
                        break
                    }
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                watchdog.cancel()
            }
        }
    }

    private static func makeRequest(config: AIProviderConfiguration, endpoint: URL, timeout: TimeInterval = 180) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch config.compatibility {
        case .openAI:
            if !config.apiKey.isEmpty { request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            if !config.apiKey.isEmpty { request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        return request
    }

    private static func logRequest(
        kind: String,
        config: AIProviderConfiguration,
        endpoint: URL,
        system: String,
        messages: [(String, String)]
    ) async {
        var value = "Type: \(kind)\nAPI URL: \(config.apiURL)\nEndpoint: \(endpoint.absoluteString)\nModel: \(config.model)\nCompatibility: \(config.compatibility.rawValue)\n\n[SYSTEM]\n\(system)"
        for (role, content) in messages {
            value += "\n\n[\(role.uppercased())]\n\(content)"
        }
        let requestTrace = value
        await MainActor.run { AIDebugTraceStore.shared.append("AI REQUEST", requestTrace) }
    }

    private static func requestBody(
        config: AIProviderConfiguration,
        system: String,
        messages: [(String, String)],
        stream: Bool,
        maxTokens: Int?,
        tokenParameterOverride: String? = nil
    ) -> [String: Any] {
        switch config.compatibility {
        case .openAI:
            var list: [[String: String]] = [["role": "system", "content": system]]
            list.append(contentsOf: messages.map { ["role": $0.0, "content": $0.1] })
            var body: [String: Any] = ["model": config.model, "messages": list, "stream": stream]
            if let maxTokens {
                body[tokenParameterOverride ?? "max_tokens"] = max(64, maxTokens)
            }
            return body
        case .anthropic:
            let list: [[String: String]] = messages.map { ["role": $0.0 == "assistant" ? "assistant" : "user", "content": $0.1] }
            return [
                "model": config.model,
                "max_tokens": maxTokens.map { max(64, $0) } ?? 32000,
                "system": system,
                "messages": list,
                "stream": stream
            ]
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let detail = String(decoding: data.prefix(1500), as: UTF8.self)
        throw providerHTTPError(http, detail: detail)
    }

    private static func providerHTTPError(_ http: HTTPURLResponse, detail: String) -> AIProviderRequestError {
        let status = http.statusCode
        let retryable = [408, 409, 425, 429].contains(status) || (500...599).contains(status)
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
        let suffix = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = suffix.isEmpty ? "AI provider error \(status)." : "AI provider error \(status): \(suffix)"
        return AIProviderRequestError(statusCode: status, message: message, retryable: retryable, retryAfter: retryAfter)
    }

    private static func responseText(_ object: [String: Any], type: AIProviderConfiguration.Compatibility) -> String {
        switch type {
        case .openAI:
            if let choices = object["choices"] as? [[String: Any]], let first = choices.first {
                if let message = first["message"] as? [String: Any] {
                    let text = textContent(message["content"])
                    if !text.isEmpty { return text }
                }
                if let text = first["text"] as? String, !text.isEmpty { return text }
            }
            if let text = object["output_text"] as? String, !text.isEmpty { return text }
            if let output = object["output"] as? [[String: Any]] {
                let text = output.compactMap { item -> String? in
                    if let content = item["content"] { return textContent(content) }
                    if let text = item["text"] as? String { return text }
                    return nil
                }.joined()
                if !text.isEmpty { return text }
            }
            return ""
        case .anthropic:
            if let blocks = object["content"] as? [[String: Any]] {
                return blocks.compactMap { $0["text"] as? String }.joined()
            }
            return ""
        }
    }

    private static func textContent(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let blocks = value as? [[String: Any]] {
            return blocks.compactMap { block in
                if let text = block["text"] as? String { return text }
                if let text = block["content"] as? String { return text }
                return nil
            }.joined()
        }
        if let block = value as? [String: Any] {
            return (block["text"] as? String) ?? (block["content"] as? String) ?? ""
        }
        return ""
    }

    private static func streamedText(_ object: [String: Any], type: AIProviderConfiguration.Compatibility) -> String? {
        switch type {
        case .openAI:
            guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return nil }
            if let delta = first["delta"] as? [String: Any] {
                let text = textContent(delta["content"])
                if !text.isEmpty { return text }
            }
            if let text = first["text"] as? String, !text.isEmpty { return text }
            return nil
        case .anthropic:
            guard object["type"] as? String == "content_block_delta", let delta = object["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
    }

    private static func responseShape(_ object: [String: Any]) -> String {
        let topKeys = object.keys.sorted().prefix(8).joined(separator: ",")
        if let choices = object["choices"] as? [[String: Any]], let first = choices.first {
            let choiceKeys = first.keys.sorted().prefix(8).joined(separator: ",")
            if let message = first["message"] as? [String: Any] {
                let messageKeys = message.keys.sorted().prefix(8).joined(separator: ",")
                return "keys=[\(topKeys)] choice=[\(choiceKeys)] message=[\(messageKeys)]"
            }
            return "keys=[\(topKeys)] choice=[\(choiceKeys)]"
        }
        return "keys=[\(topKeys)]"
    }

    private static func streamError(from object: [String: Any], type: AIProviderConfiguration.Compatibility) -> AIProviderRequestError? {
        if type == .anthropic, object["type"] as? String == "error",
           let error = object["error"] as? [String: Any] {
            let kind = (error["type"] as? String) ?? "provider_error"
            let message = (error["message"] as? String) ?? "Anthropic returned a streaming error."
            let retryable = kind == "overloaded_error" || kind == "rate_limit_error" || kind == "api_error"
            return AIProviderRequestError(statusCode: nil, message: "AI provider stream error (\(kind)): \(message)", retryable: retryable, retryAfter: nil)
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "The AI provider returned a streaming error."
            return AIProviderRequestError(statusCode: nil, message: "AI provider stream error: \(message)", retryable: false, retryAfter: nil)
        }
        return nil
    }

    private static func streamWasTruncated(_ object: [String: Any], type: AIProviderConfiguration.Compatibility) -> Bool {
        switch type {
        case .openAI:
            guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else { return false }
            let reason = (first["finish_reason"] as? String)?.lowercased()
            return reason == "length" || reason == "max_tokens"
        case .anthropic:
            guard object["type"] as? String == "message_delta",
                  let delta = object["delta"] as? [String: Any],
                  let reason = (delta["stop_reason"] as? String)?.lowercased() else { return false }
            return reason == "max_tokens" || reason == "length"
        }
    }

    private static func shouldRetryWithMaxCompletionTokens(_ message: String) -> Bool {
        let lower = message.lowercased()
        guard lower.contains("max_tokens") else { return false }
        return lower.contains("max_completion_tokens")
            || lower.contains("unsupported")
            || lower.contains("not supported")
            || lower.contains("invalid parameter")
            || lower.contains("unknown parameter")
    }

    private static func retryInfo(for error: Error) -> (retryable: Bool, retryAfter: TimeInterval?) {
        if error is CancellationError { return (false, nil) }
        if let providerError = error as? AIProviderRequestError {
            return (providerError.retryable, providerError.retryAfter)
        }
        if let urlError = error as? URLError {
            let retryable = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet].contains(urlError.code)
            return (retryable, nil)
        }
        let message = error.localizedDescription.lowercased()
        return (
            message.contains("without usable text") || message.contains("did not contain text") || message.contains("invalid json"),
            nil
        )
    }

    private static func retryDelay(forAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 { return min(retryAfter, 60) }
        let base = min(1.2 * pow(2.0, Double(max(0, attempt - 1))), 12.0)
        return base + Double.random(in: 0...(base * 0.25))
    }
}

enum AIHTMLAgent {
    static let designGuide = ForgeProductContract.rules + "\n\n" + """
Build one complete, self-contained standards-compliant HTML file with semantic HTML, all CSS in <style>, all JavaScript in <script>, inline SVG icons, and no build step. Unless the user explicitly requests a demo/mockup/snippet, treat the result as a full application: complete core workflows, real persistent state, appropriate create/edit/delete/search/import/export behavior, useful settings/help when warranted, honest lifecycle behavior, meaningful loading/empty/error/offline/permission states, and no dead controls. It must behave like a real mobile product with clear hierarchy, native-feeling navigation, useful pressed states, sheets/overlays where appropriate, smooth state transitions, 44px minimum touch targets, excellent phone/iPad resizing, polished light/dark appearance, accessible forms, and release-quality cleanup. Respect prefers-reduced-motion, prefers-contrast, and prefers-reduced-transparency.

SAFE AREA IS NON-NEGOTIABLE: use <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"> and reusable env(safe-area-inset-top/right/bottom/left) CSS variables. HTMLApp is edge-to-edge, so the root/top chrome must own the top inset exactly once and interactive content must never sit behind the notch/Dynamic Island/status bar. Bottom bars must own the Home Indicator inset, and landscape must respect left/right cutouts. Full-bleed backgrounds may extend under cutouts; content and controls may not.

Use the HTMLApp runtime rather than assuming ordinary Safari limitations:
- Camera/mic: navigator.mediaDevices.getUserMedia; stop tracks when finished; MediaRecorder/Web Audio when available.
- Location: navigator.geolocation.getCurrentPosition and watchPosition are natively bridged; clear watches.
- Motion/orientation: request DeviceMotionEvent/DeviceOrientationEvent permission from a user gesture when required. Compass can also use window.htmlappCompassHeading and the htmlappcompass event.
- Haptics: navigator.vibrate is bridged to native iOS feedback; keep it brief and user-initiated.
- Notifications: Notification.requestPermission and immediate new Notification(...) are bridged to native iOS local notifications. Do not promise remote push or use notifications as a fake background engine.
- Downloads/export: normal downloads plus Blob/data/object-URL downloads are handled by HTMLApp and open the iOS share sheet after retrieval. Use meaningful MIME types and filenames.
- Files/photos: use <input type=file> for user-selected files/photos/videos; read with File/Blob/FileReader/arrayBuffer/object URLs; do not claim unrestricted Photo Library access.
- Storage: prefer HTMLAppNative.appStorage for important non-secret generated-app data that should travel with HTMLApp backups/shares. localStorage is fine for disposable compatibility/preferences; IndexedDB is for larger structured/blob data and should have an explicit export path if valuable. Use secureStorage only for secrets/tokens.
- Widgets: HTMLAppNative.widgets.configure/list/remove/reload can publish real Home Screen/Lock Screen WidgetKit widgets. Use widgets when glanceable status, quick metrics, reminders, progress, lists, or current public data materially improve the product. Widgets can bind fields to public HTTPS JSON and deep-link back into the HTMLApp.
- Background refresh: HTMLAppNative.background.configure/list/remove/refreshNow can register opportunistic iOS BGAppRefresh public-HTTPS JSON fetches that store results in appStorage. iOS chooses actual timing; minimum requested interval is 15 minutes. This does not run arbitrary JavaScript after suspension.
- Networking: fetch/WebSocket/EventSource are allowed subject to CORS, server support, and normal security constraints.
- iOS handoffs: documented HTMLAppNative.externalApps.maps and externalApps.shortcuts can open Apple Maps or run a user-installed Shortcut from deliberate user actions. Do not invent other structured adapters.
- Sharing/media/credentials: feature-detect navigator.share/canShare, Media Session, navigator.credentials/WebAuthn, Clipboard, and other optional APIs.

When research contains HTMLAPP DEVICE API CATALOG RESULTS, treat those results as the authoritative runtime reference. Prefer documented HTMLAppNative wrappers for contacts, user-selected Photos media, Calendar, Reminders, local notifications, biometrics, secure storage, portable app storage, generated widgets, opportunistic background JSON refresh, Maps/Shortcuts handoffs, speech, Files, sharing, clipboard, device info, and keep-awake behavior when they match the task. Follow the exact method names and constraints from the catalog; never invent adjacent methods.

Never invent native bridges. HealthKit, HomeKit, NFC, Nearby Interaction, background location, arbitrary continuously running HTML/JavaScript beyond the documented background-fetch/widget mechanisms, remote push, Live Activities/Dynamic Island activities, CallKit/CarPlay, Apple Pay merchant flows, unrestricted hidden Photo Library enumeration/deletion, and other entitlement-gated frameworks are unavailable to generated HTMLApps unless the device catalog explicitly documents a bridge. If a requested capability is unavailable, build the best honest fallback and expose the limitation rather than simulating success.

Other browser APIs such as Bluetooth, USB, Serial, HID, WebGPU, WebXR, Wake Lock, Service Workers, App Badging, Network Information, Battery, keyboard APIs, Audio Session, and similar capabilities are feature-detect-only. Presence of an object is not proof the requested operation will succeed; handle rejection and unsupported states.

Never invent facts, live values, people, accounts, reviews, measurements, availability, prices, API responses, endpoints, or capabilities unless the user explicitly requested fictional/demo/sample content, and label demo data visibly. If real data is needed, use researched documented APIs. Verify endpoint URL, parameters, fields, auth, CORS, and client-side feasibility. If no real source/capability exists, build the best honest local/user-mediated alternative.

Permission-requiring APIs activate only after a meaningful user gesture. Request the minimum access needed. Never embed private API keys or secrets. If user/device data is sent to a remote service, do not claim it stays on-device.

Design from the product rather than a template. Use restrained iOS-quality materials, purposeful typography, strong hierarchy, content-specific identity, and motion that communicates state. Avoid generic SaaS dashboards, excessive glass/glow/gradients, emoji-as-icons, browser alert/confirm for routine feedback, fake avatars/badges, and desktop-first layouts.

Engineering quality is mandatory: loading/empty/error/offline/permission/unsupported states when relevant; guarded async code; AbortController for racing fetches; safe DOM insertion; cleanup of media tracks, object URLs, listeners, timers, workers, sockets and animation loops; keyboard/focus accessibility; no undefined handlers, placeholder endpoints, fake keys, TODOs, or pseudocode.
"""

    static let iconGuide = """
Inside <icon_script>, output only a static drawing script. Commands: SIZE width height; BG color; RECT x y width height color; CIRCLE center_x center_y radius color; LINE x1 y1 x2 y2 thickness color; TRIANGLE x1 y1 x2 y2 x3 y3 color; optional FILL_LINEAR, FILL_RADIAL, FILL_TEXTURE immediately before a shape. Use absolute coordinates and CSS/HEX colors, draw back-to-front, and never use ANIM, GROUP or FPS.
"""

    private static let webResearchSignals = [
        "api", "website", "web site", "url", "current", "live", "latest", "weather",
        "news", "stock", "crypto", "price", "restaurant", "menu", "nearby", "places",
        "flight", "sports", "score", "search the web", "internet", "online", "remote",
        "oauth", "server", "fetch", "public data", "real-time", "realtime",
        "specification", "specifications", "specs", "manual", "handbook", "manufacturer",
        "product model", "e-bike", "ebike", "business hours", "reviews", "official site"
    ]

    private static let deviceCapabilitySignals = [
        "camera", "microphone", "mic", "photo", "video", "contact", "calendar", "reminder",
        "notification", "face id", "touch id", "biometric", "clipboard", "file", "download",
        "share", "speech", "text to speech", "location", "gps", "map", "motion", "orientation",
        "compass", "sensor", "battery", "haptic", "vibrate", "keychain", "secure storage",
        "passkey", "widget", "widgets", "widgetkit", "home screen widget", "lock screen widget", "background", "background refresh", "dynamic island", "live activity", "healthkit", "homekit",
        "nfc", "bluetooth", "carplay", "callkit", "apple pay"
    ]

    static func canSkipPreflight(for prompt: String) -> Bool {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, clean.count <= 180,
              !needsCapabilityResearch(for: clean),
              !needsWebResearch(for: clean) else { return false }
        let selfContainedSignals = [
            "calculator", "counter", "timer", "stopwatch", "converter", "checklist",
            "notepad", "notes app", "flashcards", "pomodoro", "random picker", "dice roller"
        ]
        return selfContainedSignals.contains(where: { containsSignal($0, in: clean) })
    }

    static func planPrompt(_ prompt: String, config: AIProviderConfiguration) async throws -> AIPlanningResult {
        let system = """
You are HTMLApp Forge's combined product-planning and capability-research planner. Turn the user's raw app idea into a compact implementation-ready brief AND decide what device/public API research is actually required.

(ForgeProductContract.rules)

Return exactly one <brief>...</brief>, followed by zero or more:
<device_query>concise capability query</device_query>
<query>concise public/web API discovery query</query>

BRIEF REQUIREMENTS:
- Preserve the user's actual intent and define the smallest complete useful product.
- Cover outcome, core loop, must features, 0-3 strongly implied adjacent conveniences, structure, data model/persistence, capabilities, widgets/background only when useful, onboarding only when needed, real states, phone/iPad/accessibility experience, completeness, and observable acceptance criteria.
- Never add accounts, subscriptions, social features, analytics, tracking, or fabricated backend infrastructure by default.

RESEARCH RULES:
- Use <device_query> for iPhone/iPad hardware, sensors, camera/microphone, files, downloads, sharing, contacts, photos, calendar, reminders, notifications, biometrics, secure storage, speech, authentication, widgets, WidgetKit, background refresh, or other HTMLApp-native capabilities.
- Use <query> only for real-world/live/current remote data or external services that cannot be satisfied locally.
- Prefer documented no-auth APIs and browser-safe free tiers. Never invent a native bridge.
- If no research is needed, return no query tags.
- At most six device queries and six public queries.

Resolve ambiguity with ordinary reversible defaults. Do not expose hidden reasoning.
"""
        do {
            let text = try await AIProviderClient.complete(
                config: config,
                system: system,
                messages: [("user", prompt)],
                timeout: 100,
                maxTokens: 7000,
                retryOnTransient: true
            )
            let brief = value("brief", in: text).trimmed
            return AIPlanningResult(
                brief: brief.isEmpty ? prompt : brief,
                research: AIResearchPlan(
                    publicQueries: plannedValues("query", in: text),
                    deviceQueries: plannedValues("device_query", in: text)
                )
            )
        } catch {
            await MainActor.run {
                AIDebugTraceStore.shared.append(
                    "PLANNER FALLBACK",
                    "Combined planning was unavailable; continuing with the original request and no new research instead of stopping. \(error.localizedDescription)"
                )
            }
            return AIPlanningResult(brief: prompt, research: AIResearchPlan())
        }
    }

    static func needsWebResearch(for prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return webResearchSignals.contains(where: { containsSignal($0, in: lower) })
    }

    static func needsCapabilityResearch(for prompt: String) -> Bool {
        let lower = prompt.lowercased()
        return needsWebResearch(for: prompt)
            || deviceCapabilitySignals.contains(where: { containsSignal($0, in: lower) })
    }

    private static func containsSignal(_ signal: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: signal.lowercased())
        let pattern = #"(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    static func refinePrompt(_ prompt: String, config: AIProviderConfiguration) async throws -> String {
        let system = """
You are HTMLApp Forge's product-specification agent. Convert the user's raw app idea into a compact but implementation-ready product brief for another coding agent.
\(ForgeProductContract.rules)

Preserve the user's actual intent, then think one step ahead: infer what the user is likely to ask for immediately after trying the first version. Add a small number of high-value adjacent features when they clearly advance the same goal. Do not inflate the scope with generic startup features, dashboards, accounts, analytics, or decorative complexity. Never invent live data sources, native capabilities, APIs, or backend infrastructure.

Examples of good anticipation:
- "Make a handbook for my e-bike" -> researched specifications for the exact model when identifiable, maintenance schedule, searchable troubleshooting, useful conversions, range/battery helpers, notes/bookmarks, and quick-reference safety info.
- "Let me view a restaurant menu" -> nearby restaurant discovery when location/map data can be implemented honestly, recent/favorite places, map/list switching, and a fast place -> menu flow.
Bad anticipation is adding unrelated social feeds, profiles, subscriptions, gamification, or remote infrastructure merely because many apps have them.

The brief must explicitly cover:
- OUTCOME: what success means for the user
- CORE LOOP: entry -> primary action -> result -> repeat
- MUST FEATURES: behavior that cannot be omitted
- ANTICIPATED VALUE: 0-3 adjacent features the user would probably ask for next, with a one-line reason for each
- STRUCTURE: screens/navigation/sheets/overlays only where useful
- DATA MODEL: important entities, state, persistence, import/export, and source of truth
- CAPABILITIES: browser/native/network needs that require verification
- WIDGETS & BACKGROUND: whether glanceable WidgetKit content or opportunistic background JSON refresh would materially help; if yes, define what information, source, refresh behavior, and deep-link destination are useful. Do not force these into products that do not benefit.
- ONBOARDING: whether first-run setup is genuinely useful; if so, exactly what must be chosen/explained and how completion persists
- STATES: loading/empty/error/offline/permission/unsupported/invalid/destructive states that genuinely apply
- EXPERIENCE: phone-first interaction, mandatory notch/Dynamic-Island/Home-Indicator safe-area ownership, iPad behavior, accessibility, visual direction, and meaningful motion
- COMPLETENESS: what makes this a full usable application rather than a prototype—data management, persistence, settings/help, import/export, recovery, and repeated-use behavior where relevant
- ACCEPTANCE: observable conditions the finished app must satisfy

Prefer the smallest complete product that already feels like a thoughtful first public release, not a mockup or shallow prototype. Resolve ambiguity in favor of ordinary user expectations and reversible choices. Return only <brief>...</brief>.
"""
        do {
            let text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", prompt)], timeout: 90, maxTokens: 6000, retryOnTransient: true)
            return value("brief", in: text).trimmed.isEmpty ? prompt : value("brief", in: text).trimmed
        } catch {
            await MainActor.run {
                AIDebugTraceStore.shared.append("PLANNER FALLBACK", "Prompt refinement was unavailable; continuing with the original request. \(error.localizedDescription)")
            }
            return prompt
        }
    }

    static func refineRevision(_ change: String, appBrief: String, config: AIProviderConfiguration) async throws -> String {
        let system = """
You are HTMLApp Forge's change-planning agent. Turn the requested edit into a precise implementation brief for an existing working app.

Preserve every behavior, storage key, API integration, navigation path, visual convention, and user-created-data assumption that the user did not ask to change. Identify the smallest coherent change surface, any state/data migration implications, edge cases, and acceptance criteria. Resolve ambiguity conservatively and prefer reversible edits. Never invent facts, APIs, capabilities, or live data.

Return only <brief>...</brief>.
"""
        do {
            let text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", "Current brief: \(appBrief)\nRequested change: \(change)")], timeout: 90, maxTokens: 6000, retryOnTransient: true)
            return value("brief", in: text).trimmed.isEmpty ? change : value("brief", in: text).trimmed
        } catch {
            await MainActor.run {
                AIDebugTraceStore.shared.append("CHANGE PLANNER FALLBACK", "Change planning was unavailable; applying the user's requested edit directly. \(error.localizedDescription)")
            }
            return change
        }
    }

    private static func plannedValues(_ tag: String, in text: String) -> [String] {
        let complete = values(tag, in: text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !complete.isEmpty { return Array(complete.prefix(6)) }
        let partialValue = partial(tag, in: text)
            .replacingOccurrences(of: "</", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return partialValue.isEmpty ? [] : [partialValue]
    }

    static func planResearch(original: String, revision: String?, config: AIProviderConfiguration) async throws -> AIResearchPlan {
        let system = """
Plan capability research for an HTMLApp. Return only zero or more tags in these two forms:
<device_query>concise capability query</device_query>
<query>concise public/web API discovery query</query>

Use <device_query> whenever the requested app or revision touches iPhone/iPad hardware, sensors, camera/microphone, files, downloads/exports, sharing, contacts, photos, calendar, reminders, notifications, biometrics, secure storage, speech, authentication, widgets, WidgetKit, background refresh/system integration, or another capability that might be provided by HTMLApp itself. The internal device catalog returns exact supported methods, usage examples, and limitations.

Use <query> only when the app needs real-world/live/current remote data or a remote service that cannot be satisfied locally. Prefer documented no-auth APIs, then documented browser-safe free tiers.

It is valid to return both kinds. If neither device capabilities nor external services are needed, return no tags. If unsure whether HTMLApp provides a device capability, emit a <device_query> instead of guessing. Never invent a native bridge. Never search age-restricted, dangerous, gambling, weapon, intoxicant, explicit, or malware-acquisition categories. Return at most six of each tag.
"""
        let user = revision.map { "App: \(original)\nRevision: \($0)" } ?? original
        let text: String
        do {
            text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)], timeout: 75, maxTokens: 3000, retryOnTransient: true)
        } catch {
            await MainActor.run {
                AIDebugTraceStore.shared.append("RESEARCH PLANNER FALLBACK", "Capability research planning was unavailable; continuing without new research instead of stopping generation. \(error.localizedDescription)")
            }
            return AIResearchPlan()
        }

        return AIResearchPlan(
            publicQueries: plannedValues("query", in: text),
            deviceQueries: plannedValues("device_query", in: text)
        )
    }

    static func systemPrompt(research: String) -> String {
        let base = AISettingsStore.resolvedSystemPrompt(research: research)
        let contract = base.contains("FORGE PRODUCT CONTRACT") ? "" : "\n\n" + ForgeProductContract.rules
        return base + contract + """

HTMLAPP FACT-CHECK OVERRIDES:
- Treat supplied research as evidence, not permission to extrapolate. Use only API endpoints, parameters, response fields, authentication behavior, and browser capabilities actually supported by that evidence or the documented HTMLApp/browser runtime.
- Never invent a reverse-geocoding mode, endpoint variant, search parameter, response field, or window.htmlapp* native bridge because a related capability exists elsewhere.
- Do not assume that "iOS can do this" means a generated HTMLApp can do it. Entitlement-gated/native-framework features require an explicit HTMLApp bridge; otherwise use a truthful user-mediated/web fallback.
- If device coordinates, photos, contacts, files, recordings, or other user data are sent to a remote API, do not claim that information stays only on the device.
- Prefer a slightly simpler app with verified behavior over a richer app built on guessed network or native behavior.
"""
    }

    static func patchSystemPrompt(research: String) -> String {
        """
You are HTMLApp's code-editing agent. Edit the existing single-file HTML app with the smallest safe patch that satisfies the requested change. Preserve all unrelated behavior, IDs, storage keys, API integrations, permissions, navigation and working code. Prefer patching over rewriting.

Return these sections with no Markdown fences:
<build_summary>short updated implementation plan; conclusions only, not hidden reasoning</build_summary>
<description>updated one-sentence description if materially changed, otherwise repeat the current purpose</description>
<icon_script>updated icon script only if the app identity changed; otherwise leave empty</icon_script>
<asset_scripts>optional new portable IconScript assets using ASSET filename / END_ASSET blocks; leave empty unless the edit genuinely needs generated artwork</asset_scripts>
<htmlapp_patch>
<<<<<<< SEARCH
exact text copied from the existing HTML
=======
replacement text
>>>>>>> REPLACE
</htmlapp_patch>

You may include multiple SEARCH/REPLACE blocks. SEARCH text must match exactly and should be as small and unique as practical. If an exact safe patch is genuinely impossible, return a complete <htmlapp_code> document instead.

RULES:
\(designGuide)
Keep or improve native-feeling animation and mobile interactions. Do not fabricate facts, APIs, live data or capabilities. If the revision depends on something uncertain, use the documented research below; if no credible API is available, implement an honest local/limited state rather than fake data.

RESEARCH RESULTS:
\(research.isEmpty ? "No new external API research was needed or no suitable public API was found." : research)
"""
    }

    static func refineAssetScripts(
        html: String,
        originalPrompt: String,
        drafts: [AIGeneratedAsset],
        config: AIProviderConfiguration
    ) async throws -> [AIGeneratedAsset] {
        guard !drafts.isEmpty else { return [] }
        let system = """
You are HTMLApp's specialist portable-asset illustrator. Refine the supplied IconScript asset drafts into clean, useful original artwork for the finished app.

Return only:
<asset_scripts>
ASSET filename.png
SIZE width height
...IconScript...
END_ASSET
</asset_scripts>

RULES:
- Preserve every draft filename exactly because the HTML already references {{HTMLAPP_ASSET:filename}} tokens.
- Return one asset block for every supplied draft, at most six.
- Keep the intended function of each asset, but simplify confusing or overly decorative compositions.
- Artwork should be immediately understandable at its actual UI size, not overloaded like a poster.
- Prefer strong silhouettes, clean geometry, restrained palettes, useful negative space, and only the detail needed for the asset's purpose.
- Generated diagrams/illustrations must be original and must not imitate logos, copyrighted characters, trademarks, or proprietary product artwork.
- Do not add text unless the draft absolutely requires a simple diagram label; in practice IconScript has no text command, so use shapes only.
- Use only SIZE, BG, RECT, CIRCLE, LINE, TRIANGLE, FILL_LINEAR, FILL_RADIAL, and FILL_TEXTURE.
- SIZE may be 64 through 4096 pixels per side.
- No Markdown, prose, comments, SVG, HTML, external URLs, ANIM, GROUP, or FPS.
"""
        let draftText = drafts.map { asset in
            """
            ASSET \(asset.name)
            \(asset.script)
            END_ASSET
            """
        }.joined(separator: "\n\n")
        let user = """
APP REQUEST:
\(originalPrompt)

CURRENT APP EXCERPT:
\(String(html.prefix(12_000)))

ASSET DRAFTS:
\(draftText)
"""
        let response = try await AIProviderClient.complete(
            config: config,
            system: system,
            messages: [("user", user)],
            timeout: 90,
            maxTokens: 7000,
            retryOnTransient: true
        )
        let parsed = parseAssetScripts(value("asset_scripts", in: response))
        guard !parsed.isEmpty else { return drafts }

        let byName = Dictionary(uniqueKeysWithValues: parsed.map { ($0.name, $0) })
        return drafts.map { byName[$0.name] ?? $0 }
    }

    static func generateIconScript(
        html: String,
        originalPrompt: String,
        previousScript: String,
        repairReason: String? = nil,
        config: AIProviderConfiguration
    ) async throws -> String {
        let system = """
You are HTMLApp's specialist iOS app-icon designer. Produce an icon that could plausibly ship beside polished App Store icons: simple, instantly understandable, balanced, and specific to this exact app.

ICON DESIGN PROCESS:
1. Identify the app's single primary job.
2. Choose one concrete visual metaphor that communicates that job without text.
3. Remove secondary ideas until the concept reads at thumbnail size.
4. Build a large, centered silhouette with strong negative space and clean geometry.
5. Add only restrained depth or supporting detail if it strengthens recognition.
6. Mentally downscale to 64px and 32px; if the idea becomes muddy, simplify again.

QUALITY BAR:
- SIZE must be 1024 1024 with an opaque full-canvas BG.
- Aim for one dominant symbol and, at most, one supporting form.
- Prefer about 6-18 visible shape commands. More detail is allowed only when genuinely necessary.
- Use large shapes and intentional spacing. Avoid tiny decorative marks.
- Make the icon understandable in about one second.
- Match the app's palette/personality without drawing a screenshot of the interface.
- Avoid generic AI imagery unless AI itself is the product: no automatic sparkles, magic wands, brains, chat bubbles, rockets, or purple-gradient filler.
- Avoid generic "circle + triangle + dot" constructions unless they directly depict the product.
- No text, letters, numbers, copied third-party logos, emoji, copyrighted characters, SVG, HTML, prose, or comments.
- Keep key artwork away from extreme edges; iOS applies its own icon mask.
- If the previous concept is weak or overcomplicated, replace the concept rather than cosmetically tweaking it.

SUPPORTED COMMANDS ONLY:
SIZE width height
BG color
RECT x y width height color
CIRCLE center_x center_y radius color
LINE x1 y1 x2 y2 thickness color
TRIANGLE x1 y1 x2 y2 x3 y3 color
FILL_LINEAR color1 color2
FILL_RADIAL color1 color2
FILL_TEXTURE color1 color2

A FILL_* command modifies only the immediately following shape. Use absolute coordinates and CSS/HEX colors. Never use ANIM, GROUP, FPS, Markdown fences, SVG, or explanatory text.
"""
        let context = iconDesignBrief(html: html, originalPrompt: originalPrompt)
        let user = """
APP IDENTITY BRIEF:
\(context)

PREVIOUS ICON SCRIPT:
\(previousScript.isEmpty ? "None — create a fresh, purpose-built concept." : previousScript)

REPAIR / QUALITY NOTE:
\(repairReason ?? "None. Produce a polished icon without asking the user for more icon details.")
"""
        await MainActor.run {
            AIDebugTraceStore.shared.append("ICON CONTEXT", context)
        }

        var lastError: Error?
        for retry in 1...3 {
            do {
                let response = try await AIProviderClient.complete(
                    config: config,
                    system: system,
                    messages: [("user", user)],
                    timeout: 75,
                    maxTokens: 3200,
                    retryOnTransient: false
                )
                let parsed = iconScriptFromProviderResponse(response)
                if !parsed.isEmpty { return parsed }
                await MainActor.run {
                    AIDebugTraceStore.shared.append("ICON COMPLETE RETRY", "Attempt \(retry) returned no usable icon script.")
                }
            } catch {
                lastError = error
                await MainActor.run {
                    AIDebugTraceStore.shared.append("ICON COMPLETE RETRY", "Attempt \(retry) failed: \(error.localizedDescription)")
                }
            }
        }
        if let lastError { throw lastError }
        return ""
    }

    private static func iconScriptFromProviderResponse(_ response: String) -> String {
        let tagged = value("icon_script", in: response).trimmed
        if !tagged.isEmpty { return tagged }
        var bare = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = bare.range(of: "SIZE ", options: .caseInsensitive) {
            bare = String(bare[start.lowerBound...]).trimmed
        }
        let upper = bare.uppercased()
        guard upper.contains("SIZE "),
              ["BG ", "RECT ", "CIRCLE ", "LINE ", "TRIANGLE "].contains(where: { upper.contains($0) }),
              !upper.contains("<HTML") else { return "" }
        return bare
    }

    static func iconQualityIssue(_ script: String) -> String? {
        let lines = script
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let commands = lines.compactMap { $0.split(whereSeparator: \.isWhitespace).first?.uppercased() }
        let shapeCommands = commands.filter { ["RECT", "CIRCLE", "LINE", "TRIANGLE"].contains($0) }
        let shapeKinds = Set(shapeCommands)
        guard commands.contains("SIZE"), commands.contains("BG") else {
            return "The icon must include SIZE 1024 1024 and a full opaque BG."
        }
        guard shapeCommands.count >= 5 else {
            return "The icon is too sparse to communicate a clear app-specific symbol. Redesign it with one simple, unmistakable concept and enough supporting geometry to read at small size."
        }
        guard shapeKinds.count >= 2 else {
            return "The icon relies on only one primitive type. Add purposeful supporting geometry so the concept reads as designed rather than autogenerated."
        }
        if shapeCommands.count > 28 {
            return "The icon is too detailed for app-icon scale. Simplify toward one bold symbol, strong negative space, and roughly 6-18 purposeful shapes."
        }
        return nil
    }

    static func fallbackIconScript(html: String, originalPrompt: String) -> String {
        let palette = fallbackIconPalette(html)
        let background = palette.0, accent = palette.1, light = palette.2
        let intent = (originalPrompt + " " + String(html.prefix(8_000))).lowercased()

        if intent.contains("weather") || intent.contains("forecast") {
            return """
SIZE 1024 1024
BG \(background)
FILL_RADIAL \(accent) \(background)
CIRCLE 330 320 205 \(accent)
CIRCLE 330 320 125 \(light)
LINE 330 82 330 145 30 \(light)
LINE 110 320 174 320 30 \(light)
LINE 486 164 532 118 28 \(light)
CIRCLE 500 585 210 \(light)
CIRCLE 690 590 160 \(light)
CIRCLE 360 620 145 \(light)
RECT 315 580 515 190 \(light)
LINE 380 810 350 885 30 \(accent)
LINE 540 810 510 885 30 \(accent)
LINE 700 810 670 885 30 \(accent)
"""
        }
        if intent.contains("game") || intent.contains("engine") || intent.contains("synapse") || intent.contains("canvas") {
            return """
SIZE 1024 1024
BG \(background)
FILL_RADIAL \(accent) \(background)
CIRCLE 512 512 330 \(accent)
CIRCLE 512 512 246 \(background)
LINE 300 330 512 512 38 \(accent)
LINE 724 330 512 512 38 \(accent)
LINE 300 694 512 512 38 \(accent)
LINE 724 694 512 512 38 \(accent)
CIRCLE 300 330 78 \(light)
CIRCLE 724 330 78 \(light)
CIRCLE 300 694 78 \(light)
CIRCLE 724 694 78 \(light)
FILL_RADIAL \(light) \(accent)
CIRCLE 512 512 138 \(light)
TRIANGLE 478 430 478 594 620 512 \(background)
CIRCLE 512 512 42 \(accent)
"""
        }
        if intent.contains("music") || intent.contains("audio") || intent.contains("sound") {
            return """
SIZE 1024 1024
BG \(background)
FILL_LINEAR \(accent) \(light)
RECT 440 210 110 470 \(accent)
RECT 540 210 300 105 \(accent)
LINE 548 420 808 350 52 \(light)
CIRCLE 365 705 132 \(accent)
CIRCLE 715 650 132 \(accent)
CIRCLE 365 705 62 \(background)
CIRCLE 715 650 62 \(background)
LINE 210 360 210 580 30 \(light)
LINE 270 320 270 620 30 \(light)
LINE 330 385 330 555 30 \(light)
"""
        }
        if intent.contains("calculator") || intent.contains("math") {
            return """
SIZE 1024 1024
BG \(background)
RECT 238 150 548 724 \(light)
RECT 290 210 444 150 \(background)
CIRCLE 340 475 54 \(accent)
CIRCLE 512 475 54 \(accent)
CIRCLE 684 475 54 \(accent)
CIRCLE 340 635 54 \(accent)
CIRCLE 512 635 54 \(accent)
CIRCLE 684 635 54 \(accent)
LINE 316 785 364 737 30 \(background)
LINE 316 737 364 785 30 \(background)
LINE 488 760 536 760 30 \(background)
LINE 684 724 684 796 30 \(background)
LINE 648 760 720 760 30 \(background)
"""
        }
        if intent.contains("map") || intent.contains("location") || intent.contains("place") {
            return """
SIZE 1024 1024
BG \(background)
FILL_RADIAL \(accent) \(background)
CIRCLE 512 420 260 \(accent)
TRIANGLE 332 565 692 565 512 866 \(accent)
CIRCLE 512 420 128 \(background)
CIRCLE 512 420 66 \(light)
LINE 240 760 400 700 26 \(light)
LINE 624 720 800 650 26 \(light)
LINE 250 825 430 760 26 \(light)
LINE 610 790 790 720 26 \(light)
"""
        }
        if intent.contains("note") || intent.contains("write") || intent.contains("editor") || intent.contains("code") {
            return """
SIZE 1024 1024
BG \(background)
RECT 220 150 584 724 \(light)
TRIANGLE 680 150 804 274 680 274 \(accent)
LINE 320 390 430 500 34 \(accent)
LINE 430 500 320 610 34 \(accent)
LINE 704 390 594 500 34 \(accent)
LINE 594 500 704 610 34 \(accent)
LINE 485 650 555 350 32 \(background)
LINE 315 735 710 735 22 \(background)
"""
        }
        return """
SIZE 1024 1024
BG \(background)
FILL_RADIAL \(accent) \(background)
CIRCLE 512 512 330 \(accent)
CIRCLE 512 512 235 \(background)
TRIANGLE 512 275 742 665 282 665 \(light)
CIRCLE 512 512 105 \(accent)
LINE 512 185 512 255 28 \(light)
LINE 215 512 285 512 28 \(light)
LINE 739 512 809 512 28 \(light)
LINE 305 305 355 355 28 \(light)
LINE 669 669 719 719 28 \(light)
"""
    }

    private static func fallbackIconPalette(_ html: String) -> (String, String, String) {
        guard let regex = try? NSRegularExpression(pattern: "#[0-9A-Fa-f]{6}") else {
            return ("#111827", "#7C3AED", "#F8FAFC")
        }
        let range = NSRange(html.startIndex..., in: html)
        var colors: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let swiftRange = Range(match.range, in: html) else { continue }
            let color = String(html[swiftRange])
            if !colors.contains(where: { $0.caseInsensitiveCompare(color) == .orderedSame }) {
                colors.append(color)
            }
            if colors.count == 8 { break }
        }
        return (colors.first ?? "#111827", colors.dropFirst().first ?? "#7C3AED", colors.dropFirst(2).first ?? "#F8FAFC")
    }

    private static func iconDesignBrief(html: String, originalPrompt: String) -> String {
        func firstMatch(_ pattern: String, in source: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let title = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html)
        let description = firstMatch(#"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#, in: html)
            ?? firstMatch(#"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']description["']"#, in: html)

        var stripped = html
        stripped = stripped.replacingOccurrences(of: #"<style(?s:.*?)</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        stripped = stripped.replacingOccurrences(of: #"<script(?s:.*?)</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        stripped = stripped.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"&[A-Za-z0-9#]+;"#, with: " ", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let visible = String(stripped.prefix(1_800)).trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = html.lowercased()
        let categories: [(String, [String])] = [
            ("game / simulation engine", ["game", "canvas", "engine", "player", "level", "sprite"]),
            ("weather", ["weather", "forecast", "temperature", "precipitation"]),
            ("music / audio", ["audio", "music", "playlist", "waveform"]),
            ("developer / code editor", ["code", "editor", "javascript", "console", "developer"]),
            ("calculator / math", ["calculator", "equation", "math", "compute"]),
            ("maps / location", ["map", "location", "latitude", "longitude"]),
            ("notes / writing", ["note", "document", "textarea", "markdown"]),
            ("media / photos", ["photo", "image", "gallery", "camera"])
        ]
        let ranked = categories.map { item in
            (item.0, item.1.reduce(0) { $0 + (lower.components(separatedBy: $1).count - 1) })
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let categoryText = ranked.prefix(3).map { "\($0.0) (signal \($0.1))" }.joined(separator: ", ")

        guard let colorRegex = try? NSRegularExpression(pattern: "#[0-9A-Fa-f]{6}") else {
            return "Original request: \(originalPrompt)\nTitle: \(title ?? "Unknown")\nVisible app text: \(visible)"
        }
        var colors: [String] = []
        for match in colorRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let color = String(html[range]).uppercased()
            if !colors.contains(color) { colors.append(color) }
            if colors.count == 8 { break }
        }

        return """
Original request: \(originalPrompt)
HTML title: \(title ?? "Not found")
Meta description: \(description ?? "Not found")
Likely product category: \(categoryText.isEmpty ? "Infer from the title and visible labels." : categoryText)
UI palette candidates: \(colors.isEmpty ? "No reliable hex palette found; choose a restrained purpose-appropriate palette." : colors.joined(separator: ", "))
Visible labels/content excerpt: \(visible.isEmpty ? "No useful visible text extracted; infer from title and code-category signals." : visible)
Icon direction: infer the most distinctive product metaphor yourself. Do not require the user to provide icon details.
"""
    }

    static func reviewArtifact(
        html: String,
        iconScript: String,
        originalPrompt: String,
        research: String,
        localIssues: [String],
        pass: Int,
        config: AIProviderConfiguration
    ) async throws -> String {
        let system = """
You are HTMLApp Forge's independent release-gate reviewer. Treat the supplied HTML as a real app candidate, not a design exercise. Find concrete defects that would stop or materially degrade the user's requested outcome, and repair them with the smallest exact patch.

Audit in this order:
1. REQUEST COVERAGE — core requested behavior exists and is not replaced by decorative UI or fake data.
2. FUNCTIONAL PATHS — visible controls, navigation, forms, state transitions, CRUD operations, imports/exports, and primary actions have coherent handlers.
3. DATA/STATE — important user data survives expected rerenders/navigation, persistence is appropriate, IDs are stable where needed, and success is not shown before operations complete.
4. ASYNC/NETWORK — fetches and native calls handle loading/failure, stale results, races, cancellation where relevant, malformed responses, and honest offline behavior.
5. CAPABILITIES — APIs/native bridges are supported by the supplied evidence or are properly feature-detected. Never approve invented native methods or guessed endpoint fields.
6. PRIVACY/SECURITY — no embedded secrets, unsafe insertion of untrusted content, or unnecessary sensitive-data transmission.
7. LIFECYCLE — timers, listeners, media tracks, sensors, sockets, workers, observers, and object URLs are cleaned up where relevant.
8. MOBILE UX — safe areas, keyboard/scrolling, touch targets, phone/iPad resizing, dark/light presentation, and reduced-motion/accessibility behavior are plausible from source.
9. SOURCE INTEGRITY — no obvious broken references, unbalanced structure, placeholder endpoints/keys, dead controls, or source-level syntax mistakes.
10. ICON — icon script is valid, app-specific, and matches the product identity.

Use the local static warnings as leads, not unquestionable facts. Use research evidence only to constrain factual/API claims; do not extrapolate beyond it. Do not claim you visually rendered, executed, or device-tested code you only inspected.

Do not rewrite functioning code for taste. Patch only concrete defects. SEARCH text must be copied exactly from the supplied HTML and be as small and unique as practical. If there is no concrete defect worth changing, leave <htmlapp_patch> empty. Replace the icon only if it is actually missing, invalid, or mismatched.

Return only, in this order so any required repair is completed before commentary:
<htmlapp_patch>optional exact SEARCH/REPLACE blocks</htmlapp_patch>
<verification>concise release-gate result, including remaining limitations</verification>
<icon_script>optional complete replacement icon script</icon_script>
"""
        let user = """
REVIEW PASS: \(pass)

ORIGINAL PROMPT:
\(originalPrompt)

LOCAL STATIC WARNINGS:
\(localIssues.isEmpty ? "None." : localIssues.joined(separator: "\n"))

CAPABILITY / API EVIDENCE:
\(research.isEmpty ? "No additional research evidence was supplied." : research)

HTML:
<htmlapp_existing>
\(html)
</htmlapp_existing>

ICON:
<icon_script_existing>
\(iconScript)
</icon_script_existing>
"""
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)], timeout: 120, maxTokens: 8000, retryOnTransient: true)
    }

    static func review(html: String, originalPrompt: String, research: String, localIssues: [String], config: AIProviderConfiguration) async throws -> String {
        let system = """
You are HTMLApp's final QA reviewer. Review the complete HTML/CSS/JavaScript source for likely functional defects and mobile UI quality problems. Check that controls have actions, navigation and state transitions make sense, APIs are not fabricated, error/loading/empty states are honest, permissions require gestures, touch targets are usable, light/dark layouts are coherent, and motion makes the app feel alive without being distracting. Also check for obvious syntax/DOM-reference problems.

Do not claim you visually rendered or device-tested anything you cannot actually observe. Do not invent failures. If you find a concrete issue, return a minimal exact SEARCH/REPLACE patch. If no concrete source-level issue is found, leave <htmlapp_patch> empty.

Return only:
<verification>brief QA summary including what was checked and any limitations</verification>
<htmlapp_patch>optional SEARCH/REPLACE blocks</htmlapp_patch>
"""
        let user = """
Original request/intent:
\(originalPrompt)

Local static checks:
\(localIssues.isEmpty ? "No local structural warnings." : localIssues.joined(separator: "\n"))

Relevant API research:
\(research.isEmpty ? "None." : research)

HTML to review:
<htmlapp_existing>
\(html)
</htmlapp_existing>
"""
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
    }

    static func recoverGeneration(
        response: String,
        brief: String,
        research: String,
        config: AIProviderConfiguration
    ) async throws -> String {
        let system = """
You are HTMLApp's recovery editor. The previous app-generation response was truncated or malformed. Reconstruct it into one complete, valid HTMLApp response while preserving all useful work already present. Fix unclosed HTML/CSS/JavaScript, missing required sections, duplicated cutoff text, and obvious source errors. Do not invent APIs or data. Return exactly:
<build_summary>concise implementation conclusions</build_summary>
<description>one sentence</description>
<icon_script>static icon drawing script</icon_script>
<asset_scripts>optional ASSET filename / END_ASSET IconScript blocks needed by the recovered HTML</asset_scripts>
<htmlapp_code><!DOCTYPE html>...one complete self-contained app...</htmlapp_code>
No Markdown fences and no text outside those sections.
"""
        let user = """
Original brief:
\(brief)

Research evidence:
\(research.isEmpty ? "None." : research)

Interrupted/malformed response:
<interrupted_response>
\(response)
</interrupted_response>
"""
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)])
    }

    static func parse(_ text: String) -> AIGenerationOutput {
        let summary = value("build_summary", in: text).trimmed
        return AIGenerationOutput(
            html: sanitizeHTMLPayload(value("htmlapp_code", in: text)),
            patch: sanitizePatchPayload(value("htmlapp_patch", in: text)),
            description: value("description", in: text).trimmed,
            iconScript: value("icon_script", in: text).trimmed,
            assetScripts: parseAssetScripts(value("asset_scripts", in: text)),
            refinedBrief: summary.isEmpty ? value("thinking", in: text).trimmed : summary
        )
    }

    static func parsePartial(_ text: String) -> AIGenerationOutput {
        let summary = partial("build_summary", in: text).trimmed
        return AIGenerationOutput(
            html: sanitizeHTMLPayload(partial("htmlapp_code", in: text)),
            patch: sanitizePatchPayload(partial("htmlapp_patch", in: text)),
            description: partial("description", in: text).trimmed,
            iconScript: partial("icon_script", in: text).trimmed,
            assetScripts: parseAssetScripts(value("asset_scripts", in: text)),
            refinedBrief: summary.isEmpty ? partial("thinking", in: text).trimmed : summary
        )
    }

    private static func stripMarkdownFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            }
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeHTMLPayload(_ raw: String) -> String {
        var html = stripMarkdownFences(raw)
        if let start = html.range(of: "<!DOCTYPE html", options: [.caseInsensitive])?.lowerBound
            ?? html.range(of: "<html", options: [.caseInsensitive])?.lowerBound {
            html = String(html[start...])
        }
        if let end = html.range(of: "</html>", options: [.caseInsensitive])?.upperBound {
            html = String(html[..<end])
        }
        return stripProgressMarkers(html).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizePatchPayload(_ raw: String) -> String {
        var patch = stripMarkdownFences(raw)
        if let start = patch.range(of: "<<<<<<< SEARCH")?.lowerBound {
            patch = String(patch[start...])
        }
        if let end = patch.range(of: ">>>>>>> REPLACE", options: [.backwards])?.upperBound {
            patch = String(patch[..<end])
        }
        return patch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func streamingProgress(in text: String) -> String? {
        if let marker = latestProgressNote(in: text) { return marker }
        if text.contains("<htmlapp_code>") {
            return "Building the responsive interface and wiring the app’s real behavior."
        }
        if text.contains("<asset_scripts>") {
            return "Preparing only the portable visual assets this app actually needs."
        }
        if text.contains("<icon_script>") {
            return "Sketching an app-specific icon before the dedicated icon pass validates it."
        }
        if text.contains("<description>") {
            return "Locking the finished product scope before writing the app."
        }
        if text.contains("<build_summary>") || text.contains("<thinking>") {
            return "Turning the product plan into concrete build decisions."
        }
        return nil
    }

    static func latestProgressNote(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<!--\s*HTMLAPP_PROGRESS:\s*(.*?)\s*-->"#,
            options: []
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              match.numberOfRanges > 1,
              let noteRange = Range(match.range(at: 1), in: text) else { return nil }
        let clean = String(text[noteRange])
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(160))
    }

    static func stripProgressMarkers(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<!--\s*HTMLAPP_PROGRESS:\s*.*?-->"#,
            options: []
        ) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    static func safeAssetName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let clean = trimmed.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : Character("-") }
        return String(clean).trimmingCharacters(in: CharacterSet(charactersIn: "-.")).prefix(80).description
    }

    private static func parseAssetScripts(_ text: String) -> [AIGeneratedAsset] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var result: [AIGeneratedAsset] = []
        var currentName: String?
        var currentLines: [String] = []

        func finish() {
            guard let currentName else { return }
            let name = safeAssetName(currentName)
            let script = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !script.isEmpty, !result.contains(where: { $0.name == name }) {
                result.append(AIGeneratedAsset(name: name, script: script))
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.uppercased().hasPrefix("ASSET ") {
                finish()
                currentName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentLines = []
            } else if line.uppercased() == "END_ASSET" {
                finish()
                currentName = nil
                currentLines = []
            } else if currentName != nil {
                currentLines.append(rawLine)
            }
        }
        finish()
        return Array(result.prefix(6))
    }

    static func verification(from text: String) -> String { value("verification", in: text).trimmed }
    static func patch(from text: String) -> String { value("htmlapp_patch", in: text) }
    static func iconScript(from text: String) -> String { value("icon_script", in: text) }

    private static func values(_ tag: String, in text: String) -> [String] {
        var result: [String] = []
        var remaining = text[...]
        let open = "<\(tag)>"; let close = "</\(tag)>"
        while let start = remaining.range(of: open) {
            let tail = remaining[start.upperBound...]
            guard let end = tail.range(of: close) else { break }
            result.append(String(tail[..<end.lowerBound]).trimmed)
            remaining = tail[end.upperBound...]
        }
        return result
    }

    private static func value(_ tag: String, in text: String) -> String { values(tag, in: text).first ?? "" }
    private static func partial(_ tag: String, in text: String) -> String {
        let open = "<\(tag)>"; let close = "</\(tag)>"
        guard let start = text.range(of: open) else { return "" }
        let tail = text[start.upperBound...]
        if let end = tail.range(of: close) { return String(tail[..<end.lowerBound]) }
        return String(tail)
    }
}

struct HTMLPatchApplication {
    let html: String?
    let failureReason: String?
    let contextSnippet: String

    var succeeded: Bool { html != nil }
}

enum HTMLPatchApplier {
    private struct Block {
        let search: String
        let replacement: String
    }

    static func apply(_ patch: String, to source: String) -> String? {
        applyDetailed(patch, to: source).html
    }

    static func applyDetailed(_ patch: String, to source: String) -> HTMLPatchApplication {
        guard let blocks = parseBlocks(patch), !blocks.isEmpty else {
            return HTMLPatchApplication(
                html: nil,
                failureReason: "The patch did not contain a complete SEARCH/REPLACE block.",
                contextSnippet: String(source.prefix(1800))
            )
        }

        var result = source
        for (offset, block) in blocks.enumerated() {
            let match = uniqueRange(of: block.search, in: result)
            switch match {
            case .success(let range):
                result.replaceSubrange(range, with: block.replacement)
            case .failure(let reason, let hintRange):
                return HTMLPatchApplication(
                    html: nil,
                    failureReason: "SEARCH block \(offset + 1) failed: \(reason)",
                    contextSnippet: sourceSnippet(in: result, around: hintRange, fallbackSearch: block.search)
                )
            }
        }

        return HTMLPatchApplication(html: result, failureReason: nil, contextSnippet: "")
    }

    private enum MatchResult {
        case success(Range<String.Index>)
        case failure(String, Range<String.Index>?)
    }

    private static func parseBlocks(_ patch: String) -> [Block]? {
        let searchMarker = "<<<<<<< SEARCH"
        let splitMarker = "======="
        let replaceMarker = ">>>>>>> REPLACE"
        var cursor = patch[...]
        var blocks: [Block] = []

        while let searchStart = cursor.range(of: searchMarker) {
            let afterSearchMarker = cursor[searchStart.upperBound...]
            guard let divider = afterSearchMarker.range(of: splitMarker) else { return nil }
            let search = String(afterSearchMarker[..<divider.lowerBound]).trimmingCharacters(in: .newlines)
            let afterDivider = afterSearchMarker[divider.upperBound...]
            guard let replaceEnd = afterDivider.range(of: replaceMarker) else { return nil }
            let replacement = String(afterDivider[..<replaceEnd.lowerBound]).trimmingCharacters(in: .newlines)
            guard !search.isEmpty else { return nil }
            blocks.append(Block(search: search, replacement: replacement))
            cursor = afterDivider[replaceEnd.upperBound...]
        }
        return blocks
    }

    private static func uniqueRange(of search: String, in source: String) -> MatchResult {
        let exact = allRanges(of: search, in: source, limit: 3)
        if exact.count == 1 { return .success(exact[0]) }
        if exact.count > 1 {
            return .failure("the exact SEARCH text matched more than once; the model must make the block more specific.", exact[0])
        }

        let tokens = search.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else {
            return .failure("the SEARCH text was empty after whitespace normalization.", nil)
        }
        let pattern = tokens
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return .failure("the whitespace-normalized SEARCH pattern could not be compiled.", nil)
        }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        if matches.count == 1, let range = Range(matches[0].range, in: source) {
            return .success(range)
        }
        if matches.count > 1, let range = Range(matches[0].range, in: source) {
            return .failure("the whitespace-normalized SEARCH text matched more than once; the model must make the block more specific.", range)
        }
        return .failure("the SEARCH text matched zero times, even after whitespace normalization.", nil)
    }

    private static func allRanges(of needle: String, in haystack: String, limit: Int) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = haystack.startIndex
        while cursor < haystack.endIndex,
              let range = haystack.range(of: needle, range: cursor..<haystack.endIndex) {
            ranges.append(range)
            if ranges.count >= limit { break }
            cursor = range.upperBound
        }
        return ranges
    }

    private static func sourceSnippet(
        in source: String,
        around range: Range<String.Index>?,
        fallbackSearch: String
    ) -> String {
        var anchor = range
        if anchor == nil {
            let line = fallbackSearch
                .split(separator: "\n")
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty && $0.count >= 8 })
            if let line, let found = source.range(of: line) { anchor = found }
        }

        guard let anchor else { return String(source.prefix(2200)) }
        let lower = source.index(anchor.lowerBound, offsetBy: -900, limitedBy: source.startIndex) ?? source.startIndex
        let upper = source.index(anchor.upperBound, offsetBy: 900, limitedBy: source.endIndex) ?? source.endIndex
        return String(source[lower..<upper])
    }
}

enum HTMLQualityChecks {
    static func issues(in html: String) -> [String] {
        let lower = html.lowercased()
        var issues: [String] = []
        if !lower.contains("<!doctype html") { issues.append("Missing <!DOCTYPE html>.") }
        if !lower.contains("name=\"viewport\"") && !lower.contains("name='viewport'") { issues.append("Missing mobile viewport metadata.") }
        if !lower.contains("viewport-fit=cover") { issues.append("Viewport must include viewport-fit=cover for HTMLApp's edge-to-edge WebView.") }
        if !lower.contains("safe-area-inset-top") { issues.append("Missing top safe-area handling; content may sit under the notch or Dynamic Island.") }
        if !lower.contains("safe-area-inset-bottom") { issues.append("Missing bottom safe-area handling for the Home Indicator.") }
        if count("<script", in: lower) != count("</script>", in: lower) { issues.append("Unbalanced <script> tags.") }
        if count("<style", in: lower) != count("</style>", in: lower) { issues.append("Unbalanced <style> tags.") }
        if lower.contains("alert(") { issues.append("Uses browser alert(); routine feedback should use in-app UI.") }
        if lower.contains("example.com") || lower.contains("your_api_key") || lower.contains("api-key-here") { issues.append("Contains a likely placeholder endpoint or key.") }
        if html.contains("{{HTMLAPP_ASSET:") { issues.append("Contains an unresolved generated-asset token.") }
        return issues
    }

    private static func count(_ needle: String, in haystack: String) -> Int { haystack.components(separatedBy: needle).count - 1 }
}

enum SafePublicAPIResearch {
    private static let publicAPIsURL = URL(string: "https://raw.githubusercontent.com/public-apis/public-apis/master/README.md")!
    private static let excluded = ["gambling", "betting", "casino", "alcohol", "beer", "wine", "weapon", "firearm", "drug", "porn", "adult", "malware"]

    static func research(queries: [String]) async -> String {
        guard !queries.isEmpty else { return "" }
        async let publicCatalog = fetchText(publicAPIsURL)
        let catalog = await publicCatalog
        var output: [String] = [ForgeProductContract.catalog]

        for query in queries where safe(query) {
            let terms = searchTerms(query)
            var matches: [String] = []

            if let catalog {
                let rows = catalog.split(separator: "\n").map(String.init).filter { row in
                    guard row.hasPrefix("|") else { return false }
                    let lower = row.lowercased()
                    let columns = row.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    let noKey = columns.count > 3 && (columns[3].isEmpty || columns[3].lowercased() == "no")
                    return noKey && safe(lower) && terms.contains(where: { lower.contains($0) })
                }
                matches.append(contentsOf: rows.prefix(6))
            }


            if matches.isEmpty {
                output.append("Query: \(query)\nNo matching no-key API listing was found. Browse official documentation or use a local fallback.")
            } else {
                output.append("Query: \(query)\n" + matches.joined(separator: "\n"))
            }
        }
        return output.joined(separator: "\n\n")
    }

    private static func fetchText(_ url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func searchTerms(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 }
    }

    private static func safe(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !excluded.contains(where: { lower.contains($0) })
    }
}

enum HTMLStreamRepair {
    static func isSafeForLivePreview(_ fragment: String) -> Bool {
        guard !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return count("<script", fragment) == count("</script>", fragment)
    }

    static func previewDocument(_ fragment: String) -> String {
        var html = fragment
        let lower = html.lowercased()
        if !lower.contains("<!doctype") && !lower.contains("<html") {
            html = "<!DOCTYPE html><html><head><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\"></head><body>" + html
        }
        if count("<script", html) > count("</script>", html) { html += "\n</script>" }
        if count("<style", html) > count("</style>", html) { html += "\n</style>" }
        if count("<head", html) > count("</head>", html) { html += "\n</head>" }
        if count("<body", html) > count("</body>", html) { html += "\n</body>" }
        if count("<html", html) > count("</html>", html) { html += "\n</html>" }
        return html
    }
    private static func count(_ needle: String, _ haystack: String) -> Int { haystack.lowercased().components(separatedBy: needle).count - 1 }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
