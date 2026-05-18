import Foundation
import CoreGraphics

public enum SystemShortcutChecker {
    /// `AppleSymbolicHotKeys` IDs for "Move left/right a space".
    static let moveLeftSpaceID = 79
    static let moveRightSpaceID = 81

    /// Modifier mask "Move left/right a space" is registered with: Control + Fn
    /// (`0x040000 | 0x800000` = 8650752). Arrow keys are *secondary-function*
    /// keys, so macOS records the Fn bit too — distinct from "Switch to Desktop
    /// N"'s pure Control (262144). The app's relative-arrow switcher synthesizes
    /// exactly this chord (see `CGKeystrokeSynthesizer.postControlKey` /
    /// *Design Revision 2026-05-17c*); a mismatch is why the warning must check
    /// *this* mask, not the old desktop one.
    static let controlFnModifierMask = 8650752

    /// `true` iff **both** "Move left a space" (Ctrl+Fn+←) and "Move right a
    /// space" (Ctrl+Fn+→) are enabled and bound to exactly what the app
    /// synthesizes — the prerequisite for relative-arrow desktop switching in
    /// either direction. Replaces the old "Switch to Desktop N" check, which
    /// the switcher no longer uses (Design Revision 2026-05-17c). Either one
    /// missing/misbound means the user can't switch in that direction, so the
    /// app should warn.
    public static func spaceMoveShortcutsEnabled() -> Bool {
        let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        return spaceMoveShortcutsEnabled(in: raw)
    }

    /// Pure decision logic over a raw `AppleSymbolicHotKeys` dictionary.
    /// Unit-tested; `internal` for `@testable` access.
    static func spaceMoveShortcutsEnabled(in raw: [String: Any]?) -> Bool {
        guard let raw else { return false }
        let bound: (Int, CGKeyCode) -> Bool = { id, expectedKey in
            guard let entry = raw[String(id)] as? [String: Any],
                  let enabled = entry["enabled"] as? Bool, enabled,
                  let value = entry["value"] as? [String: Any] else { return false }
            // parameters arrive as [NSNumber] from CFPreferences or [Int] from
            // tests — extract robustly.
            let params: [Int]? = (value["parameters"] as? [Any])?.compactMap { v in
                if let i = v as? Int { return i }
                if let n = v as? NSNumber { return n.intValue }
                return nil
            }
            guard let params, params.count >= 3 else { return false }
            return params[1] == Int(expectedKey) && params[2] == controlFnModifierMask
        }
        return bound(moveLeftSpaceID, CGKeystrokeSynthesizer.leftArrowKeyCode)
            && bound(moveRightSpaceID, CGKeystrokeSynthesizer.rightArrowKeyCode)
    }
}
