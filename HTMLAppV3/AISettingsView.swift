import SwiftUI
import UniformTypeIdentifiers

struct AIConfigurationSettingsView: View {
    @AppStorage("htmlapp.aiBridge.enabled") private var aiBridgeEnabled = false
    @AppStorage("htmlapp.compactOutput.enabled") private var compactOutputEnabled = false
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("htmlapp.offlineForge.effort") private var offlineForgeEffort = "balanced"
    @AppStorage("ai.quickMode.policy") private var quickModePolicy = "automatic"
    @AppStorage("ai.quickLowReasoning") private var quickLowReasoning = true
    @AppStorage("generationMusic.enabled") private var musicEnabled = false
    @AppStorage("generationMusic.url") private var musicURL = ""
    @AppStorage("generationMusic.sourceMode") private var musicSourceMode = "file"
    @AppStorage("generationMusic.remoteURL") private var remoteMusicURL = ""
    @AppStorage("generationMusic.localURL") private var localMusicURL = ""
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
    @State private var showAdvancedGeneration = false
    @State private var musicPrefetchTask: Task<Void, Never>?
    @State private var choosingMusicFile = false
    @State private var musicFileError: String?

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

            Section("AI in saved apps") {
                Toggle("Allow saved apps to request AI", isOn: $aiBridgeEnabled)
                Text("Off by default. Each saved app also needs its own AI permission. Requests can consume API credits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Generation") {
                Toggle("Compact output (experimental)", isOn: $compactOutputEnabled)
                Text("Builds apps from a shared component library so they generate faster. Experimental.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Compact generation is not yet active; standard generation remains in use.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Offline Forge (Experimental)") {
                Picker("Default offline effort", selection: $offlineForgeEffort) {
                    ForEach(HTMLAppOfflineEffort.allCases) { effort in
                        Text(effort.title).tag(effort.rawValue)
                    }
                }
                LabeledContent("Apple Intelligence") {
                    Text(HTMLAppOfflineForge.availabilityMessage == nil ? "Ready on this device" : "Unavailable")
                        .foregroundStyle(HTMLAppOfflineForge.availabilityMessage == nil ? Color.green : Color.secondary)
                }
                Text(HTMLAppOfflineForge.availabilityMessage ?? "Offline generation is available. You will be asked to confirm before it runs.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("On-device generation needs iOS 26+, an eligible Apple Intelligence device, and a ready language model. Offline generation is generally slower and less capable and may use more battery. Cloud generation remains preferred while connected.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Button(showAdvancedGeneration ? "Hide advanced options" : "Show advanced options") {
                    showAdvancedGeneration.toggle()
                }
            }
            if showAdvancedGeneration {
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
                Picker("Music source", selection: $musicSourceMode) {
                    Text("Choose File").tag("file")
                    Text("Download URL").tag("url")
                }
                .pickerStyle(.segmented)
                .onAppear {
                    if remoteMusicURL.isEmpty && localMusicURL.isEmpty && !musicURL.isEmpty {
                        if musicURL.hasPrefix("file:") {
                            localMusicURL = musicURL
                            musicSourceMode = "file"
                        } else {
                            remoteMusicURL = musicURL
                            musicSourceMode = "url"
                        }
                    }
                }
                .onChange(of: musicSourceMode) { newMode in
                    musicURL = newMode == "url" ? remoteMusicURL : localMusicURL
                    generationMusic.prefetch()
                }
                if musicSourceMode == "url" {
                    TextField("Direct audio URL (https://…)", text: $remoteMusicURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: remoteMusicURL) { value in
                            musicURL = value
                            generationMusic.prefetch()
                        }
                } else {
                    Button {
                        choosingMusicFile = true
                    } label: {
                        Label(localMusicURL.isEmpty ? "Choose Audio File" : "Change Audio File", systemImage: "folder")
                    }
                    .fileImporter(isPresented: $choosingMusicFile,
                                  allowedContentTypes: [.audio]) { result in
                        do {
                            let selected = try result.get()
                            let accessed = selected.startAccessingSecurityScopedResource()
                            defer { if accessed { selected.stopAccessingSecurityScopedResource() } }
                            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("GenerationMusic", isDirectory: true)
                            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                            let ext = selected.pathExtension.isEmpty ? "m4a" : selected.pathExtension
                            let destination = root.appendingPathComponent(UUID().uuidString + "." + ext)
                            try FileManager.default.copyItem(at: selected, to: destination)
                            localMusicURL = destination.absoluteString
                            musicURL = localMusicURL
                            musicFileError = nil
                            generationMusic.prefetch()
                        } catch {
                            musicFileError = "Could not import audio file: \(error.localizedDescription)"
                        }
                    }
                    if !localMusicURL.isEmpty {
                        Text(URL(string: localMusicURL)?.lastPathComponent ?? "Selected audio")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let musicFileError {
                    Text(musicFileError).font(.caption).foregroundStyle(.red)
                }
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
                Text("Choose an audio file from Files or enter a direct HTTPS audio URL to download and cache it. Playback loops during generation and edits.")
            }

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
