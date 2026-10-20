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
    @State private var showActivity = false
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
                Text("No speech API key required. On-device recognition is preferred; otherwise Apple may process audio with your permission.").font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text("What do you want to make?")
            } footer: {
                Text("Forge plans a complete usable app—not a mockup—researches real data/APIs when useful, can add native widgets and iOS-supported background refresh when they improve the product, builds a live preview, and runs final repair/QA before you save.")
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
                    Label("Your separate UI Overhaul model will make a conservative visual refinement, then the main AI will review the result again.", systemImage: "paintbrush")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var studioView: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 5) {
                    HStack(spacing: 10) {
                        if session.isWorking || browserResearch.isBrowsing { ProgressView() }
                        if browserResearch.isBrowsing {
                            Image(systemName: "globe")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        Text(browserResearch.isBrowsing ? browserResearch.status : session.phase)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer()
                        if !session.refinedBrief.isEmpty {
                            Menu {
                                Text(session.refinedBrief)
                            } label: {
                                Image(systemName: "list.bullet.clipboard")
                            }
                            .accessibilityLabel("View AI plan")
                        }
                        if !session.verificationReport.isEmpty {
                            Menu {
                                Text(session.verificationReport)
                            } label: {
                                Image(systemName: "checkmark.shield")
                            }
                            .accessibilityLabel("View AI QA report")
                        }
                    }
                    if browserResearch.isBrowsing {
                        Text(browserResearch.progressNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentTransition(.opacity)
                    } else if session.isWorking {
                        Text(session.progressNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentTransition(.opacity)
                    } else if let uiPolishNotice {
                        Text(uiPolishNotice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !session.verificationReport.isEmpty {
                        Text("AI QA reviewed the generated source for mobile UI quality and likely functional issues.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

                DisclosureGroup("Build notes & research", isExpanded: $showActivity) {
                    ScrollView {
                        Text((browserResearch.activity + session.activity).suffix(30).joined(separator: "\n"))
                            .font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.frame(maxHeight: 130)
                    if !browserResearch.lastReport.isEmpty {
                        DisclosureGroup("Research evidence") {
                            ScrollView { Text(browserResearch.lastReport).font(.caption).textSelection(.enabled) }.frame(maxHeight: 150)
                        }
                    }
                    Text("Source review is not a device test. Try your app before saving.").font(.caption2)
                }.padding(.horizontal, 16).padding(.vertical, 6)

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
                                    .disabled(saving || (existingApp == nil && session.renderedIconData == nil))
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
            guard session.errorMessage == nil else { return }
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
        if existingApp == nil && session.renderedIconData == nil {
            session.errorMessage = "The generated app does not have a valid rendered icon yet."
            return
        }
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
            saving = false
            dismiss()
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
