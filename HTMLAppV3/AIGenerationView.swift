import SwiftUI

struct AIGenerationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = AIGenerationSession()
    @State private var prompt = ""
    @State private var changePrompt = ""
    @State private var showingChange = false
    @State private var saving = false
    @State private var showCancelConfirmation = false
    @State private var uiPolishNotice: String?
    @State private var didLoadExisting = false

    let existingApp: SavedHTMLApp?

    init(existingApp: SavedHTMLApp? = nil) {
        self.existingApp = existingApp
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.streamedHTML.isEmpty && !session.isWorking {
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
                        if session.isWorking || !session.streamedHTML.isEmpty {
                            showCancelConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
            }
            .confirmationDialog(
                existingApp == nil ? "Discard this AI generation?" : "Discard AI edits?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard and Close", role: .destructive) { dismiss() }
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text(existingApp == nil ? "The generated preview and current AI work will be lost if you close it without saving." : "Your saved HTMLApp will not be changed unless you choose Save Changes.")
            }
            .alert("AI Error", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK") { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "")
            }
        }
        .task {
            guard let existingApp, !didLoadExisting else { return }
            didLoadExisting = true
            session.load(existing: existingApp)
        }
        .interactiveDismissDisabled(true)
    }

    private var promptView: some View {
        Form {
            Section {
                TextEditor(text: $prompt)
                    .frame(minHeight: 170)
                    .font(.body)
            } header: {
                Text("What do you want to make?")
            } footer: {
                Text("HTMLApp will improve your prompt, plan the app, search documented public API catalogs when real data or capabilities are needed, build a live preview, and run a final AI QA pass before you save it.")
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
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        if session.isWorking { ProgressView() }
                        Text(session.phase)
                            .font(.subheadline.weight(.semibold))
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
                    if let uiPolishNotice {
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

                HTMLWebView(
                    html: session.streamedHTML.isEmpty ? loadingHTML : session.streamedHTML,
                    appID: existingApp?.id ?? "PREVIEW"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !session.isWorking && !session.streamedHTML.isEmpty {
                    VStack(spacing: 10) {
                        if showingChange {
                            HStack(spacing: 8) {
                                TextField("Tell AI what to change…", text: $changePrompt, axis: .vertical)
                                    .lineLimit(1...4)
                                    .textFieldStyle(.roundedBorder)
                                Button("Apply") { applyAIChange() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(changePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            Text("AI edits use exact patches so unrelated HTML, JavaScript, APIs, storage, and behavior stay intact.")
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
        let originalPrompt = prompt
        uiPolishNotice = nil
        Task {
            await session.generate(prompt: originalPrompt)
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
        Task {
            await session.revise(change: change)
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
            let polished = try await UIOverhaulService.polish(html: functionalHTML, originalPrompt: originalPrompt)
            session.acceptExternalHTML(polished)
            uiPolishNotice = "UI Overhaul refined the presentation. Running final AI QA…"
            session.isWorking = false
            await session.verifyCurrent()
            if session.errorMessage == nil {
                uiPolishNotice = "UI Overhaul finished and the main AI completed a final source-level QA review."
            }
        } catch {
            session.acceptExternalHTML(functionalHTML)
            session.isWorking = false
            session.phase = "Ready to review"
            uiPolishNotice = "UI Overhaul was skipped because it failed. The verified functional version was preserved."
        }
    }

    private func saveGeneratedApp() {
        saving = true
        Task {
            var html = session.streamedHTML
            if !session.iconScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let icon = await AIIconRenderer.render(script: session.iconScript) {
                html = injectIcon(icon, into: html)
            }
            if let existingApp {
                await store.update(existingApp, html: html, summary: session.description.isEmpty ? existingApp.summary : session.description)
                store.notice = "Saved AI changes to \(existingApp.name)."
            } else {
                await store.add(html: html, summary: session.description)
            }
            saving = false
            dismiss()
        }
    }

    private func injectIcon(_ data: Data, into html: String) -> String {
        let tag = "<link rel=\"apple-touch-icon icon\" href=\"data:image/jpeg;base64,\(data.base64EncodedString())\">"
        if let range = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: tag + "\n", at: range.lowerBound)
            return result
        }
        return tag + "\n" + html
    }
}
