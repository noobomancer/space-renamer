# Space Renamer — Phase B (App Shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the macOS menu-bar `.app` shell on top of the already-shipped `SpaceRenamerCore` SwiftPM package — status-item with the active Space's name, a menu to switch Spaces, inline rename, global hotkeys, a Preferences window, and launch-at-login.

**Architecture:** An xcodegen-generated Xcode application target (`SpaceRenamer`, `LSUIElement` agent app) that depends on the **local `SpaceRenamerCore` package** (path `.`) and the remote `KeyboardShortcuts` package. The app contributes only the AppKit layer — `AppDelegate`, `MenuBarController`, `PreferencesWindowController`, `HotkeyManager`, `LaunchAtLogin` — and consumes the Core's public, `@MainActor`-isolated API. Core logic is already unit-tested in the package (26 tests via `swift test`); it is **not** duplicated here. Phase B verification = the app builds via `xcodebuild` + a manual end-to-end smoke checklist (UI/Accessibility-gated behaviors a headless agent cannot exercise).

**Tech Stack:** Swift 5.10 (Swift 5 language mode — see D9; full Swift 6 strict-concurrency adoption remains tracked as task #26), AppKit, Combine, `KeyboardShortcuts` (Sindre Sorhus) for global hotkeys, `SMAppService` for launch-at-login. Project generated via `xcodegen`. macOS 13+.

---

## TOOLCHAIN NOTE (applies to EVERY task)

The global `xcode-select` developer dir points at the Command Line Tools; full Xcode is at `/Applications/Xcode.app`. **Every `xcodebuild` and `swift` command MUST be prefixed** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the `/usr/bin` shims honour this env var; without it `xcodebuild` errors "requires Xcode" and `swift test` has no XCTest). `xcodegen` and `git` need no prefix.

**COMMIT CONVENTION (every task):** Never modify git config. Commit gpg-unsigned with the required footer:
```bash
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
<subject>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
Work on branch `main` (this project's established flow). The pre-existing committed Phase A package (`Package.swift`, `Sources/SpaceRenamerCore`, `Tests/`) MUST NOT be modified by Phase B.

## Current Core public API (consume exactly this — do NOT recreate Core in the app)

`import SpaceRenamerCore` gives:
- `NameStore` (`@MainActor`): `init(defaults: UserDefaults = .standard)`, `name(for spaceID: String, defaultOrdinal: Int) -> String`, `setName(_ spaceID: String, _ name: String)`, `forget(_ spaceID: String)`, `var didWarnAboutSystemShortcuts: Bool`.
- `ParsedSpace` (value type): `let id: String`, `let ordinal: Int`, `static let maxShortcutOrdinal: Int` (=9), `var isShortcutAvailable: Bool`.
- `SpaceMonitor` (`@MainActor`): `init(plistURL: URL? = nil)`, `@Published private(set) var spaces: [ParsedSpace]`, `@Published private(set) var activeID: String?`, `@Published private(set) var lastLoadError: String?`, `func reload()`, `func ordinal(for id: String) -> Int?`. Conforms to `OrdinalLookup`.
- `SwitcherEngine` (`@MainActor`): `init(synthesizer: KeystrokeSynthesizing = CGKeystrokeSynthesizer(), lookup: OrdinalLookup)`, `func switch(to id: String) throws`. Caller MUST retain the `lookup` (held weakly).
- `SwitcherError` (`Error, Equatable`): `.unknownSpace`, `.ordinalOutOfRange`, `.lookupUnavailable`.
- `SystemShortcutChecker`: `static func switchToDesktopShortcutsEnabled() -> Bool`.
- (`OrdinalLookup` `@MainActor protocol`, `KeystrokeSynthesizing`, `CGKeystrokeSynthesizer`, `KeystrokeError` also public.)

Identity is the Space's `ManagedSpaceID` as a decimal `String` ("id"/"spaceID"), NOT a uuid (design D1). All Core stateful types are `@MainActor` (D9): construct and use them only from the main actor — the AppKit classes below are all `@MainActor`, so this is satisfied naturally.

---

## File Structure (after Phase B)

```
rnd/
├── Package.swift                       # Phase A — UNCHANGED
├── Sources/SpaceRenamerCore/…          # Phase A — UNCHANGED
├── Tests/…                             # Phase A — UNCHANGED (26 tests)
├── project.yml                         # NEW — xcodegen config
├── SpaceRenamer.xcodeproj/             # NEW — generated, gitignored
└── SpaceRenamerApp/
    ├── App/
    │   ├── AppDelegate.swift           # wires Core + UI
    │   └── Info.plist                  # stub (xcodegen fills keys)
    ├── UI/
    │   ├── MenuBarController.swift      # NSStatusItem + NSMenu
    │   ├── PreferencesWindowController.swift
    │   └── LaunchAtLogin.swift          # SMAppService wrapper
    ├── Hotkeys/
    │   └── HotkeyManager.swift          # KeyboardShortcuts wrapper (Space id keyed)
    └── Resources/
        └── Assets.xcassets/Contents.json
