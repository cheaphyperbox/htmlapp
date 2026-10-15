import SwiftUI

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0

    private let pages = [
        ("Create an HTML app", "rectangle.stack.badge.plus", "Tap + to generate an app with AI, download a website, paste or write HTML, select a file, or receive one from another device."),
        ("Generate with AI", "sparkles", "Configure an OpenAI-compatible or Anthropic-compatible API in Settings. Describe what you want, watch the app appear live, then keep it or ask for changes."),
        ("Optional UI polish", "paintbrush", "You can configure a second AI model just for presentation. It receives the finished app and is told to improve only the UI while preserving every feature and behavior."),
        ("Downloaded websites", "arrow.down.circle", "Save a website and its referenced resources for offline use. HTMLApp opens the saved copy first and checks for a newer version in the background."),
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
    @AppStorage("librarySortMode") private var librarySortModeRaw = LibrarySortMode.alphabeticalAZ.rawValue
    @AppStorage("librarySortDateBasis") private var librarySortDateBasisRaw = LibrarySortDateBasis.modified.rawValue
    @AppStorage("libraryFoldersOnTop") private var libraryFoldersOnTop = true
    @AppStorage("libraryFavoritesOnTop") private var libraryFavoritesOnTop = true
    @AppStorage("askBeforeSwitch") private var askBeforeSwitch = true
    @AppStorage("sourceRefreshDays") private var sourceRefreshDays = 3
    @AppStorage("autoApplyWebsiteUpdates") private var autoApplyWebsiteUpdates = false
    @AppStorage("webClipFullScreen") private var webClipFullScreen = true
    @AppStorage("webClipPrecomposed") private var webClipPrecomposed = false
    @AppStorage("allowJavaScript") private var allowJavaScript = true
    @State private var working = false
    @State private var aiCompatibility = AISettingsStore.compatibility
    @State private var aiURL = AISettingsStore.apiURL
    @State private var aiModel = AISettingsStore.model
    @State private var plannerModel = AISettingsStore.plannerModel
    @State private var researchModel = AISettingsStore.researchModel
    @State private var uiModel = AISettingsStore.uiModel
    @State private var iconModel = AISettingsStore.iconModel
    @State private var verifierModel = AISettingsStore.verifierModel
    @State private var aiKey = AISettingsStore.apiKey
    @State private var aiRequestDelay = AISettingsStore.requestDelaySeconds
    @State private var aiSystemPrompt = AISettingsStore.systemPrompt
    @State private var confirmRestoreSystemPrompt = false
    @State private var aiSaved = false

    private var selectedSortMode: LibrarySortMode {
        LibrarySortMode(rawValue: librarySortModeRaw) ?? .alphabeticalAZ
    }

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
                    Toggle("Folders on top", isOn: $libraryFoldersOnTop)
                    Toggle("Favorite apps on top", isOn: $libraryFavoritesOnTop)

                    Picker("Sort", selection: $librarySortModeRaw) {
                        ForEach(LibrarySortMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }

                    if selectedSortMode.usesDateBasis {
                        Picker("Latest uses", selection: $librarySortDateBasisRaw) {
                            ForEach(LibrarySortDateBasis.allCases) { basis in
                                Text(basis.title).tag(basis.rawValue)
                            }
                        }
                    }
                } header: {
                    Text("Library Sorting")
                } footer: {
                    Text(librarySortDescription)
                }

                Section {
                    Picker("API Format", selection: $aiCompatibility) {
                        ForEach(AIProviderConfiguration.Compatibility.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    TextField("API Base URL", text: $aiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("API Key (optional for local servers)", text: $aiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !aiKey.isEmpty {
                        Button("Clear API Key", role: .destructive) {
                            aiKey = ""
                            AISettingsStore.apiKey = ""
                        }
                    }
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text("Every AI role uses this same API URL, compatibility format, and Keychain-stored API key. Only the model name changes per task.")
                }

                Section {
                    modelField("Coding Agent", text: $aiModel, help: "Builds and edits the actual HTMLApp.")
                    modelField("Prompt Planner", text: $plannerModel, help: "Turns rough requests into complete product plans and anticipates useful next-step features.")
                    modelField("Research Agent", text: $researchModel, help: "Chooses web searches/pages and summarizes evidence. Leave equal to Planner if you do not need a separate model.")
                    modelField("UI Overhaul", text: $uiModel, help: "Optional. Leave blank to skip the separate visual-only refinement stage.")
                    modelField("Icon & Asset Artist", text: $iconModel, help: "Creates App Store-style icons and portable generated artwork using IconScript.")
                    modelField("QA Verifier", text: $verifierModel, help: "Audits, repairs, and rechecks the finished app before save.")

                    Stepper(value: $aiRequestDelay, in: 0...60, step: 0.1) {
                        HStack {
                            Text("Request spacing")
                            Spacer()
                            Text("\(aiRequestDelay, specifier: "%.1f") s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Button(aiSaved ? "Saved" : "Save AI Setup") { saveAI() }
                        .disabled(
                            aiURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                } header: {
                    Text("AI Team")
                } footer: {
                    Text("Use specialized models without configuring multiple providers. Blank optional roles fall back to the most relevant configured model.")
                }

                Section {
                    NavigationLink {
                        HTMLAppDataTransferView()
                            .environmentObject(store)
                    } label: {
                        Label("Backup & Transfer", systemImage: "arrow.left.arrow.right.square")
                    }
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    LabeledContent("Folders", value: "\(store.folders.count)")
                } header: {
                    Text("Sharing & Data")
                } footer: {
                    Text("Export one app, selected apps, or the complete library as a portable ZIP. Import on another device with Merge or full Restore.")
                }

                Section {
                    DisclosureGroup("Advanced System Prompt") {
                        TextEditor(text: $aiSystemPrompt)
                            .font(.caption.monospaced())
                            .frame(minHeight: 320)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save System Prompt") {
                            AISettingsStore.systemPrompt = aiSystemPrompt
                            aiSystemPrompt = AISettingsStore.systemPrompt
                            aiSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { aiSaved = false }
                        }
                        .disabled(aiSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Restore Built-in Agent Prompt", role: .destructive) {
                            confirmRestoreSystemPrompt = true
                        }
                    }
                } header: {
                    HStack {
                        Text("Agent Instructions")
                        Spacer()
                        Text(AISettingsStore.isUsingCustomSystemPrompt ? "Custom" : "Built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Most people should leave this alone. The built-in Forge prompt includes product planning, onboarding decisions, anticipatory features, native/API truthfulness, IconScript assets, and final QA.")
                }

                Section("Opening Apps") {
                    Toggle("Ask before switching apps", isOn: $askBeforeSwitch)
                    Text("When a URL scheme arrives while an HTML app is open, HTMLApp can ask before unloading it and opening the linked app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Downloaded Websites") {
                    Toggle("Always apply website updates immediately", isOn: $autoApplyWebsiteUpdates)
                    Text(autoApplyWebsiteUpdates
                         ? "When a newer downloaded website snapshot finishes in the background, HTMLApp automatically restarts that app into the new version."
                         : "When a newer snapshot is found, HTMLApp asks whether to restart now or use it on the next launch.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Library") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    LabeledContent("Folders", value: "\(store.folders.count)")
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
            .confirmationDialog("Restore the default AI system prompt?", isPresented: $confirmRestoreSystemPrompt, titleVisibility: .visible) {
                Button("Restore Default", role: .destructive) {
                    AISettingsStore.restoreDefaultSystemPrompt()
                    aiSystemPrompt = AISettingsStore.defaultSystemPrompt
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your custom app-generation system prompt will be replaced by HTMLApp’s built-in default prompt.")
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
    }

    @ViewBuilder
    private func modelField(_ title: String, text: Binding<String>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var librarySortDescription: String {
        switch selectedSortMode {
        case .alphabeticalAZ, .alphabeticalZA:
            return libraryFoldersOnTop
                ? "Folders are grouped above apps, then names use the selected alphabetical order."
                : "Folders and apps are mixed together and sorted by name."
        case .latestFirst:
            return "The newest items appear first using \(sortDateBasisTitle.lowercased())."
        case .latestLast:
            return "The newest items appear last using \(sortDateBasisTitle.lowercased())."
        case .recentlyOpened:
            return "Recently used items appear first. Creating a new app counts as recent activity, so it appears at the top of the app ordering immediately."
        }
    }

    private var sortDateBasisTitle: String {
        (LibrarySortDateBasis(rawValue: librarySortDateBasisRaw) ?? .modified).title
    }

    private func saveAI(silent: Bool = false) {
        AISettingsStore.compatibility = aiCompatibility
        AISettingsStore.apiURL = aiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.plannerModel = plannerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.researchModel = researchModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.uiModel = uiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.iconModel = iconModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.verifierModel = verifierModel.trimmingCharacters(in: .whitespacesAndNewlines)
        AISettingsStore.apiKey = aiKey
        AISettingsStore.requestDelaySeconds = aiRequestDelay
        AISettingsStore.systemPrompt = aiSystemPrompt
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
