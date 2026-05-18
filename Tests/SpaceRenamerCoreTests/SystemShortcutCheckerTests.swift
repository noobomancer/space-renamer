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

    // MARK: - reachableSwitchToDesktopOrdinals

    private func entry(enabled: Bool, key: Int, mod: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, key, mod]]]
    }

    func test_reachable_nil_isEmpty() {
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: nil), [])
    }

    func test_reachable_ctrlDigitEnabled_includesThoseOrdinals() {
        // ids 118..121 = Desktops 1..4, Ctrl(=262144)+keyCodes 18,19,20,21
        let raw: [String: Any] = [
            "118": entry(enabled: true, key: 18, mod: 262144),
            "119": entry(enabled: true, key: 19, mod: 262144),
            "120": entry(enabled: true, key: 20, mod: 262144),
            "121": entry(enabled: true, key: 21, mod: 262144),
        ]
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: raw), [1, 2, 3, 4])
    }

    func test_reachable_disabledEntry_excluded() {
        let raw: [String: Any] = ["120": entry(enabled: false, key: 20, mod: 262144)]
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: raw), [])
    }

    func test_reachable_wrongModifier_excluded() {
        // enabled + correct key but modifier is not Control-only (e.g. Ctrl+Shift)
        let raw: [String: Any] = ["120": entry(enabled: true, key: 20, mod: 262144 + 131072)]
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: raw), [])
    }

    func test_reachable_wrongKeyCode_excluded() {
        // enabled + Control but bound to a non-digit key
        let raw: [String: Any] = ["122": entry(enabled: true, key: 99, mod: 262144)]
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: raw), [])
    }
}
