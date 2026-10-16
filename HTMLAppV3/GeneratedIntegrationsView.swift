import SwiftUI
import WidgetKit

struct GeneratedIntegrationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var widgets: [HTMLAppWidgetDefinition] = []
    @State private var jobs: [HTMLAppBackgroundFetchJob] = []
    @State private var refreshingJobID: String?

    var body: some View {
        List {
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
                                        Text("Primary")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(.thinMaterial, in: Capsule())
                                    }
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
                                    HTMLAppWidgetStore.remove(appID: widget.appID, widgetID: widget.widgetID)
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
