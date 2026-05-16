import Foundation

public enum SystemShortcutChecker {
    /// Returns true if at least one "Switch to Desktop N" symbolic hotkey is enabled.
    /// IDs 118..126 = Switch to Desktop 1..9.
    public static func switchToDesktopShortcutsEnabled() -> Bool {
        guard let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any] else {
            // No prefs at all — defaults apply, shortcuts are enabled.
            return true
        }
        for id in 118...126 {
            if let entry = raw[String(id)] as? [String: Any],
               let enabled = entry["enabled"] as? Bool,
               enabled {
                return true
            }
        }
        // None of the entries were present-and-enabled. If no entries exist at
        // all in this range, treat as default-enabled (absent entry == default).
        let anyEntry = (118...126).contains { raw[String($0)] != nil }
        return !anyEntry
    }
}
