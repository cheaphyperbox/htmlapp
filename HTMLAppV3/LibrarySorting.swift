import Foundation

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case alphabeticalAZ
    case alphabeticalZA
    case latestFirst
    case latestLast
    case recentlyOpened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabeticalAZ: return "Alphabetical (A–Z)"
        case .alphabeticalZA: return "Alphabetical (Z–A)"
        case .latestFirst: return "Latest at Top"
        case .latestLast: return "Latest at Bottom"
        case .recentlyOpened: return "Recently Used"
        }
    }

    var usesDateBasis: Bool {
        self == .latestFirst || self == .latestLast
    }
}

enum LibrarySortDateBasis: String, CaseIterable, Identifiable {
    case created
    case modified

    var id: String { rawValue }
    var title: String { self == .created ? "Creation Date" : "Date Modified" }
}

enum LibraryFolderActivityStore {
    private static let modifiedKey = "htmlapp.libraryFolderModifiedDates.v1"
    private static let openedKey = "htmlapp.libraryFolderOpenedDates.v1"

    static func markModified(_ folderID: String) {
        setDate(Date(), for: folderID, key: modifiedKey)
    }

    static func markOpened(_ folderID: String) {
        setDate(Date(), for: folderID, key: openedKey)
    }

    static func modifiedAt(_ folderID: String) -> Date? {
        date(for: folderID, key: modifiedKey)
    }

    static func lastOpenedAt(_ folderID: String) -> Date? {
        date(for: folderID, key: openedKey)
    }

    static func remove(_ folderID: String) {
        removeDate(for: folderID, key: modifiedKey)
        removeDate(for: folderID, key: openedKey)
    }

    private static func date(for folderID: String, key: String) -> Date? {
        guard let timestamp = UserDefaults.standard.dictionary(forKey: key)?[folderID] as? Double else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func setDate(_ date: Date, for folderID: String, key: String) {
        var values = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        values[folderID] = date.timeIntervalSince1970
        UserDefaults.standard.set(values, forKey: key)
    }

    private static func removeDate(for folderID: String, key: String) {
        var values = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        values.removeValue(forKey: folderID)
        UserDefaults.standard.set(values, forKey: key)
    }
}

enum LibraryDisplayItem: Identifiable {
    case folder(LibraryFolder)
    case app(SavedHTMLApp)

    var id: String {
        switch self {
        case .folder(let folder): return "folder-\(folder.id)"
        case .app(let app): return "app-\(app.id)"
        }
    }

    var name: String {
        switch self {
        case .folder(let folder): return folder.name
        case .app(let app): return app.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var isFavoriteApp: Bool {
        if case .app(let app) = self { return app.isFavorite == true }
        return false
    }

    func date(for basis: LibrarySortDateBasis) -> Date {
        switch self {
        case .folder(let folder):
            if basis == .created { return folder.createdAt }
            return LibraryFolderActivityStore.modifiedAt(folder.id) ?? folder.createdAt
        case .app(let app):
            return basis == .created ? app.createdAt : app.updatedAt
        }
    }

    /// "Recently Used" treats creation as activity. A brand-new app therefore
    /// appears immediately at the top without requiring the user to open it first.
    var recentActivityAt: Date {
        switch self {
        case .folder(let folder):
            return max(folder.createdAt, LibraryFolderActivityStore.lastOpenedAt(folder.id) ?? .distantPast)
        case .app(let app):
            return max(app.createdAt, app.lastOpenedAt ?? .distantPast)
        }
    }
}

enum LibrarySorter {
    static func sortedItems(
        folders: [LibraryFolder],
        apps: [SavedHTMLApp],
        mode: LibrarySortMode,
        dateBasis: LibrarySortDateBasis,
        foldersOnTop: Bool,
        favoritesOnTop: Bool
    ) -> [LibraryDisplayItem] {
        let items = folders.map(LibraryDisplayItem.folder) + apps.map(LibraryDisplayItem.app)
        return items.sorted {
            compare(
                $0,
                $1,
                mode: mode,
                dateBasis: dateBasis,
                foldersOnTop: foldersOnTop,
                favoritesOnTop: favoritesOnTop
            )
        }
    }

    static func sortedFolders(
        _ folders: [LibraryFolder],
        mode: LibrarySortMode,
        dateBasis: LibrarySortDateBasis
    ) -> [LibraryFolder] {
        sortedItems(
            folders: folders,
            apps: [],
            mode: mode,
            dateBasis: dateBasis,
            foldersOnTop: true,
            favoritesOnTop: false
        ).compactMap {
            if case .folder(let folder) = $0 { return folder }
            return nil
        }
    }

    static func sortedApps(
        _ apps: [SavedHTMLApp],
        mode: LibrarySortMode,
        dateBasis: LibrarySortDateBasis,
        favoritesOnTop: Bool
    ) -> [SavedHTMLApp] {
        sortedItems(
            folders: [],
            apps: apps,
            mode: mode,
            dateBasis: dateBasis,
            foldersOnTop: false,
            favoritesOnTop: favoritesOnTop
        ).compactMap {
            if case .app(let app) = $0 { return app }
            return nil
        }
    }

    private static func compare(
        _ left: LibraryDisplayItem,
        _ right: LibraryDisplayItem,
        mode: LibrarySortMode,
        dateBasis: LibrarySortDateBasis,
        foldersOnTop: Bool,
        favoritesOnTop: Bool
    ) -> Bool {
        if foldersOnTop, left.isFolder != right.isFolder {
            return left.isFolder
        }

        if favoritesOnTop,
           !left.isFolder,
           !right.isFolder,
           left.isFavoriteApp != right.isFavoriteApp {
            return left.isFavoriteApp
        }

        switch mode {
        case .alphabeticalAZ:
            return nameCompare(left, right, ascending: true)
        case .alphabeticalZA:
            return nameCompare(left, right, ascending: false)
        case .latestFirst:
            let l = left.date(for: dateBasis)
            let r = right.date(for: dateBasis)
            if l != r { return l > r }
            return nameCompare(left, right, ascending: true)
        case .latestLast:
            let l = left.date(for: dateBasis)
            let r = right.date(for: dateBasis)
            if l != r { return l < r }
            return nameCompare(left, right, ascending: true)
        case .recentlyOpened:
            let l = left.recentActivityAt
            let r = right.recentActivityAt
            if l != r { return l > r }
            return nameCompare(left, right, ascending: true)
        }
    }

    private static func nameCompare(_ left: LibraryDisplayItem, _ right: LibraryDisplayItem, ascending: Bool) -> Bool {
        let result = left.name.localizedCaseInsensitiveCompare(right.name)
        if result == .orderedSame { return left.id < right.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }
}
