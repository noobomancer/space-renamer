import XCTest
@testable import SpaceRenamerCore

final class PlaceholderTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertNotNil(_Placeholder.self)
    }
}
