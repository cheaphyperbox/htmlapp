import Foundation

/// Conservative source-level protection of existing user-data identities.
/// This does not inspect or copy user records. It detects accidental source
/// deletion/renaming, not all possible runtime data loss.
enum ForgeEditSafetyGate {
    struct Violation: CustomStringConvertible {
        let kind: String
        let names: [String]
        var description: String { "Removed \(kind) without a visible migration: \(names.joined(separator: ", "))" }
    }

    static func violations(before original: String, after revised: String,
                           request: String) -> [Violation] {
        let old = ForgeSemanticAppModel.build(html: original, purpose: "")
        let new = ForgeSemanticAppModel.build(html: revised, purpose: "")
        let text = revised.lowercased()
        // A visible, explicit migration must preserve old records. The
        // verifier cannot guarantee arbitrary migration logic is correct.
        let migrationPresent =
            text.contains("htmlappdata.migrate(") ||
            text.range(of: #"migratev[0-9]+"#, options: .regularExpression) != nil
        if migrationPresent { return [] }

        var issues: [Violation] = []
        let oldKeys = Set(old.storageKeys)
        let newKeys = Set(new.storageKeys)
        let oldCollections = Set(old.databaseCollections)
        let newCollections = Set(new.databaseCollections)

        // Explicit destructive requests still require migration when user
        // data could remain. Removing a screen is not permission to erase its
        // accumulated data.
        let missingKeys = oldKeys.subtracting(newKeys).sorted()
        let missingCollections = oldCollections.subtracting(newCollections).sorted()
        if !missingKeys.isEmpty {
            issues.append(Violation(kind: "persistent storage keys", names: missingKeys))
        }
        if !missingCollections.isEmpty {
            issues.append(Violation(kind: "native database collections", names: missingCollections))
        }
        return issues
    }
}
