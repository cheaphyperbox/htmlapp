import Foundation
import UIKit

struct HTMLAppPortableBundle: Codable {
    static let currentVersion = 4

    var formatVersion: Int
    var exportedAt: Date
    var apps: [SavedHTMLApp]
    var folders: [LibraryFolder]
    var links: [LibraryAppLink]
    var permissionChoices: [String: [String: String]]
    var sensorChoices: [String: String]
    var appData: [String: [String: String]]?
    var websiteStates: [String: WebsiteArchivePortableState]?
}

enum HTMLAppPackageError: LocalizedError {
    case invalidArchive
    case unsupportedVersion
    case missingManifest
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The selected file is not a valid HTMLApp backup."
        case .unsupportedVersion: return "This HTMLApp backup was created by a newer unsupported format."
        case .missingManifest: return "The HTMLApp backup is missing its package manifest."
        case .unsafePath: return "The HTMLApp backup contains an unsafe file path."
        }
    }
}

enum HTMLAppPackageTransfer {
    private static let manifestName = "htmlapp-package.json"

    static func createArchive(
        apps: [SavedHTMLApp],
        folders: [LibraryFolder],
        links: [LibraryAppLink]
    ) throws -> URL {
        let appIDs = Set(apps.map(\.id))
        // Permission grants are deliberately not transferred. A received HTMLApp
        // must ask again on the destination device before sensitive native access.
        let permissionChoices: [String: [String: String]] = [:]
        let sensorChoices: [String: String] = [:]

        let bundle = HTMLAppPortableBundle(
            formatVersion: HTMLAppPortableBundle.currentVersion,
            exportedAt: Date(),
            apps: apps,
            folders: folders,
            links: links.filter { appIDs.contains($0.appID) },
            permissionChoices: permissionChoices,
            sensorChoices: sensorChoices,
            appData: Dictionary(uniqueKeysWithValues: apps.map {
                ($0.id, HTMLAppPortableDataStore.all(appID: $0.id))
            }),
            websiteStates: Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                guard app.websiteSourceURL != nil else { return nil }
                return (app.id, WebsiteArchiveManager.shared.portableState(appID: app.id))
            })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var entries: [StoredZip.Entry] = [
            .init(path: manifestName, data: try encoder.encode(bundle))
        ]

        for app in apps {
            let root = SourceCache.shared.baseURL(appID: app.id)
            if FileManager.default.fileExists(atPath: root.path) {
                for item in try recursiveFiles(at: root) {
                    let relative = item.path.replacingOccurrences(of: root.path + "/", with: "")
                    guard isSafeRelativePath(relative) else { continue }
                    let data = try Data(contentsOf: item)
                    entries.append(.init(path: "cache/\(app.id)/\(relative)", data: data))
                }
            }
        }

        let safeBase: String
        if apps.count == 1 {
            safeBase = safeFilename(apps[0].name)
        } else {
            safeBase = "HTMLApp-Backup-\(apps.count)-Apps"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeBase + ".htmlapp.zip")
        try? FileManager.default.removeItem(at: url)
        try StoredZip.write(entries: entries, to: url)
        return url
    }

    static func readArchive(from url: URL) throws -> (bundle: HTMLAppPortableBundle, cacheFiles: [String: Data]) {
        let entries = try StoredZip.read(from: url)
        guard let manifest = entries[manifestName] else { throw HTMLAppPackageError.missingManifest }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(HTMLAppPortableBundle.self, from: manifest) else {
            throw HTMLAppPackageError.invalidArchive
        }
        guard bundle.formatVersion <= HTMLAppPortableBundle.currentVersion else {
            throw HTMLAppPackageError.unsupportedVersion
        }

        var cache: [String: Data] = [:]
        for (path, data) in entries where path.hasPrefix("cache/") {
            guard isSafeRelativePath(path) else { throw HTMLAppPackageError.unsafePath }
            cache[path] = data
        }
        return (bundle, cache)
    }

    static func restoreCache(
        _ files: [String: Data],
        appIDMap: [String: String]
    ) throws {
        for (path, data) in files {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, parts[0] == "cache",
                  let newID = appIDMap[parts[1]] else { continue }
            let relative = parts.dropFirst(2).joined(separator: "/")
            guard isSafeRelativePath(relative) else { throw HTMLAppPackageError.unsafePath }

            let root = SourceCache.shared.baseURL(appID: newID)
            let destination = root.appendingPathComponent(relative)
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    private static func recursiveFiles(at root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { urls.append(url) }
        }
        return urls
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "HTMLApp" : String(cleaned.prefix(80))
    }
}

