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
    public init() {}

    public func postControlDigit(_ digit: Int) throws {
        guard (1...9).contains(digit) else { throw KeystrokeError.digitOutOfRange }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        // US-layout virtual key codes for digits 1..9: 18, 19, 20, 21, 23, 22, 26, 28, 25.
        let keyMap: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keyCode = keyMap[digit - 1]

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskControl
        down?.post(tap: .cgAnnotatedSessionEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskControl
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
