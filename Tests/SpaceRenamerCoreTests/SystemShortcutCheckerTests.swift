import XCTest
@testable import SpaceRenamerCore

/// Tests the pure decision logic. On modern macOS the "Switch to Desktop N"
/// symbolic hotkeys (IDs 118...126) are OFF by default and absent from the
/// prefs until the user enables them, so "absent" MUST mean "not enabled"
/// (otherwise the app never warns the common case where switching can't work).
final class SystemShortcutCheckerTests: XCTestCase {

    func test_nilPrefs_returnsFalse() {
        // Was the bug: previously returned true ("defaults apply, enabled").
        XCTAssertFalse(SystemShortcutChecker.anyEnabled(in: nil))
    }

    func test_noSwitchToDesktopEntries_returnsFalse() {
        // Exactly the failing machine: only unrelated hotkeys (e.g. id 79
        // "move space") present; none of 118...126. Must be false.
        let raw: [String: Any] = [
            "79": ["enabled": true],
            "80": ["enabled": true],
            "81": ["enabled": true],
        ]
        XCTAssertFalse(SystemShortcutChecker.anyEnabled(in: raw))
    }

    func test_entryPresentButDisabled_returnsFalse() {
        let raw: [String: Any] = ["118": ["enabled": false]]
        XCTAssertFalse(SystemShortcutChecker.anyEnabled(in: raw))
    }

    func test_entryPresentAndEnabled_returnsTrue() {
        let raw: [String: Any] = ["120": ["enabled": true]]
        XCTAssertTrue(SystemShortcutChecker.anyEnabled(in: raw))
    }

    func test_someEnabledAmongDisabled_returnsTrue() {
        let raw: [String: Any] = [
            "118": ["enabled": false],
            "119": ["enabled": false],
            "126": ["enabled": true],
        ]
        XCTAssertTrue(SystemShortcutChecker.anyEnabled(in: raw))
    }
}
