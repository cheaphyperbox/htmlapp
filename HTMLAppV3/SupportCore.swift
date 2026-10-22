import Foundation

enum HTMLTools {
    static func title(in html: String) -> String? {
        capture("<title[^>]*>(.*?)</title>", text: html)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    static func visibleText(in html: String) -> String {
        html
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func externalURLs(in html: String) -> [URL] {
        let patterns = [
            "(?:src|href)=[\\\"'](https?://[^\\\"']+)[\\\"']",
            "url\\([\\\"']?(https?://[^)\\\"']+)[\\\"']?\\)"
        ]
        var urls = Set<URL>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: html),
                      let url = URL(string: String(html[range])) else { continue }
                urls.insert(url)
            }
        }
        return Array(urls)
    }

    private static func capture(_ pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

actor SourceCache {
    static let shared = SourceCache()
    private let root: URL
    private let session: URLSession
    private let maxFileBytes = 3 * 1_024 * 1_024
    private let maxAppBytes = 24 * 1_024 * 1_024

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    nonisolated func baseURL(appID: String) -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache/\(appID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func refresh(app: SavedHTMLApp, force: Bool) async {
        let folder = root.appendingPathComponent(app.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configured = UserDefaults.standard.integer(forKey: "sourceRefreshDays")
        let days = configured == 0 ? 3 : configured
        let maximumAge = TimeInterval(days * 86_400)

        let manager = FileManager.default
        let existingURLs = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var totalBytes = existingURLs.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        for url in HTMLTools.externalURLs(in: app.html).prefix(24) {
            guard totalBytes < maxAppBytes, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { break }
            let destination = folder.appendingPathComponent(filename(for: url))
            if !force,
               let attributes = try? manager.attributesOfItem(atPath: destination.path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < maximumAge { continue }
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.setValue("HTMLApp/1.5", forHTTPHeaderField: "User-Agent")
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { continue }
                let type = (http.mimeType ?? "").lowercased()
                if type.hasPrefix("video/") || type.hasPrefix("audio/") ||
                   type.contains("zip") || type.contains("pdf") { continue }
                guard http.expectedContentLength < 0 ||
                      http.expectedContentLength <= Int64(maxFileBytes) else { continue }
                let previousSize = (try? manager.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
                let budget = min(maxFileBytes, maxAppBytes - totalBytes + previousSize)
                guard budget > 0 else { break }
                var data = Data()
                data.reserveCapacity(min(budget, 32_768))
                var exceeded = false
                for try await byte in bytes {
                    if data.count >= budget {
                        exceeded = true
                        break
                    }
                    data.append(byte)
                }
                guard !exceeded, !data.isEmpty else { continue }
                try data.write(to: destination, options: .atomic)
                totalBytes += data.count - previousSize
            } catch {
                // An interrupted or oversized transfer never replaces existing
                // valid cached data.
            }
        }
    }

    nonisolated func remove(appID: String) {
        try? FileManager.default.removeItem(at: baseURL(appID: appID))
    }

    nonisolated func clearAll() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/SourceCache", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func filename(for url: URL) -> String {
        let hash = url.absoluteString.utf8.reduce(UInt64(1469598103934665603)) {
            ($0 ^ UInt64($1)) &* 1099511628211
        }
        return String(hash, radix: 16) + "." + (url.pathExtension.isEmpty ? "resource" : url.pathExtension)
    }
}
