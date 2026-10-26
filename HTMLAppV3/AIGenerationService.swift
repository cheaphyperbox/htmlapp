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

struct AIResearchPlan: Sendable {
    var publicQueries: [String] = []
    var deviceQueries: [String] = []

    var isEmpty: Bool {
        publicQueries.isEmpty && deviceQueries.isEmpty
    }
}

struct AIPlanningResult: Sendable {
    var brief: String
    var research: AIResearchPlan
    var purpose: String = ""
    var assumptions: [String] = []
    var impliedFeatures: [String] = []
    var capabilities: [String] = []
    var recommendedMode: String? = nil
}

enum ForgeTestMode: String, CaseIterable, Identifiable {
    case skip, fast, balanced
    var id: String { rawValue }
    var label: String {
        switch self {
        case .skip: return "Skip tests (fastest)"
        case .fast: return "Fast checks"
        case .balanced: return "Balanced checks + repair"
        }
    }
    static var selected: ForgeTestMode {
        ForgeTestMode(rawValue: UserDefaults.standard.string(forKey: "forgeTestMode") ?? "fast") ?? .fast
    }
}

enum AIGenerationError: LocalizedError {
    case notConfigured, invalidEndpoint, missingHTML, invalidPatch, missingIcon, brokenJavaScript
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Configure an AI API URL and model in Settings first."
        case .invalidEndpoint: return "The configured AI API URL is invalid."
        case .missingHTML: return "The AI response did not contain a complete HTML app."
        case .brokenJavaScript: return "The generated app contains JavaScript syntax errors. Forge stopped before saving broken buttons. Retry the app checks to repair the script."
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
    @Published var lastEditSummary = ""
    @Published var wantsUIPolish = false
    @Published var errorMessage: String?
    @Published var isWorking = false
    @Published private(set) var skippableStage: String?
    private var skipCurrentOperation: (() -> Void)?
    private var skipWasRequested = false
    @Published var streamedByteCount = 0
    @Published var streamedSection = "css"
    @Published var qaRepairResponseBytes = 0
    @Published var sectionByteCounts: [String: Int] = [:]
    @Published var failedPhase: String?

    private var originalPrompt = ""
    private var generationStartedAt = Date()
    private var lastResearch = ""
    private var editingExistingApp = false
    private var checkpointExistingAppID: String?
    private var latestPartialHTML = ""
    private var iconRefreshAllowed = true

