import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openMenu = Self("openMenu")
    static func space(_ id: String) -> Self { Self("space.\(id)") }
}

@MainActor
final class HotkeyManager {
    /// Fired when a Space's hotkey is pressed; argument is the Space id.
    var onSpaceHotkey: ((String) -> Void)?
    /// Fired when the open-menu hotkey is pressed.
    var onOpenMenu: (() -> Void)?

    private var registeredIDs: Set<String> = []

    init() {
        KeyboardShortcuts.onKeyUp(for: .openMenu) { [weak self] in
            self?.onOpenMenu?()
        }
    }

    /// Idempotently register a keyUp handler for each known Space id.
    func sync(knownIDs: [String]) {
        for id in knownIDs where !registeredIDs.contains(id) {
            KeyboardShortcuts.onKeyUp(for: .space(id)) { [weak self] in
                self?.onSpaceHotkey?(id)
            }
            registeredIDs.insert(id)
        }
    }
}
