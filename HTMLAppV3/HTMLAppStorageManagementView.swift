import SwiftUI
import Foundation

/// Developer-only inspection of the saved app's portable key/value and SQLite
/// document data. Never edits files directly; uses the existing stores.
struct HTMLAppStorageManagementView: View {
    let app: SavedHTMLApp
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var records: [[String: Any]] = []
    @State private var selectedDeletion: StorageItem?
    @State private var errorMessage: String?
    @State private var showWarning = false

    struct StorageItem: Identifiable {
        let id: String
        let kind: String
        let collection: String?
        let key: String
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Saved key/value data", value: ByteCountFormatter.string(fromByteCount: Int64(values.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }), countStyle: .file))
                    LabeledContent("SQLite database", value: ByteCountFormatter.string(fromByteCount: size(HTMLAppDocumentDatabase.databaseURL(appID: app.id)), countStyle: .file))
                    LabeledContent("Portable data file", value: ByteCountFormatter.string(fromByteCount: size(HTMLAppPortableDataStore.fileURL(appID: app.id)), countStyle: .file))
                } header: { Text("App Data Storage") } footer: {
                    Text("Storage totals cover HTMLApp's portable data and SQLite files. WKWebView localStorage, IndexedDB and cached media are not included.")
                }
                Section("Saved Key/Value Data") {
                    if values.isEmpty { Text("No key/value data").foregroundStyle(.secondary) }
                    ForEach(values.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.headline)
                            Text(values[key] ?? "").font(.caption.monospaced()).lineLimit(3).textSelection(.enabled)
                            Button("Delete saved key", role: .destructive) {
                                selectedDeletion = StorageItem(id: "key:" + key, kind: "key", collection: nil, key: key)
                            }
                        }
                    }
                }
                Section("SQLite Documents") {
                    if records.isEmpty { Text("No SQLite documents").foregroundStyle(.secondary) }
                    ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                        let collection = record["collection"] as? String ?? ""
                        let id = record["id"] as? String ?? ""
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection + " / " + id).font(.headline)
                            Text(preview(record["document"])).font(.caption.monospaced()).lineLimit(3).textSelection(.enabled)
                            Button("Delete document", role: .destructive) {
                                selectedDeletion = StorageItem(id: "db:" + collection + ":" + id, kind: "database", collection: collection, key: id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage App Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { reload(); showWarning = true }
            .alert("Modifying saved data can break this app", isPresented: $showWarning) {
                Button("I understand", role: .cancel) {}
            } message: {
                Text("Deleting or modifying keys or documents may cause problems with this app, including lost settings or progress. Only remove data you recognize. This cannot be undone here.")
            }
            .alert("Delete saved data?", isPresented: Binding(get: { selectedDeletion != nil }, set: { if !$0 { selectedDeletion = nil } })) {
                Button("Delete permanently", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) { selectedDeletion = nil }
            } message: {
                Text("Modifying saved data can cause issues with the app if done incorrectly. This action cannot be undone.")
            }
            .alert("Storage operation failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Unknown error") }
        }
    }

    private func size(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func preview(_ value: Any?) -> String {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(800))
    }

    private func reload() {
        values = HTMLAppPortableDataStore.all(appID: app.id)
        do {
            let result = try HTMLAppDocumentDatabase.exportJSON(appID: app.id)
            records = result["records"] as? [[String: Any]] ?? []
        } catch {
            records = []
            errorMessage = "Could not read the app database: " + error.localizedDescription
        }
    }

    private func deleteSelected() {
        guard let item = selectedDeletion else { return }
        selectedDeletion = nil
        if item.kind == "key" {
            HTMLAppPortableDataStore.remove(appID: app.id, key: item.key)
        } else if let collection = item.collection {
            do {
                _ = try HTMLAppDocumentDatabase.perform(appID: app.id, method: "db.delete", args: ["collection": collection, "id": item.key])
            } catch { errorMessage = error.localizedDescription }
        }
        reload()
    }
}
