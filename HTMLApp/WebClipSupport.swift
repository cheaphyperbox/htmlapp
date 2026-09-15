import Foundation
import UIKit

extension SavedHTMLApp {
    var resolvedIconData: Data {
        if let favicon,
           let image = UIImage(data: favicon),
           let png = HTMLAppIconTools.normalizedPNG(image) {
            return png
        }
        return HTMLAppIconTools.generatedIcon(name: name, html: html)
    }
}

enum HTMLAppIconTools {
    static func savedIcon(html: String, name: String) async -> Data? {
        if let source = faviconSource(in: html),
           let data = await loadIcon(source),
           let image = UIImage(data: data),
           let png = normalizedPNG(image) {
            return png
        }
        return generatedIcon(name: name, html: html)
    }

    static func generatedIcon(name: String, html: String) -> Data {
        let colors = detectedColors(in: html)
        let background = UIColor(htmlColor: colors.background) ?? .systemIndigo
        let foreground = UIColor(htmlColor: colors.foreground) ?? .white
        let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map {
            String($0).uppercased()
        } ?? "H"

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format)
        return renderer.image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 180))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            initial.draw(
                in: CGRect(x: 0, y: 35, width: 180, height: 120),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 96, weight: .bold),
                    .foregroundColor: foreground,
                    .paragraphStyle: paragraph
                ]
            )
        }.pngData() ?? Data()
    }

    static func normalizedPNG(_ image: UIImage) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 180, height: 180))
        }.pngData()
    }

    private static func faviconSource(in html: String) -> String? {
        let patterns = [
            "<link[^>]+rel=[\\\"'][^\\\"']*(?:apple-touch-icon|icon)[^\\\"']*[\\\"'][^>]+href=[\\\"']([^\\\"']+)[\\\"']",
            "<link[^>]+href=[\\\"']([^\\\"']+)[\\\"'][^>]+rel=[\\\"'][^\\\"']*(?:apple-touch-icon|icon)[^\\\"']*[\\\"']"
        ]
        return patterns.compactMap { capture($0, in: html) }.first
    }

    private static func loadIcon(_ source: String) async -> Data? {
        if source.lowercased().hasPrefix("data:image"), let comma = source.firstIndex(of: ",") {
            let metadata = String(source[..<comma]).lowercased()
            let payload = String(source[source.index(after: comma)...])
            if metadata.contains(";base64") {
                return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            }
            return payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let url = URL(string: source),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func detectedColors(in html: String) -> (background: String, foreground: String) {
        let backgroundPatterns = [
            "background(?:-color)?\\s*:\\s*([^;}{]+)",
            "<body[^>]+bgcolor=[\\\"']([^\\\"']+)"
        ]
        let foregroundPatterns = [
            "(?:^|[;{])\\s*color\\s*:\\s*([^;}{]+)",
            "<body[^>]+text=[\\\"']([^\\\"']+)"
        ]
        let background = backgroundPatterns.compactMap { capture($0, in: html) }.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "#4f46e5"
        let foreground = foregroundPatterns.compactMap { capture($0, in: html) }.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "#ffffff"
        return (background, foreground)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

enum WebClipProfile {
    enum ProfileError: LocalizedError {
        case invalidDataURL
        case unableToOpen

        var errorDescription: String? {
            switch self {
            case .invalidDataURL:
                return "The Web Clip profile data URL could not be generated."
            case .unableToOpen:
                return "iOS could not open the generated profile in Safari."
            }
        }
    }

    static func mobileConfigData(for app: SavedHTMLApp) -> Data {
        Data(mobileConfig(for: app).utf8)
    }

    static func dataURL(for app: SavedHTMLApp) throws -> URL {
        let options: Data.Base64EncodingOptions = [
            .lineLength64Characters,
            .endLineWithCarriageReturn,
            .endLineWithLineFeed
        ]
        let base64 = mobileConfigData(for: app).base64EncodedString(options: options)
        let encodedBase64 = base64
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
        guard let url = URL(string: "data:application/x-apple-aspen-config;base64,\(encodedBase64)") else {
            throw ProfileError.invalidDataURL
        }
        return url
    }

    static func mobileConfig(for app: SavedHTMLApp) -> String {
        let label = xmlEscape(app.name)
        let launchURL = xmlEscape("htmlapp://open?id=\(app.id)")
        let icon = app.resolvedIconData.base64EncodedString(options: [.lineLength64Characters])
        let profileUUID = UUID().uuidString.uppercased()
        let clipUUID = UUID().uuidString.uppercased()
        let nonce = UUID().uuidString.lowercased()
        let fullScreen = UserDefaults.standard.object(forKey: "webClipFullScreen") as? Bool ?? true
        let precomposed = UserDefaults.standard.object(forKey: "webClipPrecomposed") as? Bool ?? false

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>ConsentText</key>
        <dict>
        <key>default</key>
        <string>Choose 'Install' and enter passcode if prompted.</string>
        </dict>
        <key>PayloadContent</key>
        <array>
        <dict>
        <key>FullScreen</key>
        <\(fullScreen ? "true" : "false")/>
        <key>Icon</key>
        <data>\(icon)</data>
        <key>IgnoreManifestScope</key>
        <true/>
        <key>IsRemovable</key>
        <true/>
        <key>Label</key>
        <string>\(label)</string>
        <key>PayloadDescription</key>
        <string>Created webapp</string>
        <key>PayloadDisplayName</key>
        <string>Web Clip \(label)</string>
        <key>PayloadIdentifier</key>
        <string>space.mekabrine.htmlapp.webclip.\(app.id.lowercased()).\(nonce)</string>
        <key>PayloadOrganization</key>
        <string>Mekabrine</string>
        <key>PayloadType</key>
        <string>com.apple.webClip.managed</string>
        <key>PayloadUUID</key>
        <string>\(clipUUID)</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        <key>Precomposed</key>
        <\(precomposed ? "true" : "false")/>
        <key>URL</key>
        <string>\(launchURL)</string>
        </dict>
        </array>
        <key>PayloadDescription</key>
        <string></string>
        <key>PayloadDisplayName</key>
        <string>WebClip: \(label)</string>
        <key>PayloadIdentifier</key>
        <string>space.mekabrine.webclip.\(app.id.lowercased()).\(nonce)</string>
        <key>PayloadOrganization</key>
        <string>mekabrine.space</string>
        <key>PayloadRemovalDisallowed</key>
        <false/>
        <key>PayloadType</key>
        <string>Configuration</string>
        <key>PayloadUUID</key>
        <string>\(profileUUID)</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        </dict>
        </plist>
        """
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

@MainActor
final class WebClipInstaller {
    static let shared = WebClipInstaller()

    func install(app: SavedHTMLApp, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let url = try WebClipProfile.dataURL(for: app)
            UIApplication.shared.open(url, options: [:]) { opened in
                if opened {
                    completion(.success(()))
                } else {
                    completion(.failure(WebClipProfile.ProfileError.unableToOpen))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
}

private extension UIColor {
    convenience init?(htmlColor raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let named = [
            "white": "ffffff", "black": "000000", "red": "ff0000",
            "blue": "0000ff", "green": "008000", "gray": "808080", "grey": "808080"
        ]
        if let replacement = named[value] { value = replacement }
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255,
            alpha: 1
        )
    }
}
