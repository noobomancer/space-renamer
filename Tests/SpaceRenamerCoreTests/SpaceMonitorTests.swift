import XCTest
@testable import SpaceRenamerCore

@MainActor
final class SpaceMonitorTests: XCTestCase {

    private final class FakeActiveSpaceReader: ActiveSpaceReading {
        var id: String?
        init(id: String?) { self.id = id }
        func currentActiveSpaceID() -> String? { id }
    }

    private func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"))
    }

    func test_validPlist_loadsSpacesAndNilError() throws {
        let monitor = SpaceMonitor(plistURL: try fixtureURL("spaces-3"),
                                   activeSpaceReader: FakeActiveSpaceReader(id: "2"))
        XCTAssertEqual(monitor.spaces.map { $0.id }, ["1", "2", "3"])
        XCTAssertEqual(monitor.activeID, "2")
        XCTAssertNil(monitor.lastLoadError)
    }

    func test_activeID_comesFromReader_notPlistCurrentSpace() throws {
        // spaces-3's plist Current Space is ManagedSpaceID 2; the reader says 999.
        // activeID MUST follow the reader (the plist Current Space is ignored).
        let monitor = SpaceMonitor(plistURL: try fixtureURL("spaces-3"),
                                   activeSpaceReader: FakeActiveSpaceReader(id: "999"))
        XCTAssertEqual(monitor.activeID, "999")
        XCTAssertEqual(monitor.spaces.map { $0.id }, ["1", "2", "3"])
    }

    func test_missingFile_setsLastError_andEmptyState_butActiveIDFromReader() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMonitorTests-missing-\(UUID().uuidString).plist")
        let monitor = SpaceMonitor(plistURL: missing,
                                   activeSpaceReader: FakeActiveSpaceReader(id: "7"))
        XCTAssertTrue(monitor.spaces.isEmpty)
        XCTAssertNotNil(monitor.lastLoadError)
        XCTAssertEqual(monitor.activeID, "7")   // active-Space is decoupled from the plist read
    }

    func test_malformedPlist_setsLastError() throws {
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMonitorTests-bad-\(UUID().uuidString).plist")
        try Data("this is not a plist".utf8).write(to: badURL)
        defer { try? FileManager.default.removeItem(at: badURL) }
        let monitor = SpaceMonitor(plistURL: badURL,
                                   activeSpaceReader: FakeActiveSpaceReader(id: nil))
        XCTAssertTrue(monitor.spaces.isEmpty)
        XCTAssertNotNil(monitor.lastLoadError)
        XCTAssertNil(monitor.activeID)
    }

    func test_recoveryReload_clearsErrorAndPublishesSpaces() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMonitorTests-recovery-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let monitor = SpaceMonitor(plistURL: url,
                                   activeSpaceReader: FakeActiveSpaceReader(id: "5"))
        XCTAssertNotNil(monitor.lastLoadError)
        XCTAssertTrue(monitor.spaces.isEmpty)
        let goodData = try Data(contentsOf: try fixtureURL("spaces-3"))
        try goodData.write(to: url)
        monitor.reload()
        XCTAssertNil(monitor.lastLoadError)
        XCTAssertEqual(monitor.spaces.map { $0.id }, ["1", "2", "3"])
        XCTAssertEqual(monitor.activeID, "5")
    }
}
