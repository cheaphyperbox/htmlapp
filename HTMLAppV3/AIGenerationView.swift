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

    var body: some View {
        NavigationStack {
            Group {
                if session.streamedHTML.isEmpty && !session.isWorking {
                    promptView
                } else {
                    studioView
                }
            }
            .navigationTitle("Generate")
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
                "Discard this AI generation?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard and Close", role: .destructive) { dismiss() }
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text("The generated preview and current AI work will be lost if you close it without saving.")
            }
            .alert("Generation Error", isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )) {
                Button("OK") { session.errorMessage = nil }
            } message: {
                Text(session.errorMessage ?? "")
            }
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
                Text("Describe the app, its purpose, and any data you want it to use. HTMLApp will refine the idea, research suitable public APIs when useful, build a live preview, and optionally run the finished UI through your separate UI Overhaul model.")
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
                    Label("A separate UI Overhaul model will make a conservative visual-only refinement after the functional generation finishes.", systemImage: "paintbrush")
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
                                Image(systemName: "doc.text.magnifyingglass")
                            }
                            .accessibilityLabel("View refined brief")
                        }
                    }
                    if let uiPolishNotice {
                        Text(uiPolishNotice)
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
                    appID: "PREVIEW"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !session.isWorking && !session.streamedHTML.isEmpty {
                    VStack(spacing: 10) {
                        if showingChange {
                            HStack(spacing: 8) {
                                TextField("What should change?", text: $changePrompt, axis: .vertical)
                                    .lineLimit(1...3)
                                    .textFieldStyle(.roundedBorder)
                                Button("Apply") {
                                    let change = changePrompt
                                    changePrompt = ""
                                    showingChange = false
                                    uiPolishNotice = nil
                                    Task { await session.revise(change: change) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(changePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Button("Change this…") { showingChange = true }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity)
                                Button("Looks good") { saveGeneratedApp() }
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
                            Text("Saving app…").font(.headline)
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
                  !session.streamedHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  AISettingsStore.isUIOverhaulEnabled else { return }

            let functionalHTML = session.streamedHTML
            session.isWorking = true
            session.phase = "Polishing the interface"
            do {
                let polished = try await UIOverhaulService.polish(html: functionalHTML, originalPrompt: originalPrompt)
                session.streamedHTML = polished
                session.phase = "Ready to review"
                uiPolishNotice = "UI Overhaul finished without intentionally changing app functionality."
            } catch {
                session.streamedHTML = functionalHTML
                session.phase = "Ready to review"
                uiPolishNotice = "UI Overhaul was skipped because it failed. The original functional generation was preserved."
            }
            session.isWorking = false
        }
    }

    private func saveGeneratedApp() {
        saving = true
        Task {
            var html = session.streamedHTML
            if let icon = await AIIconRenderer.render(script: session.iconScript) {
                html = injectIcon(icon, into: html)
            }
            await store.add(html: html, summary: session.description)
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
