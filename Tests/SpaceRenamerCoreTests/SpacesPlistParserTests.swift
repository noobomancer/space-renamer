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
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-1"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1])
        XCTAssertEqual(result.activeUUID, "uuid-1")
    }

    func test_threeSpaces_activeIsMiddle() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-3"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-1", "uuid-2", "uuid-3"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeUUID, "uuid-2")
    }

    func test_nineSpaces_fifthActive() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-9"))
        XCTAssertEqual(result.spaces.count, 9)
        XCTAssertEqual(result.activeUUID, "uuid-5")
    }

    func test_reorderedSpaces_ordinalsReflectNewOrder() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-reordered"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-3", "uuid-1", "uuid-2"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeUUID, "uuid-1")
    }

    func test_emptyPlist_throws() {
        XCTAssertThrowsError(try SpacesPlistParser.parse([:]))
    }

    func test_missingMonitors_throws() {
        let bad: [String: Any] = ["SpacesDisplayConfiguration": ["Management Data": [String: Any]()]]
        XCTAssertThrowsError(try SpacesPlistParser.parse(bad))
    }
}
