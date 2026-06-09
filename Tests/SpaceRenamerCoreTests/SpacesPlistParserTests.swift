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
        XCTAssertEqual(result.spaces.map { $0.id }, ["1","2","3","4","5","6","7","8","9"])
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

    func test_realCapture_uuidsParsed() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-real"))
        XCTAssertEqual(result.spaces.map { $0.uuid },
                       ["",
                        "9DD24797-CA38-435A-8F4C-1EE03CB1B7CA",
                        "8B3CC061-9B05-4356-A685-81E538C8DBAD",
                        "B39FF9FA-F09B-40AA-9C64-C3C3E8EF661B"])
    }

    func test_storageID_isUUID_orPrimarySentinelWhenUUIDEmpty() throws {
        // The default desktop's uuid is empty in the real plist; its storage
        // identity is the "primary" sentinel. All others use their uuid.
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-real"))
        XCTAssertEqual(result.spaces.map { $0.storageID },
                       ["primary",
                        "9DD24797-CA38-435A-8F4C-1EE03CB1B7CA",
                        "8B3CC061-9B05-4356-A685-81E538C8DBAD",
                        "B39FF9FA-F09B-40AA-9C64-C3C3E8EF661B"])
    }

    func test_spaceEntryWithoutUuidKey_parsesWithEmptyUuid() throws {
        let plist: [String: Any] = [
            "SpacesDisplayConfiguration": [
                "Management Data": [
                    "Monitors": [
                        ["Spaces": [["ManagedSpaceID": 7]]]
                    ]
                ]
            ]
        ]
        let result = try SpacesPlistParser.parse(plist)
        XCTAssertEqual(result.spaces.map { $0.uuid }, [""])
        XCTAssertEqual(result.spaces.map { $0.storageID }, ["primary"])
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

    func test_spaceEntryWithNonPositiveManagedSpaceID_throws() {
        let bad: [String: Any] = [
            "SpacesDisplayConfiguration": [
                "Management Data": [
                    "Monitors": [
                        ["Spaces": [["ManagedSpaceID": 0]]]
                    ]
                ]
            ]
        ]
        XCTAssertThrowsError(try SpacesPlistParser.parse(bad)) { err in
            XCTAssertEqual(err as? SpacesPlistError, .malformedSpaceEntry)
        }
    }

    func test_tenSpaces_parsedWithTenOrdinals() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-10"))
        XCTAssertEqual(result.spaces.map { $0.id }, ["1","2","3","4","5","6","7","8","9","10"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, Array(1...10))
        XCTAssertEqual(result.activeID, "1")
        // (>9 desktops are fully switchable since Design Revision 2026-05-17c;
        // no shortcut-availability cap remains on ParsedSpace.)
    }
}
