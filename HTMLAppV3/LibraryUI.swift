import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @State private var searchText = ""
    @State private var editor: EditorMode?
    @State private var showSettings = false
    @State private var pendingDelete: SavedHTMLApp?
    @State private var profileApp: SavedHTMLApp?
    @State private var permissionsApp: SavedHTMLApp?
    @State private var refreshingID: String?

    private var results: [SavedHTMLApp] { store.results(for: searchText) }

    var body: some View {
        NavigationStack {
            Group {
                if store.apps.isEmpty {
                    EmptyLibraryView { editor = .new }
                } else if results.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "No Results",
                        systemImage: "magnifyingglass",
                        message: "Try a name, description, or text from the saved HTML."
                    )
                } else if libraryLayout == "grid" {
                    PagedAppGrid(
                        apps: results,
                        open: store.launch,
                        menu: { AnyView(appMenu(for: $0)) }
                    )
                } else {
                    appList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("HTMLApp")
            .searchable(text: $searchText, prompt: "Search HTML apps")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editor = .new } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add HTML App")
                }
            }
            .sheet(item: $editor) { EditorView(mode: $0).environmentObject(store) }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .sheet(item: $permissionsApp) { AppPermissionsView(app: $0) }
            .confirmationDialog(
                "Install Home Screen Web Clip?",
                isPresented: Binding(
                    get: { profileApp != nil },
                    set: { if !$0 { profileApp = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Open Profile in Safari") {
                    if let app = profileApp { store.installWebClip(for: app) }
                    profileApp = nil
                }
                Button("Export .mobileconfig") {
                    if let app = profileApp { store.exportProfile(for: app) }
                    profileApp = nil
                }
                Button("Cancel", role: .cancel) { profileApp = nil }
            } message: {
                Text("Safari will download the generated profile with its embedded icon. Then follow the iOS profile installation prompts.")
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "this app")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let app = pendingDelete { store.delete(app) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Its HTML, icon, metadata, cached sources, and saved permission choices will be removed.")
            }
            .alert(
                "HTMLApp",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )
            ) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if let notice = store.notice {
                    Text(notice)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 18)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                                store.notice = nil
                            }
                        }
                }
            }
        }
    }

    private var appList: some View {
        List {
            ForEach(results) { app in
                Button { store.launch(app) } label: {
                    ListAppRow(app: app, refreshing: refreshingID == app.id)
                }
                .buttonStyle(.plain)
                .contextMenu { appMenu(for: app) }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button { profileApp = app } label: {
                        Label("Home Screen", systemImage: "apps.iphone")
                    }
                    .tint(.blue)
                    Button { refresh(app) } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { pendingDelete = app } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { editor = .edit(app) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func appMenu(for app: SavedHTMLApp) -> some View {
        Button { store.launch(app) } label: {
            Label("Open", systemImage: "play.fill")
        }
        Button { permissionsApp = app } label: {
            Label("Permissions", systemImage: "hand.raised.fill")
        }
        Button { profileApp = app } label: {
            Label("Install Home Screen Web Clip", systemImage: "apps.iphone")
        }
        Button { editor = .edit(app) } label: {
            Label("Update HTML", systemImage: "pencil")
        }
        Divider()
        Button { UIPasteboard.general.string = app.id } label: {
            Label("Copy ID", systemImage: "number")
        }
        Button { UIPasteboard.general.string = "htmlapp://open?id=\(app.id)" } label: {
            Label("Copy URL Scheme", systemImage: "link")
        }
        Button { refresh(app) } label: {
            Label("Refresh External Sources", systemImage: "arrow.clockwise")
        }
        Button {} label: {
            Label("Updated \(app.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
        }
        .disabled(true)
        Divider()
        Button(role: .destructive) { pendingDelete = app } label: {
            Label("Delete HTML App", systemImage: "trash")
        }
    }

    private func refresh(_ app: SavedHTMLApp) {
        refreshingID = app.id
        Task {
            await SourceCache.shared.refresh(app: app, force: true)
            refreshingID = nil
            store.notice = "\(app.name) refreshed."
        }
    }
}

struct ListAppRow: View {
    let app: SavedHTMLApp
    let refreshing: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(app: app, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !app.summary.isEmpty {
                    Text(app.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(app.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if refreshing {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct PagedAppGrid: View {
    let apps: [SavedHTMLApp]
    let open: (SavedHTMLApp) -> Void
    let menu: (SavedHTMLApp) -> AnyView

    private let itemsPerPage = 20
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var pages: [[SavedHTMLApp]] {
        stride(from: 0, to: apps.count, by: itemsPerPage).map {
            Array(apps[$0..<min($0 + itemsPerPage, apps.count)])
        }
    }

    var body: some View {
        GeometryReader { proxy in
            TabView {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    LazyVGrid(columns: columns, alignment: .center, spacing: 24) {
                        ForEach(page) { app in
                            Button { open(app) } label: {
                                VStack(spacing: 7) {
                                    AppIconView(app: app, size: min(70, proxy.size.width / 5.2))
                                        .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                                    Text(app.name)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 32, alignment: .top)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(app) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
        }
    }
}

struct EmptyLibraryView: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Create your first HTML app")
                .font(.title2.bold())
            Text("Paste HTML, preview it, and save it as a full-screen app. Press and hold saved apps for more actions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 34)
            Button(action: add) {
                Label("Add HTML App", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
