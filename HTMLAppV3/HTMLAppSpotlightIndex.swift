import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Opt-in indexing of explicitly supplied saved-app content.
@available(iOS 16.0, *)
enum HTMLAppSpotlightIndex {
    private static func identifier(appID: String, key: String) -> String {
        "htmlapp." + appID + "." + key
    }

    static func index(appID: String, key: String, title: String, summary: String) async throws {
        guard !appID.isEmpty, !key.isEmpty, key.count <= 80,
              title.count <= 200, summary.count <= 4000 else {
            throw NSError(domain: "HTMLAppSpotlight", code: 1)
        }
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = summary
        attributes.textContent = summary
        let item = CSSearchableItem(uniqueIdentifier: identifier(appID: appID, key: key),
                                    domainIdentifier: "htmlapp." + appID,
                                    attributeSet: attributes)
        try await CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func remove(appID: String, key: String) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier(appID: appID, key: key)])
    }

    static func removeAll(appID: String) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["htmlapp." + appID])
    }
}
