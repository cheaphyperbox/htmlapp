import SwiftUI

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0

    private let pages = [
        ("Create an HTML app", "rectangle.stack.badge.plus", "Tap + to generate an app with AI, paste or write HTML, select a file, or receive one from another device."),
        ("Generate with AI", "sparkles", "Configure an OpenAI-compatible or Anthropic-compatible API in Settings. Describe what you want, watch the app appear live, then keep it or ask for changes."),
        ("Optional UI polish", "paintbrush", "You can configure a second AI model just for presentation. It receives the finished app and is told to improve only the UI while preserving every feature and behavior."),
        ("Tap, swipe, or hold", "hand.tap", "Tap an app to open it. In list view, swipe for common actions. Press and hold anywhere for the full menu."),
        ("Choose your layout", "square.grid.3x3", "Use List for details or Grid for an iPhone-style Home Screen. Grid apps automatically continue onto swipeable pages."),
        ("Device capabilities", "gyroscope", "Each app can have separate camera, microphone, location, notification, and motion/orientation choices. Haptics are available after user interaction without a per-app permission."),
        ("Add it to Home Screen", "apps.iphone", "Press and hold an app, choose Install Home Screen Web Clip, then follow the iOS profile installation prompts."),
        ("Open with deep links", "link", "Use htmlapp://open?id=ABC123. You can choose whether HTMLApp asks before replacing an app that is already open.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 { Button("Back") { withAnimation { page -= 1 } } }
                Spacer()
                Text("\(page + 1) of \(pages.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding()

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: pages[index].1)
                            .font(.system(size: 66, weight: .semibold))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                        Text(pages[index].0).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(pages[index].2)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(page == pages.count - 1 ? "Start Using HTMLApp" : "Continue") {
                if page == pages.count - 1 { complete = true }
                else { withAnimation { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @AppStorage("askBeforeSwitch") private var askBeforeSwitch = true
    @AppStorage("sourceRefreshDays") private var sourceRefreshDays = 3
    @AppStorage("webClipFullScreen") private var webClipFullScreen = true
    @AppStorage("webClipPrecomposed") private var webClipPrecomposed = false
    @AppStorage("allowJavaScript") private var allowJavaScript = true
    @State private var working = false
    @State private var aiCompatibility = AISettingsStore.compatibility
    @State private var aiURL = AISettingsStore.apiURL
    @State private var aiModel = AISettingsStore.model
    @State private var aiKey = AISettingsStore.apiKey
    @State private var uiCompatibility = AISettingsStore.uiCompatibility
    @State private var uiURL = AISettingsStore.uiAPIURL
    @State private var uiModel = AISettingsStore.uiModel
    @State private var uiKey = AISettingsStore.uiAPIKey
    @State private var aiSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Home View") {
                    Picker("Layout", selection: $libraryLayout) {
                        Label("List", systemImage: "list.bullet").tag("list")
                        Label("Grid", systemImage: "square.grid.3x3").tag("grid")
                    }
                    .pickerStyle(.segmented)
                    Text(libraryLayout == "grid"
                         ? "Grid resembles an iPhone Home Screen and creates swipeable pages when needed."
                         : "List shows descriptions and supports quick swipe actions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Picker("Compatibility", selection: $aiCompatibility) {
                        ForEach(AIProviderConfiguration.Compatibility.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    TextField("API URL", text: $aiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model", text: $aiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key (optional for local servers)", text: $aiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(aiSaved ? "Saved" : "Save AI Configuration") { saveAI() }
                        .disabled(aiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !aiKey.isEmpty {
                        Button("Clear Main API Key", role: .destructive) {
                            aiKey = ""
                            AISettingsStore.apiKey = ""
                        }
                    }
                } header: {
                    Text("AI App Generator")
                } footer: {
                    Text("This is the main functional generation model. Its API key is stored in this device’s Keychain and is sent only to the API URL you configure.")
                }

                Section {
                    Picker("Compatibility", selection: $uiCompatibility) {
                        ForEach(AIProviderConfiguration.Compatibility.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    TextField("UI API URL", text: $uiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("UI Overhaul Model (optional)", text: $uiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("UI API Key (optional)", text: $uiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !uiKey.isEmpty {
                        Button("Clear UI API Key", role: .destructive) {
                            uiKey = ""
                            AISettingsStore.uiAPIKey = ""
                        }
                    }
                } header: {
                    Text("UI Overhaul Model")
                } footer: {
                    Text("Optional. Leave the model empty to skip this stage. When configured, HTMLApp sends the completed functioning app to this second model for a conservative visual-only pass. It is instructed not to add, remove, or alter functionality. This can use a different provider, URL, key, and model from the main generator.")
                }

                Section("Opening Apps") {
                    Toggle("Ask before switching apps", isOn: $askBeforeSwitch)
                    Text("When a URL scheme arrives while an HTML app is open, HTMLApp can ask before unloading it and opening the linked app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Library") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    Button("Refresh All External Sources") { refreshAll() }.disabled(working || store.apps.isEmpty)
                    Button("Rebuild All Saved Icons") { rebuildIcons() }.disabled(working || store.apps.isEmpty)
                    Button("Clear All Source Caches", role: .destructive) { SourceCache.shared.clearAll() }
                }

                Section("External Source Cache") {
                    Stepper("Refresh after \(sourceRefreshDays) days", value: $sourceRefreshDays, in: 1...30)
                    Text("Old cached copies remain available if updating fails or the device is offline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Home Screen Profiles") {
                    Toggle("Open Web Clips full screen", isOn: $webClipFullScreen)
                    Toggle("Use precomposed icons", isOn: $webClipPrecomposed)
                    Text("Profiles include the saved PNG icon as base64 data.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Web Content") {
                    Toggle("Allow JavaScript", isOn: $allowJavaScript)
                    Text("Protected device capabilities still use each saved app’s Permissions page and applicable iOS system permissions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Tutorial") {
                    Button("Show Tutorial Again") {
                        onboardingComplete = false
                        dismiss()
                    }
                }

                Section("About") {
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("URL scheme", value: "htmlapp://")
                    Text("The interface uses native system navigation, toolbars, menus, materials, and controls and adapts across iPhone and iPad.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAI(silent: true)
                        dismiss()
                    }
                }
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
    }

    private func saveAI(silent: Bool = false) {
        AISettingsStore.compatibility = aiCompatibility
        AISettingsStore.apiURL = aiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.apiKey = aiKey
        AISettingsStore.uiCompatibility = uiCompatibility
        AISettingsStore.uiAPIURL = uiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.uiModel = uiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.uiAPIKey = uiKey
        if !silent {
            aiSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { aiSaved = false }
        }
    }

    private func refreshAll() {
        working = true
        Task {
            for app in store.apps { await SourceCache.shared.refresh(app: app, force: true) }
            working = false
            store.notice = "External sources refreshed."
        }
    }

    private func rebuildIcons() {
        working = true
        Task {
            await store.rebuildIcons()
            working = false
        }
    }
}
