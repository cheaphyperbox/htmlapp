import SwiftUI
import UniformTypeIdentifiers

struct HTMLAppDataTransferView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedIDs: Set<String> = []
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showImportMode = false
    @State private var importing = false

    var body: some View {
        List {
            Section {
                Button {
                    store.exportPortablePackage()
                } label: {
                    Label("Export Complete Library", systemImage: "shippingbox.fill")
                }

                Button {
                    showImporter = true
                } label: {
                    Label("Import HTMLApp Backup", systemImage: "square.and.arrow.down.fill")
                }
                .disabled(importing)
            } header: {
                Text("Move Between Devices")
            } footer: {
                Text("Backups are normal .zip files containing a versioned HTMLApp manifest plus offline website resources. Generated AI artwork is embedded directly in each app, so it moves with the package automatically.")
            }

            if !store.apps.isEmpty {
                Section {
                    HStack {
                        Button(selectedIDs.count == store.apps.count ? "Clear" : "Select All") {
                            if selectedIDs.count == store.apps.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(store.apps.map(\.id))
                            }
                        }
                        Spacer()
                        Text("\(selectedIDs.count) selected")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(store.orderedApps) { app in
                        Button {
                            if selectedIDs.contains(app.id) { selectedIDs.remove(app.id) }
                            else { selectedIDs.insert(app.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AppIconView(app: app, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).foregroundStyle(.primary)
                                    if !app.summary.isEmpty {
                                        Text(app.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedIDs.contains(app.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(app.id) ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        store.exportPortablePackage(appIDs: selectedIDs)
                    } label: {
                        Label("Export Selected Apps", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIDs.isEmpty)
                } header: {
                    Text("Selective Export")
                } footer: {
                    Text("Folder placement, aliases, icons, HTML, portable app data, embedded generated assets, and cached website files are included. Sensitive permissions always ask again on the receiving device.")
                }
            }

            Section {
                Label("Merge is the safe default", systemImage: "plus.square.on.square")
                Text("Imported apps receive new IDs, so your existing library cannot be overwritten by a name or ID collision.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label("Replace Library is a full restore", systemImage: "arrow.clockwise.square.fill")
                Text("Use it when moving your entire HTMLApp library to another device. Existing saved apps are removed before the backup is restored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Import Behavior")
            }
        }
        .navigationTitle("Backup & Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, UTType(filenameExtension: "zip")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            receiveImport(result)
        }
        .confirmationDialog(
            "How should this backup be imported?",
            isPresented: $showImportMode,
            titleVisibility: .visible
        ) {
            Button("Merge as New Copies") { importPending(replace: false) }
            Button("Replace Entire Library", role: .destructive) { importPending(replace: true) }
            Button("Cancel", role: .cancel) {
                if let pendingImportURL { try? FileManager.default.removeItem(at: pendingImportURL) }
                pendingImportURL = nil
            }
        } message: {
            Text("Merge keeps your current library. Replace Library removes existing saved HTMLApps first.")
        }
        .overlay {
            if importing {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    ProgressView("Importing backup…").controlSize(.large)
                }
            }
        }
    }

    private func receiveImport(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }

            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("HTMLApp-Import-\(UUID().uuidString).zip")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            pendingImportURL = destination
            showImportMode = true
        } catch {
            store.errorMessage = "The selected backup could not be opened: \(error.localizedDescription)"
        }
    }

    private func importPending(replace: Bool) {
        guard let url = pendingImportURL else { return }
        importing = true
        defer {
            importing = false
            pendingImportURL = nil
            try? FileManager.default.removeItem(at: url)
        }
        do {
            try store.importPortablePackage(from: url, replaceExisting: replace)
        } catch {
            store.errorMessage = "The HTMLApp backup could not be imported: \(error.localizedDescription)"
        }
    }
}
