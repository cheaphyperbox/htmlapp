import SwiftUI

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0

    private let pages = [
        ("Create an HTML app", "rectangle.stack.badge.plus", "Tap +, paste or write HTML, preview it, then save. HTMLApp automatically reads its name and icon."),
        ("Tap, swipe, or hold", "hand.tap", "Tap an app to open it. In list view, swipe for Edit, Delete, Refresh, or Home Screen actions. Press and hold anywhere for the full menu."),
        ("Choose your layout", "square.grid.3x3", "Use List for details or Grid for an iPhone-style Home Screen. Grid apps automatically continue onto swipeable pages."),
        ("Add it to Home Screen", "apps.iphone", "Press and hold an app, choose Install Home Screen Web Clip, then let Safari download the generated profile."),
        ("Automatic icons", "app.badge", "Favicons are saved as PNG. Without one, HTMLApp creates an icon from the first initial and the page’s detected colors."),
        ("Open with deep links", "link", "Use htmlapp://open?id=ABC123. You can choose whether HTMLApp asks before replacing an app that is already open.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                }
                Spacer()
                Text("\(page + 1) of \(pages.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                        Text(pages[index].0)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
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
                if page == pages.count - 1 {
                    complete = true
                } else {
                    withAnimation { page += 1 }
                }
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Opening Apps") {
                    Toggle("Ask before switching apps", isOn: $askBeforeSwitch)
                    Text("When a URL scheme arrives while an HTML app is open, HTMLApp can ask before unloading it and opening the linked app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Library") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    Button("Refresh All External Sources") { refreshAll() }
                        .disabled(working || store.apps.isEmpty)
                    Button("Rebuild All Saved Icons") { rebuildIcons() }
                        .disabled(working || store.apps.isEmpty)
                    Button("Clear All Source Caches", role: .destructive) {
                        SourceCache.shared.clearAll()
                    }
                }

                Section("External Source Cache") {
                    Stepper("Refresh after \(sourceRefreshDays) days", value: $sourceRefreshDays, in: 1...30)
                    Text("Old cached copies remain available if updating fails or the device is offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Home Screen Profiles") {
                    Toggle("Open Web Clips full screen", isOn: $webClipFullScreen)
                    Toggle("Use precomposed icons", isOn: $webClipPrecomposed)
                    Text("Profiles are served to Safari as application/x-apple-aspen-config and include the saved PNG icon as base64 data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Web Content") {
                    Toggle("Allow JavaScript", isOn: $allowJavaScript)
                    Text("Camera and microphone requests still receive an additional per-app prompt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Text("The interface uses system navigation, toolbars, menus, materials, and controls so iOS 26 can apply its native Liquid Glass appearance when built with the iOS 26 SDK.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if working { ProgressView().controlSize(.large) }
            }
        }
    }

    private func refreshAll() {
        working = true
        Task {
            for app in store.apps {
                await SourceCache.shared.refresh(app: app, force: true)
            }
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