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
    private static let lock = NSRecursiveLock()
    private static func valid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 80 &&
        name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    static func exportJSON(appID: String) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        let db = try open(appID: appID)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT collection,id,body FROM documents ORDER BY collection,id", -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "HTMLAppDatabase", code: 10)
        }
        defer { sqlite3_finalize(statement) }
        var records: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let collection = sqlite3_column_text(statement, 0),
                  let id = sqlite3_column_text(statement, 1),
                  let body = sqlite3_column_text(statement, 2),
                  let bytes = String(cString: body).data(using: .utf8),
                  let document = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { continue }
            records.append(["collection": String(cString: collection), "id": String(cString: id), "document": document])
        }
        return ["format": "htmlapp.sqlite-json.v1", "records": records]
    }

    /// Includes SQLite records in an explicit per-app portable data snapshot.
    static func portableSnapshot(appID: String) -> [String: Any]? {
        try? exportJSON(appID: appID)
    }

    static func restorePortableSnapshot(appID: String, snapshot: [String: Any]) throws {
        _ = try importJSON(appID: appID, payload: snapshot)
    }

    static func importJSON(appID: String, payload: [String: Any]) throws -> Int {
        guard payload["format"] as? String == "htmlapp.sqlite-json.v1",
              let records = payload["records"] as? [[String: Any]],
              records.count <= 20000 else { throw NSError(domain: "HTMLAppDatabase", code: 11) }
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        guard encoded.count <= 10 * 1024 * 1024 else { throw NSError(domain: "HTMLAppDatabase", code: 12) }
        for record in records {
            guard let collection = record["collection"] as? String,
                  let id = record["id"] as? String,
                  valid(collection), valid(id),
                  let document = record["document"] as? [String: Any] else {
                throw NSError(domain: "HTMLAppDatabase", code: 13)
            }
            _ = try perform(appID: appID, method: "db.put", args: ["collection": collection, "id": id, "document": document])
        }
        return records.count
    }

    static func perform(appID: String, method: String, args: [String: Any]) throws -> Any {
        guard let collection = args["collection"] as? String, valid(collection) else {
            throw NSError(domain: "HTMLAppDatabase", code: 3)
        }
        lock.lock()
        defer { lock.unlock() }
        let db = try open(appID: appID)
        defer { sqlite3_close(db) }
        let id = args["id"] as? String ?? ""
        if method != "db.query" && method != "db.count" && !valid(id) {
            throw NSError(domain: "HTMLAppDatabase", code: 4)
        }
        let sql: String
        switch method {
        case "db.put": sql = "INSERT OR REPLACE INTO documents(collection,id,body) VALUES(?,?,?)"
        case "db.get": sql = "SELECT body FROM documents WHERE collection=? AND id=?"
        case "db.delete": sql = "DELETE FROM documents WHERE collection=? AND id=?"
        case "db.count": sql = "SELECT COUNT(*) FROM documents WHERE collection=?"
        default: sql = "SELECT id,body FROM documents WHERE collection=? AND id>? ORDER BY id LIMIT ?"
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw NSError(domain: "HTMLAppDatabase", code: 5) }
        defer { sqlite3_finalize(statement) }
        func bind(_ value: String, _ position: Int32) {
            let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, position, value, -1, destructor)
        }
        bind(collection, 1)
        if method == "db.query" {
            bind(args["cursor"] as? String ?? "", 2)
            sqlite3_bind_int(statement, 3, Int32(max(1, min(100, args["limit"] as? Int ?? 50))))
        } else if method != "db.count" {
            bind(id, 2)
        }
        if method == "db.put" {
            guard let document = args["document"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(document),
                  let bytes = try? JSONSerialization.data(withJSONObject: document),
                  bytes.count <= 256 * 1024,
                  let json = String(data: bytes, encoding: .utf8) else {
                throw NSError(domain: "HTMLAppDatabase", code: 6)
            }
            bind(json, 3)
        }
        if method == "db.query" {
            var rows: [[String: Any]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let key = sqlite3_column_text(statement, 0),
                      let body = sqlite3_column_text(statement, 1),
                      let bytes = String(cString: body).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: bytes) else { continue }
                rows.append(["id": String(cString: key), "document": object])
            }
            return ["items": rows, "cursor": rows.last?["id"] ?? NSNull()]
        }
        if method == "db.put" {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: databaseURL(appID: appID).path)[.size] as? NSNumber)?.intValue ?? 0
            let incoming = (args["document"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0).count } ?? 0
            guard fileSize + incoming <= 10 * 1024 * 1024 else {
                throw NSError(domain: "HTMLAppDatabase", code: 9)
            }
        }
        let result = sqlite3_step(statement)
        if method == "db.count" {
            guard result == SQLITE_ROW else { throw NSError(domain: "HTMLAppDatabase", code: 7) }
            return ["count": Int(sqlite3_column_int(statement, 0))]
        }
        if method == "db.get" {
            guard result == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0),
                  let data = String(cString: raw).data(using: .utf8) else { return NSNull() }
            return try JSONSerialization.jsonObject(with: data)
        }
        guard result == SQLITE_DONE else { throw NSError(domain: "HTMLAppDatabase", code: 8) }
        return ["ok": true]
    }

}