    private static func sectionForLatestStream(_ text: String, fallback: String) -> String {
        let lower = text.lowercased()
        let markers = ["<style": "css", "<body": "body", "<script": "script",
                       "</script>": "body", "</style>": "body"]
        let last = markers.compactMap { (tag, label) -> (Int, String)? in
            guard let range = lower.range(of: tag, options: .backwards) else { return nil }
            return (lower.distance(from: lower.startIndex, to: range.lowerBound), label)
        }.max { $0.0 < $1.0 }
        return last?.1 ?? fallback
    }

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
        case "Running app checks": return "Loading the generated HTML in an isolated offscreen WebView and checking real runtime failures at phone and iPad widths."
        case "Reviewing source (not running device tests)": return "Combining runtime findings with source checks for a focused release review."
        case "Rechecking repaired app": return "Re-running local and offscreen runtime checks only where the first repair still needs verification."
        case "Polishing the interface": return "Refining the visual hierarchy without changing the app’s working product model."
        case "Draft recovered": return "Recovered the latest local Forge draft. Nothing was sent or resumed automatically."
        case "Ready to review": return "The generated source is ready for you to try on-device and review."
        case "Generation stopped", "Edit stopped", "Verification stopped": return "The current operation stopped; completed source has been preserved where possible."
        default: return "Working on the current build stage."
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let provider = error as? AIProviderRequestError {
            if let status = provider.statusCode {
                switch status {
                case 401, 403:
                    return "The AI provider rejected the API key or account access. Check your key in Settings, then retry."
                case 404:
                    return "The configured AI endpoint or model was not found. Check the API URL and model name in Settings."
                case 408:
                    return "The AI provider timed out. Your current draft was kept; retry when the connection is stable."
                case 429:
                    if let retryAfter = provider.retryAfter, retryAfter > 0 {
                        return "The AI provider is rate limiting requests. Try again in about \(Int(ceil(retryAfter))) seconds."
                    }
                    return "The AI provider is rate limiting requests. Your current draft was kept; wait a moment and retry."
                case 500...599:
                    return "The AI provider is temporarily unavailable. Your current draft was kept; retry shortly."
                default:
                    break
                }
            }
            let lower = provider.message.lowercased()
            if lower.contains("context") && (lower.contains("length") || lower.contains("token")) {
                return "This request exceeded the model's context limit. Shorten the request or use a model with a larger context window."
            }
            if lower.contains("max_tokens") || lower.contains("max_completion_tokens") {
                return "The model rejected the configured output-token setting. Forge tried its compatibility fallback; check the selected model if this continues."
            }
            return "The AI provider could not complete this step. Your current draft was kept. Open AI Debug for the technical details."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "You appear to be offline. Your current draft was kept; reconnect and retry."
            case .timedOut:
                return "The AI request timed out. Your current draft was kept; retry when the connection is stable."
            default:
                return "The network request failed. Your current draft was kept; retry when the connection is stable."
            }
        }
        if error is AIGenerationError {
            return error.localizedDescription
        }
        return "Forge could not complete this step. Your current draft was kept. Open AI Debug for technical details, then retry."
    }

    private static func changeMayNeedIconRefresh(_ change: String) -> Bool {
        let lower = change.lowercased()
        let signals = [
            "app icon", "icon", "logo", "branding", "brand identity",
            "rebrand", "rename the app", "rename app", "app name"
        ]
        return signals.contains { signal in
            let escaped = NSRegularExpression.escapedPattern(for: signal)
            let pattern = #"(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
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
        iconRefreshAllowed = false
        checkpointExistingAppID = app.id
        originalPrompt = "Maintain and improve the existing HTML app named \(app.name). Preserve its current purpose and working behavior unless the user explicitly asks to change them."
        streamedHTML = app.html
        description = app.summary
        renderedIconData = app.favicon
        refinedBrief = "Editing \(app.name) with AI. Existing functionality is the starting point and revisions will be applied as patches."
        verificationReport = ""
        phase = "Ready for AI edits"
    }

    func skipCurrentStage() {
        guard let skipCurrentOperation else { return }
        skipWasRequested = true
        skipCurrentOperation()
    }

    /// Cancel an optional model call without cancelling the entire Forge run.
    /// If an optional stage is skipped, the caller preserves its safe input.
    private func optionalStage<T: Sendable>(
        _ title: String,
        operation: @escaping () async throws -> T
    ) async throws -> T? {
        skipWasRequested = false
        let worker = Task { try await operation() }
        skippableStage = title
        skipCurrentOperation = { worker.cancel() }
        defer {
            skippableStage = nil
            skipCurrentOperation = nil
        }
        return try await withTaskCancellationHandler {
            do {
                let result = try await worker.value
                return skipWasRequested ? nil : result
            } catch {
                if skipWasRequested { return nil }
                throw error
            }
        } onCancel: {
            worker.cancel()
        }
    }

    func generate(prompt: String, originalUserPrompt: String? = nil, researchReport: String = "", preplanned: AIPlanningResult? = nil) async {
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        editingExistingApp = false
        iconRefreshAllowed = true
        checkpointExistingAppID = nil
        originalPrompt = originalUserPrompt ?? prompt
        isWorking = true
        errorMessage = nil
        failedPhase = nil
        verificationReport = ""
        do {
            let suppliedResearch = researchReport.trimmingCharacters(in: .whitespacesAndNewlines)
            let improved: String
            if ForgeRunOptions.quick || AIHTMLAgent.canSkipPreflight(for: originalUserPrompt ?? prompt) {
                improved = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                refinedBrief = improved
                let localCapabilities = AIHTMLAgent.fastPathCapabilityQueries(for: originalPrompt)
                let knownAPIs = HTMLAppDeviceAPIResearch.research(queries: localCapabilities)
                lastResearch = [suppliedResearch, knownAPIs].filter { !$0.isEmpty }.joined(separator: "\n\n")
                phase = "Generating live preview"
            } else {
                phase = "Designing the app"
                // Plan the user's intent without inflating planning tokens with
                // the full style mockup. Preserve the raw chosen HTML for CODING.
                let visualReference: String
                if let originalUserPrompt, prompt.hasPrefix(originalUserPrompt) {
                    visualReference = String(prompt.dropFirst(originalUserPrompt.count))
                } else {
                    visualReference = ""
                }
                let planning: AIPlanningResult?
                if let preplanned {
                    planning = preplanned
                    AIDebugTraceStore.shared.append("PREFLIGHT", "Reused prompt planning prepared while choosing a look.")
                } else {
                    planning = try await optionalStage("Prompt improvement") {
                        try await AIHTMLAgent.planPrompt(
                            originalUserPrompt ?? prompt,
                            config: AISettingsStore.configuration(for: .planner)
                        )
                    }
                }
                if let planning {
                improved = planning.brief + visualReference
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
                } else {
                    improved = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    refinedBrief = improved
                    lastResearch = suppliedResearch
                    phase = "Generating live preview"
                    AIDebugTraceStore.shared.append("FORGE SKIP", "Optional prompt improvement was skipped.")
                }
            }

            // Pre-design an icon while the coding model streams. An invalid
            // speculative icon is ignored in favor of the existing repair path.
            let iconWorker: Task<String?, Never>? = ForgeRunOptions.quick ? nil : Task {
                do {
                    return try await AIHTMLAgent.generateIconScript(
                        html: "", originalPrompt: self.originalPrompt,
                        previousScript: "", config: AISettingsStore.configuration(for: .icon)
                    )
                } catch {
                    return nil
                }
            }
            defer { iconWorker?.cancel() }
            let systemPrompt = AIHTMLAgent.systemPrompt(research: lastResearch)
            var full = ""
            var recoveredFromStream: AIGenerationOutput?
            var receivedBytes = 0
            var lastPreviewBytes = 0
            var lastPreviewAt = Date.distantPast
            var lastProgressAt = Date.distantPast
            var lastPublishedByteCount = 0
            var progressTail = ""
            streamedSection = "css"
            sectionByteCounts = [:]
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
                        streamedSection = Self.sectionForLatestStream(progressTail, fallback: streamedSection)
                        sectionByteCounts[streamedSection, default: 0] += max(0, receivedBytes - lastPublishedByteCount)
                        lastPublishedByteCount = receivedBytes
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
                streamedSection = Self.sectionForLatestStream(progressTail, fallback: streamedSection)
                sectionByteCounts[streamedSection, default: 0] += max(0, receivedBytes - lastPublishedByteCount)
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
            var speculativeIconAccepted = false
            if iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let candidate = await iconWorker?.value, !candidate.isEmpty,
               AIHTMLAgent.iconQualityIssue(candidate) == nil,
               let rendered = await AIIconRenderer.render(script: candidate) {
                iconScript = candidate
                renderedIconData = rendered
                speculativeIconAccepted = true
                AIDebugTraceStore.shared.append("ICON", "Used an icon generated alongside the app.")
            }
            _ = try await optionalStage("App icon") {
                try await self.ensureValidIcon(
                    config: AISettingsStore.configuration(for: .icon),
                    // Reuse a valid coding-agent draft unless a separate icon artist is selected.
                    forceRegenerate: !ForgeRunOptions.quick && !speculativeIconAccepted && (AISettingsStore.usesSpecialistProvider(for: .icon) ||
                        AISettingsStore.iconModel != AISettingsStore.model)
                )
            }
            try await verifyAndRepair(config: config)
            try Task.checkCancellation()
            phase = "Ready to review"
        } catch is CancellationError {
            failedPhase = phase
            errorMessage = nil
            persistCheckpoint()
            phase = "Generation stopped"
        } catch {
            failedPhase = phase
            AIDebugTraceStore.shared.append("GENERATION ERROR", error.localizedDescription)
            errorMessage = Self.friendlyMessage(for: error)
            persistCheckpoint()
            phase = "Generation stopped"
        }
        isWorking = false
    }

    func revise(change: String, researchReport: String = "", styleInstruction: String? = nil) async {
        guard !streamedHTML.trimmed.isEmpty else { return }
        let config = AISettingsStore.configuration
        guard config.isConfigured else { errorMessage = AIGenerationError.notConfigured.localizedDescription; return }
        lastEditSummary = ""
        let beforeEditHTML = streamedHTML
        let beforeEditDescription = description
        let beforeEditIconScript = iconScript
        let beforeEditIcon = renderedIconData
        isWorking = true
        errorMessage = nil
        failedPhase = nil
        verificationReport = ""
        wantsUIPolish = false
        do {
            let cleanChange = change.trimmingCharacters(in: .whitespacesAndNewlines)
            iconRefreshAllowed = Self.changeMayNeedIconRefresh(cleanChange) || renderedIconData == nil
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

\(styleInstruction ?? "")
"""
            let response = try await AIProviderClient.complete(
                config: config,
                system: AIHTMLAgent.patchSystemPrompt(research: lastResearch),
                messages: [("user", user)]
            )
            let initialOutput = AIHTMLAgent.parse(response)
            // The edit contract returns a concise one-sentence edit summary.
            // Fall back to a meaningful description of the requested change.
            let concise = AIHTMLAgent.value("edit_summary", in: response)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lastEditSummary = concise.isEmpty ? "Applied AI edit: " + String(cleanChange.prefix(160)) : concise
            AIDebugTraceStore.shared.append("EDIT SUMMARY", lastEditSummary)
            wantsUIPolish = AIHTMLAgent.editNeedsPolish(response: response, requestedChange: cleanChange)
            let changedSource = initialOutput.patch.isEmpty ? initialOutput.html : initialOutput.patch
            let changedText = changedSource.lowercased()
            streamedSection = changedText.contains("<script") || changedText.contains("javascript")
                ? "script" : (changedText.contains("<style") || changedText.contains("css")
                    ? "css" : "body")
            sectionByteCounts = [streamedSection: changedSource.utf8.count]
            streamedByteCount = response.utf8.count
            AIDebugTraceStore.shared.append("EDIT PATCH VOLUME",
                "Source bytes: \(changedSource.utf8.count); response bytes: \(response.utf8.count); section: \(streamedSection)")
            let output = try await applyEditOutputWithRecovery(
                initialOutput,
                requestedChange: improvedChange,
                config: config
            )
            if !output.description.isEmpty { description = output.description }
            if iconRefreshAllowed, !output.iconScript.isEmpty { iconScript = output.iconScript }
            if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }
            let revisedAssets = await refineGeneratedAssets(output.assetScripts)
            await installGeneratedAssets(revisedAssets)

            if iconRefreshAllowed && (!output.iconScript.isEmpty || renderedIconData == nil) {
                try await ensureValidIcon(
                    config: AISettingsStore.configuration(for: .icon),
                    forceRegenerate: false
                )
            } else if editingExistingApp {
                AIDebugTraceStore.shared.append("ICON", "Preserved the existing app icon because this edit did not request an icon or identity change.")
            }
            try await verifyAndRepair(config: config)
            try Task.checkCancellation()
            phase = "Ready to review"
        } catch is CancellationError {
            failedPhase = phase
            streamedHTML = beforeEditHTML
            description = beforeEditDescription
            iconScript = beforeEditIconScript
            renderedIconData = beforeEditIcon
            errorMessage = nil
            AIDebugTraceStore.shared.append("EDIT ROLLBACK", "Canceled edit restored previous working draft.")
            persistCheckpoint()
            phase = "Edit stopped"
        } catch {
            failedPhase = phase
            streamedHTML = beforeEditHTML
            description = beforeEditDescription
            iconScript = beforeEditIconScript
            renderedIconData = beforeEditIcon
            AIDebugTraceStore.shared.append("EDIT ERROR", error.localizedDescription)
            AIDebugTraceStore.shared.append("EDIT ROLLBACK", "Restored previous HTML (\(beforeEditHTML.utf8.count) bytes) without changing saved app.")
            errorMessage = Self.friendlyMessage(for: error)
            persistCheckpoint()
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

    func beginDraft(prompt: String) {
        editingExistingApp = false
        checkpointExistingAppID = nil
        originalPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        generationStartedAt = Date()
        persistCheckpoint()
    }

    func persistCheckpoint() {
        let checkpointHTML = latestPartialHTML.isEmpty ? streamedHTML : latestPartialHTML
        guard !originalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ForgeDraftCheckpointStore.save(
            ForgeDraftCheckpoint(
                startedAt: generationStartedAt,
                savedAt: Date(),
                originalPrompt: originalPrompt,
                refinedBrief: refinedBrief,
                research: lastResearch,
                html: checkpointHTML,
                description: description,
                iconScript: iconScript,
                phase: phase,
                existingAppID: checkpointExistingAppID,
                streamedByteCount: streamedByteCount
            )
        )
    }

    func restore(checkpoint: ForgeDraftCheckpoint, existingIcon: Data? = nil) {
        checkpointExistingAppID = checkpoint.existingAppID
        editingExistingApp = checkpoint.existingAppID != nil
        generationStartedAt = checkpoint.startedAt ?? checkpoint.savedAt
        originalPrompt = checkpoint.originalPrompt
        refinedBrief = checkpoint.refinedBrief
        lastResearch = checkpoint.research
        streamedHTML = checkpoint.html
        latestPartialHTML = ""
        description = checkpoint.description
        iconScript = checkpoint.iconScript
        renderedIconData = existingIcon
        streamedByteCount = checkpoint.streamedByteCount
        verificationReport = ""
        errorMessage = nil
        failedPhase = nil
        isWorking = false
        phase = "Draft recovered"
    }

    func clearCheckpoint() {
        ForgeDraftCheckpointStore.clear()
    }

    func keepCurrentPartialDraft() {
        if !latestPartialHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            streamedHTML = latestPartialHTML
            latestPartialHTML = ""
        }
        persistCheckpoint()
    }

    func showTutorialExample(_ html: String) {
        // Onboarding must not overwrite a recoverable real generation checkpoint.
        streamedHTML = html
        isWorking = false
        phase = "Ready to review — practice calculator"
        errorMessage = nil
    }

    func acceptExternalHTML(_ html: String) {
        streamedHTML = html
        verificationReport = ""
        persistCheckpoint()
    }

    func verifyCurrent() async {
        let config = AISettingsStore.configuration
        guard config.isConfigured, !streamedHTML.trimmed.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        failedPhase = nil
        do {
            if !editingExistingApp || !iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await ensureValidIcon(config: config)
            }
            try await verifyAndRepair(config: config)
            try Task.checkCancellation()
            phase = "Ready to review"
        } catch is CancellationError {
            failedPhase = phase
            errorMessage = nil
            persistCheckpoint()
            phase = "Verification stopped"
        } catch {
            failedPhase = phase
            AIDebugTraceStore.shared.append("VERIFICATION ERROR", error.localizedDescription)
            errorMessage = Self.friendlyMessage(for: error)
            persistCheckpoint()
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
                    repairReason: "Create the final original icon for this product. Preserve a strong silhouette while welcoming layered detail, dimensional composition, and a fresh palette. Reject repetitive flat ticks/discs and default green templates.",
                    config: config
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !designed.isEmpty { candidate = designed }
            } catch {
                lastError = error
                AIDebugTraceStore.shared.append("ICON ARTIST", "The dedicated icon pass failed; validating the coding-agent draft instead. \(error.localizedDescription)")
            }
        }

        for attempt in 0..<2 {
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

        AIDebugTraceStore.shared.append(
            "ICON FALLBACK",
            lastError.map { "Icon generation failed and the local script fallback did not render: \($0.localizedDescription). Saving remains available; HTMLApp will derive a local icon from the document." }
                ?? "The local icon fallback did not render. Saving remains available; HTMLApp will derive a local icon from the document."
        )
        iconScript = ""
        renderedIconData = nil
        return
    }

    private func selfHealBrokenJavaScript(config: AIProviderConfiguration, issues: [String]) async -> Bool {
        let baseline = streamedHTML
        let diagnostic = issues.joined(separator: "\n")
        AIDebugTraceStore.shared.append("SELF HEAL", "Beginning bounded syntax repair. HTML bytes: \(baseline.utf8.count)\n\(diagnostic)")
        phase = "Repairing unresponsive app controls"
        // The original remains in memory until a candidate actually passes the
        // same offscreen JavaScript checks that detected the failure.
        for attempt in 1...1 {
            do {
                let response = try await AIProviderClient.complete(
                    config: config,
                    system: """
                    You are repairing a single-file HTML app that currently contains invalid inline JavaScript.
                    Return a COMPLETE valid <htmlapp_code>...</htmlapp_code> document, NOT SEARCH/REPLACE patches.
                    Prioritize valid parsing and functioning event handlers. Preserve the app UI, IDs, storage keys,
                    native integrations, external endpoints, and existing user data. Change only broken code.
                    Avoid fragile nested strings or dense minified expressions. No Markdown fences.
                    """,
                    messages: [("user", """
                        ORIGINAL HTML:
                        <htmlapp_existing>
                        \(baseline)
                        </htmlapp_existing>

                        EXACT OFFSCREEN WEBVIEW ERRORS:
                        \(diagnostic)

                        Repair attempt: \(attempt). Re-check the complete JavaScript syntax before responding.
                        """)],
                    timeout: 85,
                    maxTokens: 12000,
                    retryOnTransient: false
                )
                let candidate = AIHTMLAgent.parse(response).html
                guard !candidate.trimmed.isEmpty else {
                    AIDebugTraceStore.shared.append("SELF HEAL", "Attempt \(attempt): no complete HTML returned.")
                    continue
                }
                let structural = HTMLQualityChecks.issues(in: candidate)
                let runtime = await HTMLRuntimeVerifier.verify(html: candidate)
                let fatal = HTMLQualityChecks.blockingIssues(structural) +
                    runtime.filter {
                        $0.hasPrefix("JavaScript syntax in inline script") ||
                        $0.hasPrefix("JavaScript did not compile") ||
                        $0.hasPrefix("Runtime: document body rendered empty") ||
                        $0.hasPrefix("Runtime tapability:") ||
                        $0.hasPrefix("uncaught error:")
                    }
                if fatal.isEmpty {
                    streamedHTML = candidate
                    verificationReport += "\nSelf-heal succeeded: complete HTML was checked in the offscreen runtime."
                    AIDebugTraceStore.shared.append("SELF HEAL", "Attempt \(attempt): repaired HTML passed local checks.")
                    return true
                }
                AIDebugTraceStore.shared.append("SELF HEAL", "Attempt \(attempt) still had issues: " + (structural + runtime).joined(separator: "\n"))
            } catch {
                AIDebugTraceStore.shared.append("SELF HEAL", "Attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }
        streamedHTML = baseline
        return false
    }

    /// Deterministic red flags that the actual requested workflow is missing.
    /// This cannot prove live APIs work, so these are explicitly advisory,
    /// never reported as a verified network/location success.
    private static func coreWorkflowWarnings(prompt: String, html: String) -> [String] {
        let goal = prompt.lowercased()
        let code = html.lowercased()
        var warnings: [String] = []
        let routeIntent = (goal.contains("nearest") || goal.contains("nearby")) &&
            (goal.contains("direction") || goal.contains("route"))
        if routeIntent {
            if !code.contains("getcurrentposition") && !code.contains("watchposition") {
                warnings.append("Core workflow: no foreground location request was found.")
            }
            if !code.contains("fetch(") && !code.contains("maps.apple.com") {
                warnings.append("Core workflow: no real nearby-search or map handoff data path was found.")
            }
            if !code.contains("route/v1") && !code.contains("directions") && !code.contains("mapkit") {
                warnings.append("Core workflow: no driving route or directions implementation was found.")
            }
            if !code.contains("miles") && !code.contains("distance") {
                warnings.append("Core workflow: requested distance display is missing.")
            }
        }
        let networkOrLocation = code.contains("fetch(") ||
            code.contains("getcurrentposition") || code.contains("watchposition")
        if networkOrLocation && !code.contains("loading") &&
            !code.contains("finding") && !code.contains("calculating") &&
            !code.contains("progress") {
            warnings.append("Loading UX: no meaningful async loading status found.")
        }
        if networkOrLocation && !code.contains("finally") {
            warnings.append("Loading UX: async cleanup path is missing; a failed request could leave the app busy.")
        }
        return warnings
    }

    private func verifyAndRepair(config: AIProviderConfiguration) async throws {
        try Task.checkCancellation()
        phase = "Testing the app"
        verificationReport = ""
        qaRepairResponseBytes = 0

        let normalized = HTMLQualityChecks.normalizeDocument(streamedHTML)
        if normalized != streamedHTML {
            streamedHTML = normalized
            AIDebugTraceStore.shared.append("LOCAL AUTOFIX", "Added missing doctype or viewport metadata without using AI.")
        }
        let structural = HTMLQualityChecks.issues(in: streamedHTML)
        let functional = Self.coreWorkflowWarnings(prompt: originalPrompt, html: streamedHTML)
        if !functional.isEmpty {
            AIDebugTraceStore.shared.append("CORE WORKFLOW AUDIT", functional.joined(separator: "\n"))
        }
        let testMode = ForgeTestMode.selected
        if testMode == .skip {
            // Keep inexpensive structural warnings visible, but do not pretend to
            // have executed JavaScript or checked any live button.
            verificationReport = "Tests skipped at your request. App behavior and buttons have NOT been verified. " + (structural + functional).joined(separator: " ")
            AIDebugTraceStore.shared.append("QA SKIPPED", verificationReport)
            return
        }
        let runtime = await HTMLRuntimeVerifier.verify(html: streamedHTML, timeout: testMode == .fast ? 3 : 6)

        // Offline preview intentionally blocks some native/device features.
        // Warnings about CSS conventions, remote resources, timeouts,
        // placeholder prose and console noise should not trigger 120-second
        // remote review requests or a chain of full-source rewrites.
        // Missing primary user-requested behavior should receive the same
        // focused repair opportunity as broken JavaScript in balanced QA.
        let blocking = HTMLQualityChecks.blockingIssues(structural) +
            (testMode == .balanced ? functional.filter { $0.hasPrefix("Core workflow:") } : []) +
            runtime.filter { issue in
                issue.hasPrefix("JavaScript syntax in inline script") ||
                issue.hasPrefix("JavaScript did not compile") ||
                issue.hasPrefix("Runtime: document body rendered empty") ||
                issue.hasPrefix("Runtime tapability:") ||
                issue.hasPrefix("uncaught error:") ||
                issue.hasPrefix("Runtime: document became blank")
            }
        let advisory = (structural + runtime + functional).filter { !blocking.contains($0) }
        AIDebugTraceStore.shared.append("QA CLASSIFICATION",
            "Blocking: \(blocking.count); Advisory: \(advisory.count)\n" +
            (blocking + advisory).joined(separator: "\n"))
        if testMode == .fast {
            verificationReport = blocking.isEmpty
                ? "Fast local smoke checks passed (not every button was exercised). " + advisory.joined(separator: " ")
                : "Fast checks found problems; AI repair skipped to save time: " + blocking.joined(separator: " ")
            return
        }
        if blocking.isEmpty {
            verificationReport = advisory.isEmpty
                ? "Local JavaScript, layout and interaction smoke tests passed."
                : "Core app checks passed. Advisory notes: " + advisory.joined(separator: " ")
            return
        }

        // Exactly one focused remote patch request. Do not recursively invoke
        // the patch applier's separate multi-call recovery chain.
        phase = "Repairing confirmed app error"
        let baseline = streamedHTML
        do {
            let response = try await AIHTMLAgent.reviewArtifact(
                html: streamedHTML,
                iconScript: iconScript,
                originalPrompt: originalPrompt,
                research: lastResearch,
                localIssues: blocking,
                pass: 1,
                config: AISettingsStore.configuration(for: .verifier)
            )
            qaRepairResponseBytes = response.utf8.count
            let patch = AIHTMLAgent.patch(from: response)
            let proposed = AIHTMLAgent.parse(response)
            if !patch.trimmed.isEmpty, let fixed = HTMLPatchApplier.apply(patch, to: baseline) {
                streamedHTML = fixed
            } else if !proposed.html.trimmed.isEmpty {
                streamedHTML = proposed.html
            } else {
                AIDebugTraceStore.shared.append("QA PATCH", "Reviewer did not return an applicable patch; retaining existing source.")
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AIDebugTraceStore.shared.append("QA REPAIR ERROR", error.localizedDescription)
        }

        try Task.checkCancellation()
        if streamedHTML != baseline {
            phase = "Retesting changed code"
            let newStructural = HTMLQualityChecks.issues(in: streamedHTML)
            let newRuntime = await HTMLRuntimeVerifier.verify(html: streamedHTML)
            let remaining = HTMLQualityChecks.blockingIssues(newStructural) +
                newRuntime.filter {
                    $0.hasPrefix("JavaScript syntax in inline script") ||
                    $0.hasPrefix("JavaScript did not compile") ||
                    $0.hasPrefix("Runtime: document body rendered empty") ||
                    $0.hasPrefix("Runtime tapability:") ||
                    $0.hasPrefix("uncaught error:") ||
                    $0.hasPrefix("Runtime: document became blank")
                }
            if remaining.isEmpty {
                verificationReport = "Focused repair passed the local checks."
                return
            }
            AIDebugTraceStore.shared.append("QA RETEST", remaining.joined(separator: "\n"))
            if remaining.contains(where: {
                $0.hasPrefix("JavaScript syntax in inline script") || $0.hasPrefix("JavaScript did not compile")
            }) {
                if await selfHealBrokenJavaScript(config: config, issues: remaining) { return }
                streamedHTML = baseline
                throw AIGenerationError.brokenJavaScript
            }
            verificationReport = "Some problems remain after one repair: " + remaining.joined(separator: " ")
            return
        }

        if blocking.contains(where: {
            $0.hasPrefix("JavaScript syntax in inline script") || $0.hasPrefix("JavaScript did not compile")
        }) {
            if await selfHealBrokenJavaScript(config: config, issues: blocking) { return }
            throw AIGenerationError.brokenJavaScript
        }
        verificationReport = "App checks found unresolved issues: " + blocking.joined(separator: " ")
    }

    private func refineGeneratedAssets(_ assets: [AIGeneratedAsset]) async -> [AIGeneratedAsset] {
        guard !assets.isEmpty else { return [] }
        // Render valid draft assets immediately. Calling a second AI artist for
        // every small decorative image adds significant generation latency.
        // Keep optional specialist refinement for users who configured one.
        guard AISettingsStore.usesSpecialistProvider(for: .icon) else {
            AIDebugTraceStore.shared.append("ASSET FAST PATH",
                "Used coding-agent asset drafts directly; skipped redundant artwork model request.")
            return assets
        }
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
        if !output.html.isEmpty {
            if partial {
                latestPartialHTML = HTMLStreamRepair.previewDocument(output.html)
            } else {
                streamedHTML = output.html
                latestPartialHTML = ""
            }
        }
        if !output.description.isEmpty { description = output.description }
        if !output.iconScript.isEmpty { iconScript = output.iconScript }
        if !output.refinedBrief.isEmpty { refinedBrief = output.refinedBrief }
        persistCheckpoint()
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
                let finishReason = (object["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String ?? "unspecified"
                let usage = object["usage"] as? [String: Any]
                let completionTokens = usage?["completion_tokens"] as? Int
                    ?? usage?["output_tokens"] as? Int
                let visibleTokens = usage?["completion_tokens_details"] as? [String: Any]
                let reasoningTokens = visibleTokens?["reasoning_tokens"] as? Int
                let responseMetadata = "Finish: \(finishReason); visible characters: \(text.count); output tokens: \(completionTokens.map { String($0) } ?? "unknown"); reasoning tokens: \(reasoningTokens.map { String($0) } ?? "unknown")"
                await MainActor.run {
                    AIDebugTraceStore.shared.append("AI RESPONSE METADATA", responseMetadata)
                    AIDebugTraceStore.shared.append("AI RESPONSE", text)
                }
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

    // File-backed request for iOS background URLSession. The Authorization
    // header stays on the request; the persisted body contains no API key.
    static func backgroundUploadRequest(
        config: AIProviderConfiguration, system: String, messages: [(String, String)]
    ) throws -> (URLRequest, URL) {
        guard let endpoint = config.endpointURL(),
              endpoint.scheme?.lowercased() == "https" else {
            throw AIGenerationError.invalidEndpoint
        }
        let body = requestBody(config: config, system: system, messages: messages,
                               stream: false, maxTokens: 24_000)
        let data = try JSONSerialization.data(withJSONObject: body)
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForgeBackgroundUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: file, options: .atomic)
        var request = makeRequest(config: config, endpoint: endpoint, timeout: 600)
        request.timeoutInterval = 600
        return (request, file)
    }

    static func backgroundResponseText(_ data: Data, type: AIProviderConfiguration.Compatibility) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text = responseText(object, type: type).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
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
            // Only the first-party OpenAI endpoint is known to support this
            // parameter. Generic OpenAI-compatible proxies may reject it.
            let host = URLComponents(string: config.apiURL)?.host?.lowercased()
            let model = config.model.lowercased()
            let reasoningModel = model.hasPrefix("gpt-5") ||
                model.hasPrefix("gpt-6") || model.hasPrefix("o1") ||
                model.hasPrefix("o3") || model.hasPrefix("o4")
            if ForgeRunOptions.quick,
               UserDefaults.standard.object(forKey: "ai.quickLowReasoning") as? Bool != false,
               host == "api.openai.com", reasoningModel,
               !model.contains("-pro") {
                body["reasoning_effort"] = "low"
            }
            return body
        case .anthropic:
            let list: [[String: String]] = messages.map { ["role": $0.0 == "assistant" ? "assistant" : "user", "content": $0.1] }
            var systemValue: Any = system
            // Only the official Anthropic API is guaranteed to understand
            // cache_control. Keep the stable contract before dynamic research.
            if URLComponents(string: config.apiURL)?.host?.lowercased() == "api.anthropic.com",
               system.count >= 1024 {
                let separators = ["\n\nUSER VISUAL TASTE", "\n\nRESEARCH RESULTS",
                                  "\n\nHTMLAPP RESEARCH", "\n\nUSER REQUEST"]
                let cut = separators.compactMap { system.range(of: $0)?.lowerBound }.min() ?? system.endIndex
                let prefix = String(system[..<cut])
                if prefix.count >= 1024 {
                    var blocks: [[String: Any]] = [[
                        "type": "text", "text": prefix,
                        "cache_control": ["type": "ephemeral"]
                    ]]
                    if cut != system.endIndex {
                        blocks.append(["type": "text", "text": String(system[cut...])])
                    }
                    systemValue = blocks
                }
            }
            return [
                "model": config.model,
                "max_tokens": maxTokens.map { max(64, $0) } ?? 32000,
                "system": systemValue,
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
- Live Activities: HTMLAppNative.liveActivities.start/update/end/list can manage short native running-task status on Lock Screen and Dynamic Island on compatible devices. It cannot display custom HTML or continue arbitrary JavaScript while suspended. Start only by deliberate user action; update on meaningful state changes and end when the task finishes.
- Widgets: HTMLAppNative.widgets.configure/list/remove/reload can publish real Home Screen/Lock Screen WidgetKit widgets. Widget definitions and individual item rows may have action {id,type:open|route|event,route?,payload?}; openBehavior controls whole-widget tapping. Handle signed widget launch data using HTMLAppNative.launch.get() and the htmlapplaunch event. Use widgets for glanceable information or meaningful navigation, not unrelated decoration.
- Background refresh: HTMLAppNative.background.configure/list/remove/refreshNow can register opportunistic iOS BGAppRefresh public-HTTPS JSON fetches that store results in appStorage. iOS chooses actual timing; minimum requested interval is 15 minutes. This does not run arbitrary JavaScript after suspension.
- Bluetooth discovery on iPhone: ALWAYS use HTMLAppNative.bluetooth.scan(6) from a user tap to discover nearby advertising BLE devices (returns {devices:[{id,name,rssi}]}). HTMLApp's native bridge uses CoreBluetooth and asks for permission. Do NOT use navigator.bluetooth, navigator.bluetooth.requestDevice(), a Web Bluetooth chooser, or browser-support warnings for Bluetooth scanning inside HTMLApp: iOS WKWebView does not provide Web Bluetooth. Show an actual list of all returned BLE devices and their RSSI, with empty/permission/error states. Native scan cannot find every paired/Classic Bluetooth device or pair with them. For compatible scanned BLE devices, HTMLAppNative.bluetooth.battery(device.id) can read the standard 0x180F / 0x2A19 accessory battery level; use try/catch and show unavailable when unsupported. HTMLApp also has a requestDevice compatibility chooser backed by native scanning for older generated apps, but prefer the direct native API for new apps.
- Device status: HTMLAppNative.device.battery() returns percentage (nullable), charging, batteryState and thermalState. Poll only while visible; handle unknown readings.
- AI privacy: Forge can optionally research personal data only with explicit AI Privacy toggles. Never hard-code the user's current latitude/longitude, appointments or reminders into a generated app or widget. Request runtime permissions and fetch live data when the actual saved app runs.
- Networking: fetch/WebSocket/EventSource are allowed subject to CORS, server support, and normal security constraints.
- iOS handoffs: documented HTMLAppNative.externalApps.maps and externalApps.shortcuts can open Apple Maps or run a user-installed Shortcut from deliberate user actions. Do not invent other structured adapters.
- Sharing/media/credentials: feature-detect navigator.share/canShare, Media Session, navigator.credentials/WebAuthn, Clipboard, and other optional APIs.

When research contains HTMLAPP DEVICE API CATALOG RESULTS, treat those results as the authoritative runtime reference. Prefer documented HTMLAppNative wrappers for contacts, user-selected Photos media, Calendar, Reminders, local notifications, biometrics, secure storage, portable app storage, generated widgets, opportunistic background JSON refresh, Maps/Shortcuts handoffs, speech, Files, sharing, clipboard, device info, and keep-awake behavior when they match the task. Follow the exact method names and constraints from the catalog; never invent adjacent methods.

Never invent native bridges. HealthKit, HomeKit, NFC, Nearby Interaction, background location, arbitrary continuously running HTML/JavaScript beyond the documented background-fetch/widget mechanisms, remote push updates to Live Activities, CallKit/CarPlay, Apple Pay merchant flows, unrestricted hidden Photo Library enumeration/deletion, and other entitlement-gated frameworks are unavailable to generated HTMLApps unless the device catalog explicitly documents a bridge. If a requested capability is unavailable, build the best honest fallback and expose the limitation rather than simulating success.

Other browser APIs such as USB, Serial, HID, WebGPU, WebXR, Wake Lock, Service Workers, App Badging, Network Information, keyboard APIs, Audio Session, and similar capabilities are feature-detect-only. Presence of an object is not proof the requested operation will succeed; handle rejection and unsupported states.

Before signaling finished, verify the PRIMARY user request has executable paths and functioning controls. The first critical operation must not be a decorative placeholder. For a nearest-place/route app, inspect the live location trigger, place lookup, route request, displayed distance and directions, offline and permission-denied states, and fallback if CORS or public APIs fail. A successful HTML parse is NOT evidence that a request works. Never invent facts, live values, people, accounts, reviews, measurements, availability, prices, API responses, endpoints, or capabilities unless the user explicitly requested fictional/demo/sample content, and label demo data visibly. If real data is needed, use researched documented APIs. Verify endpoint URL, parameters, fields, auth, CORS, and client-side feasibility. If no real source/capability exists, build the best honest local/user-mediated alternative.

Permission-requiring APIs activate only after a meaningful user gesture. Request the minimum access needed. Never embed private API keys or secrets. If user/device data is sent to a remote service, do not claim it stays on-device.

Design from the product rather than a template. Use restrained iOS-quality materials, purposeful typography, strong hierarchy, content-specific identity, and motion that communicates state. Avoid generic SaaS dashboards, excessive glass/glow/gradients, emoji-as-icons, browser alert/confirm for routine feedback, fake avatars/badges, and desktop-first layouts.

Engineering quality is mandatory: meaningful PER-OPERATION loading/empty/error/offline/permission/unsupported states when relevant; ALWAYS show a visible non-blocking progress indicator and specific loading message immediately on tap for geolocation, fetch, search, routing, imports, saves, file reads, and AI/network calls; prevent repeated taps; clear the indicator in finally; keep old results visible on refresh; use aria-live and reduced-motion-safe skeletons; never use an empty visual as a loading indicator; guarded async code; AbortController for racing fetches; safe DOM insertion; cleanup of media tracks, object URLs, listeners, timers, workers, sockets and animation loops; keyboard/focus accessibility; no undefined handlers, placeholder endpoints, fake keys, TODOs, or pseudocode.
"""

    static let iconGuide = """
Draw a distinctive, purpose-specific 1024px icon in IconScript. Use a crisp iOS-style metaphor with restrained layers, clear negative space, a distinct palette and no excessive decorative shapes. Aim for about 8–20 purposeful primitives. Avoid generic teal/green checkmarks. Use SIZE, BG, RECT, CIRCLE, LINE, TRIANGLE and optional FILL_LINEAR, FILL_RADIAL, FILL_TEXTURE; no ANIM, GROUP, FPS or SVG. Draw back-to-front.
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
        guard !clean.isEmpty, clean.count <= 600,
              !needsWebResearch(for: clean) else { return false }
        // Explicitly offline, local-only apps do not need another planning
        // round trip when no iOS device integration is requested.
        if (clean.contains("offline") || clean.contains("local-only") ||
            clean.contains("no internet")) && !needsCapabilityResearch(for: clean) {
            return true
        }
        if clean.contains("habit tracker") || clean.contains("habit tracking") {
            // Notifications are covered by the built-in native API catalog;
            // a second planning model call is unnecessary for ordinary trackers.
            return !clean.contains("sync") && !clean.contains("cloud") && !clean.contains("live data")
        }
        guard !needsCapabilityResearch(for: clean) else { return false }
        let selfContainedSignals = [
            "calculator", "counter", "timer", "stopwatch", "converter", "checklist",
            "notepad", "notes app", "flashcards", "pomodoro", "random picker", "dice roller",
            "packing list", "trip packing", "trip planner", "shopping list", "to-do list",
            "daily journal", "journal", "diary", "simple planner", "meal planner",
            "expense tracker", "budget tracker", "study tracker", "reading log",
            "mood tracker", "workout log", "recipe organizer", "flashcard", "habit checklist"
        ]
        return selfContainedSignals.contains(where: { containsSignal($0, in: clean) })
    }

    static func fastPathCapabilityQueries(for prompt: String) -> [String] {
        let lower = prompt.lowercased()
        var queries: [String] = []
        if lower.contains("remind") || lower.contains("notif") || lower.contains("alert") {
            queries.append("local notification permission scheduling and cancellation")
        }
        if lower.contains("habit") || lower.contains("checklist") || lower.contains("packing") {
            queries.append("local persistence for structured offline data")
        }
        return queries
    }

    static func planPrompt(_ prompt: String, config: AIProviderConfiguration) async throws -> AIPlanningResult {
        let system = """
You are HTMLApp Forge's combined product-planning and capability-research planner. Turn the user's raw app idea into a compact implementation-ready brief AND decide what device/public API research is actually required.

\(ForgeProductContract.rules)

Return exactly one <brief>...</brief>, a one-line <purpose>who, where, why</purpose>, followed by zero or more:
<assumption>reversible assumption to confirm (at most 3)</assumption>
<implied_feature>feature, reason and confidence (at most 3)</implied_feature>
<capability>specific device or public API capability needed</capability>
<mode>fast or polished</mode>
<device_query>concise capability query</device_query>
<query>concise public/web API discovery query</query>

BRIEF REQUIREMENTS:
- Keep the <brief> under 300 words and avoid repeating the user's wording.
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
                config: AISettingsStore.quickModel.isEmpty ? config : ForgeRunOptions.$quick.withValue(true) { AISettingsStore.configuration(for: .planner) },
                system: system,
                messages: [("user", prompt)],
                timeout: 45,
                maxTokens: 1800,
                retryOnTransient: false
            )
            let brief = value("brief", in: text).trimmed
            return AIPlanningResult(
                brief: brief.isEmpty ? prompt : brief,
                research: AIResearchPlan(
                    publicQueries: plannedValues("query", in: text),
                    deviceQueries: plannedValues("device_query", in: text)
                ),
                purpose: String(value("purpose", in: text).trimmed.prefix(220)),
                assumptions: Array(plannedValues("assumption", in: text).prefix(3)),
                impliedFeatures: Array(plannedValues("implied_feature", in: text).prefix(3)),
                capabilities: Array(plannedValues("capability", in: text).prefix(10)),
                recommendedMode: value("mode", in: text).trimmed
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
            text = try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)], timeout: 75, maxTokens: 3000, retryOnTransient: false)
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

