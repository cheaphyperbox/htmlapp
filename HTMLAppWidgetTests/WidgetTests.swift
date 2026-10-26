import XCTest
import WidgetKit
import UIKit

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
    func testWidgetActionSerializationAndOldItemCompatibility() throws {
        let old = Data(#"{"id":"row","label":"Tasks","value":"3"}"#.utf8)
        let decoded = try JSONDecoder().decode(HTMLAppWidgetItem.self, from: old)
        XCTAssertNil(decoded.action)

        var published = definition("test-actions")
        published.openBehavior = "action"
        published.action = HTMLAppWidgetAction(id: "open-board", type: "route", route: "board")
        published.snapshot.items = [
            HTMLAppWidgetItem(id: "today", label: "Today", value: "2",
                action: HTMLAppWidgetAction(id: "show-today", type: "event",
                    payload: #"{"filter":"today"}"#))
        ]
        let data = try JSONEncoder().encode(published)
        let restored = try JSONDecoder().decode(HTMLAppWidgetDefinition.self, from: data)
        XCTAssertEqual(restored.action?.route, "board")
        XCTAssertEqual(restored.openBehavior, "action")
        XCTAssertEqual(restored.snapshot.items?.first?.action?.payload, #"{"filter":"today"}"#)
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

final class LocalProfileResponseTests: XCTestCase {
    func testOnlyExactGETRouteDeliversProfile() {
        let profile = Data("profile-body".utf8)
        let path = "/unguessable/HTMLApp.mobileconfig"
        let good = HTMLAppLocalProfileResponse.response(request: "GET \(path) HTTP/1.1\r\nHost: localhost\r\n\r\n", path: path, profile: profile)
        XCTAssertTrue(String(decoding: good, as: UTF8.self).contains("200 OK"))
        XCTAssertTrue(String(decoding: good, as: UTF8.self).contains("application/x-apple-aspen-config"))
        XCTAssertTrue(good.suffix(profile.count).elementsEqual(profile))
        for request in ["GET / HTTP/1.1", "POST \(path) HTTP/1.1", "GET \(path)?other HTTP/1.1", "invalid"] {
            let result = HTMLAppLocalProfileResponse.response(request: request, path: path, profile: profile)
            XCTAssertFalse(String(decoding: result, as: UTF8.self).contains("profile-body"))
            XCTAssertTrue(String(decoding: result, as: UTF8.self).contains("404 Not Found"))
        }
    }

    func testAIGeneratedFillCommandsRenderLocally() async throws {
        // Three real-world examples use FILL followed by colorless shapes;
        // before 1.6.8 the parser rejected every shape, causing the
        // unrelated generic fallback icon to appear after each retry.
        let scripts = [
            """
            SIZE 1024 1024
            BG #26213D
            FILL #E9E1F4
            RECT 215 158 570 646
            FILL #CDBBE5
            RECT 215 158 570 150
            FILL #5B4A7C
            CIRCLE 340 158 38
            FILL #83A89D
            TRIANGLE 510 578 424 527 458 622
            FILL #F4D78E
            CIRCLE 554 510 42
            """,
            """
            SIZE 1024 1024
            BG #30274A
            FILL #BDA5D3
            CIRCLE 250 502 176
            FILL #DCCBEA
            TRIANGLE 500 412 760 355 666 545
            FILL #E9DDF3
            CIRCLE 413 520 202
            FILL #83A89D
            LINE 731 720 731 558 20
            """,
            """
            SIZE 1024 1024
            BG #332746
            FILL #E9DDF3
            RECT 182 144 640 690
            FILL #CDB6DF
            RECT 182 144 640 146
            FILL #9B78B7
            CIRCLE 289 217 22
            FILL #A8C9BD
            LINE 512 706 512 496 30
            """
        ]
        for source in scripts {
            let png = await AIIconRenderer.render(script: source)
            XCTAssertNotNil(png, "FILL/inherited-color IconScript should render into a visible PNG")
            if let png { XCTAssertNotNil(UIImage(data: png)) }
        }
    }
}
