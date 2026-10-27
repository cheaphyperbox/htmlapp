import Foundation

/// Advisory static analysis of native APIs used by generated HTML.
/// Never executes untrusted app JavaScript.
enum HTMLAppBridgeLint {
    static func warnings(in html: String) -> [String] {
        let known = Set(HTMLAppDeviceAPIResearch.entries.map(\.id))
        let pattern = #"\b(?:HTMLAppNative|HTMLApp)\.([A-Za-z][A-Za-z0-9]*)\.([A-Za-z][A-Za-z0-9]*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = html as NSString
        var warnings: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard match.numberOfRanges == 3 else { continue }
            let namespace = source.substring(with: match.range(at: 1))
            let method = source.substring(with: match.range(at: 2))
            let name = namespace + "." + method
            if !known.contains(name), seen.insert(name).inserted {
                warnings.append("Bridge lint: \\(name) is not in the supported API catalog; feature-detect it and provide a fallback.")
            }
        }
        if html.contains("navigator.bluetooth.requestDevice(") {
            warnings.append("Bridge lint: Web Bluetooth requestDevice is not supported by this WKWebView runtime; use an available native capability.")
        }
        return warnings
    }
}