```

No app unit-test target: Core logic is tested in the SwiftPM package (`DEVELOPER_DIR=… swift test` → 26 tests). The app is verified by build + manual smoke.

---

## Task B1: xcodegen scaffold — app target on the SpaceRenamerCore package, launches as an agent

**Files:**
- Create: `project.yml`
- Create: `SpaceRenamerApp/App/Info.plist`
- Create: `SpaceRenamerApp/App/AppDelegate.swift`
- Create: `SpaceRenamerApp/Resources/Assets.xcassets/Contents.json`
- Modify: `.gitignore`

- [ ] **Step 1: Install xcodegen**

```bash
which xcodegen || brew install xcodegen
xcodegen --version
```
Expected: prints a version (installs via the available Homebrew if absent).

- [ ] **Step 2: Append Xcode artefacts to `.gitignore`**

Append these lines to the existing `.gitignore` (do not remove existing entries):
```
SpaceRenamer.xcodeproj/
*.xcodeproj/xcuserdata/
```

- [ ] **Step 3: Write `project.yml`**

```yaml
name: SpaceRenamer
options:
  bundleIdPrefix: com.saint
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true

packages:
  SpaceRenamerCore:
    path: .
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.0.0"

targets:
  SpaceRenamer:
    type: application
    platform: macOS
    sources:
      - path: SpaceRenamerApp
    resources:
      - SpaceRenamerApp/Resources/Assets.xcassets
    info:
      path: SpaceRenamerApp/App/Info.plist
      properties:
        CFBundleName: Space Renamer
        CFBundleDisplayName: Space Renamer
        LSUIElement: true
        NSSupportsAutomaticTermination: false
        NSSupportsSuddenTermination: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.saint.SpaceRenamer
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.0"
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
    dependencies:
      - package: SpaceRenamerCore
        product: SpaceRenamerCore
      - package: KeyboardShortcuts
```
(`SWIFT_VERSION: "5.0"` = Swift 5 language mode, matching the Core/D9; Swift 6 is tracked task #26. Ad-hoc signing `"-"` + stable bundle id is the dev-time choice; Accessibility-grant stability caveats are covered in Task B4.)

- [ ] **Step 4: Stub `SpaceRenamerApp/App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 5: Stub `SpaceRenamerApp/Resources/Assets.xcassets/Contents.json`**

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 6: Minimal `@main` AppDelegate** `SpaceRenamerApp/App/AppDelegate.swift`

```swift
import Cocoa

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Core + UI wired in Task B2.
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
```

- [ ] **Step 7: Generate the project**

```bash
cd /Users/saint/projects/rnd
xcodegen generate
```
Expected: `Generated project successfully` and `SpaceRenamer.xcodeproj/` exists.

