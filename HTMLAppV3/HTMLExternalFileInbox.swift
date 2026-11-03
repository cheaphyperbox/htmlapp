import Foundation

/// Secure temporary staging for Files/Open In and share-sheet documents.
/// Copy while the external security scope is valid, so a cold launch,
/// onboarding, or a pending release-notes sheet cannot lose the source.
enum HTMLExternalFileInbox {
    private static let maxBytes = 12_000_000
    private static let extensions = Set(["html", "htm", "xhtml", "txt"])

    private static var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("htmlapp-incoming-files", isDirectory: true)
    }

    enum ImportError: LocalizedError {
        case unsupportedType, tooLarge, empty, unavailable
        var errorDescription: String? {
            switch self {
            case .unsupportedType:
                return "Choose an HTML file (.html, .htm or .xhtml). A .txt file containing HTML also works."
            case .tooLarge:
                return "This HTML file exceeds the 12 MB limit."
            case .empty:
                return "The selected HTML file is empty."
            case .unavailable:
                return "The file is not ready yet. Download it in Files and try again."
            }
        }
    }

    static func read(_ url: URL) throws -> Data {
        guard url.isFileURL, extensions.contains(url.pathExtension.lowercased()) else {
            throw ImportError.unsupportedType
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatedError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatedError) { readable in
            result = Result {
                let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if size > maxBytes { throw ImportError.tooLarge }
                return try Data(contentsOf: readable, options: .mappedIfSafe)
            }
        }
        if let coordinatedError { throw coordinatedError }
        guard let result else { throw ImportError.unavailable }
        let data = try result.get()
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        guard !data.isEmpty else { throw ImportError.empty }
        return data
    }

    static func stage(_ incomingURL: URL) throws -> URL {
        guard incomingURL.isFileURL, extensions.contains(incomingURL.pathExtension.lowercased()) else {
            throw ImportError.unsupportedType
        }
        let data = try read(incomingURL)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let originalName = incomingURL.lastPathComponent
        // lastPathComponent is a single path component, not a path supplied by
        // the document itself. Use safe fallback for provider-specific names.
        let filename = originalName.isEmpty ? "Imported.html" : originalName
        let destination = directory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func disposeIfStaged(_ url: URL) {
        guard url.isFileURL else { return }
        let directory = url.deletingLastPathComponent().standardizedFileURL
        let relative = directory.deletingLastPathComponent().standardizedFileURL
        guard relative == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
