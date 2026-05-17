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

        warnIfMissionControlShortcutsDisabled()
    }

    func applicationWillTerminate(_ notification: Notification) {}

    private func showPreferences() {
        // Implemented in Task B3.
    }

    private func warnIfMissionControlShortcutsDisabled() {
        guard !names.didWarnAboutSystemShortcuts else { return }
        guard !SystemShortcutChecker.switchToDesktopShortcutsEnabled() else { return }
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
