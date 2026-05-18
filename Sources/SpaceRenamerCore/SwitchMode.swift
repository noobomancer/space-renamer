import Foundation

/// User-selectable desktop-switch delivery mechanism (chosen in Preferences;
/// see *Design Revision 2026-05-18*). Persisted via its `rawValue`.
public enum SwitchMode: String, CaseIterable, Sendable {
    /// Relative `Ctrl+Fn+arrow` ("Move left/right a space") — switches to **any**
    /// desktop (no 9-cap), multi-hop animated. The default.
    case arrow
    /// `Ctrl+1…9` ("Switch to Desktop N") — a single instant keystroke, but
    /// only reaches desktops 1–9 and needs those shortcuts enabled.
    case ctrlDigit

    public static let `default`: SwitchMode = .arrow
}
