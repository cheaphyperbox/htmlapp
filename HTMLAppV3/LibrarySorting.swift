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
        case .recentlyOpened: return "Recently Opened"
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
            return basis == .created ? folder.createdAt : (folder.updatedAt ?? folder.createdAt)
        case .app(let app):
            return basis == .created ? app.createdAt : app.updatedAt
        }
    }

    var lastOpenedAt: Date? {
        switch self {
        case .folder(let folder): return folder.lastOpenedAt
        case .app(let app): return app.lastOpenedAt
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
            switch (left.lastOpenedAt, right.lastOpenedAt) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return nameCompare(left, right, ascending: true)
        }
    }

    private static func nameCompare(_ left: LibraryDisplayItem, _ right: LibraryDisplayItem, ascending: Bool) -> Bool {
        let result = left.name.localizedCaseInsensitiveCompare(right.name)
        if result == .orderedSame { return left.id < right.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }
}
