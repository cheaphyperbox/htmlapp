import SwiftUI

struct AIConfigurationSettingsView: View {
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("ai.quickMode.policy") private var quickModePolicy = "manual"
    @AppStorage("ai.quickLowReasoning") private var quickLowReasoning = true
    @AppStorage("generationMusic.enabled") private var musicEnabled = false
    @AppStorage("generationMusic.url") private var musicURL = ""
    @AppStorage("generationMusic.volume") private var musicVolume = 0.6
    @ObservedObject private var generationMusic = GenerationMusic.shared
    @State private var compatibility = AISettingsStore.compatibility
    @State private var apiURL = AISettingsStore.apiURL
    @State private var apiKey = AISettingsStore.apiKey
    @State private var coderModel = AISettingsStore.model
    @State private var quickModel = AISettingsStore.quickModel
    @State private var plannerModel = AISettingsStore.plannerModel
    @State private var researchModel = AISettingsStore.researchModel
    @State private var uiModel = AISettingsStore.uiModel
    @State private var iconModel = AISettingsStore.iconModel
    @State private var verifierModel = AISettingsStore.verifierModel
    @State private var requestDelay = AISettingsStore.requestDelaySeconds
    @State private var appearancePreference = AISettingsStore.appearancePreference
    @State private var saved = false
    @State private var showAdvancedRoles = false

    var body: some View {
        Form {
            Section {
                Picker("API Format", selection: $compatibility) {
                    ForEach(AIProviderConfiguration.Compatibility.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                TextField("API Base URL", text: $apiURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("API Key (optional for local servers)", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Coding model name", text: $coderModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !apiKey.isEmpty {
                    Button("Clear API Key", role: .destructive) {
                        apiKey = ""
                        AISettingsStore.apiKey = ""
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Shared provider for normal generation; specialist AIs can use separate endpoints, models, and Keychain keys below.")
            }

            Section("Look & Feel") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What kinds of designs do you like?")
                        .font(.subheadline.weight(.medium))
                    TextField("e.g. Detailed, classic and warm — or very simple", text: $appearancePreference, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                    Text("Optional. The AI chooses the actual theme, colors, animations and icon for each new app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("QUICK! model name", text: $quickModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Quick mode", selection: $quickModePolicy) {
                    Text("Manual").tag("manual")
                    Text("Automatic").tag("automatic")
                }
                Toggle("Low reasoning on supported OpenAI models", isOn: $quickLowReasoning)
                Text("Optional: use a smaller, faster model on your main provider for planning, coding, research, icons, previews and verification during a QUICK! run. Low reasoning is sent only to supported direct OpenAI models, never generic compatible proxies. Normal specialist settings are unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("QUICK! Generation")
            }

            Section {
                Toggle("Play music while generating", isOn: $musicEnabled)
                TextField("Audio file URL (https://…)", text: $musicURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit { generationMusic.prefetch() }
                HStack {
                    Text("Volume")
                    Slider(value: $musicVolume, in: 0...1)
                        .onChange(of: musicVolume) { _ in generationMusic.applyVolume() }
                }
                Button(generationMusic.isPreview ? "Stop preview" : "Play preview") {
                    generationMusic.togglePreview()
                }
                .disabled((!generationMusic.isPreview && GenerationMusicSettings.validatedURL(musicURL) == nil) ||
                          generationMusic.isGenerationActive)
                Text(generationMusic.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Generation Music")
            } footer: {
                Text("Link to any audio file (MP3, M4A, WAV…). It downloads once, then loops during every app generation or edit and stops when the run finishes.")
            }

            Section("AI & Personal Data") {
                NavigationLink {
                    AIPrivacySettingsView()
                } label: {
                    Label("AI Generation Privacy", systemImage: "hand.raised.shield")
                }
            }

            Section("AI Specialists") {
                DisclosureGroup("Advanced per-role overrides", isExpanded: $showAdvancedRoles) {
                NavigationLink { AIRoleProviderSettingsView(role: .planner) } label: {
                    specialistLabel("Thinking", symbol: "brain", role: .planner)
                }
                NavigationLink { AIRoleProviderSettingsView(role: .research) } label: {
                    specialistLabel("Research", symbol: "globe", role: .research)
                }
                NavigationLink { AIRoleProviderSettingsView(role: .coder) } label: {
                    specialistLabel("Programming", symbol: "chevron.left.forwardslash.chevron.right", role: .coder)
                }
                NavigationLink { AIRoleProviderSettingsView(role: .ui) } label: {
                    specialistLabel("UI Redesigning", symbol: "paintpalette", role: .ui)
                }
                NavigationLink { AIRoleProviderSettingsView(role: .icon) } label: {
                    specialistLabel("Icon Artist", symbol: "app.badge", role: .icon)
                }
                NavigationLink { AIRoleProviderSettingsView(role: .verifier) } label: {
                    specialistLabel("QA Reviewer", symbol: "checkmark.shield", role: .verifier)
                }
                }
            }
            if developerMode {
            Section {
                Stepper(value: $requestDelay, in: 0...60, step: 0.1) {
                    HStack {
                        Text("Minimum request spacing")
                        Spacer()
                        Text("\(requestDelay, specifier: "%.1f") s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Keep this low for fast agent loops. Increase it only when your API provider rate-limits consecutive planning, research, coding, icon, or QA requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Performance")
            }
            } // Developer Mode

            Section {
                Button {
                    save()
                } label: {
                    Label(saved ? "Saved" : "Save AI Configuration", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    coderModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .htmlAppFirstUseToasts()
        .onAppear { HTMLAppFirstUseTips.show("aiSettings") }
        .navigationTitle("AI & Creation")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            generationMusic.stopPreview()
            if !apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !coderModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                save(showConfirmation: false)
            }
        }
    }

    private func specialistLabel(_ name: String, symbol: String, role: AIModelRole) -> some View {
        HStack {
            Label(name, systemImage: symbol)
            Spacer()
            if AISettingsStore.usesSpecialistProvider(for: role) {
                Circle().fill(Color.green)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Specialist enabled")
            }
        }
    }

    @ViewBuilder
    private func modelField(_ title: String, text: Binding<String>, icon: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            TextField("Model name", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private func save(showConfirmation: Bool = true) {
        AISettingsStore.compatibility = compatibility
        AISettingsStore.apiURL = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.apiKey = apiKey
        AISettingsStore.model = coderModel
        AISettingsStore.quickModel = quickModel
        AISettingsStore.plannerModel = plannerModel
        AISettingsStore.researchModel = researchModel
        AISettingsStore.uiModel = uiModel
        AISettingsStore.iconModel = iconModel
        AISettingsStore.verifierModel = verifierModel
        AISettingsStore.requestDelaySeconds = requestDelay
        AISettingsStore.appearancePreference = appearancePreference
        if musicEnabled && GenerationMusicSettings.validatedURL(musicURL) != nil &&
           !generationMusic.isGenerationActive && !generationMusic.isPreview {
            // Prepare the real audible track before the user locks the screen.
            generationMusic.prefetch()
        }

        guard showConfirmation else { return }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }
}
