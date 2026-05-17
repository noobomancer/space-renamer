import Cocoa
import Combine
import SpaceRenamerCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var names: NameStore!
    private var monitor: SpaceMonitor!
    private var switcher: SwitcherEngine!
    private var menuBar: MenuBarController!
    private var hotkeys: HotkeyManager!
    private var prefs: PreferencesWindowController?
    private var spaceIDsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Named UserDefaults suite so app data is separate from .standard (D9).
        let defaults = UserDefaults(suiteName: "com.saint.SpaceRenamer") ?? .standard
        names = NameStore(defaults: defaults)
        monitor = SpaceMonitor()
        switcher = SwitcherEngine(lookup: monitor)   // AppDelegate retains `monitor` (SwitcherEngine holds it weakly)

        menuBar = MenuBarController(
            monitor: monitor,
            names: names,
            switcher: switcher,
            openPreferences: { [weak self] in self?.showPreferences() }
        )

        hotkeys = HotkeyManager()
        hotkeys.onSpaceHotkey = { [weak self] id in
            do { try self?.switcher.switch(to: id) }
            catch { NSLog("Space Renamer: hotkey switch failed: \(error)") }
        }
        hotkeys.onOpenMenu = { [weak self] in self?.menuBar.openMenu() }
        spaceIDsObserver = monitor.$spaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaces in self?.hotkeys.sync(knownIDs: spaces.map { $0.id }) }

        warnIfMissionControlShortcutsDisabled()
    }

    func applicationWillTerminate(_ notification: Notification) {}

    private func showPreferences() {
        if prefs == nil { prefs = PreferencesWindowController(monitor: monitor, names: names) }
        prefs?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func warnIfMissionControlShortcutsDisabled() {
        guard !names.didWarnAboutSystemShortcuts else { return }
        guard !SystemShortcutChecker.switchToDesktopShortcutsEnabled() else { return }
        // Set before showing the modal on purpose: a one-shot warning — we do not
        // want to re-prompt every launch if the user force-quits during the alert.
        names.didWarnAboutSystemShortcuts = true

        let alert = NSAlert()
        alert.messageText = "Enable Mission Control shortcuts"
        alert.informativeText = "Space Renamer switches desktops using the \u{201C}Switch to Desktop N\u{201D} keyboard shortcuts. Enable them in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Mission Control, or clicking a desktop won\u{2019}t switch."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
