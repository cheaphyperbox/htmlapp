import SwiftUI

struct WebsiteSourcesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let app: SavedHTMLApp
    @State private var revision = 0
    @State private var working = false
    @State private var errorMessage: String?

    private var records: [WebsiteSourceRecord] {
        _ = revision
        return WebsiteArchiveManager.shared.sourceRecords(appID: app.id)
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No Source Manifest Yet",
                        systemImage: "doc.text.magnifyingglass",
                        message: "Re-download this website to build a list of every discovered dependency."
                    )
                } else {
                    List {
                        Section {
                            ForEach(records) { record in
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(
                                        isOn: Binding(
                                            get: {
                                                WebsiteArchiveManager.shared.isDownloadEnabled(
                                                    appID: app.id,
                                                    sourceURL: record.sourceURL
                                                )
                                            },
                                            set: { enabled in
                                                WebsiteArchiveManager.shared.setDownloadEnabled(
                                                    enabled,
                                                    appID: app.id,
                                                    sourceURL: record.sourceURL
                                                )
                                                revision += 1
                                            }
                                        )
                                    ) {
                                        Text(record.sourceURL)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }

                                    HStack(spacing: 8) {
                                        if record.isCached {
                                            Label("Saved locally", systemImage: "checkmark.circle.fill")
                                        } else {
                                            Label("Remote only", systemImage: "network")
                                        }
                                        if let localPath = record.localPath {
                                            Text(localPath)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("\(records.count) discovered sources")
                        } footer: {
                            Text("Turn a source off when it must stay live, such as an API endpoint. Disabled URLs are left remote instead of downloaded or rewritten the next time the website is downloaded.")
                        }

                        Section {
                            Button {
                                redownload()
                            } label: {
                                if working {
                                    HStack {
                                        ProgressView()
                                        Text("Re-downloading…")
                                    }
                                } else {
                                    Label("Re-download With These Rules", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(working)
                        } footer: {
                            Text("Changing a toggle does not alter the currently saved snapshot until you re-download. Existing local files are replaced by the new snapshot.")
                        }
                    }
                }
            }
            .navigationTitle("Downloaded Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Website Download Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func redownload() {
        guard let source = app.websiteSourceURL else { return }
        working = true
        Task {
            do {
                try await store.updateWebsiteSource(app, urlString: source)
                revision += 1
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }
}
