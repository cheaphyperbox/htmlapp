import SwiftUI

struct WebsiteSourceEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let app: SavedHTMLApp
    @State private var url: String
    @State private var working = false
    @State private var previewing = false
    @State private var errorMessage: String?

    init(app: SavedHTMLApp) {
        self.app = app
        _url = State(initialValue: app.websiteSourceURL ?? "https://")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Website URL") {
                    TextField("https://example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Text("This app is backed by a downloaded website. Editing it changes the source URL instead of directly editing the downloaded HTML. HTMLApp will download a fresh package from the new URL when you save.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Preview Current Download") { previewing = true }
                }
            }
            .navigationTitle("Edit Website Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(working || WebsiteArchiveManager.shared.normalizedURL(url) == nil)
                }
            }
            .sheet(isPresented: $previewing) {
                NavigationStack {
                    HTMLWebView(html: app.html, appID: app.id)
                        .navigationTitle("Downloaded Copy")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { previewing = false } } }
                }
            }
            .overlay { if working { ProgressView("Downloading latest copy…") } }
            .alert("Couldn’t Update Website", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        working = true
        Task {
            do {
                try await store.updateWebsiteSource(app, urlString: url)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                working = false
            }
        }
    }
}