// A tiny ZIP implementation using the STORE method (no compression).
// It keeps the backup interoperable with normal ZIP tools without adding a dependency.
private enum StoredZip {
    struct Entry {
        let path: String
        let data: Data
    }

    private struct CentralRecord {
        let path: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    static func write(entries: [Entry], to url: URL) throws {
        var archive = Data()
        var central: [CentralRecord] = []

        for entry in entries {
            guard let pathData = entry.path.data(using: .utf8),
                  pathData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw HTMLAppPackageError.invalidArchive
            }
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(archive.count)

            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(crc)
            archive.appendLE(size)
            archive.appendLE(size)
            archive.appendLE(UInt16(pathData.count))
            archive.appendLE(UInt16(0))
            archive.append(pathData)
            archive.append(entry.data)

            central.append(.init(path: pathData, crc: crc, size: size, offset: offset))
        }

        let centralStart = UInt32(archive.count)
        for record in central {
            archive.appendLE(UInt32(0x02014b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(record.crc)
            archive.appendLE(record.size)
            archive.appendLE(record.size)
            archive.appendLE(UInt16(record.path.count))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt32(0))
            archive.appendLE(record.offset)
            archive.append(record.path)
        }

        let centralSize = UInt32(archive.count) - centralStart
        guard central.count <= Int(UInt16.max) else { throw HTMLAppPackageError.invalidArchive }
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(central.count))
        archive.appendLE(UInt16(central.count))
        archive.appendLE(centralSize)
        archive.appendLE(centralStart)
        archive.appendLE(UInt16(0))
        try archive.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        var cursor = 0
        var result: [String: Data] = [:]

        while cursor + 4 <= data.count {
            let signature: UInt32 = try data.readLE(at: cursor)
            if signature == 0x02014b50 || signature == 0x06054b50 { break }
            guard signature == 0x04034b50, cursor + 30 <= data.count else {
                throw HTMLAppPackageError.invalidArchive
            }

            let flags: UInt16 = try data.readLE(at: cursor + 6)
            let method: UInt16 = try data.readLE(at: cursor + 8)
            let compressedSize: UInt32 = try data.readLE(at: cursor + 18)
            let uncompressedSize: UInt32 = try data.readLE(at: cursor + 22)
            let nameLength: UInt16 = try data.readLE(at: cursor + 26)
            let extraLength: UInt16 = try data.readLE(at: cursor + 28)

            guard method == 0, flags & 0x0008 == 0, compressedSize == uncompressedSize else {
                throw HTMLAppPackageError.invalidArchive
            }

            let nameStart = cursor + 30
            let nameEnd = nameStart + Int(nameLength)
            let dataStart = nameEnd + Int(extraLength)
            let dataEnd = dataStart + Int(compressedSize)
            guard nameEnd <= data.count, dataEnd <= data.count else {
                throw HTMLAppPackageError.invalidArchive
            }

            let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""
            guard isSafePath(name) else { throw HTMLAppPackageError.unsafePath }
            result[name] = Data(data[dataStart..<dataEnd])
            cursor = dataEnd
        }

        return result
    }

    private static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty &&
        !path.hasPrefix("/") &&
        !path.contains("\\") &&
        !path.split(separator: "/").contains("..")
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else {
            throw HTMLAppPackageError.invalidArchive
        }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { buffer in
            copyBytes(to: buffer, from: offset..<(offset + MemoryLayout<T>.size))
        }
        return T(littleEndian: value)
    }
}
