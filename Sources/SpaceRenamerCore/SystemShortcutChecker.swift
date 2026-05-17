import Foundation

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
}