REMOTE PUSH AND BACKGROUND VOICE:
- HTMLAppNative.push.register() requests opt-in iOS push registration and returns a token only on APNs-provisioned builds. This does not create a server. Remote notifications require the user's backend to register tokens and send APNs messages; never claim notifications will arrive before that infrastructure exists.
- A web page or WKWebView cannot reliably run custom JavaScript after suspension. Use the native local notification API for on-device reminders. A real walkie-talkie experience needs Apple's PushToTalk framework, approved signing capability, a channel/push server, and a live audio relay. Do not invent a working native PushToTalk API.

HTMLAPP LIVE ACTIVITY COUNTDOWNS AND WIDGETS:
- For any Live Activity representing a timer or deadline, include primaryDeadlineMs and optionally secondaryDeadlineMs as absolute Unix milliseconds in liveActivities.start/update. Native WidgetKit displays these with Text(date, style: .timer), so they continue counting while HTMLApp is suspended. Do NOT rely on one-minute JavaScript calls to refresh strings in the Lock Screen.
- Continue to send strings for fallback content; use liveActivities.update when plans/deadlines actually change, rather than on every second or minute.
- Published widgets are snapshot-based and iOS controls refresh budgets; never promise second-by-second or exact 15-minute background reloads. For countdown widgets, set snapshot.deadlineMs to the absolute Unix timestamp in milliseconds. WidgetKit will display its value with Text(date, style: .timer), even while the extension is inactive. Keep value as readable fallback text.

