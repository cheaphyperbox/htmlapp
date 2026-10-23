import Foundation

struct ForgeDraftCheckpoint: Codable, Equatable {
    var startedAt: Date?
    var savedAt: Date
    var originalPrompt: String
    var refinedBrief: String
    var research: String
    var html: String
    var description: String
    var iconScript: String
    var phase: String
    var existingAppID: String?
    var streamedByteCount: Int
}

enum ForgeDraftCheckpointStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("forge-draft.json")
    }

    static func load() -> ForgeDraftCheckpoint? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ForgeDraftCheckpoint.self, from: data)
    }

    static func save(_ checkpoint: ForgeDraftCheckpoint) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(checkpoint)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Draft recovery is best-effort and must never block Forge.
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
