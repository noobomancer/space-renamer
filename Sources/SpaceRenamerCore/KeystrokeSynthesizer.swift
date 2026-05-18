import Foundation
import CoreGraphics

public protocol KeystrokeSynthesizing {
    /// Posts a Ctrl + <digit> keystroke (1...9).
    /// Throws if `digit` is out of range.
    func postControlDigit(_ digit: Int) throws
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

    public init() {}

    public func postControlDigit(_ digit: Int) throws {
        guard (1...9).contains(digit) else { throw KeystrokeError.digitOutOfRange }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        let keyCode = Self.digitVirtualKeyCodes[digit - 1]

        // Post at the HID tap so the synthesized chord is processed like a real
        // keypress and reaches the WindowServer "Switch to Desktop N" symbolic-
        // hotkey handler. `.cgAnnotatedSessionEventTap` is downstream of that
        // handler, so events posted there never triggered the shortcut
        // (verified on a real machine). Requires Accessibility (TCC) trust.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        down.flags = .maskControl
        down.post(tap: .cghidEventTap)

        guard let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        up.flags = .maskControl
        up.post(tap: .cghidEventTap)
    }
}
