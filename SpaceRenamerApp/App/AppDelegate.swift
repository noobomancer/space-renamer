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
    private var overlay: SpaceLabelOverlayManager!
    private var prefs: PreferencesWindowController?
    private var spaceIDsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app persists to its own standard UserDefaults domain (keyed by the
        // bundle id). D9: tests use isolated suites; the app must NOT pass its own
        // bundle id as a `suiteName` — UserDefaults rejects that as nonsensical.
        names = NameStore()
        monitor = SpaceMonitor()
        // Routing switcher reads the user's SwitchMode per call, so the
        // Preferences toggle takes effect on the next switch (no relaunch).
        switcher = SwitcherEngine(
            spaceSwitcher: ModeRoutingSpaceSwitcher(mode: { [weak names] in names?.switchMode ?? .default }),
            lookup: monitor)   // AppDelegate retains `monitor` (SwitcherEngine holds it weakly)

        menuBar = MenuBarController(
            monitor: monitor,
            names: names,
            switcher: switcher,
            openPreferences: { [weak self] in self?.showPreferences() }
        )

        // Mission Control overlay labels (per-Space window with two visual
        // modes). Disabled by default; enabled via Preferences. The manager
        // is constructed unconditionally so toggling on at runtime needs no
        // additional wiring; setEnabled(true) is what actually spawns windows.
        overlay = SpaceLabelOverlayManager(monitor: monitor, names: names)
        overlay.setEnabled(names.showMissionControlOverlay)

        hotkeys = HotkeyManager()
        hotkeys.onSpaceHotkey = { [weak self] id in
            do { try self?.switcher.switch(to: id) }
            catch { NSLog("Space Renamer: hotkey switch failed: \(error)") }
        }
        hotkeys.onOpenMenu = { [weak self] in self?.menuBar.openMenu() }
        spaceIDsObserver = monitor.$spaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaces in self?.hotkeys.sync(knownIDs: spaces.map { $0.id }) }

        // Defer the first-run alerts off the synchronous launch path so the
        // status item appears first and the modal isn't the very first thing
        // the user sees on a cold start (#31).
        DispatchQueue.main.async { [weak self] in
            self?.promptForAccessibilityIfNeeded()
            self?.warnIfSwitchShortcutsDisabled()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {}

    private func showPreferences() {
        if prefs == nil {
            prefs = PreferencesWindowController(
                monitor: monitor,
                names: names,
                overlayChanged: { [weak self] enabled in
                    self?.overlay.setEnabled(enabled)
                }
            )
        }
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

    private func warnIfSwitchShortcutsDisabled() {
        guard !names.didWarnAboutSystemShortcuts else { return }
        let mode = names.switchMode
        let enabled: Bool
        switch mode {
        case .arrow:     enabled = SystemShortcutChecker.spaceMoveShortcutsEnabled()
        case .ctrlDigit: enabled = SystemShortcutChecker.switchToDesktopShortcutsEnabled()
        }
        guard !enabled else { return }
        // Set before showing the modal on purpose: a one-shot warning — we do not
        // want to re-prompt every launch if the user force-quits during the alert.
        names.didWarnAboutSystemShortcuts = true

        let alert = NSAlert()
        alert.messageText = "Enable Mission Control shortcuts"
        switch mode {
        case .arrow:
            alert.informativeText = "Space Renamer switches desktops using the \u{201C}Move left a space\u{201D} and \u{201C}Move right a space\u{201D} keyboard shortcuts (Ctrl+\u{2190} / Ctrl+\u{2192}). Enable both in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Mission Control, or clicking a desktop won\u{2019}t switch. (Or pick \u{201C}Switch to Desktop N\u{201D} mode in Preferences.)"
        case .ctrlDigit:
            alert.informativeText = "Space Renamer is set to switch via the \u{201C}Switch to Desktop N\u{201D} shortcuts (Ctrl+1\u{2013}9). Enable them in System Settings \u{2192} Keyboard \u{2192} Keyboard Shortcuts \u{2192} Mission Control, or clicking a desktop won\u{2019}t switch. (Or pick \u{201C}Move a space\u{201D} mode in Preferences.)"
        }
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
