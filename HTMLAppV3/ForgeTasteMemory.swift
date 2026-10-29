import Foundation

/// Optional, device-local summaries of aesthetic preferences. No raw prompts,
/// personal data, app names, saved HTML or model transcripts are retained.
enum ForgeTasteMemory {
    private static let enabledKey = "htmlapp.forgeTaste.enabled"
    private static let notesKey = "htmlapp.forgeTaste.notes"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var summary: String {
        guard enabled else { return "" }
        return String((UserDefaults.standard.string(forKey: notesKey) ?? "").prefix(900))
    }

    static func recordStyle(_ tokens: [String]) {
        guard enabled else { return }
        let safe = tokens.prefix(6).compactMap { declaration -> String? in
            let text = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 90,
                  text.hasPrefix("--"),
                  text.range(of: #"^[a-zA-Z0-9#(),.%:;\s-]+$"#, options: .regularExpression) != nil
            else { return nil }
            return text
        }
        append("Preferred visual tokens: " + safe.joined(separator: "; "))
    }

    static func recordEditPreference(_ change: String) {
        guard enabled else { return }
        let lower = change.lowercased()
        let supported: [(String, String)] = [
            ("dark mode", "Prefers dark mode"),
            ("light mode", "Prefers light mode"),
            ("larger buttons", "Prefers larger touch targets"),
            ("bigger buttons", "Prefers larger touch targets"),
            ("rounded corners", "Prefers rounded corners"),
            ("less animation", "Prefers reduced motion"),
            ("more contrast", "Prefers stronger contrast"),
            ("simpler", "Prefers simpler interfaces"),
            ("more colorful", "Prefers vivid colors"),
            ("minimalist", "Prefers minimal layouts")
        ]
        for (needle, note) in supported where lower.contains(needle) { append(note) }
    }

    private static func append(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var notes = (UserDefaults.standard.string(forKey: notesKey) ?? "")
            .components(separatedBy: "\n").filter { !$0.isEmpty }
        notes.removeAll { $0 == text }
        notes.append(text)
        while notes.joined(separator: "\n").count > 900 && notes.count > 1 {
            notes.removeFirst()
        }
        UserDefaults.standard.set(notes.joined(separator: "\n"), forKey: notesKey)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: notesKey) }
}