WIDGET FAMILY COMPLETENESS (REQUIRED WHEN ADDING WIDGETS):
- If the app benefits from a Home Screen widget, implement ALL THREE Home Screen families: systemSmall, systemMedium, and systemLarge. Do not publish just a small widget. Configure a widget definition with families: ["systemSmall","systemMedium","systemLarge"], and make each family useful at its available size: small = essential glanceable metric/action context, medium = richer snapshot, large = detailed summary or multi-item view. WidgetKit owns native family rendering. Avoid text overflow and empty placeholders.
- If the app benefits from Lock Screen widgets, implement ALL THREE Lock Screen families: accessoryCircular (square/circular compact widget), accessoryRectangular (wide rectangle), and accessoryInline (top text line). Configure families: ["accessoryCircular","accessoryRectangular","accessoryInline"]. Make meaningful, legible content for each. Lock Screen widget descriptions may call these square, rectangle, and top text. Use WidgetKit's actual families rather than inventing separate Swift targets.
- If the app supports both Home Screen and Lock Screen widgets, declare all SIX families or provide appropriately distinct widget definitions for each screen. Update widget snapshots/data bindings coherently for every relevant size, and use the actual HTMLAppNative.widgets.configure/list/remove/reload APIs. Do not claim every widget size has a unique custom free-form layout: the host widget extension controls rendering. Show users how to add and configure each kind in the iOS widget picker.
- Never fabricate WidgetKit support, background frequency guarantees, or make a widget when it does not serve the app's purpose.

