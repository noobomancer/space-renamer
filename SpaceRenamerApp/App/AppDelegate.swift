import Cocoa
import Combine
import ApplicationServices
import SpaceRenamerCore

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
        // The app persists to its own standard UserDefaults domain (keyed by the
        // bundle id). D9: tests use isolated suites; the app must NOT pass its own
        // bundle id as a `suiteName` — UserDefaults rejects that as nonsensical.
        names = NameStore()
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

        promptForAccessibilityIfNeeded()
        warnIfSpaceMoveShortcutsDisabled()
    }

    func applicationWillTerminate(_ notification: Notification) {}

    private func showPreferences() {
        if prefs == nil { prefs = PreferencesWindowController(monitor: monitor, names: names) }
        prefs?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func promptForAccessibilityIfNeeded() {
        // Switching desktops posts a synthesized Ctrl+digit CGEvent, which macOS
        // only delivers if this process is Accessibility-trusted; otherwise the
        // events are silently dropped. AXIsProcessTrustedWithOptions with the
        // prompt option triggers the system prompt when not yet trusted.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }

        let alert = NSAlert()
        alert.messageText = "Grant Accessibility access"
        alert.informativeText = "Space Renamer switches desktops by sending the macOS \u{201C}Switch to Desktop\u{201D} keyboard shortcut, which requires Accessibility permission. Enable \u{201C}SpaceRenamer\u{201D} under System Settings \u{2192} Privacy & Security \u{2192} Accessibility, then clicking a desktop will switch. (Ad-hoc development builds may need re-granting after a rebuild.)"
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func warnIfSpaceMoveShortcutsDisabled() {
        guard !names.didWarnAboutSystemShortcuts else { return }
        guard !SystemShortcutChecker.spaceMoveShortcutsEnabled() else { return }
        // Set before showing the modal on purpose: a one-shot warning — we do not
        // want to re-prompt every launch if the user force-quits during the alert.
        names.didWarnAboutSystemShortcuts = true

        let alert = NSAlert()
        alert.messageText = "Enable Mission Control shortcuts"
        alert.informativeText = "Space Renamer switches desktops using the \u{201C}Move left a space\u{201D} and \u{201C}Move right a space\u{201D} keyboard shortcuts (Ctrl+\u{2190} / Ctrl+\u{2192}). Enable both in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Mission Control, or clicking a desktop won\u{2019}t switch."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
