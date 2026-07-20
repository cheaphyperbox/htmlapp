import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var editor: EditorMode?
    @State private var showSettings = false
    @State private var pendingDelete: SavedHTMLApp?
    @State private var profileApp: SavedHTMLApp?
    @State private var refreshingID: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                if store.apps.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 58, weight: .semibold)).foregroundStyle(.tint)
                        Text("Create your first HTML app").font(.title2.bold())
                        Text("Paste HTML, preview it, and save it as a full-screen app with an optional Home Screen Web Clip.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 34)
                        Button { editor = .new } label: { Label("Add HTML App", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                } else if store.results(for: searchText).isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "magnifyingglass").font(.system(size: 46)).foregroundStyle(.secondary)
                        Text("No Results").font(.title2.bold())
                        Text("No saved app matched names, descriptions, or HTML content.").foregroundStyle(.secondary)
                    }.padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.results(for: searchText)) { app in
                                AppCard(app: app, refreshing: refreshingID == app.id,
                                    open: { store.launch(app) }, install: { profileApp = app })
                                    .contextMenu { menu(for: app) }
                            }
                        }.padding(.horizontal).padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("HTMLApp")
            .searchable(text: $searchText, prompt: "Search names, descriptions, or content")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editor = .new } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(item: $editor) { EditorView(mode: $0).environmentObject(store) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .confirmationDialog("Install Home Screen Web Clip?", isPresented: Binding(
                get: { profileApp != nil }, set: { if !$0 { profileApp = nil } }
            ), titleVisibility: .visible) {
                Button("Generate and Open Profile") {
                    if let app = profileApp { installProfile(for: app) }
                    profileApp = nil
                }
                Button("Cancel", role: .cancel) { profileApp = nil }
            } message: {
                Text("iOS will open Settings so you can review and install a profile containing this Web Clip.")
            }
            .confirmationDialog("Delete this HTML app?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let app = pendingDelete { store.delete(app) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
            .alert("HTMLApp", isPresented: Binding(
                get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
            .overlay(alignment: .bottom) {
                if let notice = store.notice {
                    Text(notice).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 18)
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { store.notice = nil } }
                }
            }
        }
    }

    @ViewBuilder private func menu(for app: SavedHTMLApp) -> some View {
        Button { store.launch(app) } label: { Label("Open", systemImage: "play.fill") }
        Button { profileApp = app } label: { Label("Install Home Screen Web Clip", systemImage: "square.and.arrow.down") }
        Button { editor = .edit(app) } label: { Label("Update HTML", systemImage: "pencil") }
        Button { UIPasteboard.general.string = app.html } label: { Label("Copy HTML", systemImage: "doc.on.doc") }
        Button { UIPasteboard.general.string = app.id } label: { Label("Copy ID", systemImage: "number") }
        Button { UIPasteboard.general.string = "htmlapp://open?id=\(app.id)" } label: { Label("Copy URL Scheme", systemImage: "link") }
        Button { store.duplicate(app) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button {
            refreshingID = app.id
            Task {
                await SourceCache.shared.refresh(app: app, force: true)
                await MainActor.run { refreshingID = nil }
            }
        } label: { Label("Refresh External Sources", systemImage: "arrow.clockwise") }
        Divider()
        Button(role: .destructive) { pendingDelete = app } label: { Label("Delete HTML App", systemImage: "trash") }
    }

    private func installProfile(for app: SavedHTMLApp) {
        do {
            let url = try WebClipProfile.dataURL(for: app)
            UIApplication.shared.open(url, options: [:]) { success in
                if !success { store.errorMessage = "iOS could not open the generated profile data URL." }
            }
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct AppCard: View {
    let app: SavedHTMLApp
    let refreshing: Bool
    let open: () -> Void
    let install: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 14) {
                    if let image = UIImage(data: app.resolvedIconData) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                        if !app.summary.isEmpty {
                            Text(app.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if refreshing { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Divider().padding(.leading, 86)
            HStack {
                Button(action: install) { Label("Home Screen", systemImage: "square.and.arrow.down") }
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(app.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
