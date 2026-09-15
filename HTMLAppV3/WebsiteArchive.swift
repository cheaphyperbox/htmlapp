import Foundation
import SwiftUI
import CryptoKit
import CoreFoundation

struct WebsiteSnapshot {
    let sourceURL: URL
    let html: String
    let fingerprint: String
    let stagingURL: URL
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
    private let maximumResources = 160
    private let maximumPackageBytes = 60 * 1024 * 1024

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp", isDirectory: true)
        pendingRoot = base.appendingPathComponent("WebsitePending", isDirectory: true)
        temporaryRoot = base.appendingPathComponent("WebsiteDownloads", isDirectory: true)
        try? fileManager.createDirectory(at: pendingRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
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

        let context = CrawlContext(root: staging, maximumResources: maximumResources, maximumBytes: maximumPackageBytes)
        do {
            let (pageData, response) = try await fetch(url)
            guard pageData.count <= maximumPackageBytes else { throw WebsiteArchiveError.pageTooLarge }
            guard let html = decodeText(pageData, response: response) else { throw WebsiteArchiveError.unreadableHTML }
            context.totalBytes += pageData.count

            let rewritten = try await rewriteHTML(html, pageURL: url, context: context)
            try Data(rewritten.utf8).write(to: staging.appendingPathComponent("snapshot.html"), options: .atomic)
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
        try? fileManager.removeItem(at: pending)
        return metadata
    }

    func remove(appID: String) {
        try? fileManager.removeItem(at: pendingURL(appID: appID))
    }

    private func pendingURL(appID: String) -> URL {
        pendingRoot.appendingPathComponent(appID, isDirectory: true)
    }

    private func replaceLiveContents(from staged: URL, live: URL) throws {
        try? fileManager.removeItem(at: live)
        try fileManager.createDirectory(at: live, withIntermediateDirectories: true)
        let names = try fileManager.contentsOfDirectory(atPath: staged.path)
        for name in names where !["snapshot.html", "fingerprint.txt", "source-url.txt"].contains(name) {
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

        init(root: URL, maximumResources: Int, maximumBytes: Int) {
            self.root = root
            self.maximumResources = maximumResources
            self.maximumBytes = maximumBytes
        }
    }

    private func rewriteHTML(_ html: String, pageURL: URL, context: CrawlContext) async throws -> String {
        var rewritten = html
        var references = Set<String>()
        for pattern in [
            #"(?i)\b(?:src|poster)\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?i)<link\b[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"(?i)url\(\s*[\"']?([^\"')]+)[\"']?\s*\)"#
        ] {
            references.formUnion(captures(pattern: pattern, in: html))
        }

        var replacements: [String: String] = [:]
        for raw in references {
            guard let remote = resolvedResource(raw, relativeTo: pageURL) else { continue }
            if let local = try await downloadResource(remote, context: context) {
                replacements[raw] = local
            }
        }

        for (raw, local) in replacements.sorted(by: { $0.key.count > $1.key.count }) {
            rewritten = rewritten.replacingOccurrences(of: "\"\(raw)\"", with: "\"\(local)\"")
            rewritten = rewritten.replacingOccurrences(of: "'\(raw)'", with: "'\(local)'")
            rewritten = rewritten.replacingOccurrences(of: "url(\(raw))", with: "url(\(local))")
            rewritten = rewritten.replacingOccurrences(of: "url(\"\(raw)\")", with: "url(\"\(local)\")")
            rewritten = rewritten.replacingOccurrences(of: "url('\(raw)')", with: "url('\(local)')")
        }
        return rewritten
    }

    private func downloadResource(_ url: URL, context: CrawlContext) async throws -> String? {
        let key = url.absoluteString
        if let existing = context.mapping[key] { return existing }
        guard context.mapping.count < context.maximumResources,
              context.totalBytes < context.maximumBytes else { return nil }
        guard !context.inProgress.contains(key) else { return nil }
        context.inProgress.insert(key)
        defer { context.inProgress.remove(key) }

        do {
            let (data, response) = try await fetch(url)
            guard context.totalBytes + data.count <= context.maximumBytes else { return nil }
            context.totalBytes += data.count

            let host = sanitize(url.host ?? "unknown-domain")
            let ext = fileExtension(url: url, response: response)
            let name = stableName(for: key) + (ext.isEmpty ? "" : "." + ext)
            let relative = host + "/" + name
            context.mapping[key] = relative
            let folder = context.root.appendingPathComponent(host, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)

            if ext.lowercased() == "css", let css = decodeText(data, response: response) {
                var rewrittenCSS = css
                let refs = Set(captures(pattern: #"(?i)(?:url\(\s*[\"']?([^\"')]+)[\"']?\s*\)|@import\s+[\"']([^\"']+)[\"'])"#, in: css, allCaptureGroups: true))
                for raw in refs {
                    guard let nested = resolvedResource(raw, relativeTo: url),
                          let local = try await downloadResource(nested, context: context) else { continue }
                    rewrittenCSS = rewrittenCSS.replacingOccurrences(of: raw, with: "../" + local)
                }
                try Data(rewrittenCSS.utf8).write(to: destination, options: .atomic)
            } else {
                try data.write(to: destination, options: .atomic)
            }
            return relative
        } catch {
            context.mapping.removeValue(forKey: key)
            return nil
        }
    }

    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 HTMLApp/1.0", forHTTPHeaderField: "User-Agent")
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

    private func resolvedResource(_ raw: String, relativeTo base: URL) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("blob:"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else { return nil }
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func captures(pattern: String, in text: String, allCaptureGroups: Bool = false) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var output: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let groups = allCaptureGroups ? Array(1..<match.numberOfRanges) : [1]
            for group in groups where match.range(at: group).location != NSNotFound {
                if let range = Range(match.range(at: group), in: text) { output.append(String(text[range])) }
            }
        }
        return output
    }

    private func fileExtension(url: URL, response: URLResponse) -> String {
        let pathExt = url.pathExtension.lowercased()
        if !pathExt.isEmpty && pathExt.count <= 8 { return sanitizeExtension(pathExt) }
        let mime = response.mimeType?.lowercased() ?? ""
        let map: [String: String] = [
            "text/css": "css", "text/javascript": "js", "application/javascript": "js",
            "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp", "image/svg+xml": "svg",
            "font/woff": "woff", "font/woff2": "woff2", "application/font-woff": "woff",
            "video/mp4": "mp4", "audio/mpeg": "mp3", "application/json": "json"
        ]
        return map[mime] ?? "resource"
    }

    private func sanitizeExtension(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber }.prefix(8))
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }.reduce(into: "", { $0.append($1) })
    }

    private func stableName(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprint(of folder: URL) throws -> String {
        let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.lastPathComponent != "fingerprint.txt" else { continue }
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
                    Text("HTMLApp downloads the page and its directly referenced scripts, styles, fonts, images, and media. Files from the same domain are stored together in that domain’s cache folder. The downloaded copy opens immediately and refreshes in the background later.")
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
