import AppKit
import Combine
import SpaceRenamerCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: SpaceMonitor
    private let names: NameStore
    private let switcher: SwitcherEngine
    private let openPreferences: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private let menu = NSMenu()

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
        menu.delegate = self
        statusItem.menu = menu

        Publishers.CombineLatest3(monitor.$spaces, monitor.$activeID, monitor.$lastLoadError)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.refreshTitle() }
            .store(in: &cancellables)
        refreshTitle()
    }

    /// Programmatically toggle the status-item menu (used by the global open-menu hotkey
    /// in Task B3). `performClick` TOGGLES: if the menu is already open this closes it —
    /// callers must NOT add extra open/closed state tracking around this.
    func openMenu() {
        statusItem.button?.performClick(nil)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        monitor.reload()
        populate()
        // Immediate title refresh; the Combine sink also fires later (async,
        // idempotent) from reload()'s @Published mutations.
        refreshTitle()
    }

    // MARK: - Private helpers

    private func populate() {
        menu.removeAllItems()

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

        if !monitor.spaces.isEmpty {
            let hint = NSMenuItem(title: "Hold \u{2325} and click a desktop to rename", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
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
    }

    private func refreshTitle() {
        if let activeID = monitor.activeID,
           let active = monitor.spaces.first(where: { $0.id == activeID }) {
            statusItem.button?.title = names.name(for: active.id, defaultOrdinal: active.ordinal)
        } else if monitor.lastLoadError != nil {
            statusItem.button?.title = "\u{26A0}\u{FE0E} Desktop"
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
        guard let id = sender.representedObject as? String,
              let space = monitor.spaces.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Desktop"
        alert.informativeText = "Enter a new name. Leave blank to revert to \u{201C}Desktop \(space.ordinal)\u{201D}."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = names.name(for: id, defaultOrdinal: space.ordinal)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            names.setName(id, field.stringValue)
            populate()   // NameStore changes don't publish; repopulate explicitly.
            refreshTitle()
        }
    }

    @objc private func prefsClicked() { openPreferences() }

    @objc private func quitClicked() { NSApp.terminate(nil) }
}
