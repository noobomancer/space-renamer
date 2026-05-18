import XCTest
@testable import SpaceRenamerCore

/// Tests the pure decision logic for the launch-time warning. Switching uses
/// relative `Ctrl+Fn+arrow` ("Move left/right a space", `symbolichotkeys` IDs
/// 79/81, modifier mask 8650752), NOT "Switch to Desktop N" — see Design
/// Revision 2026-05-17c. The warning must require BOTH directions bound.
final class SystemShortcutCheckerTests: XCTestCase {

    private let left = Int(CGKeystrokeSynthesizer.leftArrowKeyCode)    // 123, id 79
    private let right = Int(CGKeystrokeSynthesizer.rightArrowKeyCode)  // 124, id 81
    private let ctrlFn = SystemShortcutChecker.controlFnModifierMask   // 8650752
    private let ctrlOnly = 262144                                     // the real-world bug

    private func entry(enabled: Bool, key: Int, mod: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, key, mod]]]
    }

    private func both(left l: [String: Any], right r: [String: Any]) -> [String: Any] {
        ["79": l, "81": r]
    }

    func test_nilPrefs_returnsFalse() {
        XCTAssertFalse(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: nil))
    }

    func test_bothEnabledAndCorrectlyBound_returnsTrue() {
        let raw = both(left: entry(enabled: true, key: left, mod: ctrlFn),
                       right: entry(enabled: true, key: right, mod: ctrlFn))
        XCTAssertTrue(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: raw))
    }

    func test_onlyOneDirectionPresent_returnsFalse() {
        // Only "Move right a space" present — can't navigate backward.
        let raw: [String: Any] = ["81": entry(enabled: true, key: right, mod: ctrlFn)]
        XCTAssertFalse(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: raw))
    }

    func test_oneDirectionDisabled_returnsFalse() {
        let raw = both(left: entry(enabled: true,  key: left,  mod: ctrlFn),
                       right: entry(enabled: false, key: right, mod: ctrlFn))
        XCTAssertFalse(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: raw))
    }

    func test_pureControlModifier_returnsFalse() {
        // The exact post-pivot pitfall: arrows need Control+Fn (8650752);
        // a pure-Control (262144) binding must NOT count as enabled.
        let raw = both(left: entry(enabled: true, key: left,  mod: ctrlOnly),
                       right: entry(enabled: true, key: right, mod: ctrlOnly))
        XCTAssertFalse(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: raw))
    }

    func test_wrongKeyCode_returnsFalse() {
        let raw = both(left: entry(enabled: true, key: left, mod: ctrlFn),
                       right: entry(enabled: true, key: 99,   mod: ctrlFn))
        XCTAssertFalse(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: raw))
    }

    func test_absentEntries_returnFalse() {
        // Only unrelated hotkeys present.
        let raw: [String: Any] = ["118": ["enabled": true], "120": ["enabled": true]]
        XCTAssertFalse(SystemShortcutChecker.spaceMoveShortcutsEnabled(in: raw))
    }

    // MARK: - Switch to Desktop N (Ctrl+digit mode)

    func test_anyEnabled_nil_false() {
        XCTAssertFalse(SystemShortcutChecker.anyEnabled(in: nil))
    }

    func test_anyEnabled_noDesktopEntries_false() {
        // Only unrelated ids (e.g. move-space 79/81) — none of 118…126.
        XCTAssertFalse(SystemShortcutChecker.anyEnabled(in: ["79": ["enabled": true],
                                                             "81": ["enabled": true]]))
    }

    func test_anyEnabled_oneDesktopEnabled_true() {
        XCTAssertTrue(SystemShortcutChecker.anyEnabled(in: ["120": ["enabled": true]]))
    }

    func test_anyEnabled_presentButDisabled_false() {
        XCTAssertFalse(SystemShortcutChecker.anyEnabled(in: ["118": ["enabled": false]]))
    }

    private func desktopEntry(enabled: Bool, key: Int, mod: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [65535, key, mod]]]
    }

    func test_reachable_nil_isEmpty() {
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: nil), [])
    }

    func test_reachable_ctrlDigitEnabled_includesThoseOrdinals() {
        // ids 118..121 = Desktops 1..4; keyCodes 18,19,20,21; Control = 262144.
        let raw: [String: Any] = [
            "118": desktopEntry(enabled: true, key: 18, mod: 262144),
            "119": desktopEntry(enabled: true, key: 19, mod: 262144),
            "120": desktopEntry(enabled: true, key: 20, mod: 262144),
            "121": desktopEntry(enabled: true, key: 21, mod: 262144),
        ]
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: raw), [1, 2, 3, 4])
    }

    func test_reachable_wrongModifierOrKeyOrDisabled_excluded() {
        let raw: [String: Any] = [
            "118": desktopEntry(enabled: false, key: 18, mod: 262144),          // disabled
            "119": desktopEntry(enabled: true,  key: 19, mod: 262144 + 131072), // Ctrl+Shift
            "120": desktopEntry(enabled: true,  key: 99, mod: 262144),          // wrong key
            "121": desktopEntry(enabled: true,  key: 21, mod: 262144),          // OK → 4
        ]
        XCTAssertEqual(SystemShortcutChecker.reachableSwitchToDesktopOrdinals(in: raw), [4])
    }
}
