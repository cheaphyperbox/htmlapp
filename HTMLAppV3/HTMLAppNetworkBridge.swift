import Foundation
import UIKit

/// Public-HTTPS-only, explicitly consented bridge for JSON/text APIs that do
/// not expose browser CORS headers. No cookies, redirects, loopback, LAN, IP
/// literals, credentialed URLs or unbounded downloads.
enum HTMLAppNetworkBridge {
    static let maxRequestBytes = 512 * 1024
    static let maxResponseBytes = 1_048_576

    enum Failure: LocalizedError {
        case invalidURL, invalidMethod, invalidHeaders, requestTooLarge
        case responseTooLarge, invalidResponse, invalidEncoding

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Use a public HTTPS DNS hostname without embedded credentials, local addresses or IP literals."
            case .invalidMethod: return "Use GET, POST, PUT, PATCH, DELETE or HEAD."
            case .invalidHeaders: return "Request headers are invalid or include forbidden browser/transport headers."
            case .requestTooLarge: return "Native request body exceeds the 512 KB limit."
            case .responseTooLarge: return "Native response exceeds the 1 MB text limit."
            case .invalidResponse: return "The server did not return a valid HTTP response."
            case .invalidEncoding: return "This bridge accepts UTF-8 text/JSON responses only, not binary downloads."
            }
        }
    }

    static func validatedHost(_ args: [String: Any]) -> String? {
        guard let raw = args["url"] as? String, raw.count <= 4096,
              let url = URL(string: raw),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              let host = parts.host?.lowercased(),
              host.count <= 253, host.contains("."), !host.contains(":"),
              !host.hasPrefix("."), !host.hasSuffix("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".lan"),
              !host.hasSuffix(".internal"), !host.hasSuffix(".localhost"),
              !host.hasSuffix(".test"), !host.hasSuffix(".invalid"),
              !host.hasSuffix(".onion"), host != "localhost",
              host.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil,
              !host.allSatisfy({ $0.isNumber || $0 == "." }),
              host.split(separator: ".").allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else {
            return nil
        }
        return host
    }

    static func perform(_ args: [String: Any]) async throws -> [String: Any] {
        guard validatedHost(args) != nil, let raw = args["url"] as? String,
              let url = URL(string: raw) else { throw Failure.invalidURL }
        let method = (args["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].contains(method) else {
            throw Failure.invalidMethod
        }
        let headers = args["headers"] as? [String: String] ?? [:]
        guard headers.count <= 16,
              headers.allSatisfy({ key, value in
                  let lower = key.lowercased()
                  let forbidden = ["cookie", "set-cookie", "host", "origin",
                                   "referer", "content-length", "connection",
                                   "transfer-encoding", "proxy-authorization",
                                   "proxy-connection", "upgrade"]
                  return !forbidden.contains(lower) && key.count <= 80 &&
                      value.utf8.count <= 4096 &&
                      key.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil &&
                      !value.contains("\r") && !value.contains("\n")
              }) else { throw Failure.invalidHeaders }
        let body = args["body"] as? String ?? ""
        guard body.utf8.count <= maxRequestBytes else { throw Failure.requestTooLarge }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if !body.isEmpty { request.httpBody = Data(body.utf8) }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpShouldHandleCookies = false

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 40
        let delegate = NoRedirects()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if response.expectedContentLength > Int64(maxResponseBytes) {
            throw Failure.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if data.count >= maxResponseBytes { throw Failure.responseTooLarge }
            data.append(byte)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalidEncoding }
        return [
            "status": http.statusCode,
            "ok": (200...299).contains(http.statusCode),
            "contentType": http.value(forHTTPHeaderField: "Content-Type") ?? "",
            "body": text
        ]
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

@MainActor
enum HTMLAppNetworkDomainConsent {
    private static func key(_ appID: String) -> String { "htmlapp.network.allowedDomains." + appID }

    static func approved(for appID: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(appID)) ?? []
    }

    static func revoke(host: String, appID: String) {
        UserDefaults.standard.set(approved(for: appID).filter { $0 != host }, forKey: key(appID))
    }

    static func request(host: String, appID: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard appID != "PREVIEW" else { completion(false); return }
        if approved(for: appID).contains(host) { completion(true); return }
        guard let presenter = UIViewController.htmlAppTopViewController else {
            completion(false)
            return
        }
        let alert = UIAlertController(
            title: "Allow network access to \(host)?",
            message: "This saved HTML app wants to exchange data with \(host) through native iOS networking. It can send information you enter or authorize in this app. HTMLApp does not bypass website authentication. Only approve domains you trust.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Don't Allow", style: .cancel) { _ in
            completion(false)
        })
        alert.addAction(UIAlertAction(title: "Allow This Domain", style: .default) { _ in
            var domains = approved(for: appID)
            domains.append(host)
            UserDefaults.standard.set(Array(Set(domains)).sorted(), forKey: key(appID))
            completion(true)
        })
        presenter.present(alert, animated: true)
    }
}
