import Foundation
import CoreGraphics

public enum SystemShortcutChecker {
    /// AppleSymbolicHotKeys IDs 118...126 == "Switch to Desktop 1...9".
    static let switchToDesktopIDs = 118...126

    /// Returns true only if at least one "Switch to Desktop N" symbolic hotkey
    /// is present **and** enabled.
    ///
    /// On modern macOS these shortcuts are OFF by default and are entirely
    /// absent from `com.apple.symbolichotkeys` until the user enables them in
    /// System Settings. "Absent" therefore means *not enabled* — the previous
    /// implementation treated absent as default-enabled, so the app never
    /// warned the (common) case where `Ctrl+digit` switching cannot work.
    public static func switchToDesktopShortcutsEnabled() -> Bool {
        let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        return anyEnabled(in: raw)
    }

    /// Pure decision logic over a raw `AppleSymbolicHotKeys` dictionary.
    /// Unit-tested; `internal` for `@testable` access.
    static func anyEnabled(in raw: [String: Any]?) -> Bool {
        guard let raw else { return false }
        for id in switchToDesktopIDs {
            if let entry = raw[String(id)] as? [String: Any],
               let enabled = entry["enabled"] as? Bool,
               enabled {
                return true
            }
        }
        return false
    }

    /// Control modifier mask in `com.apple.symbolichotkeys` `value.parameters`.
    private static let controlModifierMask = 262144

    /// 1-based desktop ordinals whose "Switch to Desktop N" shortcut is enabled
    /// **and** bound to exactly Ctrl+<digit N> — i.e. the desktops the app's
    /// synthesized Ctrl+digit can actually switch to. (Distinct from
    /// `switchToDesktopShortcutsEnabled()`, which is the broad "is any enabled"
    /// gate for the one-shot launch warning.)
    public static func reachableSwitchToDesktopOrdinals() -> Set<Int> {
        let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        return reachableSwitchToDesktopOrdinals(in: raw)
    }

    /// Pure decision logic; `internal` for `@testable` access.
    static func reachableSwitchToDesktopOrdinals(in raw: [String: Any]?) -> Set<Int> {
        guard let raw else { return [] }
        var result: Set<Int> = []
        for ordinal in 1...9 {
            let id = 117 + ordinal
            guard let entry = raw[String(id)] as? [String: Any],
                  let enabled = entry["enabled"] as? Bool, enabled,
                  let value = entry["value"] as? [String: Any] else { continue }
            // parameters arrive as [NSNumber] from CFPreferences or [Int] from
            // tests — extract robustly.
            let params: [Int]? = (value["parameters"] as? [Any])?.compactMap { v in
                if let i = v as? Int { return i }
                if let n = v as? NSNumber { return n.intValue }
                return nil
            }
            guard let params, params.count >= 3 else { continue }
            let expectedKey = Int(CGKeystrokeSynthesizer.digitVirtualKeyCodes[ordinal - 1])
            if params[1] == expectedKey && params[2] == controlModifierMask {
                result.insert(ordinal)
            }
        }
        return result
    }
}
