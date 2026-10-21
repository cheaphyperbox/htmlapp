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
    @StateObject private var session = AIGenerationSession()
    @StateObject private var browserResearch = AgenticBrowserResearch()
    @StateObject private var milestones = ForgeBuildMilestones()
    @State private var microphoneTranslation: CGSize = .zero
    @State private var microphoneArmed = false
    @State private var microphoneCapturing = false
    @State private var promptDictationActive = false
    @State private var microphoneRecordingTask: Task<Void, Never>?
    @State private var microphoneEditNotice: String?
    @ObservedObject private var debugTrace = AIDebugTraceStore.shared
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("ai.stylePickerEnabled") private var stylePickerEnabled = true
    @State private var exploringStyles = false
    @State private var styleOptions: [ForgeStyleConcept] = []
    @State private var selectedStyleIndex = 0
    @State private var styleFailure: String?
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
    @State private var recoverableDraft: ForgeDraftCheckpoint?
    @State private var showDraftRecovery = false
    @State private var lastFailedChange: String?

    private let starterPrompts = [
        "A simple homework planner that works offline",
        "A clean habit tracker with reminders",
        "Flashcards for studying any subject",
        "A useful daily checklist with a widget"
    ]

    let existingApp: SavedHTMLApp?

    init(existingApp: SavedHTMLApp? = nil) {
        self.existingApp = existingApp
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
                            AIDebugTraceStore.shared.clear()
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
                if developerMode && debugTrace.isActive {
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
                    dictation.stop()
                    AIDebugTraceStore.shared.clear()
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
                Button("Resume Draft") { resumeRecoveredDraft() }
                Button("Discard Draft", role: .destructive) {
                    ForgeDraftCheckpointStore.clear()
                    recoverableDraft = nil
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                if let draft = recoverableDraft {
                    Text("A local draft from \(draft.savedAt.formatted(date: .abbreviated, time: .shortened)) is available. Resuming restores the saved preview and plan; it does not restart AI work automatically.")
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
            if let existingApp, !didLoadExisting {
                didLoadExisting = true
                session.load(existing: existingApp)
            }
            if recoverableDraft == nil,
               let draft = ForgeDraftCheckpointStore.load(),
               draft.existingAppID == existingApp?.id {
                recoverableDraft = draft
                showDraftRecovery = true
            }
        }
        .interactiveDismissDisabled(true)
        .onDisappear { generationTask?.cancel(); microphoneRecordingTask?.cancel(); dictation.stop() }
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
        .onChange(of: dictation.transcript) { value in
            // Drag-edit dictation is committed only on release; never overwrite a
            // typed request, and never clear the creation prompt on cancellation.
            guard !microphoneCapturing else { return }
            let merged = dictationPrefix + (dictationPrefix.isEmpty || value.isEmpty ? "" : "\n") + value
            if dictationForEdit { changePrompt = merged }
            else if promptDictationActive { prompt = merged }
        }
        .onChange(of: session.refinedBrief) { brief in
            if !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                milestones.add(.plan, "App plan ready", bytes: brief.utf8.count, key: "prompt-plan")
            }
        }
        .onChange(of: browserResearch.completedPages) { pages in
            for page in pages {
                milestones.add(.website, "Read \(page.host)", bytes: page.bytes, key: "web-\(page.id)")
            }
        }
        .onChange(of: session.streamedHTML) { html in
            milestones.inspectHTML(html)
        }
        .onChange(of: session.phase) { phase in
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
                    .frame(minHeight: 150)
                    .font(.body)
                HStack(spacing: 14) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .frame(width: 86, height: 86)
                        .foregroundStyle(dictation.recording ? Color.white : Color.primary)
                        .background(dictation.recording ? Color.red : Color(.systemGray4),
                                    in: RoundedRectangle(cornerRadius: 24))
                        .contentShape(RoundedRectangle(cornerRadius: 24))
                        .onLongPressGesture(minimumDuration: 0, maximumDistance: 90,
                                            pressing: { held in
                            if held {
                                startPromptRecording()
                            } else {
                                stopPromptRecording()
                            }
                        }, perform: {})
                        .accessibilityLabel("Hold to dictate app idea")
                        .accessibilityHint("Hold down the microphone while you speak, then release.")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dictation.recording ? "Listening…" : "Hold to talk")
                            .font(.headline)
                        Text(dictation.recording ? "Release to stop recording." :
                            "Keep the gray mic pressed while you describe your app.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(dictation.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 7)
            } header: {
                Text("What do you want to make?")
            } footer: {
                Text("Describe the result you want. Forge keeps a local recovery draft and runs isolated runtime checks before save.")
            }

            Section {
                HStack {
                    Label(AISettingsStore.configuration.model, systemImage: "cpu")
                        .lineLimit(1)
                    Spacer()
                    Text(AISettingsStore.isUIOverhaulEnabled ? "UI polish on" : "UI polish off")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if existingApp == nil {
                    Toggle("Preview 3 different styles first", isOn: $stylePickerEnabled)
                        .font(.subheadline)
                }

                Button {
                    if existingApp == nil && stylePickerEnabled {
                        exploreStyleOptions()
                    } else {
                        selectedStyle = nil
                        generateApp()
                    }
                } label: {
                    Label(existingApp == nil && stylePickerEnabled ? "Explore App Styles" : "Generate HTML App", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !AISettingsStore.configuration.isConfigured)
            }

            if !AISettingsStore.configuration.isConfigured {
                Section {
                    Label("Set an AI API URL and model in Settings before generating.", systemImage: "exclamationmark.triangle")
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
    }


    private func startPromptRecording() {
        guard !dictation.recording && !dictation.requestingPermission else { return }
        dictationForEdit = false
        promptDictationActive = true
        dictationPrefix = prompt
        microphoneRecordingTask?.cancel()
        microphoneRecordingTask = Task { await dictation.start() }
    }

    private func stopPromptRecording() {
        microphoneRecordingTask?.cancel()
        microphoneRecordingTask = nil
        dictation.stop()
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

                    if exploringStyles {
                        Spacer()
                        VStack(spacing: 15) {
                            ProgressView().controlSize(.large)
                            Text("Designing three directions").font(.headline)
                            Text("Making small previews to compare their colors, layouts, and motion. Full app generation starts only after you choose.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                            Button("Skip and build directly") { skipStyleSelection() }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                    } else if let failure = styleFailure {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "paintpalette")
                                .font(.largeTitle).foregroundStyle(.secondary)
                            Text("Style previews aren't available").font(.headline)
                            Text(failure)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try previews again") { exploreStyleOptions() }
                                .buttonStyle(.bordered)
                            Button("Build app directly") { skipStyleSelection() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(24)
                        Spacer()
                    } else if styleOptions.indices.contains(selectedStyleIndex) {
                        ForgeStyleSketchView(html: styleOptions[selectedStyleIndex].previewHTML)
                            .id(styleOptions[selectedStyleIndex].name + String(selectedStyleIndex))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        HStack(spacing: 7) {
                            ForEach(styleOptions) { option in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedStyleIndex = option.id
                                    }
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(option.name)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.8)
                                        if option.id == selectedStyleIndex {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                        } else {
                                            Image(systemName: "circle")
                                                .font(.caption)
                                                .opacity(0.6)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .padding(.horizontal, 4)
                                    .foregroundStyle(option.id == selectedStyleIndex ? Color.accentColor : Color.primary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(option.id == selectedStyleIndex ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(option.id == selectedStyleIndex ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview \(option.name)")
                                .accessibilityAddTraits(option.id == selectedStyleIndex ? [.isSelected] : [])
                            }
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
            do {
                let choices = try await ForgeStylePreviewService.generate(for: idea)
                try Task.checkCancellation()
                styleOptions = choices
                selectedStyleIndex = 0
                exploringStyles = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                styleFailure = error.localizedDescription
                exploringStyles = false
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
                        bytes: session.streamedByteCount
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
                            Text("Save the current app now, or apply another AI change first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: 10) {
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

    private func voiceEditBubble(in size: CGSize) -> some View {
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
                            dictation.stop()
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
                        if inside && wasArmed {
                            if !spoken.isEmpty {
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
                showingChange = true
                microphoneEditNotice = "Type an edit below, or drag this microphone fully on-screen to dictate."
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullyVisible && microphoneArmed ? "Recording edit" : "Drag microphone inward to dictate edit")
            .accessibilityHint("Drag fully onto the screen to record; release to submit. Drag off-screen to cancel. Tap to type instead.")
    }

    private var loadingHTML: String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0;font-family:-apple-system;background:#f2f2f7;color:#111;display:grid;place-items:center;min-height:100vh}main{text-align:center;padding:32px}.dot{width:12px;height:12px;border-radius:50%;background:#007aff;margin:18px auto;animation:p 1s infinite alternate}@keyframes p{to{transform:scale(1.6);opacity:.35}}@media(prefers-color-scheme:dark){body{background:#000;color:#fff}}</style></head><body><main><h2>Building your app</h2><p>Your last good preview stays in place while Forge builds the next stable version.</p><div class="dot"></div></main></body></html>
        """
    }

    private func generateApp() {
        milestones.reset()
        milestones.add(.plan, "Reading your request", bytes: prompt.utf8.count, key: "initial")
        dictation.stop()
        lastFailedChange = nil
        let originalPrompt = prompt
        let designBrief = selectedStyle.map { originalPrompt + "\n\n" + $0.buildInstruction } ?? originalPrompt
        uiPolishNotice = nil
        AIDebugTraceStore.shared.begin(originalPrompt: originalPrompt, config: AISettingsStore.configuration)
        session.beginDraft(prompt: originalPrompt)
        session.isWorking = true
        generationTask = Task {
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
            await runOptionalUIPolish(originalPrompt: designBrief)
        }
    }

    private func applyAIChange() {
        guard !session.isWorking && !browserResearch.isBrowsing else { return }
        milestones.reset()
        milestones.add(.plan, "Preparing your edit", bytes: changePrompt.utf8.count, key: "edit")
        let change = changePrompt
        uiPolishNotice = nil
        session.isWorking = true
        generationTask = Task {
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
            await session.revise(change: change, researchReport: webReport)
            guard session.errorMessage == nil else {
                lastFailedChange = change
                return
            }
            lastFailedChange = nil
            changePrompt = ""
            showingChange = true
            if session.wantsUIPolish {
                await runOptionalUIPolish(originalPrompt: session.refinedBrief.isEmpty ? change : session.refinedBrief)
            } else {
                uiPolishNotice = "This was a focused edit; no additional UI redesign was needed."
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
                await store.update(existingApp, html: html, summary: session.description.isEmpty ? existingApp.summary : session.description)
                if let icon = session.renderedIconData {
                    store.setGeneratedIcon(icon, for: existingApp)
                }
                store.notice = "Saved AI changes to \(existingApp.name)."
            } else {
                await store.add(html: html, summary: session.description)
            }
            AIDebugTraceStore.shared.clear()
            session.clearCheckpoint()
            saving = false
            dismiss()
        }
    }

    private func stopKeepingDraft() {
        session.keepCurrentPartialDraft()
        generationTask?.cancel()
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

    private func resumeRecoveredDraft() {
        guard let draft = recoverableDraft else { return }
        session.restore(checkpoint: draft, existingIcon: existingApp?.favicon)
        if existingApp == nil { prompt = draft.originalPrompt }
        recoverableDraft = nil
        uiPolishNotice = "Recovered the local draft. AI work was not restarted automatically."
    }

    private func persistDraftForBackground() {
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "Save Forge Draft") {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        session.persistCheckpoint()
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
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

