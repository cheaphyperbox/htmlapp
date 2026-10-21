import SwiftUI

/// An optional connection for a single Forge stage. Keys remain in Keychain,
/// and existing shared-provider settings continue to work without migration.
struct AIRoleProviderSettingsView: View {
    let role: AIModelRole
    @Environment(\.dismiss) private var dismiss
    @State private var separate: Bool
    @State private var format: AIProviderConfiguration.Compatibility
    @State private var endpoint: String
    @State private var model: String
    @State private var key: String
    @State private var saved = false

    init(role: AIModelRole) {
        self.role = role
        let config = AISettingsStore.specialistConfiguration(for: role)
        _separate = State(initialValue: AISettingsStore.usesSpecialistProvider(for: role))
        _format = State(initialValue: config.compatibility)
        _endpoint = State(initialValue: config.apiURL)
        _model = State(initialValue: config.model)
        _key = State(initialValue: config.apiKey)
    }

    private var title: String {
        switch role {
        case .planner: return "Thinking"
        case .research: return "Research"
        case .coder: return "Programming"
        case .ui: return "UI Redesigning"
        case .icon: return "Icon Artist"
        case .verifier: return "QA Reviewer"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use a different AI for \(title)", isOn: $separate)
                Text(separate ? "This stage uses its own endpoint, model and Keychain-stored key." :
                    "This stage uses your main AI provider. Nothing else needs configuring.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if separate {
                Section("Specialist Connection") {
                    Picker("API format", selection: $format) {
                        ForEach(AIProviderConfiguration.Compatibility.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    TextField("API base URL", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model ID", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key (optional for local endpoints)", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !key.isEmpty {
                        Button("Clear specialist API key", role: .destructive) { key = "" }
                    }
                } footer: {
                    Text("OpenAI-compatible providers can use their own compatible chat/completions endpoint; Anthropic uses /v1/messages. For Gemini's OpenAI-compatible API, use https://generativelanguage.googleapis.com/v1beta/openai. Costs and compatibility depend on your provider.")
                }
            }

            Section {
                Button {
                    save()
                    dismiss()
                } label: {
                    Label("Save \(title) Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(separate && (endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                       model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            } footer: {
                if saved { Text("Settings saved. Future generation requests use the selected connection.") }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { saveIfValid() }
    }

    private func saveIfValid() {
        guard !separate || (!endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return }
        save()
    }

    private func save() {
        if separate {
            AISettingsStore.saveSpecialistConfiguration(
                AIProviderConfiguration(compatibility: format, apiURL: endpoint,
                                        model: model, apiKey: key), for: role
            )
        }
        AISettingsStore.setSpecialistProvider(separate, for: role)
        saved = true
    }
}
