import SwiftUI
import UIKit
import WidgetKit

struct ForgeDeveloperDiagnosticsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var tracker = ForgeWorkTracker()
    @State private var selectedID = ""
    @State private var copied = false

    private var diagnosticText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return """
        HTMLApp support report
        Version: \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Device class: \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        Library apps: \(store.apps.count)
        App Group: \(HTMLAppSharedContainer.appGroupID)
        Shared container accessible: \(HTMLAppSharedContainer.appGroupAvailable)
        Declared common groups: \(HTMLAppSigningGroups.common.count)
        Saved AI debug runs: \(AIDebugTraceStore.shared.history.count)
        """
    }

    var body: some View {
        List {
            Section("Installed build") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                Button {
                    UIPasteboard.general.string = diagnosticText
                    copied = true
                } label: {
                    Label(copied ? "Copied support summary" : "Copy support summary", systemImage: "doc.on.doc")
                }
            }

            Section("AI failure reports") {
                NavigationLink {
                    AIDebugTraceView()
                } label: {
                    Label("Last AI generation & edit logs", systemImage: "ladybug")
                }
                LabeledContent("Saved run logs", value: "\(AIDebugTraceStore.shared.history.count)")
                Text("View past failed edits, exact stage timing, model responses and runtime QA errors. Logs are kept on this device and may include source code or private app descriptions; only share them intentionally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Time spent on apps") {
                Picker("Saved app", selection: $selectedID) {
                    Text("Pick an app").tag("")
                    ForEach(store.orderedApps) { app in
                        Text(app.name).tag(app.id)
                    }
                }
                if tracker.recentRuns.isEmpty {
                    Text("No recorded runs yet for this app. The next generation or edit will add a timing report.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForgeWorkRing(runs: tracker.recentRuns, active: false)
                        .frame(maxWidth: .infinity)
                    ForgeRunBreakdown(runs: tracker.recentRuns)
                }
            }

            Section("Widget storage") {
                LabeledContent("App Group", value: HTMLAppSharedContainer.appGroupID)
                LabeledContent("Storage", value: HTMLAppSharedContainer.appGroupAvailable ? "Accessible" : "Unavailable")
                if !HTMLAppSharedContainer.appGroupAvailable {
                    Text("iOS code cannot grant missing App Group signing entitlements. Re-sign the main app and extension with an authorized common App Group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Developer Diagnostics")
        .onAppear {
            selectedID = store.orderedApps.first?.id ?? ""
            tracker.select(appKey: selectedID)
        }
        .onChange(of: selectedID) { tracker.select(appKey: $0) }
    }
}
