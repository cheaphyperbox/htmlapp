import SwiftUI

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0

    private let pages = [
        ("Make, save, and remix", "rectangle.stack.badge.plus", "HTMLApp keeps websites, hand-written HTML, imported files, and AI-created apps together in one native library."),
        ("An AI team, not one model", "sparkles", "Use one API connection, then choose separate models for planning, web research, coding, UI refinement, icon/assets, and final verification."),
        ("Agentic first editions", "wand.and.stars", "Describe the outcome you want. Forge plans the product, researches real facts/APIs when useful, anticipates a few likely next-step features, builds a live preview, and repairs concrete issues before you save."),
        ("Portable generated artwork", "photo.stack", "AI can create a real app icon plus purpose-built IconScript illustrations. Generated artwork is embedded in the HTMLApp so it survives sharing and backups."),
        ("Save whole websites", "arrow.down.circle", "Download a website and its referenced resources for offline use. HTMLApp opens the saved copy first and can refresh it in the background."),
        ("Share the actual HTMLApp", "arrow.left.arrow.right.square", "Use Share HTMLApp Package for AirDrop, Files, Messages, or another device. Packages preserve app metadata and cached resources; nearby QR transfer remains available for smaller apps."),
        ("Back up your library", "shippingbox.fill", "Settings > Backup & Transfer can export selected apps or the complete library as a ZIP, then Merge or fully Restore it on another device."),
        ("Real device capabilities", "gyroscope", "Generated apps can use HTMLApp's documented camera, microphone, location, contacts, photos, calendar, reminders, notifications, biometrics, Files, Maps, Shortcuts, secure storage, speech, sharing, and local-network bridges when appropriate."),
        ("Tap, swipe, or hold", "hand.tap", "Tap an app to open it. In list view, swipe for common actions. Press and hold for sharing, permissions, AI editing, icon generation, raw HTML, and advanced actions."),
        ("Add it to Home Screen", "apps.iphone", "Any saved HTMLApp can still be installed as a Home Screen Web Clip with its saved icon.")
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
                    NavigationLink {
                        AIConfigurationSettingsView()
                    } label: {
                        Label("AI & Creation", systemImage: "sparkles.rectangle.stack")
                    }

                    NavigationLink {
                        HTMLAppDataTransferView()
                            .environmentObject(store)
                    } label: {
                        Label("Backup & Transfer", systemImage: "arrow.left.arrow.right.square")
                    }
                } header: {
                    Text("Creation & Transfer")
                } footer: {
                    Text("Configure your specialized AI team in one place, or move selected apps and complete libraries between devices with portable ZIP backups.")
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
                    Button("Done") { dismiss() }
                }
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
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
