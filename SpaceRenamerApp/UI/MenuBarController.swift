import AppKit
import Combine
import SpaceRenamerCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let monitor: SpaceMonitor
    private let names: NameStore
    private let switcher: SwitcherEngine
    private let openPreferences: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(monitor: SpaceMonitor,
         names: NameStore,
         switcher: SwitcherEngine,
         openPreferences: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.monitor = monitor
        self.names = names
        self.switcher = switcher
        self.openPreferences = openPreferences
        super.init()
        statusItem.button?.title = "Desktop"

        Publishers.CombineLatest3(monitor.$spaces, monitor.$activeID, monitor.$lastLoadError)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.rebuild() }
            .store(in: &cancellables)
        rebuild()
    }

    /// Programmatically drop the menu (used by the open-menu hotkey).
    func openMenu() {
        statusItem.button?.performClick(nil)
    }

    private func rebuild() {
        let menu = NSMenu()

        for space in monitor.spaces {
            let title = names.name(for: space.id, defaultOrdinal: space.ordinal)
            let item = NSMenuItem(title: title, action: #selector(spaceClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = space.id
            if space.id == monitor.activeID { item.state = .on }
            if !space.isShortcutAvailable {
                item.isEnabled = false
                item.toolTip = "No Ctrl+digit shortcut (more than \(ParsedSpace.maxShortcutOrdinal) Spaces)"
            }
            menu.addItem(item)

            // ⌥-held alternate row → rename (implemented in Task B3).
            let renameAlt = NSMenuItem(title: "Rename \u{201C}\(title)\u{201D}\u{2026}",
                                       action: #selector(renameClicked(_:)),
                                       keyEquivalent: "")
            renameAlt.target = self
            renameAlt.representedObject = space.id
            renameAlt.keyEquivalentModifierMask = .option
            renameAlt.isAlternate = true
            menu.addItem(renameAlt)
        }

        if monitor.lastLoadError != nil {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "⚠︎ Spaces unavailable — showing last known", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(prefsClicked), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let quit = NSMenuItem(title: "Quit Space Renamer", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu

        if let activeID = monitor.activeID,
           let active = monitor.spaces.first(where: { $0.id == activeID }) {
            statusItem.button?.title = names.name(for: active.id, defaultOrdinal: active.ordinal)
        } else if monitor.lastLoadError != nil {
            statusItem.button?.title = "⚠︎ Desktop"
        } else {
            statusItem.button?.title = "Desktop"
        }
    }

    @objc private func spaceClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        do {
            try switcher.switch(to: id)
        } catch {
            NSLog("Space Renamer: switch failed for \(id): \(error)")
        }
    }

    @objc private func renameClicked(_ sender: NSMenuItem) {
        // Implemented in Task B3.
    }

    @objc private func prefsClicked() { openPreferences() }

    @objc private func quitClicked() { NSApp.terminate(nil) }
}
