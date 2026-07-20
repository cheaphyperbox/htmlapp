import SwiftUI

struct OnboardingView: View {
    @Binding var complete: Bool
    @State private var page = 0
    private let pages = [
        ("Welcome to HTMLApp", "rectangle.stack.badge.plus", "Tap +, paste or write HTML, preview it, then save."),
        ("Open and manage", "hand.tap", "Tap to launch. Press and hold to edit, copy, refresh, duplicate, install a Web Clip, or delete."),
        ("Add to Home Screen", "apps.iphone", "Tap Home Screen, generate the profile, then review and install it in iOS Settings."),
        ("Automatic icons", "app.badge", "Favicons are saved as PNG. Otherwise HTMLApp uses the first initial and detected page colors."),
        ("Permissions", "hand.raised.fill", "Camera and microphone requests receive an extra prompt for the requesting saved app."),
        ("Deep links", "link", "Use htmlapp://open?id=ABC123 to launch a saved app from Shortcuts or a Web Clip.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 { Button("Back") { withAnimation { page -= 1 } } }
                Spacer()
                Text("\(page + 1) of \(pages.count)").font(.caption).foregroundStyle(.secondary)
            }.padding()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: pages[index].1).font(.system(size: 66, weight: .semibold)).foregroundStyle(.tint)
                        Text(pages[index].0).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(pages[index].2).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 34)
                        Spacer()
                    }.tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .always))
            Button(page == pages.count - 1 ? "Start Using HTMLApp" : "Continue") {
                if page == pages.count - 1 { complete = true } else { withAnimation { page += 1 } }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).padding()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("sourceRefreshDays") private var sourceRefreshDays = 3
    @AppStorage("webClipFullScreen") private var webClipFullScreen = true
    @AppStorage("webClipPrecomposed") private var webClipPrecomposed = false
    @AppStorage("allowJavaScript") private var allowJavaScript = true
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Saved apps", value: "\(store.apps.count)")
                    Button("Refresh All External Sources") { refreshAll() }.disabled(working || store.apps.isEmpty)
                    Button("Rebuild All Saved Icons") { rebuildIcons() }.disabled(working || store.apps.isEmpty)
                    Button("Clear All Source Caches", role: .destructive) { SourceCache.shared.clearAll() }
                }
                Section("External Source Cache") {
                    Stepper("Refresh after \(sourceRefreshDays) days", value: $sourceRefreshDays, in: 1...30)
                    Text("Old cached copies are preserved if updating fails or the device is offline.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Home Screen Web Clips") {
                    Toggle("Open Web Clips full screen", isOn: $webClipFullScreen)
                    Toggle("Use precomposed icons", isOn: $webClipPrecomposed)
                    Text("The saved PNG icon is converted to base64 and embedded in the generated .mobileconfig profile.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Web Content") {
                    Toggle("Allow JavaScript", isOn: $allowJavaScript)
                    Text("Camera and microphone requests still receive per-app prompts.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Tutorial") {
                    Button("Show Tutorial Again") { onboardingComplete = false; dismiss() }
                }
                Section("About") {
                    LabeledContent("Minimum iOS", value: "16.0")
                    LabeledContent("URL scheme", value: "htmlapp://")
                    Text("Review profiles before installation and only import HTML or JavaScript you trust.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
    }

    private func refreshAll() {
        working = true
        Task { for app in store.apps { await SourceCache.shared.refresh(app: app, force: true) }; working = false; store.notice = "External sources refreshed." }
    }
    private func rebuildIcons() {
        working = true
        Task { await store.rebuildIcons(); working = false }
    }
}
