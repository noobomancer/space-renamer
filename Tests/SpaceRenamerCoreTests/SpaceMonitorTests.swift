import XCTest
@testable import SpaceRenamerCore

@MainActor
final class SpaceMonitorTests: XCTestCase {

    private func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"))
    }

    func test_validPlist_loadsSpacesAndNilError() throws {
        let monitor = SpaceMonitor(plistURL: try fixtureURL("spaces-3"))
        XCTAssertEqual(monitor.spaces.map { $0.id }, ["1", "2", "3"])
        XCTAssertEqual(monitor.activeID, "2")
        XCTAssertNil(monitor.lastLoadError)
    }

    func test_missingFile_setsLastError_andEmptyState() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMonitorTests-missing-\(UUID().uuidString).plist")
        let monitor = SpaceMonitor(plistURL: missing)
        XCTAssertTrue(monitor.spaces.isEmpty)
        XCTAssertNil(monitor.activeID)
        XCTAssertNotNil(monitor.lastLoadError)
    }

    func test_malformedPlist_setsLastError() throws {
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMonitorTests-bad-\(UUID().uuidString).plist")
        try Data("this is not a plist".utf8).write(to: badURL)
        defer { try? FileManager.default.removeItem(at: badURL) }
        let monitor = SpaceMonitor(plistURL: badURL)
        XCTAssertTrue(monitor.spaces.isEmpty)
        XCTAssertNotNil(monitor.lastLoadError)
    }

    func test_recoveryReload_clearsErrorAndPublishesSpaces() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceMonitorTests-recovery-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }

        // No file at `url` yet → monitor starts degraded.
        let monitor = SpaceMonitor(plistURL: url)
        XCTAssertNotNil(monitor.lastLoadError)
        XCTAssertTrue(monitor.spaces.isEmpty)

        // Write a valid plist to the same path and reload → recovers.
        let goodData = try Data(contentsOf: try fixtureURL("spaces-3"))
        try goodData.write(to: url)
        monitor.reload()

        XCTAssertNil(monitor.lastLoadError)
        XCTAssertEqual(monitor.spaces.map { $0.id }, ["1", "2", "3"])
        XCTAssertEqual(monitor.activeID, "2")
    }
}
