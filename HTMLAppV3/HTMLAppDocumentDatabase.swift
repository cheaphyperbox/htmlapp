import Foundation
import SQLite3

enum HTMLAppDocumentDatabase {
    static func databaseURL(appID: String) -> URL {
        HTMLAppPortableDataStore.fileURL(appID: appID)
            .deletingPathExtension().appendingPathExtension("sqlite")
    }

    static func open(appID: String) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_open(databaseURL(appID: appID).path, &pointer) == SQLITE_OK,
              let pointer else {
            if pointer != nil { sqlite3_close(pointer) }
            throw NSError(domain: "HTMLAppDatabase", code: 1)
        }
        guard sqlite3_exec(pointer, "CREATE TABLE IF NOT EXISTS documents (collection TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(collection,id))", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(pointer)
            throw NSError(domain: "HTMLAppDatabase", code: 2)
        }
        return pointer
    }
}