- [ ] **Step 8: Build (resolves both packages)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpaceRenamer.xcodeproj -scheme SpaceRenamer \
  -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`. (First build resolves `SpaceRenamerCore` (local) and `KeyboardShortcuts` (remote, needs network). If KeyboardShortcuts fails to resolve, report BLOCKED with the resolver error.)

- [ ] **Step 9: Launch as an agent, verify no Dock icon + stays running**

```bash
APP="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2}/ WRAPPER_NAME/{w=$2}END{print d"/"w}')"
open "$APP"; sleep 2
pgrep -x SpaceRenamer && echo "RUNNING (no Dock icon expected)"
pkill -x SpaceRenamer
```
Expected: prints a PID and `RUNNING`; no Dock icon appears.

- [ ] **Step 10: Commit**

```bash
git add .gitignore project.yml SpaceRenamerApp
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
chore: xcodegen app target on SpaceRenamerCore + KeyboardShortcuts (Phase B B1)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```
(`SpaceRenamer.xcodeproj/` is gitignored — `project.yml` is the source of truth; regenerate with `xcodegen generate`.)

---

## Task B2: AppDelegate wiring + MenuBarController (status item, menu, switch, active-name, >9, degraded)

**Files:**
- Create: `SpaceRenamerApp/UI/MenuBarController.swift`
- Modify: `SpaceRenamerApp/App/AppDelegate.swift`

- [ ] **Step 1: Write `SpaceRenamerApp/UI/MenuBarController.swift`**

```swift
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
            let renameAlt = NSMenuItem(title: "Rename “\(title)”…",
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
```

- [ ] **Step 2: Replace `SpaceRenamerApp/App/AppDelegate.swift`**

```swift
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
        alert.informativeText = "Space Renamer switches desktops using the “Switch to Desktop N” keyboard shortcuts. Enable them in System Settings → Keyboard → Keyboard Shortcuts → Mission Control, or clicking a desktop won't switch."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 3: Regenerate + build**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpaceRenamer.xcodeproj -scheme SpaceRenamer \
  -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Launch sanity (no automated UI assertions possible)**

```bash
APP="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2}/ WRAPPER_NAME/{w=$2}END{print d"/"w}')"
open "$APP"; sleep 2; pgrep -x SpaceRenamer && echo RUNNING; pkill -x SpaceRenamer
```
Expected: `RUNNING`. (Visual verification of the status item is part of the Task B4 manual smoke — a headless agent cannot assert menu contents.)

- [ ] **Step 5: Commit**

```bash
git add SpaceRenamerApp/App/AppDelegate.swift SpaceRenamerApp/UI/MenuBarController.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: status-item menu — list/switch Spaces, active name, >9 + degraded (B2)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B3: Hotkeys + inline rename + Preferences window + Launch-at-Login

**Files:**
- Create: `SpaceRenamerApp/Hotkeys/HotkeyManager.swift`
- Create: `SpaceRenamerApp/UI/LaunchAtLogin.swift`
- Create: `SpaceRenamerApp/UI/PreferencesWindowController.swift`
- Modify: `SpaceRenamerApp/UI/MenuBarController.swift` (implement `renameClicked`)
- Modify: `SpaceRenamerApp/App/AppDelegate.swift` (wire hotkeys + Preferences)

- [ ] **Step 1: `SpaceRenamerApp/Hotkeys/HotkeyManager.swift`**

```swift
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
```

- [ ] **Step 2: `SpaceRenamerApp/UI/LaunchAtLogin.swift`**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue, SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                } else if !newValue, SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Space Renamer: LaunchAtLogin toggle failed: \(error)")
            }
        }
    }
}
```

- [ ] **Step 3: `SpaceRenamerApp/UI/PreferencesWindowController.swift`**

```swift
import AppKit
import Combine
import KeyboardShortcuts
import SpaceRenamerCore

@MainActor
final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let monitor: SpaceMonitor
    private let names: NameStore
    private let table = NSTableView()
    private let openMenuRecorder = KeyboardShortcuts.RecorderCocoa(for: .openMenu)
    private var cancellables: Set<AnyCancellable> = []

    init(monitor: SpaceMonitor, names: NameStore) {
        self.monitor = monitor
        self.names = names
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Space Renamer Preferences"
        super.init(window: window)
        setupContent()
        monitor.$spaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.table.reloadData() }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        let openMenuLabel = NSTextField(labelWithString: "Open-menu hotkey:")
        let launchToggle = NSButton(checkboxWithTitle: "Launch at Login",
                                    target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchToggle.state = LaunchAtLogin.isEnabled ? .on : .off

        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "Desktop"; nameCol.width = 210
        let hotkeyCol = NSTableColumn(identifier: .init("hotkey"))
        hotkeyCol.title = "Hotkey"; hotkeyCol.width = 230
        table.addTableColumn(nameCol)
        table.addTableColumn(hotkeyCol)
        table.dataSource = self
        table.delegate = self
        table.headerView = NSTableHeaderView()
        table.rowHeight = 30

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let stack = NSStackView(views: [openMenuLabel, openMenuRecorder, scroll, launchToggle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scroll.widthAnchor.constraint(equalToConstant: 440)
        ])
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.isEnabled = (sender.state == .on)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { monitor.spaces.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let space = monitor.spaces[row]
        switch tableColumn?.identifier.rawValue {
        case "name":
            return NSTextField(labelWithString: names.name(for: space.id, defaultOrdinal: space.ordinal))
        case "hotkey":
            return KeyboardShortcuts.RecorderCocoa(for: .space(space.id))
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Implement `renameClicked` in `MenuBarController.swift`**

Replace the placeholder `@objc private func renameClicked(_ sender: NSMenuItem) {}` body with:
```swift
    @objc private func renameClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let space = monitor.spaces.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Desktop"
        alert.informativeText = "Enter a new name. Leave blank to revert to “Desktop \(space.ordinal)”."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = names.name(for: id, defaultOrdinal: space.ordinal)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            names.setName(id, field.stringValue)
            rebuild()   // NameStore changes don't publish; rebuild explicitly.
        }
    }
