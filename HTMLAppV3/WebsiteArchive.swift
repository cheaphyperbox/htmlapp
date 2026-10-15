import Foundation
import SwiftUI
import CryptoKit
import CoreFoundation

struct WebsiteSourceRecord: Codable, Hashable, Identifiable {
    let sourceURL: String
    let localPath: String?

    var id: String { sourceURL }
    var isCached: Bool { localPath != nil }
}

struct WebsiteSnapshot {
    let sourceURL: URL
    let html: String
    let fingerprint: String
    let stagingURL: URL
}

struct WebsiteArchivePortableState: Codable {
    var sourceManifest: Data?
    var disabledSources: [String]
}

enum WebsiteArchiveError: LocalizedError {
    case invalidURL
    case invalidResponse
    case pageTooLarge
    case unreadableHTML

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid http or https website URL."
        case .invalidResponse: return "The website could not be downloaded."
        case .pageTooLarge: return "The website package is too large to download safely."
        case .unreadableHTML: return "The downloaded page was not readable HTML."
        }
    }
}

final class WebsiteArchiveManager: @unchecked Sendable {
    static let shared = WebsiteArchiveManager()

    private let fileManager = FileManager.default
    private let pendingRoot: URL
    private let temporaryRoot: URL
    private let manifestRoot: URL
    private let disabledSourcesKeyPrefix = "htmlapp.websiteDisabledSources."
    private let maximumResources = 500
    private let maximumPackageBytes = 150 * 1024 * 1024

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        pendingRoot = base.appendingPathComponent("WebsitePending", isDirectory: true)
        temporaryRoot = base.appendingPathComponent("WebsiteDownloads", isDirectory: true)
        manifestRoot = base.appendingPathComponent("WebsiteSourceManifests", isDirectory: true)
        try? fileManager.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: manifestRoot, withIntermediateDirectories: true)
    }

    func portableState(appID: String) -> WebsiteArchivePortableState {
        let manifestURL = manifestRoot.appendingPathComponent(appID + ".json")
        return WebsiteArchivePortableState(
            sourceManifest: try? Data(contentsOf: manifestURL),
            disabledSources: Array(disabledSources(appID: appID)).sorted()
        )
    }

    func restorePortableState(_ state: WebsiteArchivePortableState?, appID: String) {
        let manifestURL = manifestRoot.appendingPathComponent(appID + ".json")
        try? fileManager.removeItem(at: manifestURL)
        if let data = state?.sourceManifest {
            try? data.write(to: manifestURL, options: .atomic)
        }

        let key = disabledSourcesKeyPrefix + appID
        if let values = state?.disabledSources, !values.isEmpty {
            UserDefaults.standard.set(values, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func sourceRecords(appID: String) -> [WebsiteSourceRecord] {
        let url = manifestRoot.appendingPathComponent(appID + ".json")
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([WebsiteSourceRecord].self, from: data) else { return [] }
        return records.sorted { $0.sourceURL.localizedCaseInsensitiveCompare($1.sourceURL) == .orderedAscending }
    }

    func isDownloadEnabled(appID: String, sourceURL: String) -> Bool {
        !disabledSources(appID: appID).contains(canonicalString(sourceURL))
    }

    func setDownloadEnabled(_ enabled: Bool, appID: String, sourceURL: String) {
        let key = disabledSourcesKeyPrefix + appID
        var disabled = disabledSources(appID: appID)
        let canonical = canonicalString(sourceURL)
        if enabled { disabled.remove(canonical) }
        else { disabled.insert(canonical) }
        UserDefaults.standard.set(Array(disabled).sorted(), forKey: key)
    }

    func normalizedURL(_ string: String) -> URL? {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://" + value
        }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    func download(url: URL, appID: String) async throws -> WebsiteSnapshot {
        let staging = temporaryRoot.appendingPathComponent("\(appID)-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let context = CrawlContext(root: staging, maximumResources: maximumResources, maximumBytes: maximumPackageBytes, disabledURLs: disabledSources(appID: appID))
        do {
            let (pageData, response) = try await fetch(url)
            guard pageData.count <= maximumPackageBytes else { throw WebsiteArchiveError.pageTooLarge }
            guard let html = decodeText(pageData, response: response) else { throw WebsiteArchiveError.unreadableHTML }
            context.totalBytes += pageData.count

            // Relative references must resolve against the URL after redirects, not only the URL the user typed.
            let pageURL = response.url ?? url
            let rewritten = try await rewriteHTML(html, pageURL: pageURL, context: context)
            try Data(rewritten.utf8).write(to: staging.appendingPathComponent("snapshot.html"), options: .atomic)
            let sourceRecords = context.discovered.sorted().map { key in
                WebsiteSourceRecord(sourceURL: key, localPath: context.mapping[key])
            }
            let manifestData = try JSONEncoder().encode(sourceRecords)
            try manifestData.write(to: staging.appendingPathComponent("sources-manifest.json"), options: .atomic)
            let fingerprint = try fingerprint(of: staging)
            try fingerprint.write(to: staging.appendingPathComponent("fingerprint.txt"), atomically: true, encoding: .utf8)
            try url.absoluteString.write(to: staging.appendingPathComponent("source-url.txt"), atomically: true, encoding: .utf8)
            return WebsiteSnapshot(sourceURL: url, html: rewritten, fingerprint: fingerprint, stagingURL: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func installInitial(_ snapshot: WebsiteSnapshot, appID: String) throws {
        let live = SourceCache.shared.baseURL(appID: appID)
        try replaceLiveContents(from: snapshot.stagingURL, live: live)
        try persistManifest(from: snapshot.stagingURL, appID: appID)
        try? fileManager.removeItem(at: snapshot.stagingURL)
    }

    func stageIfChanged(url: URL, appID: String, currentFingerprint: String?) async throws -> Bool {
        let snapshot = try await download(url: url, appID: appID)
        guard snapshot.fingerprint != currentFingerprint else {
            try? fileManager.removeItem(at: snapshot.stagingURL)
            return false
        }
        let pending = pendingURL(appID: appID)
        try? fileManager.removeItem(at: pending)
        try fileManager.moveItem(at: snapshot.stagingURL, to: pending)
        return true
    }

    func pendingSnapshot(appID: String) -> (html: String, fingerprint: String, sourceURL: String)? {
        let pending = pendingURL(appID: appID)
        guard let html = try? String(contentsOf: pending.appendingPathComponent("snapshot.html"), encoding: .utf8),
              let fingerprintText = try? String(contentsOf: pending.appendingPathComponent("fingerprint.txt"), encoding: .utf8),
              let sourceText = try? String(contentsOf: pending.appendingPathComponent("source-url.txt"), encoding: .utf8) else { return nil }
        return (
            html,
            fingerprintText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func activatePending(appID: String) throws -> (html: String, fingerprint: String, sourceURL: String)? {
        guard let metadata = pendingSnapshot(appID: appID) else { return nil }
        let pending = pendingURL(appID: appID)
        let live = SourceCache.shared.baseURL(appID: appID)
        try replaceLiveContents(from: pending, live: live)
        try persistManifest(from: pending, appID: appID)
        try? fileManager.removeItem(at: pending)
        return metadata
    }

    func remove(appID: String) {
        try? fileManager.removeItem(at: pendingURL(appID: appID))
        try? fileManager.removeItem(at: manifestRoot.appendingPathComponent(appID + ".json"))
        UserDefaults.standard.removeObject(forKey: disabledSourcesKeyPrefix + appID)
    }

    private func disabledSources(appID: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: disabledSourcesKeyPrefix + appID) ?? [])
    }

    private func canonicalString(_ value: String) -> String {
        guard let url = URL(string: value) else { return value }
        return canonicalKey(url)
    }

    private func persistManifest(from staged: URL, appID: String) throws {
        let source = staged.appendingPathComponent("sources-manifest.json")
        let destination = manifestRoot.appendingPathComponent(appID + ".json")
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: source, to: destination)
    }

    private func pendingURL(appID: String) -> URL {
        pendingRoot.appendingPathComponent(appID, isDirectory: true)
    }

    private func replaceLiveContents(from staged: URL, live: URL) throws {
        try? fileManager.removeItem(at: live)
        try fileManager.createDirectory(at: live, withIntermediateDirectories: true)
        let names = try fileManager.contentsOfDirectory(atPath: staged.path)
        for name in names where !["snapshot.html", "fingerprint.txt", "source-url.txt", "sources-manifest.json"].contains(name) {
            try fileManager.copyItem(at: staged.appendingPathComponent(name), to: live.appendingPathComponent(name))
        }
    }

    private final class CrawlContext {
        let root: URL
        let maximumResources: Int
        let maximumBytes: Int
        var totalBytes = 0
        var mapping: [String: String] = [:]
        var inProgress = Set<String>()
        var discovered = Set<String>()
        let disabledURLs: Set<String>

        init(root: URL, maximumResources: Int, maximumBytes: Int, disabledURLs: Set<String>) {
            self.root = root
            self.maximumResources = maximumResources
            self.maximumBytes = maximumBytes
            self.disabledURLs = disabledURLs
        }
    }

    private func rewriteHTML(_ html: String, pageURL: URL, context: CrawlContext) async throws -> String {
        var rewritten = html
        var references = Set<String>()
        let effectiveBaseURL = htmlBaseURL(in: html, pageURL: pageURL) ?? pageURL

        // Standard HTML resources, including third-party/CDN URLs and root-relative paths
        // such as /assets/icon.png. Both quoted and common unquoted attributes are handled.
        for pattern in [
            #"(?i)\b(?:src|poster|data)\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?i)\b(?:src|poster|data)\s*=\s*(?![\"'])([^\s\"'<>`]+)"#,
            #"(?i)<link\b[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"(?i)<link\b[^>]*\bhref\s*=\s*(?![\"'])([^\s\"'<>`]+)[^>]*>"#,
            #"(?i)<(?:use|image)\b[^>]*\b(?:href|xlink:href)\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"(?i)<(?:use|image)\b[^>]*\b(?:href|xlink:href)\s*=\s*(?![\"'])([^\s\"'<>`]+)[^>]*>"#,
            #"(?i)url\(\s*[\"']?([^\"')]+)[\"']?\s*\)"#
        ] {
            references.formUnion(captures(pattern: pattern, in: html))
        }

        // srcset/imagesrcset can contain several URLs in one attribute.
        for value in captures(pattern: #"(?i)\b(?:srcset|imagesrcset)\s*=\s*[\"']([^\"']+)[\"']"#, in: html) {
            for candidate in srcsetURLs(value) { references.insert(candidate) }
        }

        var replacements: [String: String] = [:]
        for raw in references {
            guard let remote = resolvedResource(raw, relativeTo: effectiveBaseURL) else { continue }
            if let replacement = try await replacementForResource(remote, context: context, fromNestedFile: false) {
                replacements[raw] = replacement
            }
        }

        // Replace references anywhere they occur. This intentionally also catches static URL strings
        // used by scripts in the document, not just src/href attributes.
        for (raw, local) in replacements.sorted(by: { $0.key.count > $1.key.count }) {
            rewritten = rewritten.replacingOccurrences(of: raw, with: local)
        }

        // A remote <base> would make our local domain/file paths resolve back to the network.
        rewritten = rewritten.replacingOccurrences(
            of: #"(?i)<base\b[^>]*>"#,
            with: "",
            options: .regularExpression
        )
        return rewritten
    }

    private func downloadResource(_ url: URL, context: CrawlContext) async throws -> String? {
        let key = canonicalKey(url)
        context.discovered.insert(key)
        if let existing = context.mapping[key] { return existing }
        guard context.mapping.count < context.maximumResources,
              context.totalBytes < context.maximumBytes else { return nil }
        guard !context.inProgress.contains(key) else { return context.mapping[key] }
        context.inProgress.insert(key)
        defer { context.inProgress.remove(key) }

        do {
            let (data, response) = try await fetch(url)
            guard context.totalBytes + data.count <= context.maximumBytes else { return nil }
            context.totalBytes += data.count

            let finalURL = response.url ?? url
            let host = sanitize(finalURL.host ?? url.host ?? "unknown-domain")
            let ext = fileExtension(url: finalURL, response: response)
            let name = stableName(for: key) + (ext.isEmpty ? "" : "." + ext)
            let relative = host + "/" + name
            context.mapping[key] = relative
            context.mapping[canonicalKey(finalURL)] = relative

            let folder = context.root.appendingPathComponent(host, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)

            if isCSS(response: response, ext: ext), let css = decodeText(data, response: response) {
                let rewrittenCSS = try await rewriteCSS(css, sourceURL: finalURL, context: context)
                try Data(rewrittenCSS.utf8).write(to: destination, options: .atomic)
            } else if isJavaScript(response: response, ext: ext), let script = decodeText(data, response: response) {
                let rewrittenScript = try await rewriteJavaScript(script, sourceURL: finalURL, context: context)
                try Data(rewrittenScript.utf8).write(to: destination, options: .atomic)
            } else {
                try data.write(to: destination, options: .atomic)
            }
            return relative
        } catch {
            context.mapping.removeValue(forKey: key)
            return nil
        }
    }

    private func rewriteCSS(_ css: String, sourceURL: URL, context: CrawlContext) async throws -> String {
        var rewritten = css
        let patterns = [
            #"(?i)url\(\s*[\"']?([^\"')]+)[\"']?\s*\)"#,
            #"(?i)@import\s+(?:url\()?\s*[\"']([^\"']+)[\"']"#
        ]
        var references = Set<String>()
        for pattern in patterns { references.formUnion(captures(pattern: pattern, in: css)) }

        for raw in references.sorted(by: { $0.count > $1.count }) {
            guard let nested = resolvedResource(raw, relativeTo: sourceURL),
                  let replacement = try await replacementForResource(nested, context: context, fromNestedFile: true) else { continue }
            rewritten = rewritten.replacingOccurrences(of: raw, with: replacement)
        }
        return rewritten
    }

    private func rewriteJavaScript(_ script: String, sourceURL: URL, context: CrawlContext) async throws -> String {
        var rewritten = script
        var references = Set<String>()

        // ES modules, dynamic imports, workers, importScripts, literal fetches, and
        // new URL("/asset", import.meta.url) commonly point at additional resources.
        for pattern in [
            #"(?m)\b(?:import|export)\s+(?:[^\"']*?\s+from\s+)?[\"']([^\"']+)[\"']"#,
            #"(?m)\bimport\s*\(\s*[\"']([^\"']+)[\"']\s*\)"#,
            #"(?m)\bimportScripts\s*\(\s*[\"']([^\"']+)[\"']"#,
            #"(?m)\b(?:new\s+)?(?:Worker|SharedWorker)\s*\(\s*[\"']([^\"']+)[\"']"#,
            #"(?m)\bfetch\s*\(\s*[\"']([^\"']+)[\"']"#,
            #"(?m)\bnew\s+URL\s*\(\s*[\"']([^\"']+)[\"']\s*,\s*import\.meta\.url\s*\)"#
        ] {
            references.formUnion(captures(pattern: pattern, in: script))
        }

        for raw in references.sorted(by: { $0.count > $1.count }) {
            guard let nested = resolvedResource(raw, relativeTo: sourceURL),
                  let replacement = try await replacementForResource(nested, context: context, fromNestedFile: true) else { continue }
            rewritten = rewritten.replacingOccurrences(of: raw, with: replacement)
        }
        return rewritten
    }

    private func replacementForResource(_ url: URL, context: CrawlContext, fromNestedFile: Bool) async throws -> String? {
        let key = canonicalKey(url)
        context.discovered.insert(key)
        if context.disabledURLs.contains(key) {
            // A disabled relative URL must become absolute because archived HTML/CSS/JS
            // runs from local storage and would otherwise resolve /api/... against file://.
            return url.absoluteString
        }
        guard let local = try await downloadResource(url, context: context) else { return nil }
        return fromNestedFile ? "../" + local : local
    }

    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HTMLApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,text/css,application/javascript,application/json,image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw WebsiteArchiveError.invalidResponse }
        return (data, response)
    }

    private func decodeText(_ data: Data, response: URLResponse) -> String? {
        if let encodingName = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                if let text = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) { return text }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private func htmlBaseURL(in html: String, pageURL: URL) -> URL? {
        let quoted = captures(
            pattern: #"(?i)<base\b[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            in: html
        ).first
        let unquoted = captures(
            pattern: #"(?i)<base\b[^>]*\bhref\s*=\s*(?![\"'])([^\s\"'<>`]+)[^>]*>"#,
            in: html
        ).first
        guard let raw = quoted ?? unquoted else { return nil }
        return resolvedResource(raw, relativeTo: pageURL)
    }

    private func resolvedResource(_ raw: String, relativeTo base: URL) -> URL? {
        let value = decodeHTMLAttribute(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("blob:"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:"),
              !value.lowercased().hasPrefix("tel:") else { return nil }

        let candidate: URL?
        if value.hasPrefix("//") {
            candidate = URL(string: "\(base.scheme ?? "https"):\(value)")
        } else if value.hasPrefix("/") {
            // Explicitly resolve root-relative references against the website origin.
            // This covers /assets/icon.png even when the page itself is nested deeply.
            var origin = URLComponents(url: base.absoluteURL, resolvingAgainstBaseURL: true)
            origin?.path = ""
            origin?.query = nil
            origin?.fragment = nil
            if let originURL = origin?.url {
                candidate = URL(string: value, relativeTo: originURL)?.absoluteURL
            } else {
                candidate = URL(string: value, relativeTo: base)?.absoluteURL
            }
        } else {
            candidate = URL(string: value, relativeTo: base)?.absoluteURL
        }

        guard let url = candidate,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func decodeHTMLAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&#x27;", with: "'", options: .caseInsensitive)
    }

    private func srcsetURLs(_ value: String) -> [String] {
        value.split(separator: ",").compactMap { item in
            let value = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return value.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        }
    }

    private func captures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var output: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            output.append(String(text[range]))
        }
        return output
    }

    private func fileExtension(url: URL, response: URLResponse) -> String {
        let pathExt = url.pathExtension.lowercased()
        if !pathExt.isEmpty && pathExt.count <= 10 { return sanitizeExtension(pathExt) }
        let mime = response.mimeType?.lowercased() ?? ""
        let map: [String: String] = [
            "text/css": "css", "text/javascript": "js", "application/javascript": "js", "application/x-javascript": "js",
            "application/json": "json", "application/manifest+json": "json", "application/wasm": "wasm",
            "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp", "image/avif": "avif", "image/svg+xml": "svg", "image/x-icon": "ico",
            "font/woff": "woff", "font/woff2": "woff2", "application/font-woff": "woff", "application/vnd.ms-fontobject": "eot", "font/ttf": "ttf", "font/otf": "otf",
            "video/mp4": "mp4", "video/webm": "webm", "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/ogg": "ogg"
        ]
        return map[mime] ?? "resource"
    }

    private func isCSS(response: URLResponse, ext: String) -> Bool {
        ext.lowercased() == "css" || response.mimeType?.lowercased() == "text/css"
    }

    private func isJavaScript(response: URLResponse, ext: String) -> Bool {
        let value = ext.lowercased()
        if value == "js" || value == "mjs" { return true }
        let mime = response.mimeType?.lowercased() ?? ""
        return ["text/javascript", "application/javascript", "application/x-javascript"].contains(mime)
    }

    private func sanitizeExtension(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber }.prefix(10))
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }.reduce(into: "", { $0.append($1) })
    }

    private func canonicalKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private func stableName(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprint(of folder: URL) throws -> String {
        let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            guard !["fingerprint.txt", "sources-manifest.json"].contains(file.lastPathComponent) else { continue }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                files.append(file)
            }
        }
        var hasher = SHA256()
        for file in files.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data(file.path.replacingOccurrences(of: folder.path, with: "").utf8))
            hasher.update(data: try Data(contentsOf: file))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct WebsiteImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = "https://"
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Website URL") {
                    TextField("https://example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Text("HTMLApp downloads the page plus its required local and third-party dependencies, including root-relative paths such as /assets/icon.png, stylesheets, scripts and module imports, fonts, images, media, workers, and other directly referenced files. Each domain gets its own cache folder. The downloaded copy opens immediately and refreshes in the background later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    working = true
                    Task {
                        do {
                            try await store.addWebsite(urlString: url)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            working = false
                        }
                    }
                } label: {
                    Label("Download Website", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || WebsiteArchiveManager.shared.normalizedURL(url) == nil)
            }
            .navigationTitle("Download Website")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overlay { if working { ProgressView("Downloading website…") } }
            .alert("Download Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
