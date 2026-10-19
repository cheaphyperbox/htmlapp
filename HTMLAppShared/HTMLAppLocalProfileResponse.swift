import Foundation

enum HTMLAppLocalProfileResponse {
    static func response(request: String, path: String, profile: Data) -> Data {
        let first = request.components(separatedBy: "\r\n").first ?? ""
        let parts = first.split(separator: " ")
        let allowed = parts.count == 3 && parts[0] == "GET" && String(parts[1]) == path && parts[2].hasPrefix("HTTP/1.")
        let body = allowed ? profile : Data("Not found".utf8)
        let status = allowed ? "200 OK" : "404 Not Found"
        let mime = allowed ? "application/x-apple-aspen-config" : "text/plain"
        let attachment = allowed ? "Content-Disposition: attachment; filename=HTMLApp.mobileconfig\r\n" : ""
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\n\(attachment)Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return Data(headers.utf8) + body
    }
}
