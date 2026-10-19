import SwiftUI
import WidgetKit

struct GeneratedIntegrationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var widgets: [HTMLAppWidgetDefinition] = []
    @State private var jobs: [HTMLAppBackgroundFetchJob] = []
    @State private var refreshingJobID: String?
    @State private var diagnostic = ""
    @State private var installedStatus = "Widget placement: checking"
    @State private var widgetError: String?
    @State private var pendingGroup: String?
    @State private var confirmGroup = false

    var body: some View {
        List {
            if !HTMLAppSharedContainer.appGroupAvailable {
                Section("Widget Signing Problem") {
                    Label("App Group storage is unavailable on this installation.", systemImage: "exclamationmark.triangle")
                    Text("Select an authorized group below. Both signed binaries and their provisioning profiles must authorize the same group. A certificate alone is insufficient.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("Generated apps can publish native Home Screen and Lock Screen widgets.", systemImage: "square.grid.2x2")
                Text("On iOS 17 and later, add an HTMLApp widget and choose a widget published by one of your saved apps. On iOS 16, HTMLApp shows the current primary widget.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                    reload()
                    store.notice = "Widget timelines were asked to refresh."
                } label: {
                    Label("Reload Widget Timelines", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("Widgets")
            } footer: {
                Text("WidgetKit controls the actual refresh schedule. A generated app can request periodic refresh, but iOS may coalesce or delay it.")
            }

            Section("Signing group setup") {
                Text("Active widget storage: \(HTMLAppSharedContainer.appGroupID)").font(.caption.monospaced())
                if HTMLAppSharedContainer.appGroupID != HTMLAppSharedContainer.originalGroupID {
                    Label("Compatible signer group in use. Original bundle ID and private saved apps are unchanged.", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                Text("Provider groups may also be accessible to other apps signed by that provider. Publish only non-sensitive snapshots. Saved HTMLApps stay in private app storage. Switching groups requires republishing your widgets.").font(.footnote)
                ForEach(HTMLAppSigningGroups.common.filter { $0 != HTMLAppSharedContainer.originalGroupID }, id: \.self) { group in
                    Button("Use \(group)") { widgetError = nil; pendingGroup = group; confirmGroup = true }
                }
                if HTMLAppSigningGroups.common.isEmpty {
                    Text("No common declared App Group could be inspected. Ask your signer to preserve XML App Group entitlements in both binaries and supply matching profiles.").font(.caption)
                }
                Button("Use original HTMLApp group") {
                    pendingGroup = HTMLAppSharedContainer.originalGroupID; confirmGroup = true
                }.disabled(!HTMLAppProviderStorage.originalAvailable)
                if !HTMLAppProviderStorage.originalAvailable {
                    Text("The original group.com.mekabrine.htmlapp is not authorized by this installation. Swift cannot repair a provisioning profile. The compatible mode below uses a different, verified shared group for widgets, without changing the app's bundle ID or saved apps.").font(.caption)
                    if let compatible = HTMLAppProviderStorage.recommendedCompatibleGroup {
                        Button {
                            widgetError = nil
                            pendingGroup = compatible
                            confirmGroup = true
                        } label: {
                            Label("Repair Widget Storage with Compatible Group", systemImage: "checkmark.shield")
                        }
                        Text("Compatible container: \(compatible). Choosing it shares published widget snapshots with other apps authorized for that provider group; do not publish secrets. Republish your widgets after switching.").font(.caption)
                    } else {
                        Text("No accessible common App Group was found. Re-sign both the main app and the widget extension with a matching authorized group, then reopen HTMLApp.").font(.caption)
                    }
                }
            }

            Section("Shared-container diagnostic") {
                Text(diagnostic).font(.caption.monospaced()).textSelection(.enabled)
                Text(installedStatus).font(.caption)
                Text("Published means the main app saved and read back a snapshot. Selected Primary chooses the iOS 16 / Primary widget. WidgetKit reports configured widgets separately; a reload request is not a completed refresh or proof of visible rendering.").font(.footnote)
                Button("Start Extension Read Test") {
                    do {
                        _ = try HTMLAppWidgetDiagnostics.begin()
                        WidgetCenter.shared.reloadAllTimelines()
                    } catch { widgetError = error.localizedDescription }
                    reload()
                }
                Button("Read Diagnostic Result") { widgetError = nil; reload() }
                if let widgetError { Text(widgetError).foregroundStyle(.red).font(.caption) }
            }

            if widgets.isEmpty {
                Section {
                    emptyState(
                        title: "No Generated Widgets",
                        systemImage: "square.grid.2x2",
                        detail: "Forge-created apps can publish widgets when a glanceable view genuinely improves the product."
                    )
                }
            } else {
                ForEach(widgetGroups, id: \.appID) { group in
                    Section {
                        ForEach(group.widgets) { widget in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: widget.snapshot.systemSymbol ?? "square.grid.2x2")
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(widget.name)
                                            .font(.headline)
                                        Text(widget.widgetID)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if widget.primary {
                                        Text("Selected Primary")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(.thinMaterial, in: Capsule())
                                    }
                                }

                                if !widget.primary {
                                    Button("Select Primary") {
                                        do { try HTMLAppWidgetStore.setPrimaryVerified(compositeID: widget.id) }
                                        catch { widgetError = error.localizedDescription; return }
                                        WidgetCenter.shared.reloadAllTimelines()
                                        reload()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                                if widget.refresh != nil {
                                    Label("Background JSON refresh enabled", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let error = widget.lastError, !error.isEmpty {
                                    Label(error, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    do { try HTMLAppWidgetStore.removeVerified(appID: widget.appID, widgetID: widget.widgetID) }
                                    catch { widgetError = error.localizedDescription; return }
                                    WidgetCenter.shared.reloadAllTimelines()
                                    reload()
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(group.appName)
                    }
                }
            }

            Section {
                if jobs.isEmpty {
                    emptyState(
                        title: "No Background Jobs",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        detail: "Generated apps can ask iOS to refresh public HTTPS JSON and save it into their portable app data."
                    )
                } else {
                    ForEach(jobs) { job in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.jobID)
                                        .font(.headline)
                                    Text(appName(for: job.appID))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if refreshingJobID == job.id {
                                    ProgressView()
                                }
                            }

                            Text(job.url)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            HStack {
                                Label("~\(job.intervalMinutes) min requested", systemImage: "clock")
                                Spacer()
                                Text(job.enabled ? "Enabled" : "Paused")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let last = job.lastRunAt {
                                Text("Last run \(last.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = job.lastError, !error.isEmpty {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Button("Refresh Now") {
                                    refresh(job)
                                }
                                .buttonStyle(.bordered)
                                .disabled(refreshingJobID != nil)

                                Spacer()

                                Button("Remove", role: .destructive) {
                                    HTMLAppBackgroundJobStore.remove(appID: job.appID, jobID: job.jobID)
                                    HTMLAppBackgroundCoordinator.shared.schedule()
                                    reload()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Background Refresh")
            } footer: {
                Text("These are iOS BGAppRefresh jobs, not permanently running JavaScript. The minimum requested interval is 15 minutes, and iOS decides when a job actually runs based on system policy, power, and Background App Refresh settings.")
            }
        }
        .navigationTitle("Widgets & Background")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .alert("Use this shared signing group?", isPresented: $confirmGroup) {
            Button("Cancel", role: .cancel) {}
            Button("Use Group") {
                guard let group = pendingGroup else { return }
                do {
                    try HTMLAppProviderStorage.activate(group)
                    _ = try HTMLAppWidgetDiagnostics.begin()
                    widgetError = nil
                    WidgetCenter.shared.reloadAllTimelines()
                } catch { widgetError = error.localizedDescription }
                reload()
            }
        } message: {
            Text("Other apps with access to this group may read or change published snapshots, refresh URLs and widget diagnostics. Use only non-sensitive content. Encryption with a key shared through this group would not prevent that access.")
        }
    }

    @ViewBuilder
    private func emptyState(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var widgetGroups: [(appID: String, appName: String, widgets: [HTMLAppWidgetDefinition])] {
        let grouped = Dictionary(grouping: widgets, by: \.appID)
        return grouped.map { appID, values in
            (appID, appName(for: appID), values.sorted { $0.updatedAt > $1.updatedAt })
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func appName(for id: String) -> String {
        store.apps.first(where: { $0.id == id })?.name ?? "Unknown HTMLApp"
    }

    private func reload() {
        diagnostic = HTMLAppWidgetDiagnostics.summary()
        WidgetCenter.shared.getCurrentConfigurations { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let configurations):
                    installedStatus = "WidgetKit configured instances: \(configurations.count) (placement and visible rendering are not reported)"
                case .failure: installedStatus = "WidgetKit configured instances: unavailable"
                }
            }
        }
        let valid = Set(store.apps.map(\.id))
        widgets = HTMLAppWidgetStore.all().filter { valid.contains($0.appID) }
        jobs = HTMLAppBackgroundJobStore.all()
            .filter { valid.contains($0.appID) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func refresh(_ job: HTMLAppBackgroundFetchJob) {
        refreshingJobID = job.id
        Task {
            _ = await HTMLAppBackgroundCoordinator.shared.runNow(appID: job.appID, jobID: job.jobID)
            await MainActor.run {
                refreshingJobID = nil
                reload()
            }
        }
    }
}

