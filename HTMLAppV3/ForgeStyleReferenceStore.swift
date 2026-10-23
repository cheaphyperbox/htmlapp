import Foundation

/// Stores selected mockup references separately from Library HTML and user data.
enum ForgeStyleReferenceStore {
    private static func url(for appID: String) -> URL {
        let safe = appID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SelectedStyles", isDirectory: true)
        return base.appendingPathComponent(safe + ".json")
    }

    static func save(_ style: ForgeStyleConcept, for appID: String) {
        let path = url(for: appID)
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try JSONEncoder().encode(style).write(to: path, options: .atomic)
        } catch {
            // An optional style reference must never prevent saving the app.
        }
    }

    static func clear(for appID: String) {
        try? FileManager.default.removeItem(at: url(for: appID))
    }

    static func load(for appID: String) -> ForgeStyleConcept? {
        guard let data = try? Data(contentsOf: url(for: appID)) else { return nil }
        return try? JSONDecoder().decode(ForgeStyleConcept.self, from: data)
    }
}
