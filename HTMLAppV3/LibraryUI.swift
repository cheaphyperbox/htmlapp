import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum FolderDestinationOperation: Identifiable {
    case moveFolder(LibraryFolder)
    case copyFolder(LibraryFolder)
    case moveApp(SavedHTMLApp, sourceFolderID: String?)

    var id: String {
        switch self {
        case .moveFolder(let folder): return "move-folder-\(folder.id)"
        case .copyFolder(let folder): return "copy-folder-\(folder.id)"
        case .moveApp(let app, let sourceFolderID): return "move-app-\(app.id)-\(sourceFolderID ?? "root")"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("libraryLayout") private var libraryLayout = "list"
    @AppStorage("librarySortMode") private var librarySortModeRaw = LibrarySortMode.alphabeticalAZ.rawValue
    @AppStorage("librarySortDateBasis") private var librarySortDateBasisRaw = LibrarySortDateBasis.modified.rawValue
    @AppStorage("libraryFoldersOnTop") private var libraryFoldersOnTop = true
    @AppStorage("libraryFavoritesOnTop") private var libraryFavoritesOnTop = true

    @State private var searchText = ""
    @State private var folderPath: [LibraryFolder] = []
    @State private var editor: EditorMode?
    @State private var websiteEditorApp: SavedHTMLApp?
    @State private var websiteSourcesApp: SavedHTMLApp?
    @State private var showSettings = false
    @State private var showAllApps = false
    @State private var showAddOptions = false
    @State private var showGenerator = false
    @State private var aiEditorApp: SavedHTMLApp?
    @State private var aiIconApp: SavedHTMLApp?
    @State private var importingFile = false
    @State private var showWebsiteImporter = false
    @State private var showReceiver = false
    @State private var senderApp: SavedHTMLApp?
    @State private var pendingImport: OpticalImportPayload?
    @State private var pendingDelete: SavedHTMLApp?
    @State private var profileApp: SavedHTMLApp?
    @State private var permissionsApp: SavedHTMLApp?
    @State private var refreshingID: String?

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParentID: String?
    @State private var renamingFolder: LibraryFolder?
    @State private var renameFolderName = ""
    @State private var tintFolder: LibraryFolder?
    @State private var pendingFolderDelete: LibraryFolder?
    @State private var destinationOperation: FolderDestinationOperation?

    private var sortMode: LibrarySortMode {
        LibrarySortMode(rawValue: librarySortModeRaw) ?? .alphabeticalAZ
    }

    private var sortDateBasis: LibrarySortDateBasis {
        LibrarySortDateBasis(rawValue: librarySortDateBasisRaw) ?? .modified
    }

    private var globalSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack(path: $folderPath) {
            libraryPage(folderID: nil)
                .navigationDestination(for: LibraryFolder.self) { folder in
                    libraryPage(folderID: folder.id)
                }
        }
        // Present from the navigation container, not the root page. This keeps
        // dialogs/sheets active while a nested folder destination is on screen.
        .sheet(item: $editor) { EditorView(mode: $0).environmentObject(store) }
        .sheet(item: $websiteEditorApp) { WebsiteSourceEditorView(app: $0).environmentObject(store) }
        .sheet(item: $websiteSourcesApp) { WebsiteSourcesView(app: $0).environmentObject(store) }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
        .sheet(isPresented: $showAllApps) { AllHTMLAppsView().environmentObject(store) }
        .sheet(isPresented: $showWebsiteImporter) { WebsiteImportView().environmentObject(store) }
        .fullScreenCover(isPresented: $showGenerator) {
            AIGenerationView().environmentObject(store).interactiveDismissDisabled(true)
        }
        .fullScreenCover(item: $aiEditorApp) { app in
            AIGenerationView(existingApp: app).environmentObject(store).interactiveDismissDisabled(true)
        }
        .sheet(item: $aiIconApp) { app in
            AIIconGenerationView(app: app).environmentObject(store)
        }
        .sheet(item: $permissionsApp) { EnhancedAppPermissionsView(app: $0) }
        .sheet(item: $pendingImport) { ImportHTMLDestinationView(payload: $0).environmentObject(store) }
        .fullScreenCover(item: $senderApp) { OpticalSenderView(app: $0) }
        .fullScreenCover(isPresented: $showReceiver) {
            OpticalReceiverView { payload in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pendingImport = payload }
            }
        }
        .sheet(item: $tintFolder) { folder in
            FolderTintPicker(folder: folder) { hex in
                store.setFolderTint(folder, hex: hex)
                LibraryFolderActivityStore.markModified(folder.id)
            }
        }
        .sheet(item: $destinationOperation) { operation in
            FolderDestinationPicker(
                title: destinationTitle(operation),
                actionTitle: destinationActionTitle(operation),
                excludedFolderIDs: excludedDestinationIDs(operation)
            ) { destinationID in
                applyDestination(operation, destinationID: destinationID)
            }
            .environmentObject(store)
        }
        .confirmationDialog("Add HTML App", isPresented: $showAddOptions, titleVisibility: .visible) {
            Button("Generate with AI") { showGenerator = true }
            Button("Download Website") { showWebsiteImporter = true }
            Button("Enter Custom Code") { editor = .new }
            Button("Select an HTML File") { importingFile = true }
            Button("Import from Another Device") { showReceiver = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generate an app, download a website for offline use, paste code, choose an HTML file, or scan a transfer.")
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let created = store.createFolder(newFolderName, parentID: newFolderParentID) {
                    LibraryFolderActivityStore.markModified(created.id)
                }
                newFolderName = ""
                newFolderParentID = nil
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
                newFolderParentID = nil
            }
        } message: {
            Text("The new folder will be created inside the folder you are currently viewing.")
        }
        .alert(
            "Rename Folder",
            isPresented: Binding(
                get: { renamingFolder != nil },
                set: { if !$0 { renamingFolder = nil } }
            )
        ) {
            TextField("Folder name", text: $renameFolderName)
            Button("Rename") {
                if let folder = renamingFolder {
                    store.renameFolder(folder, to: renameFolderName)
                    LibraryFolderActivityStore.markModified(folder.id)
                }
                renamingFolder = nil
                renameFolderName = ""
            }
            Button("Cancel", role: .cancel) {
                renamingFolder = nil
                renameFolderName = ""
            }
        } message: {
            Text("Renaming a folder does not change the apps or nested folders inside it.")
        }
        .fileImporter(
            isPresented: $importingFile,
            allowedContentTypes: [.html, .plainText],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .confirmationDialog(
            "Install Home Screen Web Clip?",
            isPresented: Binding(get: { profileApp != nil }, set: { if !$0 { profileApp = nil } }),
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
            Text("Safari will open the generated profile with its embedded icon. Then follow the iOS profile installation prompts.")
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this app")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let app = pendingDelete { store.delete(app) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the one canonical app and all of its folder links, HTML, icon, metadata, caches, downloaded website files, and saved permission choices.")
        }
        .confirmationDialog(
            "Delete \(pendingFolderDelete?.name ?? "this folder")?",
            isPresented: Binding(get: { pendingFolderDelete != nil }, set: { if !$0 { pendingFolderDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = pendingFolderDelete {
                    store.deleteFolder(folder)
                    LibraryFolderActivityStore.remove(folder.id)
                }
                pendingFolderDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingFolderDelete = nil }
        } message: {
            Text("The folder itself will be deleted. Its app links and nested folders will be moved up one level, so no app data is copied or lost.")
        }
        .alert(
            "HTMLApp",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { store.notice = nil }
                    }
            }
        }
    }

    @ViewBuilder
    private func libraryPage(folderID: String?) -> some View {
        let folders = visibleFolders(in: folderID)
        let apps = visibleApps(in: folderID)
        let entries = sortedEntries(folders: folders, apps: apps)
        let folderName = folderID.flatMap { store.folder(withID: $0)?.name }
        let queryIsEmpty = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        Group {
            if folderID == nil && store.apps.isEmpty && store.folders.isEmpty && queryIsEmpty {
                EmptyLibraryView { prepareAdd(in: nil) }
            } else if entries.isEmpty {
                ContentUnavailableViewCompat(
                    title: queryIsEmpty ? "Folder is Empty" : "No Results",
                    systemImage: queryIsEmpty ? "folder" : "magnifyingglass",
                    message: queryIsEmpty
                        ? "Create a folder or add an HTML app here."
                        : "Search checks every saved HTML app, including apps inside nested folders."
                )
            } else if libraryLayout == "grid" {
                PagedLibraryGrid(
                    entries: entries,
                    openFolder: openFolder,
                    openApp: store.launch,
                    folderMenu: { AnyView(folderMenu(for: $0)) },
                    appMenu: { app in
                        AnyView(appMenu(for: app, sourceFolderID: sourceFolderID(for: app, pageFolderID: folderID)))
                    }
                )
            } else {
                libraryList(folderID: folderID, entries: entries)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(folderName ?? "HTMLApp")
        .searchable(text: $searchText, prompt: "Search all HTML apps")
        .toolbar {
            if folderID == nil {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showAllApps = true } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .accessibilityLabel("All HTML Apps")

                Button {
                    newFolderParentID = folderID
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("New Folder")

                Button { prepareAdd(in: folderID) } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add or Import HTML App")
            }
        }
    }

    private func sortedEntries(folders: [LibraryFolder], apps: [SavedHTMLApp]) -> [LibraryDisplayItem] {
        LibrarySorter.sortedItems(
            folders: folders,
            apps: apps,
            mode: sortMode,
            dateBasis: sortDateBasis,
            foldersOnTop: libraryFoldersOnTop,
            favoritesOnTop: libraryFavoritesOnTop
        )
    }

    private func libraryList(folderID: String?, entries: [LibraryDisplayItem]) -> some View {
        List {
            ForEach(entries) { entry in
                switch entry {
                case .folder(let folder):
                    Button { openFolder(folder) } label: {
                        FolderListRow(
                            folder: folder,
                            appCount: store.descendantAppCount(in: folder.id),
                            subfolderCount: store.childFolders(of: folder.id).count
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu { folderMenu(for: folder) }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

                case .app(let app):
                    Button { store.launch(app) } label: {
                        ListAppRow(app: app, refreshing: refreshingID == app.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        appMenu(for: app, sourceFolderID: sourceFolderID(for: app, pageFolderID: folderID))
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { store.toggleFavorite(app) } label: {
                            Label(app.isFavorite == true ? "Unfavorite" : "Favorite", systemImage: app.isFavorite == true ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                        Button { refresh(app) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = app } label: { Label("Delete", systemImage: "trash") }
                        Button { edit(app) } label: { Label(app.websiteSourceURL == nil ? "Code" : "URL", systemImage: "pencil") }
                            .tint(.orange)
                        Button { aiEditorApp = app } label: { Label("AI Edit", systemImage: "sparkles") }
                            .tint(.purple)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func folderMenu(for folder: LibraryFolder) -> some View {
        Button { destinationOperation = .moveFolder(folder) } label: { Label("Move To", systemImage: "folder") }
        Button { destinationOperation = .copyFolder(folder) } label: { Label("Copy To", systemImage: "doc.on.doc") }
        Button {
            renamingFolder = folder
            renameFolderName = folder.name
        } label: { Label("Rename", systemImage: "pencil") }
        Button { tintFolder = folder } label: { Label("Choose Tint", systemImage: "paintpalette") }
        Divider()
        Button(role: .destructive) { pendingFolderDelete = folder } label: { Label("Delete", systemImage: "trash") }
    }

    @ViewBuilder
    private func appMenu(for app: SavedHTMLApp, sourceFolderID: String?) -> some View {
        Button { store.launch(app) } label: { Label("Open", systemImage: "play.fill") }
        Button { store.toggleFavorite(app) } label: {
            Label(app.isFavorite == true ? "Remove from Favorites" : "Favorite", systemImage: app.isFavorite == true ? "star.slash" : "star.fill")
        }
        Button { destinationOperation = .moveApp(app, sourceFolderID: sourceFolderID) } label: { Label("Move To", systemImage: "folder") }
        Button { permissionsApp = app } label: { Label("Permissions", systemImage: "hand.raised.fill") }
        Button { aiEditorApp = app } label: { Label("Edit with AI", systemImage: "sparkles") }
        Button { aiIconApp = app } label: { Label("Generate Icon with AI", systemImage: "app.badge") }
        Button { edit(app) } label: {
            Label(app.websiteSourceURL == nil ? "Edit HTML Code" : "Edit Website URL", systemImage: app.websiteSourceURL == nil ? "pencil" : "link")
        }
        if app.websiteSourceURL != nil {
            Button { websiteSourcesApp = app } label: { Label("Downloaded Sources", systemImage: "externaldrive") }
        }
        Divider()
        Button { senderApp = app } label: { Label("Send to Another Device", systemImage: "qrcode") }
        Button { store.exportHTML(app) } label: { Label("Export HTML File", systemImage: "square.and.arrow.up") }
        Button { profileApp = app } label: { Label("Install Home Screen Web Clip", systemImage: "apps.iphone") }
        Divider()
        Button { UIPasteboard.general.string = app.id } label: { Label("Copy ID", systemImage: "number") }
        Button { UIPasteboard.general.string = "htmlapp://open?id=\(app.id)" } label: { Label("Copy URL Scheme", systemImage: "link") }
        Button { refresh(app) } label: { Label("Refresh External Sources", systemImage: "arrow.clockwise") }
        Button {} label: { Label("Updated \(app.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock") }
            .disabled(true)
        Divider()
        Button(role: .destructive) { pendingDelete = app } label: { Label("Delete HTML App", systemImage: "trash") }
    }

    private func visibleFolders(in parentID: String?) -> [LibraryFolder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty else { return [] }
        return store.childFolders(of: parentID)
    }

    private func visibleApps(in folderID: String?) -> [SavedHTMLApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.apps(in: folderID) }
        // Search is global rather than scoped to the currently-open folder.
        // store.results returns canonical apps, so linked folder appearances do not duplicate results.
        return store.results(for: query)
    }

    private func sourceFolderID(for app: SavedHTMLApp, pageFolderID: String?) -> String? {
        globalSearchActive ? app.folderID : pageFolderID
    }

    private func openFolder(_ folder: LibraryFolder) {
        searchText = ""
        LibraryFolderActivityStore.markOpened(folder.id)
        folderPath.append(folder)
    }

    private func prepareAdd(in folderID: String?) {
        store.prepareNewItemDestination(folderID)
        showAddOptions = true
    }

    private func destinationTitle(_ operation: FolderDestinationOperation) -> String {
        switch operation {
        case .moveFolder(let folder): return "Move \(folder.name)"
        case .copyFolder(let folder): return "Copy \(folder.name)"
        case .moveApp(let app, _): return "Move \(app.name)"
        }
    }

    private func destinationActionTitle(_ operation: FolderDestinationOperation) -> String {
        switch operation {
        case .copyFolder: return "Copy"
        case .moveFolder, .moveApp: return "Move"
        }
    }

    private func excludedDestinationIDs(_ operation: FolderDestinationOperation) -> Set<String> {
        switch operation {
        case .moveFolder(let folder), .copyFolder(let folder):
            return store.subtreeFolderIDs(startingAt: folder.id)
        case .moveApp:
            return []
        }
    }

    private func applyDestination(_ operation: FolderDestinationOperation, destinationID: String?) {
        switch operation {
        case .moveFolder(let folder):
            store.moveFolder(folder, toParent: destinationID)
            LibraryFolderActivityStore.markModified(folder.id)
        case .copyFolder(let folder):
            store.copyFolder(folder, toParent: destinationID)
        case .moveApp(let app, let sourceFolderID):
            store.movePlacement(app, fromFolderID: sourceFolderID, toFolderID: destinationID)
        }
        destinationOperation = nil
    }

    private func edit(_ app: SavedHTMLApp) {
        if app.websiteSourceURL != nil { websiteEditorApp = app }
        else { editor = .edit(app) }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                store.errorMessage = "The selected file was empty."
                return
            }
            pendingImport = OpticalImportPayload(fileName: url.lastPathComponent, html: html)
        } catch {
            store.errorMessage = "The selected HTML file could not be opened."
        }
    }

    private func refresh(_ app: SavedHTMLApp) {
        refreshingID = app.id
        Task {
            if app.websiteSourceURL != nil {
                store.launch(app)
            } else {
                await SourceCache.shared.refresh(app: app, force: true)
                store.notice = "\(app.name) refreshed."
            }
            refreshingID = nil
        }
    }
}

func folderTintColor(_ hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
        return Color(uiColor: .systemBlue)
    }
    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
}

func folderTintHex(_ color: Color) -> String {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return LibraryFolder.defaultTintHex
    }
    return String(
        format: "#%02X%02X%02X",
        Int((red * 255).rounded()),
        Int((green * 255).rounded()),
        Int((blue * 255).rounded())
    )
}

struct FolderGlyph: View {
    let folder: LibraryFolder
    var size: CGFloat = 58

    var body: some View {
        Image(systemName: "folder.fill")
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(folderTintColor(folder.tintHex))
            .frame(width: size, height: size * 0.82)
            .accessibilityHidden(true)
    }
}

struct FolderListRow: View {
    let folder: LibraryFolder
    let appCount: Int
    let subfolderCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(folderTintColor(folder.tintHex).opacity(0.12))
                    .frame(width: 58, height: 58)
                FolderGlyph(folder: folder, size: 42)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(folder.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 8) {
                    Label("\(appCount) app\(appCount == 1 ? "" : "s")", systemImage: "square.grid.2x2")
                    if subfolderCount > 0 {
                        Label("\(subfolderCount) folder\(subfolderCount == 1 ? "" : "s")", systemImage: "folder")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct FolderTintPicker: View {
    @Environment(\.dismiss) private var dismiss
    let folder: LibraryFolder
    let save: (String) -> Void
    @State private var tint: Color

    init(folder: LibraryFolder, save: @escaping (String) -> Void) {
        self.folder = folder
        self.save = save
        _tint = State(initialValue: folderTintColor(folder.tintHex))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Image(systemName: "folder.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(tint)
                            .frame(width: 112, height: 92)
                            .padding(.vertical, 18)
                        Spacer()
                    }
                }
                Section {
                    ColorPicker("Folder Tint", selection: $tint, supportsOpacity: false)
                } footer: {
                    Text("The tint is applied lightly to the folder icon throughout the library and folder picker.")
                }
            }
            .navigationTitle("Choose Tint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(folderTintHex(tint))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FolderDestinationPicker: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("librarySortMode") private var librarySortModeRaw = LibrarySortMode.alphabeticalAZ.rawValue
    @AppStorage("librarySortDateBasis") private var librarySortDateBasisRaw = LibrarySortDateBasis.modified.rawValue
    @AppStorage("libraryFavoritesOnTop") private var libraryFavoritesOnTop = true

    let title: String
    let actionTitle: String
    let excludedFolderIDs: Set<String>
    let choose: (String?) -> Void
    @State private var path: [String] = []

    private var sortMode: LibrarySortMode { LibrarySortMode(rawValue: librarySortModeRaw) ?? .alphabeticalAZ }
    private var sortDateBasis: LibrarySortDateBasis { LibrarySortDateBasis(rawValue: librarySortDateBasisRaw) ?? .modified }

    var body: some View {
        NavigationStack(path: $path) {
            level(folderID: nil)
                .navigationDestination(for: String.self) { folderID in
                    level(folderID: folderID)
                }
        }
    }

    private func level(folderID: String?) -> some View {
        let folders = LibrarySorter.sortedFolders(store.childFolders(of: folderID), mode: sortMode, dateBasis: sortDateBasis)
        let apps = LibrarySorter.sortedApps(store.apps(in: folderID), mode: sortMode, dateBasis: sortDateBasis, favoritesOnTop: libraryFavoritesOnTop)
        let canChooseHere = folderID.map { !excludedFolderIDs.contains($0) } ?? true
        let currentName = folderID.flatMap { store.folder(withID: $0)?.name } ?? "HTMLApp"

        return List {
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders) { folder in
                        if excludedFolderIDs.contains(folder.id) {
                            folderPickerRow(folder).opacity(0.35)
                        } else {
                            NavigationLink(value: folder.id) { folderPickerRow(folder) }
                        }
                    }
                }
            }
            if !apps.isEmpty {
                Section("Apps") {
                    ForEach(apps) { app in
                        HStack(spacing: 12) {
                            AppIconView(app: app, size: 34).saturation(0.15).opacity(0.45)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).lineLimit(1)
                                Text(app.id).font(.caption.monospaced())
                            }
                            .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .allowsHitTesting(false)
                    }
                }
            }
            if folders.isEmpty && apps.isEmpty {
                Section {
                    Label("This folder is empty.", systemImage: "folder").foregroundStyle(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                choose(folderID)
                dismiss()
            } label: {
                Text("\(actionTitle) Here")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canChooseHere)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(currentName).font(.headline).lineLimit(1)
                    Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func folderPickerRow(_ folder: LibraryFolder) -> some View {
        let count = store.descendantAppCount(in: folder.id)
        return HStack(spacing: 12) {
            FolderGlyph(folder: folder, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name).foregroundStyle(.primary).lineLimit(1)
                Text("\(count) app\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ListAppRow: View {
    let app: SavedHTMLApp
    let refreshing: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(app: app, size: 58)
                .overlay(alignment: .topTrailing) {
                    if app.isFavorite == true {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .padding(4)
                            .background(.ultraThinMaterial, in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                if !app.summary.isEmpty {
                    Text(app.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 7) {
                    Text(app.id).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    if app.websiteSourceURL != nil {
                        Label("Website", systemImage: "arrow.down.circle.fill").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            if refreshing { ProgressView() }
            else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct PagedLibraryGrid: View {
    let entries: [LibraryDisplayItem]
    let openFolder: (LibraryFolder) -> Void
    let openApp: (SavedHTMLApp) -> Void
    let folderMenu: (LibraryFolder) -> AnyView
    let appMenu: (SavedHTMLApp) -> AnyView

    private let itemsPerPage = 20
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private var pages: [[LibraryDisplayItem]] {
        stride(from: 0, to: entries.count, by: itemsPerPage).map { Array(entries[$0..<min($0 + itemsPerPage, entries.count)]) }
    }

    var body: some View {
        GeometryReader { proxy in
            TabView {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    LazyVGrid(columns: columns, alignment: .center, spacing: 24) {
                        ForEach(page) { entry in
                            switch entry {
                            case .folder(let folder):
                                Button { openFolder(folder) } label: {
                                    VStack(spacing: 7) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(folderTintColor(folder.tintHex).opacity(0.10))
                                            FolderGlyph(folder: folder, size: min(68, proxy.size.width / 5.3))
                                        }
                                        .frame(width: min(76, proxy.size.width / 4.8), height: min(70, proxy.size.width / 5.0))
                                        Text(folder.name)
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
                                .contextMenu { folderMenu(folder) }

                            case .app(let app):
                                Button { openApp(app) } label: {
                                    VStack(spacing: 7) {
                                        AppIconView(app: app, size: min(70, proxy.size.width / 5.2))
                                            .shadow(color: Color.black.opacity(0.12), radius: 5, y: 3)
                                            .overlay(alignment: .topTrailing) {
                                                if app.isFavorite == true {
                                                    Image(systemName: "star.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(.yellow)
                                                        .padding(4)
                                                        .background(.regularMaterial, in: Circle())
                                                        .offset(x: 5, y: -5)
                                                }
                                            }
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
                                .contextMenu { appMenu(app) }
                            }
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
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 58, weight: .semibold)).foregroundStyle(.tint)
            Text("Create your first HTML app").font(.title2.bold()).multilineTextAlignment(.center)
            Text("Generate with AI, download a website, enter HTML code, select a file, or receive one from another device.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 34)
            Button(action: add) { Label("Add HTML App", systemImage: "plus") }
                .buttonStyle(.borderedProminent).controlSize(.large)
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
            Image(systemName: systemImage).font(.system(size: 46)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
    }
}
