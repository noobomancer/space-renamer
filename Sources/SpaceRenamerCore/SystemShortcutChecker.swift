import Foundation
import CoreGraphics

/// Reads `com.apple.symbolichotkeys` to tell whether the keyboard shortcuts a
/// given `SwitchMode` depends on are actually enabled & bound as the app
/// synthesizes them. Drives the mode-aware launch warning and the Ctrl+digit
/// menu greying. All decision logic is pure (`internal` for `@testable`).
public enum SystemShortcutChecker {

    // MARK: - Move a space (arrow mode)

    /// `AppleSymbolicHotKeys` IDs for "Move left/right a space".
    static let moveLeftSpaceID = 79
    static let moveRightSpaceID = 81

    /// Modifier mask "Move left/right a space" is registered with: Control + Fn
    /// (`0x040000 | 0x800000` = 8650752). Arrow keys are *secondary-function*
    /// keys, so macOS records the Fn bit too — distinct from "Switch to Desktop
    /// N"'s pure Control (262144). The arrow switcher synthesizes exactly this
    /// chord (`CGKeystrokeSynthesizer.postControlKey`; *Design Revision
    /// 2026-05-17c*).
    static let controlFnModifierMask = 8650752

    /// `true` iff **both** "Move left a space" (Ctrl+Fn+←) and "Move right a
    /// space" (Ctrl+Fn+→) are enabled and bound to exactly what the app
    /// synthesizes — the prerequisite for `SwitchMode.arrow` in either
    /// direction.
    public static func spaceMoveShortcutsEnabled() -> Bool {
        spaceMoveShortcutsEnabled(in: symbolicHotKeys())
    }

    static func spaceMoveShortcutsEnabled(in raw: [String: Any]?) -> Bool {
        guard let raw else { return false }
        let bound: (Int, CGKeyCode) -> Bool = { id, expectedKey in
            guard let params = parameters(raw, id: id) else { return false }
            return params[1] == Int(expectedKey) && params[2] == controlFnModifierMask
        }
        return bound(moveLeftSpaceID, CGKeystrokeSynthesizer.leftArrowKeyCode)
            && bound(moveRightSpaceID, CGKeystrokeSynthesizer.rightArrowKeyCode)
    }

    // MARK: - Switch to Desktop N (Ctrl+digit mode)

    /// `AppleSymbolicHotKeys` IDs 118…126 == "Switch to Desktop 1…9".
    static let switchToDesktopIDs = 118...126

    /// Control modifier mask "Switch to Desktop N" is registered with (digits
    /// are not function keys, so no Fn bit — contrast `controlFnModifierMask`).
    static let controlModifierMask = 262144

    /// `true` iff at least one "Switch to Desktop N" hotkey is enabled — the
    /// broad gate for the `SwitchMode.ctrlDigit` launch warning. (On modern
    /// macOS these are OFF by default and absent until enabled, so "absent"
    /// means "not enabled".)
    public static func switchToDesktopShortcutsEnabled() -> Bool {
        anyEnabled(in: symbolicHotKeys())
    }

    static func anyEnabled(in raw: [String: Any]?) -> Bool {
        guard let raw else { return false }
        for id in switchToDesktopIDs {
            if let entry = raw[String(id)] as? [String: Any],
               let enabled = entry["enabled"] as? Bool, enabled {
                return true
            }
        }
        return false
    }

    /// 1-based desktop ordinals whose "Switch to Desktop N" shortcut is enabled
    /// **and** bound to exactly Ctrl+<digit N> — the desktops the app's
    /// synthesized `Ctrl+digit` can actually reach. The menu greys the rest
    /// while in `SwitchMode.ctrlDigit`.
    public static func reachableSwitchToDesktopOrdinals() -> Set<Int> {
        reachableSwitchToDesktopOrdinals(in: symbolicHotKeys())
    }

    static func reachableSwitchToDesktopOrdinals(in raw: [String: Any]?) -> Set<Int> {
        guard raw != nil else { return [] }
        var result: Set<Int> = []
        for ordinal in 1...9 {
            guard let params = parameters(raw, id: 117 + ordinal) else { continue }
            let expectedKey = Int(CGKeystrokeSynthesizer.digitVirtualKeyCodes[ordinal - 1])
            if params[1] == expectedKey && params[2] == controlModifierMask {
                result.insert(ordinal)
            }
        }
        return result
    }

    // MARK: - Shared

    private static func symbolicHotKeys() -> [String: Any]? {
        CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any]
    }

    /// `value.parameters` for an enabled hotkey `id`, robustly extracted (it
    /// arrives as `[NSNumber]` from CFPreferences or `[Int]` from tests).
    /// `nil` unless the entry exists, is enabled, and has ≥3 parameters.
    private static func parameters(_ raw: [String: Any]?, id: Int) -> [Int]? {
        guard let raw,
              let entry = raw[String(id)] as? [String: Any],
              let enabled = entry["enabled"] as? Bool, enabled,
              let value = entry["value"] as? [String: Any] else { return nil }
        let params: [Int]? = (value["parameters"] as? [Any])?.compactMap { v in
            if let i = v as? Int { return i }
            if let n = v as? NSNumber { return n.intValue }
            return nil
        }
        guard let params, params.count >= 3 else { return nil }
        return params
    }
}
