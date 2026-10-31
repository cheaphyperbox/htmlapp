import UserNotifications
import SwiftUI
import UIKit

struct AIGenerationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var dictation = ForgeDictation()
    @StateObject private var forgeConnectivity = HTMLAppForgeConnectivity()
    @State private var showingOfflineConsent = false
    @State private var offlineActionIsEdit = false
    @State private var offlineUnavailableMessage: String?
    @State private var dictationPrefix = ""
    @State private var nextRequestFromVoice = false
    @State private var dictationForEdit = false
    @State private var generationTask: Task<Void, Never>?
    @State private var polishTask: Task<UIOverhaulResult, Error>?
    @State private var skipUIPolish = false
    @State private var forgeActivityJobID: String?
    @State private var forgeActivityStartTask: Task<Void, Never>?
    @StateObject private var session = AIGenerationSession()
    @StateObject private var browserResearch = AgenticBrowserResearch()
    @StateObject private var milestones = ForgeBuildMilestones()
    @StateObject private var workTracker = ForgeWorkTracker()
    @State private var draftWorkID = "draft-\(UUID().uuidString)"
    @State private var microphoneTranslation: CGSize = .zero
    @State private var microphoneArmed = false
    @State private var microphoneCapturing = false
    @State private var promptDictationActive = false
    @State private var promptMicHeld = false
    @State private var promptDictationAwaitingResult = false
    @State private var generateAfterVoiceTranscription = false
    @State private var widgetTapRecordingFinished = false
    @State private var importedDraftLoaded = false
    @State private var microphoneRecordingTask: Task<Void, Never>?
    @State private var microphoneEditNotice: String?
    @State private var pendingFloatingVoiceFeedback: Bool?
    @ObservedObject private var debugTrace = AIDebugTraceStore.shared
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("forgeTestMode") private var forgeTestMode = ForgeTestMode.fast.rawValue
    @AppStorage("ai.stylePickerEnabled") private var stylePickerEnabled = true
    @AppStorage("ai.quickMode.policy") private var quickModePolicy = "automatic"
    @State private var quickMode = false
    @State private var showHurryUp = false
    @State private var hurriedThisRun = false
    @State private var autoQuickReason: String?
    @State private var polishThisRun = false
    @State private var exploringStyles = false
    @State private var preparedStylePrompt: String?
    @State private var preparedStyleTask: Task<(String, AIPlanningResult?), Never>?
    @State private var styleOptions: [ForgeStyleConcept] = []
    @State private var styleRegenerationRound = 0
    @State private var runtimeErrors: [String] = []
    @State private var showingRuntimeErrors = false
    @State private var selectedStyleIndex = 0
    @State private var styleFailure: String?
    @State private var styleFeedback = ""
    @State private var purposeGuess = ""
    @State private var purposeEdited = false
    @State private var showingStyleFeedback = false
    @State private var styleFeedbackNotice: String?
    @State private var selectedStyle: ForgeStyleConcept?
    @State private var prompt = ""
    @State private var changePrompt = ""
    @State private var unsavedEditHistory: [String] = []
    @State private var rewriteApprovalPending = false
    @State private var rewriteApproved = false
    @State private var rewriteCheckedPrompt: String?
    @State private var showingChange = false
    @State private var saving = false
    @State private var showCancelConfirmation = false
    @State private var uiPolishNotice: String?
    @State private var didLoadExisting = false
    @State private var showDebug = false
    @State private var showDetails = false
    @State private var showRunHistory = false
    @State private var recoverableDraft: ForgeDraftCheckpoint?
    @State private var showDraftRecovery = false
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    @State private var lastFailedChange: String?
    @State private var handledShortcutNonce = 0
    @State private var activeShortcutPrompt = ""
    @State private var pendingChoiceQuestion = false
    @State private var choiceResponse = ""
    @State private var questionTimer: Task<Void, Never>?
    @State private var questionAlreadyAsked = false
    @State private var customQuestionAnswer = ""
    @State private var questionTitle = "Which direction should Forge prioritize?"
    @State private var questionChoices = ["More visual detail", "Simple and fast"]
    @State private var suggestedAnswer = "Simple and fast"

    private let starterPrompts = [
        "A simple homework planner that works offline",
        "A clean habit tracker with reminders",
        "Flashcards for studying any subject",
        "A useful daily checklist with a widget"
    ]

    let existingApp: SavedHTMLApp?
    let demoMode: Bool
    @State private var showPracticeEditNotice = false
    @State private var practiceStep = 0

    let shortcutGenerationNonce: Int
    let shortcutSource: String
    let importedDraft: RemoteHTMLImportDraft?
    private var isWidgetVoiceEntry: Bool { shortcutSource == "widgetMic" && existingApp == nil }

    init(existingApp: SavedHTMLApp? = nil, initialPrompt: String = "",
         shortcutGenerationNonce: Int = 0, shortcutSource: String = "siri",
         importedDraft: RemoteHTMLImportDraft? = nil, demoMode: Bool = false) {
        self.existingApp = existingApp
        self.shortcutGenerationNonce = shortcutGenerationNonce
        self.shortcutSource = shortcutSource
        self.importedDraft = importedDraft
        self.demoMode = demoMode
        _prompt = State(initialValue: demoMode ? "Make a simple calculator" : initialPrompt)
    }

    var body: some View {
        NavigationStack {
            Group {
                if ForgeBackgroundUpload.shared.isActive {
                    backgroundForgePendingView
                } else if existingApp == nil && (exploringStyles || !styleOptions.isEmpty || styleFailure != nil) {
                    styleSelectionView
                } else if session.streamedHTML.isEmpty && !session.isWorking && !browserResearch.isBrowsing {
                    promptView
                } else {
                    studioView
                }
            }
            .htmlAppFirstUseToasts()
            .navigationTitle(importedDraft != nil ? "Edit imported HTML" : existingApp == nil ? "Generate" : "Edit with AI")
            .alert("Full app rewrite required?", isPresented: $rewriteApprovalPending) {
                Button("Rewrite Entire App", role: .destructive) {
                    rewriteApproved = true
                    applyAIChange()
                }
                Button("Cancel", role: .cancel) {
                    rewriteApproved = false
                    rewriteCheckedPrompt = nil
                }
            } message: {
                Text("The AI determined this overhaul cannot be completed safely with patches. A complete rewrite will replace the current unsaved HTML. You can undo it afterward.")
            }
            .alert(practiceStep >= 5 ? "Practice complete!" : "Practice edit", isPresented: $showPracticeEditNotice) {
                Button("Continue Practicing", role: .cancel) {}
            } message: {
                Text("You practiced Forge without sending an AI request or saving anything to your Library.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if demoMode { generationTask?.cancel(); dismiss(); return }
                        if ForgeBackgroundUpload.shared.isActive || exploringStyles || !styleOptions.isEmpty || styleFailure != nil || session.isWorking || browserResearch.isBrowsing || !session.streamedHTML.isEmpty {
                            showCancelConfirmation = true
                        } else {
                            AIDebugTraceStore.shared.finish(outcome: "Canceled before starting")
                            microphoneRecordingTask?.cancel()
                            dictation.cancel()
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
                if !unsavedEditHistory.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            guard !session.isWorking, !saving,
                                  let previous = unsavedEditHistory.popLast() else { return }
                            session.acceptExternalHTML(previous)
                            uiPolishNotice = "Restored an earlier unsaved edit."
                        } label: { Label("Undo Edit", systemImage: "arrow.uturn.backward") }
                        .disabled(session.isWorking || saving)
                    }
                }
                if developerMode && (debugTrace.isActive || !debugTrace.history.isEmpty) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { showDebug = true } label: { Image(systemName: "ladybug") }
                            .accessibilityLabel("View AI debug trace")
                    }
                }
            }
            .sheet(isPresented: $showingOfflineConsent) {
                HTMLAppOfflineForgeConsentView(isEdit: offlineActionIsEdit) { effort in
                    runOfflineForge(edit: offlineActionIsEdit, effort: effort)
                }
            }
            .alert("Offline Forge unavailable", isPresented: Binding(
                get: { offlineUnavailableMessage != nil },
                set: { if !$0 { offlineUnavailableMessage = nil } }
            )) {
                Button("OK", role: .cancel) { offlineUnavailableMessage = nil }
            } message: {
                Text(offlineUnavailableMessage ?? "This device cannot use offline Apple Intelligence.")
            }
            .sheet(isPresented: $pendingChoiceQuestion, onDismiss: {
                if !questionAlreadyAsked { return }
                resolveCreationQuestion(answer: choiceResponse.isEmpty ? "Choose the most practical option" : choiceResponse)
            }) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("One quick question").font(.title2.bold())
                        Text(questionTitle)
                            .font(.headline)
                        Text("Forge will choose a sensible default after 20 seconds if you don't answer.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(questionChoices, id: \.self) { option in
                            Button {
                                choiceResponse = option
                                pendingChoiceQuestion = false
                            } label: {
                                HStack { Text(option); Spacer(); Image(systemName: "chevron.right") }
                                    .padding()
                            }
                            .buttonStyle(.bordered)
                        }
                        TextField("Or describe your preference", text: $customQuestionAnswer, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        Button("Use my answer") {
                            choiceResponse = customQuestionAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                            pendingChoiceQuestion = false
                        }.buttonStyle(.borderedProminent)
                            .disabled(customQuestionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Forge Question")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Let Forge choose") {
                                choiceResponse = suggestedAnswer
                                pendingChoiceQuestion = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDebug) {
                AIDebugTraceView()
            }
            .confirmationDialog(
                existingApp == nil ? "Discard this AI generation?" : "Discard AI edits?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard and Close", role: .destructive) {
                    generationTask?.cancel()
                    ForgeBackgroundUpload.shared.cancel()
                    preparedStyleTask?.cancel()
                    preparedStyleTask = nil
                    preparedStylePrompt = nil
                    endForgeActivity()
                    dictation.stop()
                    AIDebugTraceStore.shared.finish(outcome: "Discarded")
                    workTracker.finish(outcome: "Discarded")
                    session.clearCheckpoint()
                    styleOptions = []
                    styleFailure = nil
                    exploringStyles = false
                    dismiss()
                }
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text(existingApp == nil ? "The style previews and current AI work will be lost if you close without saving." : "Your saved HTMLApp will not be changed unless you choose Save Changes.")
            }
            .alert("Forge couldn’t finish that step", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button(retryButtonTitle) {
                    session.errorMessage = nil
                    retryLastFailure()
                }
                Button("Dismiss", role: .cancel) { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "")
            }
            .confirmationDialog("Resume Forge draft?", isPresented: $showDraftRecovery, titleVisibility: .visible) {
                Button("Continue Generation") { continueRecoveredDraft() }
                Button("Discard Draft", role: .destructive) {
                    preparedStyleTask?.cancel()
                    preparedStyleTask = nil
                    preparedStylePrompt = nil
                    ForgeDraftCheckpointStore.clear()
                    recoverableDraft = nil
                    generationTask?.cancel()
                    dismiss()
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                if let draft = recoverableDraft {
                    Text("Interrupted during \(draft.phase). Generation had run for \(Self.durationText(draft.savedAt.timeIntervalSince(draft.startedAt ?? draft.savedAt))). Continue will restore the checkpoint and restart the interrupted AI request using your original prompt; the provider may charge again.")
                }
            }
            .sheet(isPresented: $showRunHistory) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForgeWorkRing(runs: workTracker.recentRuns,
                                          active: session.isWorking || browserResearch.isBrowsing)
                            ForgeRunBreakdown(runs: workTracker.recentRuns)
                        }
                        .padding(18)
                    }
                    .navigationTitle("AI Work History")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showRunHistory = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $showDetails) {
                ForgeDetailsView(
                    plan: session.refinedBrief,
                    research: browserResearch.lastReport,
                    qa: session.verificationReport,
                    debug: developerMode ? debugTrace.text : ""
                )
            }
        }
        .task {
            workTracker.select(appKey: existingApp?.id ?? draftWorkID)
            if let importedDraft, !importedDraftLoaded {
                importedDraftLoaded = true
                let now = Date()
                let source = SavedHTMLApp(
                    id: "unsaved-import-\(UUID().uuidString)", name: importedDraft.name,
                    summary: "Imported from \(importedDraft.sourceURL.host ?? "the web")",
                    html: importedDraft.html, favicon: nil, createdAt: now,
                    updatedAt: now, lastOpenedAt: nil, isFavorite: false,
                    folderName: nil, folderID: nil, websiteSourceURL: nil,
                    websiteFingerprint: nil
                )
                session.load(existing: source)
                showingChange = true
                prompt = "Improve the imported HTML app while preserving its working features."
            }
            if let existingApp, !didLoadExisting {
                didLoadExisting = true
                session.load(existing: existingApp)
                selectedStyle = ForgeStyleReferenceStore.load(for: existingApp.id)
            }
            if !demoMode && recoverableDraft == nil,
               let draft = ForgeDraftCheckpointStore.load(),
               draft.existingAppID == existingApp?.id,
               Self.isRecoverable(draft) {
                recoverableDraft = draft
                if shortcutGenerationNonce == 0 { showDraftRecovery = true }
            }
            acceptShortcutRequest(shortcutGenerationNonce, incoming: UserDefaults.standard.string(forKey: "htmlapp.shortcut.activeIdea") ?? prompt)
            restoreCompletedBackgroundDraft()
        }
        .onChange(of: shortcutGenerationNonce) { nonce in
            // Library sends a new nonce even if this screen is already open.
            // Receive the new prompt and start again only after canceling
            // the previous generation, without auto-saving anything.
            acceptShortcutRequest(nonce, incoming: UserDefaults.standard.string(forKey: "htmlapp.shortcut.activeIdea") ?? activeShortcutPrompt)
        }
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: ForgeBackgroundUpload.finishedNotification)) { _ in
            restoreCompletedBackgroundDraft()
            if let draft = ForgeDraftCheckpointStore.load(), draft.phase == "Background request failed" {
                session.phase = "Background request failed"
                uiPolishNotice = "The background request could not finish. Your previous draft was kept."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HTMLAppForgeBackgroundExpired"))) { _ in
            guard !demoMode else { return }
            session.persistCheckpoint()
            generationTask?.cancel()
        }
        .onDisappear {
            if !session.isWorking {
                preparedStyleTask?.cancel()
                preparedStyleTask = nil
                preparedStylePrompt = nil
            }
            if demoMode { generationTask?.cancel() }
            microphoneRecordingTask?.cancel(); dictation.cancel()
            // Do not cancel the generation merely because the view disappears.
            // Keep a checkpoint and allow the finite iOS background grace period.
            if !demoMode && session.isWorking { session.persistCheckpoint() }
        }
        .onChange(of: scenePhase) { value in
            if value == .active {
                restoreCompletedBackgroundDraft()
            }
            if value != .active {
                microphoneRecordingTask?.cancel()
                microphoneCapturing = false
                microphoneArmed = false
                microphoneTranslation = .zero
                if isWidgetVoiceEntry {
                    generateAfterVoiceTranscription = false
                    promptMicHeld = false
                    dictation.cancel()
                } else {
                    dictation.stop()
                }
                persistDraftForBackground()
                if value == .background {
                    // Audible, user-selected music may keep a foreground-style
                    // Forge task executing after lock. Preserve the existing
                    // generation pipeline rather than paying for a second request.
                    // Use background URLSession when music isn't playing.
                    if !BackgroundKeepAlive.shared.isRunning && !GenerationMusic.shared.isPlaying && !GenerationMusic.shared.isGenerationActive {
                        handoffForgeToBackgroundURLSession()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: GenerationMusic.playbackPausedNotification)) { _ in
            // If playback is paused by the user or the audio route changes,
            // switch to the supported file-backed background request while
            // the iOS background task still has time to submit it.
            if scenePhase == .background { handoffForgeToBackgroundURLSession() }
        }
        .onChange(of: prompt) { _ in
            if !session.isWorking && !exploringStyles {
                if quickModePolicy == "automatic" { autoQuickReason = nil }
                purposeGuess = ""
                purposeEdited = false
            }
        }
        .onChange(of: dictation.transcribingOffline) { processing in
            if !processing && generateAfterVoiceTranscription {
                generateAfterVoiceTranscription = false
                let words = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty {
                    prompt = dictationPrefix + (dictationPrefix.isEmpty ? "" : "\n") + words
                    nextRequestFromVoice = true
                }
                submitPromptGeneration()
            }
            guard !processing, let forFeedback = pendingFloatingVoiceFeedback else { return }
            pendingFloatingVoiceFeedback = nil
            let words = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else {
                microphoneEditNotice = "Whisper could not transcribe that recording."
                if forFeedback { showingStyleFeedback = true } else { showingChange = true }
                return
            }
            if forFeedback {
                styleFeedback = words
                styleFeedbackNotice = "Regenerating all looks from spoken feedback."
                exploreStyleOptions()
            } else {
                changePrompt = words
                showingChange = true
                applyAIChange()
            }
        }
        .onChange(of: dictation.recording) { recording in
            if isWidgetVoiceEntry && !recording && !dictation.requestingPermission {
                promptMicHeld = false
                promptDictationActive = false
                widgetTapRecordingFinished = true
            }
        }
        .onChange(of: dictation.transcript) { value in
            // Drag-edit dictation is committed only on release; never overwrite a
            // typed request, and never clear the creation prompt on cancellation.
            guard !microphoneCapturing else { return }
            let merged = dictationPrefix + (dictationPrefix.isEmpty || value.isEmpty ? "" : "\n") + value
            if dictationForEdit { changePrompt = merged }
            else if promptDictationAwaitingResult && (!promptMicHeld || isWidgetVoiceEntry) {
                prompt = merged
                if !value.isEmpty && !promptMicHeld { promptDictationAwaitingResult = false }
            }
        }
        .onChange(of: session.refinedBrief) { brief in
            if !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                milestones.add(.plan, "App plan ready", bytes: brief.utf8.count, key: "prompt-plan")
            }
        }
        .onChange(of: browserResearch.completedPages) { pages in
            for page in pages {
                milestones.add(.website, "Read \(page.host)", bytes: page.bytes, key: "web-\(page.id)")
                workTracker.transition(.research)
                workTracker.updateVolume(page.bytes)
            }
        }
        .onChange(of: browserResearch.status) { status in
            workTracker.observe(phase: session.phase, isBrowsing: browserResearch.isBrowsing,
                                browserStatus: status, streamSection: session.streamedSection)
        }
        .onChange(of: session.streamedSection) { part in
            workTracker.observe(phase: session.phase, isBrowsing: browserResearch.isBrowsing,
                                browserStatus: browserResearch.status, streamSection: part)
        }
        .onChange(of: session.sectionByteCounts) { parts in
            for (key, bytes) in parts {
                let stage: ForgeWorkSlice.Stage = key == "script" ? .script : (key == "body" ? .body : .css)
                workTracker.updateVolume(bytes, stage: stage)
            }
        }
        .onChange(of: session.qaRepairResponseBytes) { bytes in
            workTracker.updateVolume(bytes, stage: .repair)
        }
        .onChange(of: session.iconScript) { script in
            workTracker.updateVolume(script.utf8.count, stage: .icon)
        }
        .onChange(of: session.streamedByteCount) { bytes in
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                HTMLAppForgeContinuedProcessing.update(phase: session.phase, streamedBytes: bytes)
            }
            #endif
        }
        .onChange(of: session.streamedHTML) { html in
            milestones.inspectHTML(html)
        }
        .onChange(of: session.errorMessage) { message in
            if let message, AIDebugTraceStore.shared.isActive {
                AIDebugTraceStore.shared.append("ERROR DETAILS",
                    "Phase: \(session.phase)\nFailure: \(message)\nHTML: \(session.streamedHTML.utf8.count) bytes")
            }
        }
        .onChange(of: session.verificationReport) { report in
            if !report.isEmpty && AIDebugTraceStore.shared.isActive {
                AIDebugTraceStore.shared.append("APP QA REPORT", report)
            }
        }
        .onChange(of: session.wantsUIPolish) { needed in
            if AIDebugTraceStore.shared.isActive {
                AIDebugTraceStore.shared.append("UI SPECIALIST DECISION", needed ? "Requested" : "Skipped")
            }
        }
        .onChange(of: session.phase) { phase in
            if phase.localizedCaseInsensitiveContains("overhaul") || phase.localizedCaseInsensitiveContains("polish") { HTMLAppFirstUseTips.show("polish") }
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                HTMLAppForgeContinuedProcessing.update(phase: phase, streamedBytes: session.streamedByteCount)
            }
            #endif
            if let job = forgeActivityJobID {
                if #available(iOS 16.2, *) {
                    Task { await HTMLAppForgeActivityService.update(job: job, phase: phase) }
                }
            }
            workTracker.observe(phase: phase, isBrowsing: browserResearch.isBrowsing,
                                browserStatus: browserResearch.status, streamSection: session.streamedSection)
            if debugTrace.isActive { AIDebugTraceStore.shared.append("PHASE", phase) }
            if phase == "Generating live preview" {
                milestones.add(.api, "Capabilities checked", bytes: browserResearch.lastReport.utf8.count, key: "api-phase")
            }
            if phase.contains("icon") && (phase.contains("Checking") || phase.contains("Designing")) {
                milestones.add(.icon, "App icon designed", bytes: session.iconScript.utf8.count, key: "icon")
            }
            if phase == "Ready to review" {
                milestones.add(.test, "App checks completed", bytes: session.verificationReport.utf8.count, key: "checks")
            }
        }
    }

    private var currentProgressNote: String {
        if browserResearch.isBrowsing { return browserResearch.progressNote }
        if session.isWorking { return session.progressNote }
        if let uiPolishNotice { return uiPolishNotice }
        if !session.verificationReport.isEmpty { return "Ready to try. Runtime QA ran in an isolated preview; final behavior still needs an on-device try." }
        return session.progressNote
    }

    private var retryButtonTitle: String {
        if lastFailedChange != nil { return "Retry Edit" }
        if let failed = session.failedPhase,
           failed.contains("icon") || failed.contains("app checks") || failed.contains("Reviewing") || failed.contains("Rechecking") {
            return "Retry Checks"
        }
        return "Retry"
    }

    private var promptView: some View {
        Form {
            Section {
                if demoMode {
                    Label("PRACTICE 1 OF 5 · Edit the sample idea below, then tap Make My App. No AI calls or Library changes will occur.", systemImage: "hand.tap.fill")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                if existingApp == nil && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(starterPrompts, id: \.self) { starter in
                                Button(starter) {
                                    prompt = starter
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                TextEditor(text: $prompt)
                    .frame(height: 150)
                    .font(.body)
                HStack(spacing: 14) {
                    if isWidgetVoiceEntry && !widgetTapRecordingFinished {
                        Button {
                            if promptMicHeld || dictation.recording || dictation.requestingPermission {
                                stopPromptRecording()
                                widgetTapRecordingFinished = true
                            } else {
                                startPromptRecording()
                            }
                        } label: {
                            Image(systemName: promptMicHeld ? "stop.fill" : "mic.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .frame(width: 86, height: 86)
                                .scaleEffect(promptMicHeld ? 1.25 : 1)
                                .foregroundStyle(dictation.recording ? Color.white : Color.primary)
                                .background(dictation.recording ? Color.red : Color(.systemGray4),
                                            in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(promptMicHeld ? "Tap to stop recording" : "Tap to start recording")
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .frame(width: 86, height: 86)
                                .scaleEffect(promptMicHeld ? 1.25 : 1)
                            .foregroundStyle(dictation.recording ? Color.white : Color.primary)
                            .background(dictation.recording ? Color.red : Color(.systemGray4),
                                        in: RoundedRectangle(cornerRadius: 24))
                            .contentShape(RoundedRectangle(cornerRadius: 24))
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !promptMicHeld { startPromptRecording() }
                                    }
                                    .onEnded { _ in stopPromptRecording() }
                            )
                            .accessibilityAction {
                                if dictation.recording || promptMicHeld { stopPromptRecording() }
                                else { startPromptRecording() }
                            }
                            .accessibilityLabel("Hold to dictate app idea")
                            .accessibilityHint("Hold down the microphone while you speak, then release.")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isWidgetVoiceEntry && !widgetTapRecordingFinished && promptMicHeld ? "Listening…" : (dictation.recording ? "Listening…" : "Hold to talk"))
                            .font(.headline)
                        Text(isWidgetVoiceEntry && !widgetTapRecordingFinished
                             ? (promptMicHeld ? "Tap to stop recording." : "Tap the microphone to record your idea.")
                             : (dictation.recording ? "Release to stop recording." :
                                "Keep the gray mic pressed while you describe your app."))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(dictation.status)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86, alignment: .leading)
                    .clipped()
                }
                .frame(height: 100)
                .padding(.vertical, 7)
            } header: {
                Text("Step 1 · Describe your app")
            } footer: {
                Text(isWidgetVoiceEntry
                     ? (widgetTapRecordingFinished
                        ? "To add more words, hold the microphone while speaking and release to transcribe."
                        : "Recording starts automatically. Tap the microphone to stop, or use Generate or Cancel.")
                     : "Tell Forge what your app should do. You can type or hold the gray microphone to speak.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("App testing", selection: $forgeTestMode) {
                        ForEach(ForgeTestMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    Text("Skip: no runtime checks. Fast: short on-device smoke tests without AI repair. Balanced: test and attempt one focused AI repair. None guarantees every button works.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if existingApp == nil && demoMode {
                    Text("Practice mode: the actual Forge progress and editing screens are shown with a prebuilt calculator. No AI, mockup, or save request will occur.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if existingApp == nil {
                    if quickModePolicy == "manual" {
                    Toggle(isOn: $quickMode) {
                        Label("QUICK!", systemImage: "bolt.fill")
                            .font(.headline)
                    }
                    .disabled(AISettingsStore.quickModel.isEmpty)
                    }
                    if AISettingsStore.isUIOverhaulEnabled {
                        Toggle("Extra UI overhaul for this run", isOn: $polishThisRun)
                            .font(.subheadline)
                        Text("Optional. Adds a separate visual refinement pass; leave off for faster generation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Let me choose how it looks first", isOn: $stylePickerEnabled)
                        .font(.subheadline)
                    Text(stylePickerEnabled
                         ? "Start Generating makes three mockups first. Choose one to build the full app."
                         : "Forge will start building right away.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    submitPromptGeneration()
                } label: {
                    Label(generateAfterVoiceTranscription ? "Finishing transcription…" :
                          (existingApp == nil && stylePickerEnabled ? "Start Generating" : "Make My App"),
                          systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(generateAfterVoiceTranscription ||
                          (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                           !(isWidgetVoiceEntry && (promptMicHeld || dictation.transcribingOffline))) ||
                          (!demoMode && !AISettingsStore.configuration.isConfigured))
            }

            if !AISettingsStore.configuration.isConfigured && !demoMode {
                Section {
                    Label("Connect your AI in Settings to start making apps.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            if AISettingsStore.isUIOverhaulEnabled && !demoMode {
                Section {
                    Label("UI Overhaul is enabled. It can apply a visual CSS/markup patch, but script changes are rejected.", systemImage: "paintbrush")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollDisabled(promptMicHeld && (!isWidgetVoiceEntry || widgetTapRecordingFinished))
    }


    private func startPromptRecording() {
        guard !dictation.recording && !dictation.requestingPermission && !dictation.transcribingOffline else { return }
        promptMicHeld = true
        promptDictationAwaitingResult = false
        dictationForEdit = false
        promptDictationActive = true
        promptDictationAwaitingResult = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dictationPrefix = prompt
        microphoneRecordingTask?.cancel()
        microphoneRecordingTask = Task { await dictation.start(tapToStop: isWidgetVoiceEntry && !widgetTapRecordingFinished) }
    }

    private func stopPromptRecording() {
        promptMicHeld = false
        microphoneRecordingTask?.cancel()
        microphoneRecordingTask = nil
        dictation.stop()
        if !dictation.transcript.isEmpty {
            prompt = dictationPrefix + (dictationPrefix.isEmpty ? "" : "\n") + dictation.transcript
            nextRequestFromVoice = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        promptDictationActive = false
    }

    /// Returns true if a fully offline action was handled or offered. Never
    /// changes providers or submits source to a cloud service without consent.
    private func requestOfflineForgeIfNeeded(edit: Bool) -> Bool {
        guard !demoMode, forgeConnectivity.hasChecked, forgeConnectivity.isOffline else { return false }
        if let unavailable = HTMLAppOfflineForge.availabilityMessage {
            offlineUnavailableMessage = unavailable
        } else {
            offlineActionIsEdit = edit
            showingOfflineConsent = true
        }
        return true
    }

    private func runOfflineForge(edit: Bool, effort: HTMLAppOfflineEffort) {
        let text = (edit ? changePrompt : prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isWorking else { return }
        let originalHTML = session.streamedHTML
        if !edit { session.beginDraft(prompt: text) }
        session.errorMessage = nil
        session.isWorking = true
        session.phase = edit ? "Editing with on-device Apple Intelligence" : "Generating with on-device Apple Intelligence"
        generationTask?.cancel()
        generationTask = Task { @MainActor in
            defer { session.isWorking = false }
            do {
                let result = try await HTMLAppOfflineForge.generate(
                    request: text, existingHTML: edit ? originalHTML : nil, effort: effort
                ) { phase in session.phase = phase }
                try Task.checkCancellation()
                // Only publish an edited app after the entire document passes
                // local validation. Never replace the original on failure.
                if edit {
                    unsavedEditHistory.append(originalHTML)
                    session.lastEditSummary = "Offline Apple Intelligence edit"
                    changePrompt = ""
                    showingChange = true
                }
                session.acceptExternalHTML(result)
                session.phase = "Ready to review — offline"
                session.errorMessage = nil
            } catch is CancellationError {
                session.phase = "Offline generation cancelled"
                session.errorMessage = nil
            } catch {
                session.phase = "Offline generation failed"
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func submitPromptGeneration() {
        if isWidgetVoiceEntry && (promptMicHeld || dictation.recording || dictation.requestingPermission) {
            stopPromptRecording()
        }
        if isWidgetVoiceEntry && dictation.transcribingOffline {
            generateAfterVoiceTranscription = true
            return
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if requestOfflineForgeIfNeeded(edit: false) { return }
        if existingApp == nil && stylePickerEnabled && !demoMode {
            exploreStyleOptions()
        } else {
            selectedStyle = nil
            generateApp()
        }
    }

    private var backgroundForgePendingView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            Text("Generating in background")
                .font(.title2.bold())
            Text("Your AI provider is finishing a background request. HTMLApp will save the result as a draft for review. You can lock your screen or return later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ProgressView()
            Text("On return, Forge will check the completed HTML before saving.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var styleSelectionView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            generationTask?.cancel()
                            preparedStyleTask?.cancel()
                            preparedStyleTask = nil
                            preparedStylePrompt = nil
                            exploringStyles = false
                            styleOptions = []
                            styleFailure = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Choose your app's look").font(.subheadline.weight(.semibold))
                            Text("Quick sketches, not finished apps")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.bar)
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Who will use this app?", systemImage: "person.text.rectangle")
                            .font(.caption.weight(.medium))
                        TextField("Purpose — AI will suggest one, or edit it yourself", text: $purposeGuess)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: purposeGuess) { _ in purposeEdited = true }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    if !styleOptions.isEmpty {
                        HStack(spacing: 8) {
                            ForgeStyleSketchView(html: styleOptions[min(selectedStyleIndex, styleOptions.count - 1)].previewHTML)
                                .id(styleOptions[min(selectedStyleIndex, styleOptions.count - 1)].id)
                                .clipShape(RoundedRectangle(cornerRadius: 34))
                                .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(.primary.opacity(0.24), lineWidth: 5))
                                .padding(7)
                                .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 42))
                                .padding(.leading, 4)
                                .padding(.vertical, 8)
                                .blur(radius: exploringStyles ? 26 : 0)
                                .overlay {
                                    if exploringStyles {
                                        VStack(spacing: 10) {
                                            ProgressView()
                                            Text("\(styleOptions.count) of 3 sketches prepared")
                                                .font(.headline)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.ultraThinMaterial)
                                    }
                                }
                                .allowsHitTesting(!exploringStyles)
                            GeometryReader { choicesGeometry in
                                ScrollView(.vertical, showsIndicators: true) {
                                    VStack(spacing: 10) {
                                        ForEach(0..<max(3, (styleOptions.map(\.id).max() ?? -1) + 1), id: \.self) { slot in
                                            let available = styleOptions.firstIndex(where: { $0.id == slot })
                                            Button {
                                                if let available { selectedStyleIndex = available }
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Text("Look \(slot + 1)")
                                                    if available == nil {
                                                        Image(systemName: "hourglass").font(.caption2)
                                                    }
                                                }
                                                .font(.caption.bold())
                                                .frame(width: 76, height: 44)
                                                .foregroundStyle(available == nil ? .secondary : .primary)
                                                .background(
                                                    available == selectedStyleIndex ? Color.accentColor.opacity(0.24) : Color(.secondarySystemBackground),
                                                    in: RoundedRectangle(cornerRadius: 12)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(available == nil || exploringStyles)
                                            .accessibilityLabel("View mockup \(slot + 1)")
                                        }
                                        Button {
                                            generateAdditionalStyles()
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.title2)
                                                .frame(width: 76, height: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(exploringStyles || styleOptions.isEmpty)
                                        .accessibilityLabel("Generate three more AI-designed looks")
                                    }
                                    .padding(.horizontal, 4)
                                }
                                // 5 full rows and half the sixth hint that more choices exist.
                                // Short displays use the available height, without covering the footer.
                                .frame(height: min(292, max(0, choicesGeometry.size.height)))
                                .clipped()
                            }
                            .frame(width: 88)
                            .frame(maxHeight: 292)
                            .zIndex(2)
                        }
                    } else if exploringStyles {
                        Spacer()
                        ProgressView("Preparing first sketch…")
                        Spacer()
                    } else if let failure = styleFailure {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "paintpalette")
                            Text("Style previews aren't available").font(.headline)
                            Text(failure).font(.subheadline).foregroundStyle(.secondary)
                            Button("Try previews again") { exploreStyleOptions() }
                            Button("Build app directly") { skipStyleSelection() }
                        }
                        Spacer()
                    }
                }

                if !exploringStyles && styleFailure == nil && !styleOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pick a look")
                                .font(.caption2.weight(.bold))
                                .tracking(1.1)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Try the preview above")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(styleOptions[selectedStyleIndex].summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Button {
                                exploreStyleOptions()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .frame(width: 30, height: 32)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Generate new style choices")
                            Button {
                                selectedStyle = styleOptions[selectedStyleIndex]
                                styleOptions = []
                                styleFailure = nil
                                generateApp()
                            } label: {
                                Label("Use this look", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let styleFeedbackNotice {
                            Text(styleFeedbackNotice)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: min(500, geometry.size.width - 24))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.13)))
                    .shadow(color: .black.opacity(0.17), radius: 18, y: 7)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: "forgeEditSurface")
            .overlay(alignment: .topLeading) {
                if !exploringStyles && !styleOptions.isEmpty {
                    voiceEditBubble(in: geometry.size, forStyleFeedback: true)
                }
            }
            .alert("Feedback for all three looks", isPresented: $showingStyleFeedback) {
                TextField("What should be different?", text: $styleFeedback)
                Button("Regenerate All Looks") {
                    styleRegenerationRound += 1
                    exploreStyleOptions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Describe what you want changed. Forge will generate three fresh mockups using the same feedback.")
            }
        }
    }

    private func generateAdditionalStyles() {
        guard !exploringStyles else { return }
        let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { return }
        let firstIndex = (styleOptions.map(\.id).max() ?? -1) + 1
        let appearance = colorScheme == .dark ? "dark" : "light"
        let quick = quickMode && !AISettingsStore.quickModel.isEmpty
        exploringStyles = true
        generationTask = Task {
            await withTaskGroup(of: ForgeStyleConcept?.self) { group in
                for index in firstIndex..<(firstIndex + 3) {
                    group.addTask {
                        try? await ForgeRunOptions.$quick.withValue(quick) {
                            try await ForgeStylePreviewService.generateSingle(
                                for: idea,
                                feedback: "Invent a completely fresh, original visual direction. Avoid standard style presets and repeat looks.",
                                index: index,
                                appearance: appearance,
                                regeneration: styleRegenerationRound + 1)
                        }
                    }
                }
                for await concept in group {
                    if let concept {
                        styleOptions.append(concept)
                        styleOptions.sort { $0.id < $1.id }
                    }
                }
            }
            exploringStyles = false
        }
    }

    private func exploreStyleOptions() {
        HTMLAppFirstUseTips.show("firstAI")
        let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedAppearance = colorScheme == .dark ? "dark" : "light"
        guard !idea.isEmpty else { return }
        generationTask?.cancel()
        preparedStyleTask?.cancel()
        preparedStyleTask = nil
        preparedStylePrompt = nil
        selectedStyle = nil
        selectedStyleIndex = 0
        styleOptions = []
        styleFailure = nil
        styleFeedbackNotice = nil
        exploringStyles = true
        let feedback = styleFeedback
        let regenerationRound = styleRegenerationRound
        generationTask = Task {
            if quickModePolicy == "automatic" && !AISettingsStore.quickModel.isEmpty {
                let choice = await ForgeQuickClassifier.decide(for: idea)
                guard !Task.isCancelled else { return }
                quickMode = choice.fast
                autoQuickReason = choice.reason
            }
            let quick = quickMode && !AISettingsStore.quickModel.isEmpty
            if !quick && !AIHTMLAgent.canSkipPreflight(for: idea) {
                preparedStylePrompt = idea
                preparedStyleTask = Task {
                    async let planning = AIHTMLAgent.planPrompt(
                        idea, config: AISettingsStore.configuration(for: .planner))
                    let report = AIHTMLAgent.needsWebResearch(for: idea)
                        ? await browserResearch.research(for: idea) : ""
                    let plan = try? await planning
                    return (report, plan)
                }
                if let preparedStyleTask {
                    Task {
                        let (_, result) = await preparedStyleTask.value
                        guard !purposeEdited,
                              prompt.trimmingCharacters(in: .whitespacesAndNewlines) == idea,
                              !Task.isCancelled else { return }
                        purposeGuess = result?.purpose ?? ""
                    }
                }
            }
            var failures: [String] = []
            await withTaskGroup(of: (Int, ForgeStyleConcept?, String?).self) { group in
                for index in 0..<3 {
                    group.addTask {
                        do {
                            let concept = try await ForgeRunOptions.$quick.withValue(quick) {
                                try await ForgeStylePreviewService.generateSingle(
                                    for: idea, feedback: feedback, index: index,
                                    appearance: requestedAppearance, regeneration: regenerationRound)
                            }
                            return (index, concept, nil)
                        } catch {
                            return (index, nil, error.localizedDescription)
                        }
                    }
                }
                for await (index, concept, error) in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let concept {
                        styleOptions.append(concept)
                        styleOptions.sort { $0.id < $1.id }
                        selectedStyleIndex = min(selectedStyleIndex, styleOptions.count - 1)
                    } else {
                        failures.append("Look \(index + 1): \(error ?? "No complete HTML returned")")
                    }
                }
            }
            guard !Task.isCancelled else { return }
            exploringStyles = false
            if styleOptions.isEmpty {
                styleFailure = failures.joined(separator: "\n")
            } else {
                HTMLAppFirstUseTips.show("mockups")
                if !failures.isEmpty {
                    styleFeedbackNotice = failures.joined(separator: "\n") +
                        "\nRetry to generate missing AI looks."
                }
            }
        }
    }

    private func skipStyleSelection() {
        generationTask?.cancel()
        preparedStyleTask?.cancel()
        preparedStyleTask = nil
        preparedStylePrompt = nil
        exploringStyles = false
        styleOptions = []
        selectedStyleIndex = 0
        styleFailure = nil
        selectedStyle = nil
        generateApp()
    }

    private var studioView: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(browserResearch.isBrowsing ? "Researching your app" : session.isWorking ? "Creating your app" : "Your app is ready")
                            .font(.headline)
                        Text(browserResearch.isBrowsing ? browserResearch.status : session.phase)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if showHurryUp && !hurriedThisRun && !quickMode &&
                       !AISettingsStore.quickModel.isEmpty &&
                       (session.isWorking || browserResearch.isBrowsing) {
                        Button("Hurry Up!") {
                            UserDefaults.standard.set(true, forKey: "forge.hurryUpCurrentRun")
                            hurriedThisRun = true
                            quickMode = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    if session.isWorking || browserResearch.isBrowsing {
                        Button { stopKeepingDraft() } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let stage = session.skippableStage {
                        Button("Skip") { session.skipCurrentStage() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Skip \(stage)")
                    } else if session.phase == "Polishing the interface" {
                        Button("Skip") {
                            skipUIPolish = true
                            polishTask?.cancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Skip UI Overhaul")
                    }
                    Button { showRunHistory = true } label: {
                        Image(systemName: "chart.pie")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("AI task timings and text output history")
                    Button { showDetails = true } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Forge details")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.bar)

                if demoMode && !session.isWorking {
                    practiceGuide
                }

                if session.isWorking || browserResearch.isBrowsing {
                    ForgeBuildDashboard(
                        title: browserResearch.isBrowsing ? browserResearch.status : session.phase,
                        explanation: currentProgressNote,
                        milestones: milestones.events,
                        active: session.isWorking || browserResearch.isBrowsing,
                        bytes: session.streamedByteCount,
                        runs: workTracker.recentRuns
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HTMLWebView(
                        html: session.streamedHTML.isEmpty ? loadingHTML : session.streamedHTML,
                        appID: existingApp?.id ?? "PREVIEW",
                        onJavaScriptError: { error in
                            if !runtimeErrors.contains(error) && runtimeErrors.count < 30 { runtimeErrors.append(error) }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !session.isWorking && !browserResearch.isBrowsing && !session.streamedHTML.isEmpty {
                    VStack(spacing: 10) {
                        if let microphoneEditNotice {
                            Text(microphoneEditNotice).font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let uiPolishNotice {
                            Text(uiPolishNotice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if showingChange {
                            HStack(spacing: 8) {
                                TextField("Tell AI what to change…", text: $changePrompt, axis: .vertical)
                                    .lineLimit(1...4)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    if dictation.recording { dictation.stop(); dictationForEdit = false }
                                    else {
                                        promptDictationActive = false
                                        dictationForEdit = true
                                        dictationPrefix = changePrompt
                                        Task { await dictation.start() }
                                    }
                                } label: {
                                    Image(systemName: dictation.recording && dictationForEdit ? "stop.circle.fill" : "mic.fill")
                                }
                                .buttonStyle(.bordered)
                                .disabled(dictation.requestingPermission)
                                .accessibilityLabel(dictation.recording && dictationForEdit ? "Stop edit dictation" : "Dictate edit")
                            }
                            HStack(spacing: 10) {
                                Button("Apply Change") { applyAIChange() }
                                    .buttonStyle(.bordered)
                                    .disabled(changePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button(existingApp == nil ? "Save App" : "Save Changes") { saveGeneratedApp() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(saving)
                            }
                            if !session.lastEditSummary.isEmpty {
                                Text(session.lastEditSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Save the current app now, or apply another AI change first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: 10) {
                                if existingApp == nil {
                                    Button("Regenerate from scratch") {
                                        generationTask?.cancel()
                                        // Preserve the user's approved design and its full
                                        // mockup HTML across a from-scratch coding retry.
                                        showingChange = false
                                        session.clearCheckpoint()
                                        generateApp()
                                    }
                                    .disabled(session.isWorking || saving)
                                }
                                Button(existingApp == nil ? "Change this…" : "Ask AI to edit…") { showingChange = true }
                                    .buttonStyle(.bordered)
                                Button(existingApp == nil ? "Save App" : "Save Changes") { saveGeneratedApp() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(saving)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(.bar)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: "forgeEditSurface")
            .overlay(alignment: .bottomTrailing) {
                if !session.isWorking && !session.streamedHTML.isEmpty && !runtimeErrors.isEmpty {
                    Button {
                        showingRuntimeErrors = true
                    } label: {
                        Label("\(runtimeErrors.count)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .padding(11)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .accessibilityLabel("JavaScript errors. Review and fix.")
                    .padding(.trailing, 12)
                    .padding(.bottom, 125)
                }
            }
            .alert("JavaScript errors detected", isPresented: $showingRuntimeErrors) {
                Button("Ask AI to Fix") {
                    changePrompt = "Fix these JavaScript errors without changing the chosen visual style:\n" +
                        runtimeErrors.prefix(8).joined(separator: "\n")
                    runtimeErrors = []
                    showingChange = true
                    applyAIChange()
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text(runtimeErrors.prefix(5).joined(separator: "\n"))
            }
            .overlay(alignment: .topLeading) {
                if !session.isWorking && !browserResearch.isBrowsing && !session.streamedHTML.isEmpty && !saving {
                    voiceEditBubble(in: proxy.size)
                }
            }
            .overlay {
                if saving {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text(existingApp == nil ? "Saving app…" : "Saving changes…").font(.headline)
                        }
                    }
                }
            }
        }
    }

    private var practiceGuide: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PRACTICE \(min(practiceStep + 1, 5)) OF 5")
                .font(.caption.bold()).foregroundStyle(.blue)
            Text(practiceStep == 2
                 ? "Tap 7, +, 3 and = in the calculator. Then drag the floating gray mic from the left edge fully onto the screen, speak, and release. You can also tap it to type."
                 : practiceStep == 3
                 ? "Type a change in the edit box below, such as ‘Make the buttons purple,’ then tap Apply Change."
                 : practiceStep == 4
                 ? "Review your changed calculator. Tap Save App below to practice finishing. This demo will not enter your Library."
                 : practiceStep >= 5
                 ? "Great work! You've practiced generating, testing, dragging the mic, typing an edit and saving."
                 : "Watch Forge's short simulated build. You can stop a real build later from this screen.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if practiceStep == 2 {
                    Button("I tried the calculator") {
                        practiceStep = 3
                        showingChange = true
                    }
                    .buttonStyle(.bordered)
                }
                if practiceStep == 3 && !showingChange {
                    Button("Show edit field") { showingChange = true }
                        .buttonStyle(.bordered)
                }
                if practiceStep >= 5 {
                    Button("Finish Practice") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func voiceEditBubble(in size: CGSize, forStyleFeedback: Bool = false) -> some View {
        let side: CGFloat = 63
        let origin = CGPoint(x: -24 + microphoneTranslation.width, y: 68 + microphoneTranslation.height)
        let fullyVisible = origin.x >= 0 && origin.y >= 0 &&
            origin.x + side <= size.width && origin.y + side <= size.height
        return Image(systemName: "mic.fill")
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle((microphoneArmed && dictation.recording) ? Color.white : Color.primary.opacity(0.85))
            .frame(width: side, height: side)
            .background((microphoneArmed && dictation.recording) ? Color.red : Color(.systemGray4),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1))
            .rotationEffect(.degrees(microphoneArmed ? 0 : -16))
            .scaleEffect(microphoneArmed ? 1.25 : 1)
            .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
            .offset(x: origin.x, y: origin.y)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: microphoneArmed)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("forgeEditSurface"))
                    .onChanged { gesture in
                        microphoneTranslation = gesture.translation
                        let x = -24 + gesture.translation.width
                        let y = 68 + gesture.translation.height
                        let inside = x >= 0 && y >= 0 && x + side <= size.width && y + side <= size.height
                        if inside && !microphoneArmed {
                            microphoneArmed = true
                            if demoMode { practiceStep = max(practiceStep, 3); showingChange = true }
                            HTMLAppFirstUseTips.show("dragMic")
                            microphoneCapturing = true
                            promptDictationActive = false
                            dictationForEdit = false
                            dictationPrefix = ""
                            dictation.transcript = ""
                            microphoneEditNotice = nil
                            microphoneRecordingTask?.cancel()
                            microphoneRecordingTask = Task { await dictation.start() }
                        } else if !inside && microphoneArmed {
                            microphoneArmed = false
                            microphoneRecordingTask?.cancel()
                            microphoneRecordingTask = nil
                            dictation.cancel()
                            dictation.transcript = ""
                            microphoneCapturing = false
                            dictationForEdit = false
                            microphoneEditNotice = nil
                        }
                    }
                    .onEnded { gesture in
                        let x = -24 + gesture.translation.width
                        let y = 68 + gesture.translation.height
                        let inside = x >= 0 && y >= 0 && x + side <= size.width && y + side <= size.height
                        let wasArmed = microphoneArmed
                        let spoken = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        microphoneArmed = false
                        microphoneTranslation = .zero
                        microphoneRecordingTask?.cancel()
                        microphoneRecordingTask = nil
                        dictation.stop()
                        microphoneCapturing = false
                        dictationForEdit = false
                        if demoMode && inside && wasArmed {
                            practiceStep = 3
                            showingChange = true
                            microphoneEditNotice = "Nice drag! Now type an edit below and tap Apply Change."
                            return
                        }
                        if inside && wasArmed && spoken.isEmpty && dictation.transcribingOffline {
                            pendingFloatingVoiceFeedback = forStyleFeedback
                            microphoneEditNotice = "Whisper is transcribing…"
                            return
                        }
                        if inside && wasArmed {
                            if forStyleFeedback {
                                if !spoken.isEmpty {
                                    styleFeedback = spoken
                                    styleFeedbackNotice = "Regenerating all three looks using: " + spoken
                                    exploreStyleOptions()
                                } else {
                                    showingStyleFeedback = true
                                    styleFeedbackNotice = "No words captured. Type feedback or drag the microphone again."
                                }
                            } else if !spoken.isEmpty {
                                changePrompt = spoken
                                showingChange = true
                                applyAIChange()
                            } else {
                                showingChange = true
                                microphoneEditNotice = "No words captured. Type your change below, or drag the mic in and try again."
                            }
                        }
                    }
            )
            .onTapGesture {
                if forStyleFeedback {
                    showingStyleFeedback = true
                } else {
                    showingChange = true
                    microphoneEditNotice = "Type an edit below, or drag this microphone fully on-screen to dictate."
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullyVisible && microphoneArmed ? "Recording" : (forStyleFeedback ? "Drag microphone inward to give feedback on all mockups" : "Drag microphone inward to dictate edit"))
            .accessibilityHint(forStyleFeedback
                ? "Drag fully onto the screen and speak. Release to regenerate all three mockups, or drag offscreen to cancel. Tap to type feedback."
                : "Drag fully onto the screen to record; release to submit. Drag off-screen to cancel. Tap to type instead.")
    }

    private var loadingHTML: String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0;font-family:-apple-system;background:#f2f2f7;color:#111;display:grid;place-items:center;min-height:100vh}main{text-align:center;padding:32px}.dot{width:12px;height:12px;border-radius:50%;background:#007aff;margin:18px auto;animation:p 1s infinite alternate}@keyframes p{to{transform:scale(1.6);opacity:.35}}@media(prefers-color-scheme:dark){body{background:#000;color:#fff}}</style></head><body><main><h2>Building your app</h2><p>Your last good preview stays in place while Forge builds the next stable version.</p><div class="dot"></div></main></body></html>
        """
    }

    private func acceptShortcutRequest(_ nonce: Int, incoming: String) {
        guard existingApp == nil, nonce > 0, nonce != handledShortcutNonce else { return }
        handledShortcutNonce = nonce
        if isWidgetVoiceEntry {
            // Opening from the Lock Screen is a request to dictate, not to
            // generate immediately or show the old voice-only capture page.
            prompt = ""
            activeShortcutPrompt = ""
            generateAfterVoiceTranscription = false
            widgetTapRecordingFinished = false
            showDraftRecovery = false
            recoverableDraft = nil
            startPromptRecording()
            return
        }
        let idea = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { return }
        generationTask?.cancel()
        dictation.stop()
        exploringStyles = false
        styleOptions = []
        styleFailure = nil
        selectedStyle = nil
        showDraftRecovery = false
        recoverableDraft = nil
        activeShortcutPrompt = idea
        prompt = idea
        UserDefaults.standard.removeObject(forKey: "htmlapp.shortcut.activeIdea")
        // Other shortcuts provide a finished text prompt and can still
        // start generation directly; the Lock Screen microphone path above
        // intentionally waits for the user to finish dictating.
        generateApp()
    }

    private func startForgeActivity(edit: Bool) {
        UserDefaults.standard.set(false, forKey: "forge.hurryUpCurrentRun")
        showHurryUp = false
        hurriedThisRun = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if forgeActivityJobID != nil { showHurryUp = true }
        }
        HTMLAppForgeBackgroundNotice.prepare()
        BackgroundKeepAlive.shared.start()
        GenerationMusic.shared.start()
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            HTMLAppForgeContinuedProcessing.begin(edit: edit)
        }
        #endif
        let job = UUID().uuidString
        forgeActivityJobID = job
        if #available(iOS 16.2, *) {
            forgeActivityStartTask = Task { await HTMLAppForgeActivityService.start(job: job, edit: edit, phase: "Preparing") }
        }
    }

    private func endForgeActivity(onlyIf expected: String? = nil) {
        guard let job = forgeActivityJobID, expected == nil || expected == job else { return }
        BackgroundKeepAlive.shared.stop()
        UserDefaults.standard.set(false, forKey: "forge.hurryUpCurrentRun")
        showHurryUp = false
        if !ForgeBackgroundUpload.shared.isActive { GenerationMusic.shared.stop() }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            HTMLAppForgeContinuedProcessing.finish(success: session.errorMessage == nil && session.phase == "Ready to review")
        }
        #endif
        forgeActivityJobID = nil
        if #available(iOS 16.2, *) {
            let starting = forgeActivityStartTask
            forgeActivityStartTask = nil
            Task {
                await starting?.value
                await HTMLAppForgeActivityService.finish(job: job)
            }
        }
    }

    private static func askForgeQuestion(for idea: String) async -> (title: String, options: [String], suggested: String) {
        let fallback = (title: "What should the app prioritize?",
                        options: ["More visual detail", "Simple and fast"],
                        suggested: "Simple and fast")
        do {
            let response = try await AIProviderClient.complete(
                config: AISettingsStore.configuration(for: .planner),
                system: """
                You are a product designer. If the app idea leaves a meaningful
                design choice unresolved, ask ONE short user-facing question with
                TWO distinct options. Recommend the best default for this request.
                Return EXACTLY four lines:
                QUESTION: question
                A: first option
                B: second option
                DEFAULT: A or B
                No JSON, Markdown or commentary. Don't ask for personal data.
                """,
                messages: [("user", String(idea.prefix(900)))],
                timeout: 12, maxTokens: 170, retryOnTransient: false
            )
            let lines = response.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            func field(_ prefix: String) -> String? {
                lines.first(where: { $0.uppercased().hasPrefix(prefix) })
                    .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            guard let title = field("QUESTION:"), let first = field("A:"),
                  let second = field("B:"), !title.isEmpty, !first.isEmpty,
                  !second.isEmpty, title.count < 180, first.count < 110,
                  second.count < 110 else { return fallback }
            return (title, [first, second],
                field("DEFAULT:")?.uppercased() == "A" ? first : second)
        } catch {
            return fallback
        }
    }

    private func resolveCreationQuestion(answer: String) {
        questionTimer?.cancel()
        questionTimer = nil
        guard questionAlreadyAsked else { return }
        // Record explicit choice for this generation only; do not persist it
        // as a global taste preference.
        prompt += "\n\nAdditional preference: " + answer
        generateApp()
    }

    private func generateApp() {
        if requestOfflineForgeIfNeeded(edit: false) { return }
        if quickModePolicy == "automatic" && autoQuickReason == nil &&
           !AISettingsStore.quickModel.isEmpty && !demoMode && !session.isWorking {
            let source = prompt
            generationTask = Task {
                let choice = await ForgeQuickClassifier.decide(for: source)
                guard !Task.isCancelled else { return }
                quickMode = choice.fast
                autoQuickReason = choice.reason
                generateApp()
            }
            return
        }
        if !questionAlreadyAsked && selectedStyle == nil && existingApp == nil &&
           !demoMode && shortcutSource != "widget" && shortcutGenerationNonce == 0 &&
           prompt.count > 90 && (prompt.lowercased().contains("design") ||
               prompt.lowercased().contains("whatever you think") ||
               prompt.lowercased().contains("something like")) {
            questionAlreadyAsked = true
            let source = prompt
            Task { @MainActor in
                let question = await ForgeRunOptions.$quick.withValue(quickMode) {
                    await Self.askForgeQuestion(for: source)
                }
                questionTitle = question.title
                questionChoices = question.options
                suggestedAnswer = question.suggested
                choiceResponse = ""
                pendingChoiceQuestion = true
                questionTimer = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    guard !Task.isCancelled, pendingChoiceQuestion else { return }
                    choiceResponse = suggestedAnswer
                    pendingChoiceQuestion = false
                }
            }
            return
        }
        HTMLAppFirstUseTips.show("generation")
        guard !ForgeBackgroundUpload.shared.isActive, !session.isWorking &&
              (!browserResearch.isBrowsing || preparedStyleTask != nil) else { return }
        if demoMode {
            practiceStep = 1
            milestones.reset()
            session.isWorking = true
            session.phase = "Reading your request"
            generationTask = Task {
                for stage in ["Designing the calculator", "Generating live preview",
                              "Adding working buttons", "Running app checks"] {
                    do { try await Task.sleep(nanoseconds: 1_100_000_000) }
                    catch { session.isWorking = false; return }
                    session.phase = stage
                }
                session.showTutorialExample(OnboardingView.calculatorDemoHTML)
                practiceStep = 2
                showingChange = false
            }
            return
        }
        dictation.stop()
        runtimeErrors = []
        AIPrivacyToolRunner.resetLocationTracking()
        startForgeActivity(edit: false)
        milestones.reset()
        workTracker.begin(kind: "New app", appKey: existingApp?.id ?? draftWorkID)
        workTracker.updateVolume(prompt.utf8.count)
        milestones.add(.plan, "Reading your request", bytes: prompt.utf8.count, key: "initial")
        lastFailedChange = nil
        let originalPrompt = prompt
        let sourceFromVoice = nextRequestFromVoice
        nextRequestFromVoice = false
        let pendingPreflight = preparedStylePrompt == originalPrompt ? preparedStyleTask : nil
        preparedStylePrompt = nil
        preparedStyleTask = nil
        let confirmedPurpose = purposeGuess.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePrompt = confirmedPurpose.isEmpty ? originalPrompt :
            originalPrompt + "\n\nINTENDED AUDIENCE AND PURPOSE: " + confirmedPurpose
        let designBrief = selectedStyle.map { basePrompt + "\n\n" + $0.buildInstruction } ?? basePrompt
        uiPolishNotice = nil
        AIDebugTraceStore.shared.begin(originalPrompt: originalPrompt, config: AISettingsStore.configuration)
        session.beginDraft(prompt: originalPrompt)
        session.isWorking = true
        let activityJob = forgeActivityJobID
        generationTask = Task {
            await ForgeRunOptions.$quick.withValue(quickMode && !AISettingsStore.quickModel.isEmpty) {
            defer {
                let outcome = Task.isCancelled ? "Stopped" :
                    (session.errorMessage == nil ? "Completed" : "Failed")
                workTracker.finish(outcome: outcome)
                endForgeActivity(onlyIf: activityJob)
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
                if !Task.isCancelled && session.errorMessage == nil &&
                    !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    session.clearCheckpoint()
                } else {
                    session.persistCheckpoint()
                }
                AIDebugTraceStore.shared.finish(outcome: outcome + (session.errorMessage.map { ": " + $0 } ?? ""))
            }
            let webReport: String
            var preplanned: AIPlanningResult?
            if let pendingPreflight {
                (webReport, preplanned) = await pendingPreflight.value
                AIDebugTraceStore.shared.append("PREFLIGHT", "Used preparation started during style selection.")
            } else if ForgeRunOptions.quick || AIHTMLAgent.canSkipPreflight(for: originalPrompt) {
                session.phase = "Generating live preview"
                webReport = ""
                AIDebugTraceStore.shared.append("WEB RESEARCH", ForgeRunOptions.quick ? "Skipped for a QUICK! run." : "Skipped because this appears to be a simple local app request.")
            } else if AIHTMLAgent.needsWebResearch(for: originalPrompt) {
                session.phase = "Planning web research"
                webReport = await browserResearch.research(for: originalPrompt)
                AIDebugTraceStore.shared.append("WEB RESEARCH", webReport.isEmpty ? "No browser research result." : webReport)
            } else {
                session.phase = "Checking device capabilities"
                webReport = ""
                AIDebugTraceStore.shared.append("WEB RESEARCH", "Skipped because this request can be resolved against HTMLApp's internal device API catalog.")
            }
            guard !Task.isCancelled else { return }
            let privacyReport = await AIPrivacyToolRunner.research(
                originalPrompt, config: AISettingsStore.configuration(for: .research))
            guard !Task.isCancelled else { return }
            let combinedResearch = [webReport, privacyReport].filter { !$0.isEmpty }.joined(separator: "\n\n")
            await session.generate(
                prompt: designBrief,
                originalUserPrompt: originalPrompt,
                researchReport: combinedResearch,
                preplanned: preplanned,
                fromVoice: sourceFromVoice
            )
            if session.errorMessage != nil, forgeConnectivity.isOffline,
               HTMLAppOfflineForge.availabilityMessage == nil {
                offlineActionIsEdit = false
                showingOfflineConsent = true
                return
            }
            guard session.errorMessage == nil,
                  !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if let chosen = selectedStyle {
                let missing = chosen.visualTokenDeclarations.filter { declaration in
                    let property = String(declaration.split(separator: ":", maxSplits: 1).first ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return !property.isEmpty && !session.streamedHTML.contains(property)
                }
                let layout = session.streamedHTML.lowercased()
                let fidelityIssue: String?
                switch chosen.id {
                case 0:
                    fidelityIssue = ((layout.contains("feature") || layout.contains("hero") ||
                        layout.contains("map")) && (layout.contains("floating") ||
                        layout.contains("sheet") || layout.contains("overlay"))) ? nil :
                        "Restore the dominant domain-specific feature visual and anchored floating action panel."
                case 1:
                    fidelityIssue = (layout.contains("hero") && (layout.contains("action") ||
                        layout.contains("button"))) ? nil :
                        "Restore a distinctive action-first hero and prominent task CTA."
                default:
                    fidelityIssue = (layout.contains("list") && (layout.contains("item") ||
                        layout.contains("row"))) ? nil :
                        "Restore compact domain-specific metrics and an ordered activity or item list."
                }
                if (!missing.isEmpty || fidelityIssue != nil) && !Task.isCancelled {
                    AIDebugTraceStore.shared.append("MOCKUP FIDELITY",
                        "Missing CSS tokens: \(missing.count). Layout issue: \(fidelityIssue ?? "none").")
                    await session.revise(
                        change: "Restore the CHOSEN mockup's initial screen layout, hierarchy, component geometry and CSS variables without breaking any functionality. " +
                            (fidelityIssue ?? "") + " Missing style tokens: " +
                            missing.prefix(8).joined(separator: "; "),
                        styleInstruction: chosen.buildInstruction
                    )
                }
                // Avoid the optional generic UI-overhaul pass restyling the chosen mockup.
            } else {
                await runOptionalUIPolish(originalPrompt: designBrief)
            }
            if session.errorMessage == nil && !Task.isCancelled {
                await HTMLAppForgeCompletionFeedback.announce(edit: false)
                HTMLAppForgeBackgroundNotice.completed(edit: false)
            }
            }
        }
    }

    private func applyAIChange() {
        if demoMode {
            let words = changePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return }
            let newColor = words.localizedCaseInsensitiveContains("green") ? "#34a853" :
                words.localizedCaseInsensitiveContains("red") ? "#ed5353" :
                words.localizedCaseInsensitiveContains("orange") ? "#ed8a35" : "#8965cc"
            let updated = session.streamedHTML.replacingOccurrences(
                of: "</style>", with: "button{border:2px solid \(newColor);box-shadow:0 2px 5px #0001} </style>"
            )
            session.acceptExternalHTML(updated)
            session.phase = "Practice edit applied"
            session.lastEditSummary = "Simulated change: \(words)"
            practiceStep = 4
            showingChange = false
            return
        }
        guard !ForgeBackgroundUpload.shared.isActive, !session.isWorking,
              !browserResearch.isBrowsing else { return }
        if requestOfflineForgeIfNeeded(edit: true) { return }
        let requestedEdit = changePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rewriteApproved && rewriteCheckedPrompt != requestedEdit {
            rewriteCheckedPrompt = requestedEdit
            Task {
                let system = """
                You are assessing an edit to an existing standalone HTML app.
                Answer only REWRITE or PATCH. REWRITE is permitted ONLY when a massive
                architectural overhaul makes patching objectively impossible or unsafe.
                Minor, moderate, visual, feature, and ordinary navigation edits are PATCH.
                When uncertain, answer PATCH.
                """
                let request = "Current app summary: \(session.refinedBrief.prefix(1000))\nEdit request: \(requestedEdit)"
                let result = try? await AIProviderClient.complete(
                    config: AISettingsStore.configuration(for: .planner),
                    system: system, messages: [("user", request)],
                    timeout: 25, maxTokens: 16, retryOnTransient: false)
                guard requestedEdit == changePrompt.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                if result?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "REWRITE" {
                    rewriteApprovalPending = true
                } else {
                    applyAIChange()
                }
            }
            return
        }
        runtimeErrors = []
        if !session.streamedHTML.isEmpty {
            unsavedEditHistory.append(session.streamedHTML)
        }
        startForgeActivity(edit: true)
        milestones.reset()
        workTracker.begin(kind: "AI edit", appKey: existingApp?.id ?? draftWorkID)
        workTracker.updateVolume(changePrompt.utf8.count)
        milestones.add(.plan, "Preparing your edit", bytes: changePrompt.utf8.count, key: "edit")
        let change = changePrompt
        uiPolishNotice = nil
        AIDebugTraceStore.shared.begin(originalPrompt: "EDIT REQUEST\n" + change, config: AISettingsStore.configuration)
        AIDebugTraceStore.shared.append("EDIT INPUT", "Prior HTML bytes: \(session.streamedHTML.utf8.count); existing app: \(existingApp?.name ?? "new draft")")
        session.isWorking = true
        let activityJob = forgeActivityJobID
        generationTask = Task {
            await ForgeRunOptions.$quick.withValue(quickMode && !AISettingsStore.quickModel.isEmpty) {
            defer {
                let outcome = Task.isCancelled ? "Stopped" :
                    (session.errorMessage == nil ? "Completed" : "Failed")
                workTracker.finish(outcome: outcome)
                endForgeActivity(onlyIf: activityJob)
                AIDebugTraceStore.shared.finish(outcome: outcome + (session.errorMessage.map { ": " + $0 } ?? ""))
            }
            let researchRequest = """
Existing HTMLApp goal:
\(session.refinedBrief)

Requested edit:
\(change)
"""
            let webReport: String
            if !ForgeRunOptions.quick && AIHTMLAgent.needsWebResearch(for: researchRequest) {
                session.phase = "Planning web research"
                webReport = await browserResearch.research(for: researchRequest)
                AIDebugTraceStore.shared.append("WEB RESEARCH", webReport.isEmpty ? "No browser research result." : webReport)
            } else {
                session.phase = "Checking device capabilities"
                webReport = ""
                AIDebugTraceStore.shared.append("WEB RESEARCH", "Skipped because this edit does not require public-web research; the internal device API catalog remains available.")
            }
            guard !Task.isCancelled else { return }
            let privacyReport = await AIPrivacyToolRunner.research(
                researchRequest, config: AISettingsStore.configuration(for: .research))
            guard !Task.isCancelled else { return }
            let combinedResearch = [webReport, privacyReport].filter { !$0.isEmpty }.joined(separator: "\n\n")
            if rewriteApproved {
                let oldHTML = session.streamedHTML
                let fullBrief = """
                Rebuild this HTMLApp as a complete standalone HTML document. This is a
                user-approved major overhaul. Preserve the existing working features
                and data contracts unless the user explicitly asks to change them.

                Existing HTML:
                \(String(oldHTML.prefix(90_000)))

                Mandatory changes:
                \(change)
                """
                await session.generate(prompt: fullBrief, originalUserPrompt: change,
                                       researchReport: combinedResearch)
                rewriteApproved = false
            } else {
                await session.revise(change: change, researchReport: combinedResearch,
                                     styleInstruction: selectedStyle?.buildInstruction)
            }
            guard session.errorMessage == nil else {
                lastFailedChange = change
                if forgeConnectivity.isOffline && HTMLAppOfflineForge.availabilityMessage == nil {
                    offlineActionIsEdit = true
                    showingOfflineConsent = true
                }
                return
            }
            lastFailedChange = nil
            ForgeTasteMemory.recordEditPreference(change)
            changePrompt = ""
            showingChange = true
            if session.wantsUIPolish && selectedStyle == nil && polishThisRun {
                await runOptionalUIPolish(originalPrompt: session.refinedBrief.isEmpty ? change : session.refinedBrief)
            } else {
                uiPolishNotice = "This was a focused edit; no additional UI redesign was needed."
            }
            if session.errorMessage == nil && !Task.isCancelled {
                await HTMLAppForgeCompletionFeedback.announce(edit: true)
                HTMLAppForgeBackgroundNotice.completed(edit: true)
            }
            }
        }
    }

    private func runOptionalUIPolish(originalPrompt: String) async {
        guard AISettingsStore.isUIOverhaulEnabled, polishThisRun, !ForgeRunOptions.quick else { return }
        let functionalHTML = session.streamedHTML
        session.isWorking = true
        session.phase = "Polishing the interface"
        skipUIPolish = false
        let worker = Task {
            try await UIOverhaulService.polish(html: functionalHTML, originalPrompt: originalPrompt)
        }
        polishTask = worker
        defer { polishTask = nil }
        do {
            let result = try await worker.value
            if skipUIPolish { throw CancellationError() }
            session.acceptExternalHTML(result.html)
            session.isWorking = false
            if result.html == functionalHTML {
                session.phase = "Ready to review"
                uiPolishNotice = "UI Redesign found no safe change worth applying."
            } else {
                uiPolishNotice = "Checking the redesigned app's navigation, rendering and logic…"
                await session.verifyCurrent()
                if session.errorMessage == nil {
                    uiPolishNotice = result.changedOnlyCSS
                        ? "Refined the interface and rechecked the finished app."
                        : "Redesigned the interface and rechecked its behavior."
                }
            }
        } catch {
            session.acceptExternalHTML(functionalHTML)
            session.isWorking = false
            session.phase = "Ready to review"
            uiPolishNotice = skipUIPolish
                ? "UI Overhaul skipped. The functional app was preserved."
                : "UI Overhaul was skipped because it failed. The previous version was preserved."
        }
    }

    private func saveGeneratedApp() {
        if AIPrivacyToolRunner.generatedHTMLContainsPrivateLocation(session.streamedHTML) {
            changePrompt = "Remove hard-coded device coordinates. Read location only at runtime with user permission and preserve the chosen design."
            showingChange = true
            session.errorMessage = "This generated app appears to contain your private location. Ask AI to fix the source before saving."
            return
        }
        if demoMode {
            practiceStep = 5
            showPracticeEditNotice = true
            return
        }
        saving = true
        Task {
            var html = session.streamedHTML
            if let icon = session.renderedIconData {
                html = injectIcon(icon, into: html)
            }
            if let existingApp {
                await store.updateFromAI(existingApp, html: html, summary: session.description.isEmpty ? existingApp.summary : session.description, note: session.lastEditSummary.isEmpty ? "AI changed this app." : session.lastEditSummary)
                if let icon = session.renderedIconData {
                    store.setGeneratedIcon(icon, for: existingApp)
                }
                if let selectedStyle {
                    ForgeStyleReferenceStore.save(selectedStyle, for: existingApp.id)
                    ForgeTasteMemory.recordStyle(selectedStyle.visualTokenDeclarations)
                }
                store.notice = "Saved AI changes to \(existingApp.name)."
            } else {
                let beforeIDs = Set(store.apps.map(\.id))
                await store.add(html: html, summary: session.description)
                if let added = store.apps.first(where: { !beforeIDs.contains($0.id) }) {
                    workTracker.associateDraft(with: added.id)
                    if let selectedStyle {
                        ForgeStyleReferenceStore.save(selectedStyle, for: added.id)
                        ForgeTasteMemory.recordStyle(selectedStyle.visualTokenDeclarations)
                    }
                }
            }
            AIDebugTraceStore.shared.finish(outcome: "Saved")
            session.clearCheckpoint()
            saving = false
            dismiss()
        }
    }

    private func stopKeepingDraft() {
        preparedStyleTask?.cancel()
        preparedStyleTask = nil
        preparedStylePrompt = nil
        ForgeBackgroundUpload.shared.cancel()
        endForgeActivity()
        session.keepCurrentPartialDraft()
        generationTask?.cancel()
        workTracker.finish(outcome: "Stopped")
        AIDebugTraceStore.shared.finish(outcome: "Stopped")
        dictation.stop()
        session.isWorking = false
        uiPolishNotice = session.streamedHTML.isEmpty
            ? "Stopped. The prompt and planning draft were kept locally."
            : "Stopped. The latest safe preview was kept locally."
    }

    private func retryLastFailure() {
        if let change = lastFailedChange {
            changePrompt = change
            showingChange = true
            applyAIChange()
            return
        }

        if !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let failed = session.failedPhase,
           failed.contains("icon") || failed.contains("app checks") || failed.contains("Reviewing") || failed.contains("Rechecking") {
            generationTask = Task { await session.verifyCurrent() }
            return
        }

        generateApp()
    }

    private static func isRecoverable(_ draft: ForgeDraftCheckpoint) -> Bool {
        let phase = draft.phase.lowercased()
        if phase.contains("ready to review") || phase.contains("saved") ||
            phase.contains("completed") || phase.contains("ready for ai edits") {
            ForgeDraftCheckpointStore.clear()
            return false
        }
        return !draft.originalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (draft.streamedByteCount > 0 || !draft.html.isEmpty ||
             phase.contains("generat") || phase.contains("edit") || phase.contains("research"))
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m \(total % 60)s" }
        return "\(total / 60)m \(total % 60)s"
    }

    private func continueRecoveredDraft() {
        guard let draft = recoverableDraft else { return }
        resumeRecoveredDraft()
        if draft.phase == "Background result received" {
            generationTask = Task { await session.verifyCurrent() }
            return
        }
        if draft.existingAppID == nil {
            // A provider's old streaming connection cannot be resumed after
            // process death. Reissue the original prompt rather than
            // inventing missing bytes or silently saving an incomplete app.
            session.clearCheckpoint()
            prompt = draft.originalPrompt
            generateApp()
        } else {
            // Keep the unsaved edited source and let the user submit an edit.
            showingChange = true
        }
    }

    private func resumeRecoveredDraft() {
        guard let draft = recoverableDraft else { return }
        session.restore(checkpoint: draft, existingIcon: existingApp?.favicon)
        if existingApp == nil { prompt = draft.originalPrompt }
        recoverableDraft = nil
        uiPolishNotice = "Recovered the local draft. AI work was not restarted automatically."
    }

    /// Foreground streaming cannot be transferred into a background
    /// URLSession. Start one complete file-backed request when the app
    /// actually backgrounds, then preserve its result for foreground QA.
    private func handoffForgeToBackgroundURLSession() {
        guard !demoMode, session.isWorking, !ForgeBackgroundUpload.shared.isActive else { return }
        let config = ForgeRunOptions.$quick.withValue(quickMode && !AISettingsStore.quickModel.isEmpty) {
            AISettingsStore.configuration
        }
        let isEdit = !changePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let system: String
        let message: String
        if isEdit {
            system = AIHTMLAgent.patchSystemPrompt(research: browserResearch.lastReport)
            message = """
            CURRENT APP:
            <htmlapp_existing>
            \(session.streamedHTML)
            </htmlapp_existing>
            REQUESTED CHANGE:
            \(changePrompt)
            Return the usual complete HTMLApp patch response.
            """
        } else {
            system = AIHTMLAgent.systemPrompt(research: browserResearch.lastReport)
            let base = session.refinedBrief.isEmpty ? prompt : session.refinedBrief
            message = selectedStyle.map { base + "\n\n" + $0.buildInstruction } ?? base
        }
        session.persistCheckpoint()
        guard ForgeBackgroundUpload.shared.start(
            config: config, system: system, messages: [("user", message)], edit: isEdit
        ) else { return }
        let previous = generationTask
        previous?.cancel()
        Task { @MainActor in
            await previous?.value
            session.isWorking = false
            session.phase = "Continuing in background"
        }
    }

    /// The finished response is never executed in the background. Verify and
    /// render the app only after returning to a foreground Forge view.
    private func restoreCompletedBackgroundDraft() {
        guard scenePhase == .active, !session.isWorking,
              let draft = ForgeDraftCheckpointStore.load(),
              draft.phase == "Background result received",
              draft.existingAppID == existingApp?.id ||
                  (existingApp == nil && draft.existingAppID == nil)
        else { return }
        session.restore(checkpoint: draft, existingIcon: existingApp?.favicon)
        recoverableDraft = nil
        showDraftRecovery = false
        uiPolishNotice = "Background generation finished. Checking your app before review."
        generationTask = Task { await session.verifyCurrent() }
    }

    private func persistDraftForBackground() {
        guard !demoMode else { return }
        session.persistCheckpoint()
        guard session.isWorking, backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Forge Generation") {
            Task { @MainActor in
                session.persistCheckpoint()
                if scenePhase == .background {
                    handoffForgeToBackgroundURLSession()
                }
                // If the handoff cannot start, retain the saved checkpoint.
                if !ForgeBackgroundUpload.shared.isActive {
                    generationTask?.cancel()
                }
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
        }
        if backgroundTaskID == .invalid {
            session.persistCheckpoint()
        }
    }

    private func injectIcon(_ data: Data, into html: String) -> String {
        let tag = "<link rel=\"apple-touch-icon icon\" href=\"data:image/png;base64,\(data.base64EncodedString())\">"
        if let range = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: tag + "\n", at: range.lowerBound)
            return result
        }
        return tag + "\n" + html
    }
}

private struct ForgeDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Plan"

    let plan: String
    let research: String
    let qa: String
    let debug: String

    private var content: String {
        switch tab {
        case "Research": return research.isEmpty ? "No public-web research was needed or available for this run." : research
        case "QA": return qa.isEmpty ? "QA has not produced a report yet." : qa
        case "Debug": return debug.isEmpty ? "No active debug trace." : debug
        default: return plan.isEmpty ? "The product plan is not available yet." : plan
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Forge details", selection: $tab) {
                    Text("Plan").tag("Plan")
                    Text("Research").tag("Research")
                    Text("QA").tag("QA")
                    Text("Debug").tag("Debug")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    Text(content)
                        .font(tab == "Debug" ? .caption.monospaced() : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .navigationTitle("Forge Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}


@MainActor
private enum HTMLAppForgeBackgroundNotice {
    static func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func completed(edit: Bool) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = edit ? "App update finished" : "Your app is ready"
        content.body = edit ? "Your HTMLApp changes are complete." : "HTMLApp finished generating your app."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "htmlapp.forge.finished.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}

