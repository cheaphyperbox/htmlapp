import XCTest
import WidgetKit

final class WidgetTests: XCTestCase {
    var directory: URL!
    var repository: HTMLAppWidgetRepository!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = HTMLAppWidgetRepository(directory: directory)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func definition(_ id: String, primary: Bool = true) -> HTMLAppWidgetDefinition {
        var d = HTMLAppWidgetDefinition.placeholder(id: id)
        d.appID = "test-app"; d.primary = primary
        d.snapshot.title = "Focus Streak"; d.snapshot.value = "7"; d.snapshot.subtitle = "Goal: 10 days"
        return d
    }
    func testIndependentReaderDecodesPublishedSnapshotAndTimeline() async throws {
        let published = try repository.save(definition("focus-streak"))
        let reader = HTMLAppWidgetRepository(directory: directory)
        let decoded = try HTMLAppWidgetResolver.resolve(values: reader.all(), selectedID: nil, family: "systemSmall")
        let timeline = await HTMLAppWidgetTimeline.make(definition: decoded)
        XCTAssertEqual(timeline.entries.first?.definition, published)
        XCTAssertEqual(timeline.entries.first?.definition.snapshot.value, "7")
        XCTAssertEqual(timeline.entries.first?.definition.snapshot.subtitle, "Goal: 10 days")
        XCTAssertNotEqual(timeline.entries.first?.definition.appID, "placeholder")
    }
    func testSelectionAndFamilyErrors() throws {
        var d = definition("focus-streak"); d.families = ["systemSmall"]
        XCTAssertThrowsError(try HTMLAppWidgetResolver.resolve(values: [d], selectedID: "deleted", family: "systemSmall"))
        XCTAssertThrowsError(try HTMLAppWidgetResolver.resolve(values: [d], selectedID: nil, family: "systemLarge"))
        XCTAssertEqual(try HTMLAppWidgetResolver.resolve(values: [d], selectedID: d.id, family: "systemSmall").id, d.id)
    }
    func testPrimaryNormalizedDuringRestoreAndRead() throws {
        try repository.mutate { $0 = [self.definition("a"), self.definition("b")] }
        XCTAssertEqual(try repository.all().filter(\.primary).count, 1)
    }
    func testCorruptionNeverFallsBackOrOverwrites() throws {
        let legacy = try JSONEncoder().encode([definition("old")])
        let repo = HTMLAppWidgetRepository(directory: directory, legacy: { legacy })
        try Data("corrupt".utf8).write(to: repo.file)
        XCTAssertThrowsError(try repo.all())
        XCTAssertThrowsError(try repo.save(definition("new")))
        XCTAssertEqual(try String(contentsOf: repo.file), "corrupt")
    }
    func testLegacyMigratesOnVerifiedWrite() throws {
        let legacy = try JSONEncoder().encode([definition("old")])
        let repo = HTMLAppWidgetRepository(directory: directory, legacy: { legacy })
        XCTAssertEqual(try repo.all().count, 1)
        _ = try repo.save(definition("new"))
        XCTAssertEqual(try HTMLAppWidgetRepository(directory: directory).all().count, 2)
    }
    func testStaleNetworkResponseCannotRevertPublicationOrPrimary() throws {
        let old = try repository.save(definition("focus-streak"))
        var changed = old; changed.snapshot.value = "8"
        _ = try repository.save(changed)
        _ = try repository.save(definition("daywell"))
        var stale = old; stale.snapshot.value = "2"
        try repository.refresh(stale, original: old)
        XCTAssertEqual(try repository.all().first { $0.id == old.id }?.snapshot.value, "8")
        XCTAssertEqual(try repository.all().first { $0.primary }?.widgetID, "daywell")
    }
    func testConcurrentWritersDoNotLoseDefinitions() throws {
        let errors = NSLock(); var failures = 0
        DispatchQueue.concurrentPerform(iterations: 12) { i in
            do { _ = try HTMLAppWidgetRepository(directory: directory).save(definition("widget-\(i)")) }
            catch { errors.lock(); failures += 1; errors.unlock() }
        }
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(try repository.all().count, 12)
        XCTAssertEqual(try repository.all().filter(\.primary).count, 1)
    }
    func testWriteFailureIsReported() throws {
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        XCTAssertThrowsError(try repository.save(definition("test")))
    }
    @available(iOS 17.0, *)
    func testEntityQueryPreservesMissingSelection() async throws {
        let result = try await HTMLAppWidgetEntityQuery().entities(for: ["deleted-widget"])
        XCTAssertEqual(result.first?.id, "deleted-widget")
        let suggested = try await HTMLAppWidgetEntityQuery().suggestedEntities()
        XCTAssertEqual(suggested.first?.id, HTMLAppWidgetResolver.primaryID)
    }
}
