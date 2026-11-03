import Foundation

/// Optional context reduction for very large HTML edits with an explicitly
/// named selector. Falls back to full source rather than guessing a target.
enum ForgeFocusedEditContext {
    static func make(source html: String, request: String, semanticTargets: [String] = []) -> String? {
        guard html.utf8.count > 20_000,
              request.count <= 200,
              let pattern = try? NSRegularExpression(
                pattern: #"(?:#[A-Za-z][\w-]{2,}|\.[A-Za-z][\w-]{2,})"#) else {
            return nil
        }
        let requestText = request as NSString
        let matches = pattern.matches(in: request,
            range: NSRange(location: 0, length: requestText.length))
        let explicit = matches.map { requestText.substring(with: $0.range) }
        let inferred = semanticTargets.prefix(3).map { "#" + $0 }
        let selectors = Array(Set(explicit + inferred)).sorted()
        guard !selectors.isEmpty, selectors.count <= 3 else { return nil }
        let text = html as NSString
        var windows: [NSRange] = []
        for token in selectors {
            let selector = token as NSString
            let scanRange = NSRange(location: 0, length: text.length)
            var cursor = scanRange.location
            var occurrences = 0
            let clean = token.hasPrefix("#") ? String(token.dropFirst()) : ""
            let anchors = clean.isEmpty ? [token] : [
                token, "id=\"" + clean + "\"", "id='" + clean + "'",
                "data-forge-id=\"" + clean + "\"", "data-forge-id='" + clean + "'",
                "data-screen=\"" + clean + "\"", "data-screen='" + clean + "'",
                "data-view=\"" + clean + "\"", "data-view='" + clean + "'",
                "data-page=\"" + clean + "\"", "data-page='" + clean + "'",
                "data-route=\"" + clean + "\"", "data-route='" + clean + "'"
            ]
            for anchor in anchors {
                cursor = 0
                while cursor < text.length {
                    let found = text.range(of: anchor, options: [],
                        range: NSRange(location: cursor, length: text.length - cursor))
                    guard found.location != NSNotFound else { break }
                    occurrences += 1
                    if occurrences > 6 { return nil } // Ambiguous target.
                    let start = max(0, found.location - 1100)
                    let end = min(text.length, found.location + found.length + 1500)
                    windows.append(NSRange(location: start, length: end - start))
                    cursor = found.location + max(1, found.length)
                }
            }
            if occurrences == 0 { return nil }
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { $0.location < $1.location }
        var merged: [NSRange] = []
        for window in windows {
            if let last = merged.last, NSMaxRange(last) >= window.location {
                merged[merged.count - 1] = NSRange(location: last.location,
                    length: max(NSMaxRange(last), NSMaxRange(window)) - last.location)
            } else { merged.append(window) }
        }
        let snippets = merged.map { text.substring(with: $0) }.joined(separator: "\n\n<!-- OMITTED UNRELATED SOURCE -->\n\n")
        guard snippets.utf8.count <= 11_000 else { return nil }
        return """
The following are verbatim excerpts of the current HTML app, with unrelated
regions omitted. Return only a minimal <htmlapp_patch>. SEARCH blocks must
match verbatim source; never assume omitted code is absent.

<htmlapp_source_excerpts>
\(snippets)
</htmlapp_source_excerpts>
"""
    }
}
