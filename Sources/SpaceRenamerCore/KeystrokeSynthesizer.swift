import Foundation
import CoreGraphics

public protocol KeystrokeSynthesizing {
    /// Posts a Ctrl + <digit> keystroke (1...9). Throws if out of range.
    func postControlDigit(_ digit: Int) throws
    /// Posts a single Ctrl + <virtual key> keystroke. Used for relative Space
    /// navigation (Ctrl+← / Ctrl+→ — "Move left/right a space").
    func postControlKey(_ keyCode: CGKeyCode) throws
}

public enum KeystrokeError: Error {
    case digitOutOfRange
    case eventSourceUnavailable
}

public struct CGKeystrokeSynthesizer: KeystrokeSynthesizing {
    /// US-layout virtual key codes for digits 1...9. Single source of truth for
    /// the Ctrl+digit the app synthesizes; `SystemShortcutChecker` matches the
    /// macOS "Switch to Desktop N" binding against this to know which desktops
    /// are actually reachable.
    public static let digitVirtualKeyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// Arrow virtual key codes (US layout). Ctrl+← / Ctrl+→ trigger the macOS
    /// "Move left/right a space" symbolic hotkeys — the relative-navigation
    /// mechanism that performs a real, animated, uncapped Space switch
    /// (Design Revision 2026-05-17c, pivoted from the SkyLight write SPI).
    public static let leftArrowKeyCode: CGKeyCode = 123
    public static let rightArrowKeyCode: CGKeyCode = 124

    public init() {}

    public func postControlDigit(_ digit: Int) throws {
        guard (1...9).contains(digit) else { throw KeystrokeError.digitOutOfRange }
        // "Switch to Desktop N" is registered with the pure-Control mask
        // (262144); digits are not function keys.
        try postChord(keyCode: Self.digitVirtualKeyCodes[digit - 1], flags: .maskControl)
    }

    public func postControlKey(_ keyCode: CGKeyCode) throws {
        // Arrow keys are *secondary-function* keys, so macOS registers the
        // "Move left/right a space" hotkey with Control **+ Fn** (mask
        // 8650752 = 0x040000 | 0x800000). A Control-only event never matches
        // it — the synthesized chord must include `.maskSecondaryFn` too
        // (proven on a real machine; this was why Ctrl+arrow did nothing).
        try postChord(keyCode: keyCode, flags: [.maskControl, .maskSecondaryFn])
    }

    private func postChord(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        // Post at the HID tap so the synthesized chord is processed like a real
        // keypress and reaches the WindowServer symbolic-hotkey handler
        // ("Switch to Desktop N" / "Move left-right a space").
        // `.cgAnnotatedSessionEventTap` is downstream of that handler, so
        // events posted there never trigger the shortcut (verified on a real
        // machine). Requires Accessibility (TCC) trust.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        down.flags = flags
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        up.flags = flags
        up.post(tap: .cghidEventTap)
    }
}
