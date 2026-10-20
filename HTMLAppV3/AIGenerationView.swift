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
    @ObservedObject private var debugTrace = AIDebugTraceStore.shared
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

    let existingApp: SavedHTMLApp?

    init(existingApp: SavedHTMLApp? = nil) {
        self.existingApp = existingApp
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.streamedHTML.isEmpty && !session.isWorking && !browserResearch.isBrowsing {
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
                        if session.isWorking || browserResearch.isBrowsing || !session.streamedHTML.isEmpty {
                            showCancelConfirmation = true
                        } else {
                            AIDebugTraceStore.shared.clear()
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
                if debugTrace.isActive {
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
                    dismiss()
                }
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text(existingApp == nil ? "The generated preview and current AI work will be lost if you close it without saving." : "Your saved HTMLApp will not be changed unless you choose Save Changes.")
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
                    debug: debugTrace.text
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
        .onDisappear { generationTask?.cancel(); dictation.stop() }
        .onChange(of: scenePhase) { value in
            if value != .active {
                dictation.stop()
                persistDraftForBackground()
            }
        }
        .onChange(of: dictation.transcript) { value in
            let merged = dictationPrefix + (dictationPrefix.isEmpty || value.isEmpty ? "" : "\n") + value
            if dictationForEdit { changePrompt = merged } else { prompt = merged }
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
                TextEditor(text: $prompt)
                    .frame(minHeight: 170)
                    .font(.body)
                Button {
                    if dictation.recording { dictation.stop() }
                    else { dictationForEdit = false; dictationPrefix = prompt; Task { await dictation.start() } }
                } label: {
                    Label(dictation.recording ? "Stop Dictation" : "Dictate Your Idea", systemImage: dictation.recording ? "stop.circle.fill" : "mic.fill")
                }
                .disabled(dictation.requestingPermission)
                Text(dictation.status).font(.caption).foregroundStyle(.secondary)
                Text("Dictation uses iOS speech recognition and only starts when you tap the microphone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What do you want to make?")
            } footer: {
                Text("Forge plans the app, verifies needed capabilities, builds a preview, runs isolated runtime checks, and keeps a local recovery draft while it works.")
            }

            Section {
                Button {
                    generateApp()
                } label: {
                    Label("Generate HTML App", systemImage: "sparkles")
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

    private var studioView: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if session.isWorking || browserResearch.isBrowsing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(browserResearch.isBrowsing ? browserResearch.status : session.phase)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(currentProgressNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .contentTransition(.opacity)
                        }
                        Spacer(minLength: 8)
                        if session.isWorking || browserResearch.isBrowsing {
                            Button("Stop", systemImage: "stop.fill") { stopKeepingDraft() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Button {
                            showDetails = true
                        } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Open Forge details")
                    }

                    HStack(spacing: 10) {
                        if session.streamedByteCount > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(session.streamedByteCount), countStyle: .file) + " generated")
                        }
                        if !session.streamedHTML.isEmpty {
                            Text("Draft saved locally")
                        }
                        Spacer()
                        Text("Runtime QA is offscreen, not a device test")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

                HTMLWebView(
                    html: session.streamedHTML.isEmpty ? loadingHTML : session.streamedHTML,
                    appID: existingApp?.id ?? "PREVIEW"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !session.isWorking && !browserResearch.isBrowsing && !session.streamedHTML.isEmpty {
                    VStack(spacing: 10) {
                        if showingChange {
                            HStack(spacing: 8) {
                                TextField("Tell AI what to change…", text: $changePrompt, axis: .vertical)
                                    .lineLimit(1...4)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    if dictation.recording { dictation.stop() }
                                    else {
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
                                Button("Apply") { applyAIChange() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(changePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if dictationForEdit && (dictation.recording || dictation.requestingPermission) {
                                Text(dictation.status).font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Dictate or type your change. Forge checks existing code and relevant web documentation before patching; source review is not a device test.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: 10) {
                                Button(existingApp == nil ? "Change this…" : "Ask AI to edit…") { showingChange = true }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)
                                Button(existingApp == nil ? "Looks good" : "Save Changes") { saveGeneratedApp() }
                                    .buttonStyle(.borderedProminent)
                                    .frame(maxWidth: .infinity)
                                    .disabled(saving)
                            }
                        }
                    }
                    .padding(14)
                    .background(.bar)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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

    private var loadingHTML: String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0;font-family:-apple-system;background:#f2f2f7;color:#111;display:grid;place-items:center;min-height:100vh}main{text-align:center;padding:32px}.dot{width:12px;height:12px;border-radius:50%;background:#007aff;margin:18px auto;animation:p 1s infinite alternate}@keyframes p{to{transform:scale(1.6);opacity:.35}}@media(prefers-color-scheme:dark){body{background:#000;color:#fff}}</style></head><body><main><h2>Building your app</h2><p>The live preview will appear as HTML is generated.</p><div class="dot"></div></main></body></html>
        """
    }

    private func generateApp() {
        dictation.stop()
        lastFailedChange = nil
        let originalPrompt = prompt
        uiPolishNotice = nil
        AIDebugTraceStore.shared.begin(originalPrompt: originalPrompt, config: AISettingsStore.configuration)
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
                prompt: originalPrompt,
                originalUserPrompt: originalPrompt,
                researchReport: webReport
            )
            guard session.errorMessage == nil,
                  !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await runOptionalUIPolish(originalPrompt: originalPrompt)
        }
    }

    private func applyAIChange() {
        let change = changePrompt
        changePrompt = ""
        showingChange = false
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
            await runOptionalUIPolish(originalPrompt: session.refinedBrief.isEmpty ? change : session.refinedBrief)
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
            if result.changedOnlyCSS {
                session.phase = "Ready to review"
                uiPolishNotice = result.html == functionalHTML
                    ? "UI Overhaul found no safe visual change worth applying."
                    : "UI Overhaul applied a CSS-only refinement without rewriting app behavior."
            } else {
                uiPolishNotice = "UI Overhaul refined presentation markup. Running a focused final QA check…"
                await session.verifyCurrent()
                if session.errorMessage == nil {
                    uiPolishNotice = "UI Overhaul finished and the refined markup passed the final checks."
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
        session.persistCheckpoint()
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

