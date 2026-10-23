import SwiftUI
import UIKit

struct AIGenerationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dictation = ForgeDictation()
    @State private var dictationPrefix = ""
    @State private var dictationForEdit = false
    @State private var generationTask: Task<Void, Never>?
    @State private var forgeActivityJobID: String?
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
    @State private var microphoneRecordingTask: Task<Void, Never>?
    @State private var microphoneEditNotice: String?
    @State private var pendingFloatingVoiceFeedback: Bool?
    @ObservedObject private var debugTrace = AIDebugTraceStore.shared
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("forgeTestMode") private var forgeTestMode = ForgeTestMode.fast.rawValue
    @AppStorage("ai.stylePickerEnabled") private var stylePickerEnabled = true
    @State private var exploringStyles = false
    @State private var styleOptions: [ForgeStyleConcept] = []
    @State private var selectedStyleIndex = 0
    @State private var styleFailure: String?
    @State private var styleFeedback = ""
    @State private var showingStyleFeedback = false
    @State private var styleFeedbackNotice: String?
    @State private var selectedStyle: ForgeStyleConcept?
    @State private var prompt = ""
    @State private var changePrompt = ""
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

    private let starterPrompts = [
        "A simple homework planner that works offline",
        "A clean habit tracker with reminders",
        "Flashcards for studying any subject",
        "A useful daily checklist with a widget"
    ]

    let existingApp: SavedHTMLApp?

    let shortcutGenerationNonce: Int
    let shortcutSource: String

    init(existingApp: SavedHTMLApp? = nil, initialPrompt: String = "",
         shortcutGenerationNonce: Int = 0, shortcutSource: String = "siri") {
        self.existingApp = existingApp
        self.shortcutGenerationNonce = shortcutGenerationNonce
        self.shortcutSource = shortcutSource
        _prompt = State(initialValue: initialPrompt)
    }

    var body: some View {
        NavigationStack {
            Group {
                if existingApp == nil && (exploringStyles || !styleOptions.isEmpty || styleFailure != nil) {
                    styleSelectionView
                } else if session.streamedHTML.isEmpty && !session.isWorking && !browserResearch.isBrowsing {
                    promptView
                } else {
                    studioView
                }
            }
            .navigationTitle(existingApp == nil ? "Generate" : "Edit with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if exploringStyles || !styleOptions.isEmpty || styleFailure != nil || session.isWorking || browserResearch.isBrowsing || !session.streamedHTML.isEmpty {
                            showCancelConfirmation = true
                        } else {
                            AIDebugTraceStore.shared.finish(outcome: "Canceled before starting")
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
                if developerMode && (debugTrace.isActive || !debugTrace.history.isEmpty) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { showDebug = true } label: { Image(systemName: "ladybug") }
                            .accessibilityLabel("View AI debug trace")
                    }
                }
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
                    ForgeDraftCheckpointStore.clear()
                    recoverableDraft = nil
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
            if let existingApp, !didLoadExisting {
                didLoadExisting = true
                session.load(existing: existingApp)
                selectedStyle = ForgeStyleReferenceStore.load(for: existingApp.id)
            }
            if recoverableDraft == nil,
               let draft = ForgeDraftCheckpointStore.load(),
               draft.existingAppID == existingApp?.id {
                recoverableDraft = draft
                if shortcutGenerationNonce == 0 { showDraftRecovery = true }
            }
            acceptShortcutRequest(shortcutGenerationNonce, incoming: prompt)
        }
        .onChange(of: shortcutGenerationNonce) { nonce in
            // Library sends a new nonce even if this screen is already open.
            // Receive the new prompt and start again only after canceling
            // the previous generation, without auto-saving anything.
            acceptShortcutRequest(nonce, incoming: UserDefaults.standard.string(forKey: "htmlapp.shortcut.activeIdea") ?? activeShortcutPrompt)
        }
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("HTMLAppForgeBackgroundExpired"))) { _ in
            session.persistCheckpoint()
            generationTask?.cancel()
        }
        .onDisappear {
            microphoneRecordingTask?.cancel(); dictation.stop()
            // Do not cancel the generation merely because the view disappears.
            // Keep a checkpoint and allow the finite iOS background grace period.
            session.persistCheckpoint()
        }
        .onChange(of: scenePhase) { value in
            if value != .active {
                microphoneRecordingTask?.cancel()
                microphoneCapturing = false
                microphoneArmed = false
                microphoneTranslation = .zero
                dictation.stop()
                persistDraftForBackground()
            }
        }
        .onChange(of: dictation.transcribingOffline) { processing in
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
        .onChange(of: dictation.transcript) { value in
            // Drag-edit dictation is committed only on release; never overwrite a
            // typed request, and never clear the creation prompt on cancellation.
            guard !microphoneCapturing else { return }
            let merged = dictationPrefix + (dictationPrefix.isEmpty || value.isEmpty ? "" : "\n") + value
            if dictationForEdit { changePrompt = merged }
            else if promptDictationAwaitingResult && !promptMicHeld {
                prompt = merged
                if !value.isEmpty { promptDictationAwaitingResult = false }
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
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                HTMLAppForgeContinuedProcessing.update(phase: phase)
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
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .frame(width: 86, height: 86)
                        .foregroundStyle(promptMicHeld ? Color.white : Color.primary)
                        .background(promptMicHeld ? Color.red : Color(.systemGray4),
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dictation.recording ? "Listening…" : "Hold to talk")
                            .font(.headline)
                        Text(dictation.recording ? "Release to stop recording." :
                            "Keep the gray mic pressed while you describe your app.")
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
                Text("Tell Forge what your app should do. You can type or hold the gray microphone to speak.")
            }

            Section {
                if developerMode {
                    HStack {
                        Label(AISettingsStore.configuration.model, systemImage: "cpu")
                            .lineLimit(1)
                        Spacer()
                        Text(AISettingsStore.isUIOverhaulEnabled ? "UI polish on" : "UI polish off")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

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

                if existingApp == nil {
                    Toggle("Let me choose how it looks first", isOn: $stylePickerEnabled)
                        .font(.subheadline)
                    Text(stylePickerEnabled
                         ? "Start Generating makes three mockups first. Choose one to build the full app."
                         : "Forge will start building right away.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button {
                    if existingApp == nil && stylePickerEnabled {
                        exploreStyleOptions()
                    } else {
                        selectedStyle = nil
                        generateApp()
                    }
                } label: {
                    Label(existingApp == nil && stylePickerEnabled ? "Start Generating" : "Make My App", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !AISettingsStore.configuration.isConfigured)
            }

            if !AISettingsStore.configuration.isConfigured {
                Section {
                    Label("Connect your AI in Settings to start making apps.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            if AISettingsStore.isUIOverhaulEnabled {
                Section {
                    Label("UI Overhaul is enabled. It can apply a visual CSS/markup patch, but script changes are rejected.", systemImage: "paintbrush")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollDisabled(promptMicHeld)
    }


    private func startPromptRecording() {
        guard !dictation.recording && !dictation.requestingPermission else { return }
        promptMicHeld = true
        promptDictationAwaitingResult = false
        dictationForEdit = false
        promptDictationActive = true
        promptDictationAwaitingResult = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dictationPrefix = prompt
        microphoneRecordingTask?.cancel()
        microphoneRecordingTask = Task { await dictation.start() }
    }

    private func stopPromptRecording() {
        promptMicHeld = false
        microphoneRecordingTask?.cancel()
        microphoneRecordingTask = nil
        dictation.stop()
        if !dictation.transcript.isEmpty {
            prompt = dictationPrefix + (dictationPrefix.isEmpty ? "" : "\n") + dictation.transcript
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        promptDictationActive = false
    }

    private var styleSelectionView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            generationTask?.cancel()
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

                    if !styleOptions.isEmpty {
                        HStack(spacing: 8) {
                            ForgeStyleSketchView(html: styleOptions[min(selectedStyleIndex, styleOptions.count - 1)].previewHTML)
                                .id(styleOptions[min(selectedStyleIndex, styleOptions.count - 1)].name)
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
                            VStack(spacing: 10) {
                                ForEach(styleOptions) { option in
                                    Button {
                                        selectedStyleIndex = styleOptions.firstIndex(where: { $0.id == option.id }) ?? 0
                                    } label: {
                                        Text("Look \(option.id + 1)")
                                            .font(.caption.bold())
                                            .frame(width: 75, height: 44)
                                            .foregroundStyle(.primary)
                                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .accessibilityLabel("View mockup \(option.id + 1)")
                                        .buttonStyle(.bordered)
                                        .tint(option.id == styleOptions[min(selectedStyleIndex, styleOptions.count - 1)].id ? .accentColor : .secondary)
                                        .disabled(exploringStyles)
                                }
                            }
                            .frame(width: 84)
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
                    if exploringStyles {
                        Button("Skip and build directly") { skipStyleSelection() }
                            .buttonStyle(.bordered)
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
                        Button {
                            showingStyleFeedback = true
                        } label: {
                            Label("Give feedback on all looks", systemImage: "text.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        if let styleFeedbackNotice {
                            Text(styleFeedbackNotice)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Skip and make app now") { skipStyleSelection() }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
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
                    if !styleFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        styleFeedbackNotice = "Using your feedback for all three new mockups."
                        exploreStyleOptions()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Describe what you want changed. Forge will generate three fresh mockups using the same feedback.")
            }
        }
    }

    private func exploreStyleOptions() {
        let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty, !exploringStyles else { return }
        generationTask?.cancel()
        exploringStyles = true
        styleOptions = []
        selectedStyleIndex = 0
        styleFailure = nil
        selectedStyle = nil
        generationTask = Task {
            let started = Date()
            let feedback = styleFeedback
            var errors: [String] = []
            await withTaskGroup(of: (Int, ForgeStyleConcept?, String?).self) { group in
                for index in 0..<3 {
                    group.addTask {
                        do {
                            let result = try await ForgeStylePreviewService.generateSingle(
                                for: idea, feedback: feedback, index: index
                            )
                            return (index, result, nil)
                        } catch {
                            return (index, nil, error.localizedDescription)
                        }
                    }
                }
                for await (index, option, failure) in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    if let option {
                        styleOptions.append(option)
                        styleOptions.sort { $0.id < $1.id }
                        selectedStyleIndex = 0
                    } else if let failure { errors.append("Style \(index + 1): \(failure)") }
                    if debugTrace.isActive {
                        AIDebugTraceStore.shared.append("STYLE MOCKUP", "Completed slot \(index + 1) at \(String(format: "%.1f", Date().timeIntervalSince(started)))s.")
                    }
                }
            }
            if Task.isCancelled { return }
            exploringStyles = false
            if styleOptions.isEmpty {
                styleFailure = errors.first ?? "No previews could be generated."
            }
        }
    }

    private func skipStyleSelection() {
        generationTask?.cancel()
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
                    if session.isWorking || browserResearch.isBrowsing {
                        Button { stopKeepingDraft() } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
                        appID: existingApp?.id ?? "PREVIEW"
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
                                        selectedStyle = nil
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

    private func voiceEditBubble(in size: CGSize, forStyleFeedback: Bool = false) -> some View {
        let side: CGFloat = 63
        let origin = CGPoint(x: -24 + microphoneTranslation.width, y: 68 + microphoneTranslation.height)
        let fullyVisible = origin.x >= 0 && origin.y >= 0 &&
            origin.x + side <= size.width && origin.y + side <= size.height
        return Image(systemName: "mic.fill")
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(microphoneArmed ? Color.white : Color.primary.opacity(0.85))
            .frame(width: side, height: side)
            .background(microphoneArmed ? Color.red : Color(.systemGray4),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.55), lineWidth: 1))
            .rotationEffect(.degrees(microphoneArmed ? 0 : -16))
            .scaleEffect(microphoneArmed ? 1.07 : 1)
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
        // Voice widget follows in-app mockup selection; Siri retains
        // its previously requested direct-build behavior.
        if shortcutSource == "widget" && stylePickerEnabled {
            exploreStyleOptions()
        } else {
            generateApp()
        }
    }

    private func startForgeActivity(edit: Bool) {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            HTMLAppForgeContinuedProcessing.begin(edit: edit)
        }
        #endif
        let job = UUID().uuidString
        forgeActivityJobID = job
        if #available(iOS 16.2, *) {
            Task { await HTMLAppForgeActivityService.start(job: job, edit: edit, phase: "Preparing") }
        }
    }

    private func endForgeActivity(onlyIf expected: String? = nil) {
        guard let job = forgeActivityJobID, expected == nil || expected == job else { return }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            HTMLAppForgeContinuedProcessing.finish(success: session.errorMessage == nil && session.phase == "Ready to review")
        }
        #endif
        forgeActivityJobID = nil
        if #available(iOS 16.2, *) {
            Task { await HTMLAppForgeActivityService.finish(job: job) }
        }
    }

    private func generateApp() {
        guard !session.isWorking && !browserResearch.isBrowsing else { return }
        startForgeActivity(edit: false)
        milestones.reset()
        workTracker.begin(kind: "New app", appKey: existingApp?.id ?? draftWorkID)
        workTracker.updateVolume(prompt.utf8.count)
        milestones.add(.plan, "Reading your request", bytes: prompt.utf8.count, key: "initial")
        dictation.stop()
        lastFailedChange = nil
        let originalPrompt = prompt
        let designBrief = selectedStyle.map { originalPrompt + "\n\n" + $0.buildInstruction } ?? originalPrompt
        uiPolishNotice = nil
        AIDebugTraceStore.shared.begin(originalPrompt: originalPrompt, config: AISettingsStore.configuration)
        session.beginDraft(prompt: originalPrompt)
        session.isWorking = true
        let activityJob = forgeActivityJobID
        generationTask = Task {
            defer {
                let outcome = Task.isCancelled ? "Stopped" :
                    (session.errorMessage == nil ? "Completed" : "Failed")
                workTracker.finish(outcome: outcome)
                endForgeActivity(onlyIf: activityJob)
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
                session.persistCheckpoint()
                AIDebugTraceStore.shared.finish(outcome: outcome + (session.errorMessage.map { ": " + $0 } ?? ""))
            }
            let webReport: String
            if AIHTMLAgent.canSkipPreflight(for: originalPrompt) {
                session.phase = "Generating live preview"
                webReport = ""
                AIDebugTraceStore.shared.append("WEB RESEARCH", "Skipped because this appears to be a simple local app request.")
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
            await session.generate(
                prompt: designBrief,
                originalUserPrompt: originalPrompt,
                researchReport: webReport
            )
            guard session.errorMessage == nil,
                  !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if let chosen = selectedStyle {
                let missing = chosen.visualTokenDeclarations.filter { declaration in
                    let property = String(declaration.split(separator: ":", maxSplits: 1).first ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return !property.isEmpty && !session.streamedHTML.contains(property)
                }
                if !missing.isEmpty && !Task.isCancelled {
                    AIDebugTraceStore.shared.append("MOCKUP FIDELITY",
                        "Missing \(missing.count) CSS tokens. One focused repair requested.")
                    await session.revise(
                        change: "Restore the selected mockup's CSS variables and visual styling without changing working app behavior. Missing tokens: " + missing.prefix(8).joined(separator: "; "),
                        styleInstruction: chosen.buildInstruction
                    )
                }
                // Avoid the optional generic UI-overhaul pass restyling the chosen mockup.
            } else {
                await runOptionalUIPolish(originalPrompt: designBrief)
            }
            if session.errorMessage == nil && !Task.isCancelled {
                await HTMLAppForgeCompletionFeedback.announce(edit: false)
            }
        }
    }

    private func applyAIChange() {
        guard !session.isWorking && !browserResearch.isBrowsing else { return }
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
            if AIHTMLAgent.needsWebResearch(for: researchRequest) {
                session.phase = "Planning web research"
                webReport = await browserResearch.research(for: researchRequest)
                AIDebugTraceStore.shared.append("WEB RESEARCH", webReport.isEmpty ? "No browser research result." : webReport)
            } else {
                session.phase = "Checking device capabilities"
                webReport = ""
                AIDebugTraceStore.shared.append("WEB RESEARCH", "Skipped because this edit does not require public-web research; the internal device API catalog remains available.")
            }
            guard !Task.isCancelled else { return }
            await session.revise(change: change, researchReport: webReport,
                                styleInstruction: selectedStyle?.buildInstruction)
            guard session.errorMessage == nil else {
                lastFailedChange = change
                return
            }
            lastFailedChange = nil
            changePrompt = ""
            showingChange = true
            if session.wantsUIPolish && selectedStyle == nil {
                await runOptionalUIPolish(originalPrompt: session.refinedBrief.isEmpty ? change : session.refinedBrief)
            } else {
                uiPolishNotice = "This was a focused edit; no additional UI redesign was needed."
            }
            if session.errorMessage == nil && !Task.isCancelled {
                await HTMLAppForgeCompletionFeedback.announce(edit: true)
            }
        }
    }

    private func runOptionalUIPolish(originalPrompt: String) async {
        guard AISettingsStore.isUIOverhaulEnabled else { return }
        let functionalHTML = session.streamedHTML
        session.isWorking = true
        session.phase = "Polishing the interface"
        do {
            let result = try await UIOverhaulService.polish(html: functionalHTML, originalPrompt: originalPrompt)
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
            uiPolishNotice = "UI Overhaul was skipped because it failed. The previous version was preserved."
        }
    }

    private func saveGeneratedApp() {
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
                if let selectedStyle { ForgeStyleReferenceStore.save(selectedStyle, for: existingApp.id) }
                store.notice = "Saved AI changes to \(existingApp.name)."
            } else {
                let beforeIDs = Set(store.apps.map(\.id))
                await store.add(html: html, summary: session.description)
                if let added = store.apps.first(where: { !beforeIDs.contains($0.id) }) {
                    workTracker.associateDraft(with: added.id)
                    if let selectedStyle { ForgeStyleReferenceStore.save(selectedStyle, for: added.id) }
                }
            }
            AIDebugTraceStore.shared.finish(outcome: "Saved")
            session.clearCheckpoint()
            saving = false
            dismiss()
        }
    }

    private func stopKeepingDraft() {
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

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m \(total % 60)s" }
        return "\(total / 60)m \(total % 60)s"
    }

    private func continueRecoveredDraft() {
        guard let draft = recoverableDraft else { return }
        resumeRecoveredDraft()
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

    private func persistDraftForBackground() {
        session.persistCheckpoint()
        guard session.isWorking, backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Forge Generation") {
            session.persistCheckpoint()
            generationTask?.cancel()
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
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