APP NAME: Use a very short HTML title of one or two words, maximum 12 characters. No tagline, emoji or App suffix.

DEVICE CHROME AND STATUS BAR RULES:
- A saved HTMLApp displays the REAL iOS system status bar by default. During initial generation and functional/visual edits, decide whether keeping that real status bar visible is best for the app; ordinarily keep it visible. Only if an immersive full-screen game, media experience, or similar genuinely benefits from hiding it, include <meta name="htmlapp-status-bar" content="hidden"> inside the generated HTML <head>. To keep it visible, omit this tag. The native host reads it when opening the app. Never fake status bar content in HTML, and preserve the previously chosen visibility during unrelated AI edits.
- NEVER generate or draw a fake iOS status bar, time (9:41), battery indicators, cellular/Wi-Fi signals, notch, Dynamic Island, phone frame, mock iPhone bezel, home indicator, or simulated OS navigation chrome inside an app. HTMLApp runs in a real iOS WebView where the system owns those surfaces. Begin UI content directly with the app's content and respect safe-area insets.
- Do not render a fake CSS bottom tab strip when native tabs are available. A true iOS 26 Liquid Glass tab bar requires the host's UITabBarController; it cannot be recreated reliably with CSS.
- Do not put native status bar or Dynamic Island graphics inside previewHTML/mockups either.

