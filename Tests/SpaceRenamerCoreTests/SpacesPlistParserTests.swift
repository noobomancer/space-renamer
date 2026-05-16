import XCTest
@testable import SpaceRenamerCore

final class SpacesPlistParserTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }

    func test_singleSpace_isParsed() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-1"))
        XCTAssertEqual(result.spaces.map { $0.id }, ["1"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1])
        XCTAssertEqual(result.activeID, "1")
    }

    func test_threeSpaces_activeIsMiddle() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-3"))
        XCTAssertEqual(result.spaces.map { $0.id }, ["1", "2", "3"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeID, "2")
    }

    func test_nineSpaces_fifthActive() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-9"))
        XCTAssertEqual(result.spaces.count, 9)
        XCTAssertEqual(result.activeID, "5")
    }

    func test_reorderedSpaces_ordinalsReflectNewOrder() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-reordered"))
        XCTAssertEqual(result.spaces.map { $0.id }, ["3", "1", "2"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeID, "1")
    }

    func test_realCapture_defaultDesktopHasStableIDAndIsActive() throws {
        // The default desktop has an empty uuid in the real plist; ManagedSpaceID
        // gives it a stable identity ("1") and makes it detectable as active.
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-real"))
        XCTAssertEqual(result.spaces.map { $0.id }, ["1", "3", "4", "5"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3, 4])
        XCTAssertEqual(result.activeID, "1")
    }

    func test_emptyPlist_throws() {
        XCTAssertThrowsError(try SpacesPlistParser.parse([:])) { err in
            XCTAssertEqual(err as? SpacesPlistError, .missingConfiguration)
        }
    }

    func test_missingMonitors_throws() {
        let bad: [String: Any] = ["SpacesDisplayConfiguration": ["Management Data": [String: Any]()]]
        XCTAssertThrowsError(try SpacesPlistParser.parse(bad)) { err in
            XCTAssertEqual(err as? SpacesPlistError, .noMonitors)
        }
    }

    func test_spaceEntryMissingManagedSpaceID_throws() {
        let bad: [String: Any] = [
            "SpacesDisplayConfiguration": [
                "Management Data": [
                    "Monitors": [
                        ["Spaces": [["uuid": "x"]]]
                    ]
                ]
            ]
        ]
        XCTAssertThrowsError(try SpacesPlistParser.parse(bad)) { err in
            XCTAssertEqual(err as? SpacesPlistError, .malformedSpaceEntry)
        }
    }
}
