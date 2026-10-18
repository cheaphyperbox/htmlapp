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

final class SigningGroupTests: XCTestCase {
    func testNoSilentProviderSelectionAndDeterministicChoice() {
        typealias S = HTMLAppProviderStorage.Selection
        XCTAssertNil(HTMLAppProviderStorage.selected(from: [], allowed: ["group.provider"]))
        let a = S(version: 1, group: "group.a", date: Date(timeIntervalSince1970: 1))
        let b = S(version: 1, group: "group.b", date: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(HTMLAppProviderStorage.selected(from: [b, a], allowed: [a.group, b.group]), b.group)
        XCTAssertEqual(HTMLAppProviderStorage.selected(from: [b, a], allowed: [a.group]), a.group)
        XCTAssertNil(HTMLAppProviderStorage.selected(from: [S(version: 2, group: a.group, date: a.date)], allowed: [a.group]))
    }
    func testSignedGroupsParserAndMalformedBounds() throws {
        let xml = try PropertyListSerialization.data(fromPropertyList: ["com.apple.security.application-groups": ["group.test", "group.test"]], format: .xml, options: 0)
        func word(_ value: Int, big: Bool = false) -> Data {
            let bytes = (0..<4).map { UInt8((value >> ($0 * 8)) & 255) }
            return Data(big ? Array(bytes.reversed()) : bytes)
        }
        var binary = word(0xfeedfacf) + Data(repeating: 0, count: 12)
        binary += word(1) + word(16) + Data(repeating: 0, count: 8)
        binary += word(0x1d) + word(16) + word(48) + word(28 + xml.count)
        binary += word(0xfade0cc0, big: true) + word(28 + xml.count, big: true) + word(1, big: true)
        binary += word(5, big: true) + word(20, big: true)
        binary += word(0xfade7171, big: true) + word(8 + xml.count, big: true) + xml
        XCTAssertEqual(HTMLAppSigningGroups.groups(in: binary), ["group.test"])
        for length in 0..<binary.count {
            XCTAssertEqual(HTMLAppSigningGroups.groups(in: Data(binary.prefix(length))), [])
        }
        binary.replaceSubrange(44..<48, with: word(Int(UInt32.max)))
        XCTAssertEqual(HTMLAppSigningGroups.groups(in: binary), [])
    }
}