- All apps that need animations should include animations wherever appropriate.\n\nHTMLAPP GESTURES AND REAL NATIVE TAB BARS:
- Use gestures when appropriate: swipe between cards and views, pinch-to-zoom photos/maps where applicable, long-press for contextual options, pull-to-refresh where data can refresh, drag-to-reorder, and tactile feedback. Provide accessible buttons as equivalent actions and avoid accidental destructive gestures.
- For EVERY app with 2–7 top-level destinations, ALWAYS call HTMLAppNative.tabs.configure to create its real native navigation in the installed app. Never use a CSS tab bar as the primary navigation. Implement a working HTML navigation fallback ONLY for editing/preview or when the native bridge is unavailable; hide that fallback immediately when native tabs configure successfully. On real iOS 26, native tab bars can receive the system's Liquid Glass styling; fake HTML tab bars cannot. Bind every tab ID to a working section. Keep a CSS fallback only if capabilities() says the native API is missing and hide it when native tabs are active.
- When editing an older HTMLApp that already has fake bottom navigation, and the user requests native iOS appearance, upgrade it to this bridge without changing the app's screens, state or tab destinations.
- A saved HTMLApp can ask its native iOS host to display a REAL UIKit tab bar (including Apple's native iOS 26 visual material) by calling:
  await HTMLAppNative.tabs.configure({items: [{id:"home",title:"Home",symbol:"house.fill"},{id:"settings",title:"Settings",symbol:"gearshape.fill"}]});
  HTMLAppNative.tabs.onSelect(id => { showView(id); });
  await HTMLAppNative.tabs.select("home");
  await HTMLAppNative.tabs.remove();
- The host owns the tab bar appearance and handling. The generated app owns destinations and content through onSelect. Each item needs a stable unique ASCII id, short title, valid SF Symbol; supply 1 to 7 tabs only. Do NOT draw an overlapping fake CSS bottom tab bar when using native tabs. The host on iOS 26 chooses native materials; HTML cannot force Liquid Glass on earlier iOS releases. Always render a usable HTML fallback while editing or previewing so every page can be navigated; once running in the installed native host, configure the native tab bar and hide the fallback. Preserve the same page IDs and navigation handlers in both modes.
- Native tab items may supply onSelect JavaScript callbacks and an optional badge. Update with HTMLAppNative.tabs.update(id,{badge:""}), hide with tabs.setHidden(true), and animate with tabs.pulse(). Reserve padding-bottom: var(--htmlapp-tabbar-height, 0px) in the HTML page. The host owns system tab visuals.
- Before calling bridge APIs, query await HTMLAppNative.capabilities(); check methods includes "tabs.configure" and avoid invented APIs. Test that each tab selection renders the actual intended screen and that app data persists across switching.

HTMLAPP SF SYMBOLS:
- Generated apps may call await HTMLAppNative.symbols.search("heart") to find supported curated system-symbol names, and await HTMLAppNative.symbols.render("heart.fill") to receive {dataURL} for an <img>. SF Symbols are not a web font: do not pretend arbitrary symbol names work directly in CSS or HTML.
- Call the local catalog before selecting a symbol; render it as an image with descriptive alt text and use CSS filters/tint thoughtfully. Missing symbols must fall back to inline SVG/text. Do not use SF Symbols as app icons or trademarks. The catalog is a safe iOS 16-oriented subset, not every symbol Apple ships.

HTMLAPP APPEARANCE AND FUNCTIONAL CONTROLS:
- Every NEW generated app MUST implement light and dark color palettes, with readable semantic surface, text, border, primary, secondary, and error tokens. Use @media (prefers-color-scheme: dark) and (prefers-color-scheme: light), and apply the tokens throughout; avoid fixed light backgrounds or dark text that become unreadable in the opposite appearance. Keep the selected visual identity in both schemes.
- Provide an explicit accessible Light / Dark / System setting when an app has a Settings screen; persist selection locally and update the root data-theme attribute. System follows prefers-color-scheme changes. Otherwise automatic system switching is mandatory.
- Every visible button, tab, menu item, checkbox, modal confirmation, and form submit must perform an actual meaningful action. Do not ship placeholder click targets, alert-only fake success, dummy navigation, or buttons hidden behind overlays. Use event delegation when DOM content is rerendered and test handlers after each rerender. Handle save/reload and permission failures visibly.
- Favor fewer fully implemented features over many decorative controls. Mentally walk the first-run empty state, create/edit/delete flow, navigation, persistence, and error recovery before responding.

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
You are HTMLApp's code-editing agent. Preserve the existing HTML title unless the user asks for a rename. Edit the existing single-file HTML app with the smallest safe patch that satisfies the requested change. Preserve all unrelated behavior, IDs, storage keys, API integrations, permissions, navigation and working code. Prefer patching over rewriting.
If adding Home Screen widgets, support all three WidgetKit families (systemSmall, systemMedium, systemLarge); if adding Lock Screen widgets, support all three (accessoryCircular, accessoryRectangular, accessoryInline). If supporting both screens, declare all six or equivalent screen-specific configurations. Use actual HTMLAppNative.widgets.configure families, not invented APIs.
Keep the saved app's real iOS status bar visible by default. When an immersive redesign genuinely needs to hide it, place <meta name="htmlapp-status-bar" content="hidden"> in the HTML head; otherwise omit it. Preserve the current visibility in unrelated edits. Never draw a fake status bar or Dynamic Island.

Return these sections with no Markdown fences:
<ui_polish_needed>yes or no</ui_polish_needed>
<edit_summary>Exactly one plain-language sentence about the changes actually made.</edit_summary>
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
Decide if <ui_polish_needed> should be yes. Say yes ONLY when the requested edit significantly changes visual identity, layout hierarchy, theme, or multiple screens and a separate UI specialist could meaningfully help. Say no for bug fixes, functional changes, wording, colors on one component, and ordinary small revisions; do not waste a specialist call.
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
        config: AIProviderConfiguration,
        onPartialScript: (@MainActor (String) async -> Void)? = nil
    ) async throws -> String {
        let system = """
You design crisp, high-quality iOS-style app icons. Each icon needs ONE recognizable product-specific metaphor with good contrast, comfortable negative space, balanced proportions and refined but restrained depth. The artwork should look at home beside Apple's iOS apps, not like a dense illustration or a screenshot.
Aim for about 8–20 purposeful shape commands, not 40 or 50. Prefer one clear focal symbol and a few supporting highlights or layers. No tiny ornaments, clutter, random sparkles, repetitive concentric rings, or gratuitous gradients. Gradients and shadows are optional, not mandatory.
CRITICAL: Avoid the recurring generic icon template: dark navy rounded-square background, centered circle/dot, down-pointing triangle, and white parallel strokes. These shapes are not an acceptable fallback for unrelated apps. Do not reuse an abstract pin/radar glyph; draw an object identifiable with this specific app's purpose. Vary silhouette, composition, palette, and depth. Regeneration MUST choose a different metaphor and arrangement from the previous script. Do not draw an extra rounded-square border: iOS applies its own mask.
Every app should still have its own distinctive color palette and meaningful subject-specific symbolism. Do not fall back automatically to green, teal, checklist ticks, generic colored discs, or identical arrangements. Respect any user visual preference when appropriate.
Return only IconScript commands, each on its own line: SIZE 1024 1024, BG #RRGGBB, FILL #RRGGBB to set the current drawing color, and RECT x y width height / CIRCLE cx cy radius / LINE x1 y1 x2 y2 thickness / TRIANGLE x1 y1 x2 y2 x3 y3. Each shape inherits the most recent FILL. You may alternatively append a #RRGGBB color to a shape line. FILL_LINEAR, FILL_RADIAL, FILL_TEXTURE are allowed before a shape with two hex colors. Use an opaque background and at least one clearly visible foreground subject. No SVG, HTML, Markdown, lettering, emoji or comments.
"""
        let context = iconDesignBrief(html: html, originalPrompt: originalPrompt) + "\n" + AISettingsStore.creativeDirection
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
                let response: String
                if let onPartialScript, retry == 1 {
                    var streamed = ""
                    let chunks = try await AIProviderClient.stream(
                        config: config,
                        system: system,
                        messages: [("user", user)]
                    )
                    var lastYield = Date.distantPast
                    for try await chunk in chunks {
                        try Task.checkCancellation()
                        streamed += chunk
                        if Date().timeIntervalSince(lastYield) >= 0.45 {
                            await onPartialScript(iconScriptFromProviderResponse(streamed))
                            lastYield = Date()
                        }
                    }
                    response = streamed
                    await onPartialScript(iconScriptFromProviderResponse(streamed))
                } else {
                    response = try await AIProviderClient.complete(
                        config: config,
                        system: system,
                        messages: [("user", user)],
                        timeout: 75,
                        maxTokens: 3200,
                        retryOnTransient: false
                    )
                }
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
            return "The icon is too sparse and generic. Add product-specific composition or depth while keeping it legible at small size."
        }
        guard shapeKinds.count >= 2 else {
            return "The icon relies on only one primitive type. Add purposeful supporting geometry so the concept reads as designed rather than autogenerated."
        }
        if shapeCommands.count > 30 {
            return "The icon is too intricate for an iOS Home Screen. Keep one distinct metaphor, a few balanced layers, and typically 8–20 intentional shapes."
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
UI palette candidates (not mandatory): \(colors.isEmpty ? "Choose a distinctive product-specific palette." : colors.joined(separator: ", "))
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
You repair a generated single-file HTML app using a focused defect list produced by a local WebKit test.
Fix ONLY the specified failures, preserving all unrelated working controls and storage keys.
Return a minimal unique SEARCH/REPLACE patch under <htmlapp_patch>...</htmlapp_patch>.
If the source cannot be patched safely, return a complete <htmlapp_code>...</htmlapp_code>.
Avoid rewriting for visual taste; do not claim other tests have run.
"""
        let user = """
REVIEW PASS: \(pass)

ORIGINAL PROMPT:
\(originalPrompt)

LOCAL STATIC / OFFSCREEN RUNTIME EVIDENCE:
\(localIssues.isEmpty ? "No local or offscreen runtime warnings." : localIssues.joined(separator: "\n"))

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
        return try await AIProviderClient.complete(config: config, system: system, messages: [("user", user)], timeout: 65, maxTokens: 4500, retryOnTransient: false)
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

    static func editNeedsPolish(response: String, requestedChange: String) -> Bool {
        let decision = value("ui_polish_needed", in: response).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if decision == "yes" { return true }
        if decision == "no" { return false }
        // Older providers without the tag still skip unnecessary extra requests.
        let text = requestedChange.lowercased()
        return ["redesign entire", "redesign the app", "whole ui", "entire interface", "new design language",
                "new visual style", "complete makeover"].contains { text.contains($0) }
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

    static func value(_ tag: String, in text: String) -> String { values(tag, in: text).first ?? "" }
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
    /// Correct trivial, deterministic document metadata locally before doing
    /// any expensive AI review. Do not inject layout CSS or modify app logic.
    static func normalizeDocument(_ html: String) -> String {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return html }
        var result = html
        if !result.lowercased().contains("<!doctype html") {
            result = "<!DOCTYPE html>\n" + result
        }
        if !result.lowercased().contains("name=\"viewport\"") &&
           !result.lowercased().contains("name='viewport'"),
           let head = result.range(of: #"<head\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            result.insert(contentsOf: "\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">", at: head.upperBound)
        }
        return result
    }

    static func blockingIssues(_ issues: [String]) -> [String] {
        issues.filter { issue in
            issue.hasPrefix("Unbalanced ") ||
            issue.hasPrefix("Contains an unresolved generated-asset token")
        }
    }

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
        if count("<body", in: lower) != count("</body>", in: lower) { issues.append("Unbalanced <body> tags.") }
        if count("<html", in: lower) != count("</html>", in: lower) { issues.append("Unbalanced <html> tags.") }
        if lower.contains("alert(") { issues.append("Uses browser alert(); routine feedback should use in-app UI.") }
        if lower.contains("confirm(") { issues.append("Uses browser confirm(); destructive confirmation should use in-app UI.") }
        if lower.contains("example.com") || lower.contains("your_api_key") || lower.contains("api-key-here") { issues.append("Contains a likely placeholder endpoint or key.") }
        if html.contains("{{HTMLAPP_ASSET:") { issues.append("Contains an unresolved generated-asset token.") }

        let ids = captures(#"(?i)\bid\s*=\s*["']([^"']+)["']"#, in: html)
        let duplicateIDs = Dictionary(grouping: ids, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        if !duplicateIDs.isEmpty {
            issues.append("Duplicate DOM id values: " + duplicateIDs.prefix(8).joined(separator: ", ") + ".")
        }

        let referencedIDs =
            captures(#"(?i)getElementById\(\s*["']([^"']+)["']\s*\)"#, in: html) +
            captures(#"(?i)querySelector\(\s*["']#([^"']+)["']\s*\)"#, in: html)
        let knownIDs = Set(ids)
        let missingIDs = Set(referencedIDs.filter { !knownIDs.contains($0) }).sorted()
        if !missingIDs.isEmpty {
            issues.append("JavaScript references missing DOM id values: " + missingIDs.prefix(8).joined(separator: ", ") + ".")
        }

        if matches(#"(?is)<script\b[^>]*\bsrc\s*=\s*["']https?://"#, in: html)
            || matches(#"(?is)<link\b[^>]*\brel\s*=\s*["']stylesheet["'][^>]*\bhref\s*=\s*["']https?://"#, in: html) {
            issues.append("Contains remote script or stylesheet dependencies; generated HTMLApps should remain self-contained and offline-capable.")
        }
        return issues
    }

    private static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

actor HTMLAppPublicAPICatalogCache {
    static let shared = HTMLAppPublicAPICatalogCache()
    private var text: String?
    private var fetchedAt = Date.distantPast

    func read(_ url: URL) async -> String? {
        if let text, Date().timeIntervalSince(fetchedAt) < 86_400 { return text }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
        request.setValue("HTMLApp/1.6", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              data.count < 3_000_000,
              let decoded = String(data: data, encoding: .utf8) else { return text }
        text = decoded
        fetchedAt = Date()
        return decoded
    }
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
        await HTMLAppPublicAPICatalogCache.shared.read(url)
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
