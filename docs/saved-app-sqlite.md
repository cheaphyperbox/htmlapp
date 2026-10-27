# Saved-app SQLite document storage

Each saved app receives a separate SQLite file in the app's Application Support directory. The bridge provides:

- `HTMLAppNative.db.put(collection, id, document)`
- `HTMLAppNative.db.get(collection, id)`
- `HTMLAppNative.db.delete(collection, id)`
- `HTMLAppNative.db.query(collection, {limit, cursor})`
- `HTMLAppNative.db.count(collection)`
- `HTMLAppNative.db.export()` and `HTMLAppNative.db.import(payload)`

Collections and IDs must contain 1–80 ASCII letters, digits, underscores, or hyphens. Each JSON document is limited to 256 KiB; the database quota is 10 MiB. Queries return up to 100 records sorted by ID, with the last ID as a continuation cursor. Import merges records and overwrites matching IDs; it is not currently atomic. Backups have the format `htmlapp.sqlite-json.v1`.

**Limitations:** The new SQLite database is not yet wired into the existing portable app archive or iCloud backup pipeline. Export returns a JSON object to the saved HTML app; it does not silently upload or share data. Full-text search and Spotlight indexing are not yet implemented.

**Build/device testing:** Compile the iOS 16 target; test insert/update/get/delete, pagination, duplicate IDs, malformed names, quota boundaries, backup roundtrip, cross-app isolation, app relaunch persistence, and preview restrictions. This has not been compiled or device-tested.
