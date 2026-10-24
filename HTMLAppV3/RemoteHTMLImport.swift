import Foundation

/// An uncommitted document opened from an external HTTPS link. It only enters
/// the user's Library if they explicitly choose Save App in Forge.
struct RemoteHTMLImportDraft: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let html: String
    let name: String
}

enum RemoteHTMLImport {
    enum ImportError: LocalizedError {
        case missingURL, unsafeURL, failedDownload, tooLarge, notHTML

        var errorDescription: String? {
            switch self {
            case .missingURL: return "Use htmlapp://import?url= followed by a URL-encoded HTTPS HTML file address."
            case .unsafeURL: return "Only public HTTPS HTML URLs are allowed. Local addresses, credentials and insecure redirects are blocked."
            case .failedDownload: return "The HTML file could not be downloaded. Check the link and try again."
            case .tooLarge: return "The remote HTML file exceeds the 12 MB import limit."
            case .notHTML: return "The link did not return a UTF-8 HTML document."
            }
        }
    }

    static func sourceURL(from deepLink: URL) throws -> URL {
        guard let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: raw) else { throw ImportError.missingURL }
        guard isPublicHTTPS(url) else { throw ImportError.unsafeURL }
        return url
    }

    static func isPublicHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty,
              host != "localhost", !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"), !host.hasSuffix(".internal"),
              !host.hasSuffix(".test"), !host.hasSuffix(".invalid"),
              !host.contains(":"), host.contains("."),
              host.range(of: #"^[0-9.]+$"#, options: .regularExpression) == nil
        else { return false }
        return true
    }

    static func download(_ url: URL) async throws -> RemoteHTMLImportDraft {
        guard isPublicHTTPS(url) else { throw ImportError.unsafeURL }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 35
        config.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("text/html, application/xhtml+xml, text/plain;q=0.8", forHTTPHeaderField: "Accept")
        let redirectGuard = HTTPSRedirectGuard()
        let (temporaryFile, response) = try await session.download(for: request, delegate: redirectGuard)
        defer { try? FileManager.default.removeItem(at: temporaryFile) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let finalURL = response.url, isPublicHTTPS(finalURL)
        else { throw ImportError.failedDownload }

        let size = (try? FileManager.default.attributesOfItem(atPath: temporaryFile.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= 12_000_000 else { throw ImportError.tooLarge }
        let data = try Data(contentsOf: temporaryFile)
        guard !data.isEmpty, let html = String(data: data, encoding: .utf8),
              html.contains("<"), html.contains(">"),
              html.range(of: #"<(?:!doctype\s+html|html|head|body|main|div|section|script)"#,
                         options: .regularExpression.union(.caseInsensitive)) != nil
        else { throw ImportError.notHTML }
        let name = HTMLTools.title(in: html)
            ?? finalURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return RemoteHTMLImportDraft(sourceURL: finalURL, html: html, name: String(name.prefix(100)))
    }
}

private final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(RemoteHTMLImport.isPublicHTTPS) == true ? request : nil)
    }
}