```

- [ ] **Step 5: Wire hotkeys + Preferences in `AppDelegate.swift`**

Add two stored properties to `AppDelegate` (next to the others):
```swift
    private var hotkeys: HotkeyManager!
    private var prefs: PreferencesWindowController?
    private var spaceIDsObserver: AnyCancellable?
```
In `applicationDidFinishLaunching`, after `menuBar = MenuBarController(...)` and before `warnIfMissionControlShortcutsDisabled()`, insert:
```swift
        hotkeys = HotkeyManager()
        hotkeys.onSpaceHotkey = { [weak self] id in
            do { try self?.switcher.switch(to: id) }
            catch { NSLog("Space Renamer: hotkey switch failed: \(error)") }
        }
        hotkeys.onOpenMenu = { [weak self] in self?.menuBar.openMenu() }
        spaceIDsObserver = monitor.$spaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] spaces in self?.hotkeys.sync(knownIDs: spaces.map { $0.id }) }
```
Replace the `showPreferences()` placeholder body with:
```swift
    private func showPreferences() {
        if prefs == nil { prefs = PreferencesWindowController(monitor: monitor, names: names) }
        prefs?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 6: Regenerate + build**

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpaceRenamer.xcodeproj -scheme SpaceRenamer \
  -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Launch sanity**

```bash
APP="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2}/ WRAPPER_NAME/{w=$2}END{print d"/"w}')"
open "$APP"; sleep 2; pgrep -x SpaceRenamer && echo RUNNING; pkill -x SpaceRenamer
```
Expected: `RUNNING`.

- [ ] **Step 8: Commit**

```bash
git add SpaceRenamerApp
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: hotkeys, inline rename, Preferences window, launch-at-login (B3)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task B4: Manual end-to-end smoke test (executes tracked #20) + Swift 6 follow-up

This task is a **manual checklist run on a real machine by the user** (a headless agent cannot click menu items, grant Accessibility/TCC, or press global hotkeys). The implementer subagent's job is only Steps 1–2 (produce a Release build + the checklist); the controller coordinates the human run.

- [ ] **Step 1: Release build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project SpaceRenamer.xcodeproj -scheme SpaceRenamer \
  -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3
open "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Release -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2}/ WRAPPER_NAME/{w=$2}END{print d"/"w}')"
```
Expected: `** BUILD SUCCEEDED **`, app launches (menu-bar item appears).

- [ ] **Step 2: Run the smoke checklist** (grant Accessibility when macOS prompts: System Settings → Privacy & Security → Accessibility → enable Space Renamer)

1. [ ] Menu-bar shows the active desktop's name (e.g. "Desktop 1").
2. [ ] Clicking it lists all Spaces; the active one has a checkmark.
3. [ ] Clicking another row switches to that Space (verifies `SwitcherEngine`→Ctrl+digit + Accessibility grant).
4. [ ] **(#20 / D9)** Switch Spaces via Mission Control directly → menu-bar name updates correctly and promptly (no stale read; validates `SpaceMonitor` cfprefs sync + `activeSpaceDidChangeNotification` + the `@MainActor` construct-on-main contract on the real machine).
5. [ ] ⌥-click a row → rename dialog; rename "Desktop 2" → "Research"; menu + bar title update.
6. [ ] Quit & relaunch → "Research" persists (named UserDefaults suite).
7. [ ] Add a Space in Mission Control → appears in the menu on next open; reorder Spaces → custom name stays with the same desktop (`ManagedSpaceID` tracking).
8. [ ] Create ≥10 Spaces → the 10th row is disabled with the "no Ctrl+digit" tooltip (`isShortcutAvailable`).
9. [ ] Preferences → assign `⌃⌥D` to a desktop → press from another app → switches. Assign open-menu hotkey → press → menu drops.
10. [ ] Preferences → toggle "Launch at Login" → `SMAppService.mainApp.status` becomes `.enabled` (re-login or check via Settings → General → Login Items).
11. [ ] Disable Mission Control "Switch to Desktop" shortcuts → relaunch → one-shot alert appears; "Open Keyboard Settings" opens the right pane.
12. [ ] Temporarily rename `~/Library/Preferences/com.apple.spaces.plist` (or revoke read) → relaunch → menu shows the "⚠︎ Spaces unavailable" degraded item and the `⚠︎` bar title (`lastLoadError`); restore the file.

- [ ] **Step 3: Record results + fix regressions**

For any failed item, fix in the relevant file, `xcodegen generate`, rebuild, re-run that item, then:
```bash
git -c commit.gpgsign=false commit -am "$(cat <<'EOF'
fix: <smoke item N> — <what>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Close #20; flip #26 to ready**

When the checklist passes: mark tracked task **#20** complete. Task **#26** (adopt Swift 6 strict concurrency across the package + app target — the `deinit`-touches-isolated-`observer` and unstructured-`Task` gaps) is now unblocked (the app target exists) — execute or schedule it as a follow-up; it is intentionally OUT OF SCOPE for B1–B3.

- [ ] **Step 5: Tag**

```bash
git tag v0.1.0
```

---

## Self-Review

**Spec / decision coverage:**
- D1 ManagedSpaceID identity → app consumes `space.id`/`name(for spaceID:)`/`switch(to id:)` throughout (B2/B3).
- D2 Ctrl+N synthesis → `SwitcherEngine` from the package (B2 click, B3 hotkey).
- D3 global hotkeys via KeyboardShortcuts → `HotkeyManager` (B3).
- D4 inline rename via NSAlert → `renameClicked` ⌥-alternate item (B3).
- D5 Preferences window for hotkeys → `PreferencesWindowController` (B3).
- D6 Swift + AppKit → B1–B3.
- D7 bar title = active name → `MenuBarController.rebuild` (B2).
- D8 macOS 13+ → `project.yml` deploymentTarget (B1).
- D9 @MainActor Core + named UserDefaults suite + Swift 5 mode now → all app classes `@MainActor`; `NameStore(defaults: UserDefaults(suiteName:))`; `SWIFT_VERSION 5.0`; Swift 6 = tracked #26 (B1/B2, Task B4 Step 4).
- Edge >9 Spaces → `isShortcutAvailable` disabled item (B2, smoke 8).
- Edge Ctrl+N disabled → `SystemShortcutChecker` alert (B2, smoke 11).
- Edge plist unreadable → `lastLoadError` degraded UI (B2, smoke 12).
- Edge Accessibility denied → `switch` throws caught + logged (B2 `spaceClicked` catch; smoke 3).
- SwitcherEngine weak-lookup contract (#24) → AppDelegate retains `monitor` (B2, commented).
- Launch at Login → `LaunchAtLogin`/SMAppService (B3, smoke 10).
- Tracked #20 → Task B4 smoke items 3/4; #26 → Task B4 Step 4.

**Placeholder scan:** `renameClicked`/`showPreferences` are intentionally stubbed in B2 and explicitly implemented in B3 (chained, each task builds). No TBD/TODO; all code blocks complete and current-API-accurate.

**Type consistency:** App uses only the documented Core public symbols (`id`, `activeID`, `lastLoadError`, `isShortcutAvailable`, `maxShortcutOrdinal`, `switch(to id:)`, `name(for spaceID:defaultOrdinal:)`, `didWarnAboutSystemShortcuts`, `SystemShortcutChecker.switchToDesktopShortcutsEnabled()`); `KeyboardShortcuts.Name.space(_:)`/`.openMenu` consistent across `HotkeyManager`/`PreferencesWindowController`; `SpaceMonitor` retained by `AppDelegate` per the #24 contract.

**Out of scope (tracked, not Phase B regressions):** Swift 6 strict concurrency (#26); App Sandbox / App Store / notarization / Developer-ID signing (dev build uses ad-hoc `-`; Accessibility-grant may re-prompt after rebuilds — noted in B4); multi-display Spaces (design Non-Goal).
