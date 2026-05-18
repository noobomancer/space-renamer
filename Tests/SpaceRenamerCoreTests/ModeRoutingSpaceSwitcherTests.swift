import XCTest
@testable import SpaceRenamerCore

/// The router reads `SwitchMode` **per call** and delegates to the matching
/// underlying switcher (so flipping the Preferences setting takes effect on
/// the next switch, no relaunch).
final class ModeRoutingSpaceSwitcherTests: XCTestCase {

    private final class SpySwitcher: SpaceSwitching {
        let tag: String
        var requested: [String] = []
        var result = true
        init(_ tag: String) { self.tag = tag }
        func setCurrentSpace(managedSpaceID: String) -> Bool {
            requested.append(managedSpaceID); return result
        }
    }

    func test_arrowMode_routesToArrowSwitcher() {
        let arrow = SpySwitcher("arrow"), digit = SpySwitcher("digit")
        let r = ModeRoutingSpaceSwitcher(arrow: arrow, ctrlDigit: digit, mode: { .arrow })
        XCTAssertTrue(r.setCurrentSpace(managedSpaceID: "7"))
        XCTAssertEqual(arrow.requested, ["7"])
        XCTAssertTrue(digit.requested.isEmpty)
    }

    func test_ctrlDigitMode_routesToDigitSwitcher() {
        let arrow = SpySwitcher("arrow"), digit = SpySwitcher("digit")
        let r = ModeRoutingSpaceSwitcher(arrow: arrow, ctrlDigit: digit, mode: { .ctrlDigit })
        XCTAssertTrue(r.setCurrentSpace(managedSpaceID: "7"))
        XCTAssertEqual(digit.requested, ["7"])
        XCTAssertTrue(arrow.requested.isEmpty)
    }

    func test_modeIsReadPerCall_notCachedAtInit() {
        let arrow = SpySwitcher("arrow"), digit = SpySwitcher("digit")
        var mode: SwitchMode = .arrow
        let r = ModeRoutingSpaceSwitcher(arrow: arrow, ctrlDigit: digit, mode: { mode })
        _ = r.setCurrentSpace(managedSpaceID: "1")   // arrow
        mode = .ctrlDigit
        _ = r.setCurrentSpace(managedSpaceID: "2")   // digit, no relaunch
        XCTAssertEqual(arrow.requested, ["1"])
        XCTAssertEqual(digit.requested, ["2"])
    }

    func test_propagatesUnderlyingResult() {
        let arrow = SpySwitcher("arrow"); arrow.result = false
        let r = ModeRoutingSpaceSwitcher(arrow: arrow, ctrlDigit: SpySwitcher("digit"), mode: { .arrow })
        XCTAssertFalse(r.setCurrentSpace(managedSpaceID: "9"))
    }
}
