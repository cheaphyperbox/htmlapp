import SwiftUI
import Foundation

// File import only. Device-to-device sharing is handled by NearbyAppTransfer.
struct HTMLFileImportPayload: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let html: String
    let app: SavedHTMLApp?
    let portableData: [String: String]?
    let widgets: [HTMLAppWidgetDefinition]?
    let backgroundJobs: [HTMLAppBackgroundFetchJob]?

    init(
        fileName: String,
        html: String,
        app: SavedHTMLApp? = nil,
        portableData: [String: String]? = nil,
        widgets: [HTMLAppWidgetDefinition]? = nil,
        backgroundJobs: [HTMLAppBackgroundFetchJob]? = nil
    ) {
        self.fileName = fileName
        self.html = html
        self.app = app
        self.portableData = portableData
        self.widgets = widgets
        self.backgroundJobs = backgroundJobs
    }
}

enum HTMLFileName {
    static func safe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safe = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return String(safe.prefix(64)).isEmpty ? "HTMLApp" : String(safe.prefix(64))
    }
}

struct ImportHTMLDestinationView: View {
    let payload: HTMLFileImportPayload
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { installNew() } label: {
                        Label("Install as New HTML App", systemImage: "plus.app.fill")
                    }
                    .disabled(working)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(payload.app?.name ?? payload.fileName)
                        if let summary = payload.app?.summary, !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(payload.app == nil ? "Imported HTML file" : "Includes metadata, portable data, widgets, and background jobs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !store.orderedApps.isEmpty {
                    Section("Update an Existing App") {
                        ForEach(store.orderedApps) { app in
                            Button { update(app) } label: {
                                HStack(spacing: 12) {
                                    AppIconView(app: app, size: 44)
                                    Text(app.name).foregroundStyle(.primary)
                                    Spacer()
                                    if app.isFavorite == true {
                                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    }
                                }
                            }
                            .disabled(working)
                        }
                    }
                }
            }
            .navigationTitle("Import HTML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
    }

    private func installNew() {
        working = true
        Task {
            if let transferred = payload.app {
                await store.addTransferredApp(
                    transferred,
                    portableData: payload.portableData,
                    widgets: payload.widgets,
                    backgroundJobs: payload.backgroundJobs
                )
            } else {
                await store.add(
                    html: payload.html,
                    summary: "Imported from \(payload.fileName)"
                )
                store.notice = "HTML app imported."
            }
            dismiss()
        }
    }

    private func update(_ app: SavedHTMLApp) {
        working = true
        Task {
            await store.update(
                app,
                html: payload.html,
                summary: payload.app?.summary ?? app.summary
            )
            if let portableData = payload.portableData {
                HTMLAppPortableDataStore.replace(appID: app.id, values: portableData)
            }
            store.installTransferredIntegrations(
                appID: app.id,
                widgets: payload.widgets,
                backgroundJobs: payload.backgroundJobs
            )
            store.notice = "\(app.name) updated."
            dismiss()
        }
    }
}
