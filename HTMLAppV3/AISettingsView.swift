import SwiftUI

struct AIConfigurationSettingsView: View {
    @AppStorage("developerMode") private var developerMode = false
    @State private var compatibility = AISettingsStore.compatibility
    @State private var apiURL = AISettingsStore.apiURL
    @State private var apiKey = AISettingsStore.apiKey
    @State private var coderModel = AISettingsStore.model
    @State private var plannerModel = AISettingsStore.plannerModel
    @State private var researchModel = AISettingsStore.researchModel
    @State private var uiModel = AISettingsStore.uiModel
    @State private var iconModel = AISettingsStore.iconModel
    @State private var verifierModel = AISettingsStore.verifierModel
    @State private var requestDelay = AISettingsStore.requestDelaySeconds
    @State private var systemPrompt = AISettingsStore.systemPrompt
    @State private var saved = false
    @State private var confirmRestorePrompt = false

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

                if !apiKey.isEmpty {
                    Button("Clear API Key", role: .destructive) {
                        apiKey = ""
                        AISettingsStore.apiKey = ""
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("All roles share this provider, base URL, compatibility format, and Keychain-stored API key. HTMLApp only varies the model name by task.")
            }

            Section {
                modelField(
                    "Coding Agent",
                    text: $coderModel,
                    icon: "hammer.fill",
                    help: "Builds and edits the actual HTMLApp. This is the required model."
                )
                if developerMode {
                modelField(
                    "Prompt Planner",
                    text: $plannerModel,
                    icon: "list.bullet.clipboard.fill",
                    help: "Turns rough ideas into complete product plans, onboarding decisions, and high-value anticipated features."
                )
                modelField(
                    "Research Agent",
                    text: $researchModel,
                    icon: "globe.americas.fill",
                    help: "Plans searches, reads public pages, and summarizes current evidence before the coding pass."
                )
                modelField(
                    "UI Overhaul",
                    text: $uiModel,
                    icon: "paintbrush.fill",
                    help: "Optional. Leave blank to skip the separate visual-only refinement pass."
                )
                modelField(
                    "Icon & Asset Artist",
                    text: $iconModel,
                    icon: "app.badge.fill",
                    help: "Creates simple App Store-style icons and portable generated IconScript artwork."
                )
                modelField(
                    "QA Verifier",
                    text: $verifierModel,
                    icon: "checkmark.shield.fill",
                    help: "Runs the independent release audit, applies concrete repairs, and rechecks the result."
                )
                }
            } header: {
                Text("AI Team")
            } footer: {
                Text(developerMode ? "Blank optional model fields use fallbacks. UI Overhaul stays optional." : "The Coding Agent is all you need for normal generation. Enable Developer Mode in Settings for additional model roles.")
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

            Section {
                DisclosureGroup("Built-in Forge system prompt") {
                    TextEditor(text: $systemPrompt)
                        .font(.caption.monospaced())
                        .frame(minHeight: 360)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Restore Built-in Prompt", role: .destructive) {
                        confirmRestorePrompt = true
                    }
                }
            } header: {
                HStack {
                    Text("Advanced")
                    Spacer()
                    Text(AISettingsStore.isUsingCustomSystemPrompt ? "Custom prompt" : "Built-in prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("The built-in Forge prompt already covers product anticipation, onboarding, portable app data, device/API truthfulness, generated assets, iOS-quality icons, accessibility, and release QA. Edit it only when you intentionally want different agent behavior.")
            }

            }
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
        .navigationTitle("AI & Creation")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Restore HTMLApp Forge's built-in system prompt?",
            isPresented: $confirmRestorePrompt,
            titleVisibility: .visible
        ) {
            Button("Restore Built-in Prompt", role: .destructive) {
                AISettingsStore.restoreDefaultSystemPrompt()
                systemPrompt = AISettingsStore.defaultSystemPrompt
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your custom system prompt will be replaced with the current built-in agent instructions.")
        }
        .onDisappear {
            if !apiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !coderModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                save(showConfirmation: false)
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
        AISettingsStore.plannerModel = plannerModel
        AISettingsStore.researchModel = researchModel
        AISettingsStore.uiModel = uiModel
        AISettingsStore.iconModel = iconModel
        AISettingsStore.verifierModel = verifierModel
        AISettingsStore.requestDelaySeconds = requestDelay
        AISettingsStore.systemPrompt = systemPrompt

        guard showConfirmation else { return }
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            saved = false
        }
    }
}
