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

    private init() {
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

        for url in HTMLTools.externalURLs(in: app.html) {
            let destination = folder.appendingPathComponent(filename(for: url))
            if !force,
               let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let modified = attributes[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < maximumAge { continue }

            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("HTMLApp/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { continue }
                try data.write(to: destination, options: .atomic)
            } catch {
                // Keep the previous cached file when offline or refreshing fails.
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
