# Space Renamer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar app that gives Mission Control Spaces custom names, displays the active Space's name in the menu bar, lets the user switch Spaces by click or global hotkey, and persists names across reorders.

**Architecture:** Six small Swift components — `SpaceMonitor` (reads `com.apple.spaces.plist`), `NameStore` (persists UUID→name in UserDefaults), `SwitcherEngine` (synthesizes `Ctrl+N` CGEvents), `HotkeyManager` (wraps Carbon hotkeys via the `KeyboardShortcuts` package), `MenuBarController` (NSStatusItem + NSMenu), `PreferencesWindowController` (AppKit window with hotkey recorders). Public APIs only.

**Tech Stack:** Swift 5.9+, AppKit, XCTest, Carbon (via `KeyboardShortcuts` Swift Package by Sindre Sorhus), `SMAppService` for launch-at-login. Project generated via `xcodegen`. macOS 13+ deployment target.

---

## Reference Documents

- Design spec: `docs/superpowers/specs/2026-05-15-space-renamer-design.md`
- `KeyboardShortcuts` package: https://github.com/sindresorhus/KeyboardShortcuts (resolved in `Package.resolved` once added)

## Implementation Note: Hotkey Persistence

The spec describes `NameStore` as storing both names *and* hotkeys. In practice we'll use the `KeyboardShortcuts` package which owns hotkey persistence internally (keyed by `KeyboardShortcuts.Name` strings). `NameStore` will store only names + a map from Space UUID to the `KeyboardShortcuts.Name` it's registered under. Observable behavior matches the spec.

---

## File Structure

After all tasks complete:

```
rnd/
├── project.yml                              # xcodegen config
├── SpaceRenamer.xcodeproj/                  # generated
├── SpaceRenamer/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── Info.plist
│   ├── Core/
│   │   ├── SpacesPlistParser.swift          # pure plist → [(uuid, ordinal)]
│   │   ├── SpaceMonitor.swift               # parser + NSWorkspace notif
│   │   ├── NameStore.swift                  # UserDefaults wrapper
│   │   ├── KeystrokeSynthesizer.swift       # protocol + CGEvent impl
│   │   ├── SwitcherEngine.swift             # UUID → Ctrl+N
│   │   ├── HotkeyManager.swift              # KeyboardShortcuts wrapper
│   │   └── SystemShortcutChecker.swift      # detects if Mission Control shortcuts enabled
│   ├── UI/
│   │   ├── MenuBarController.swift          # NSStatusItem + NSMenu
│   │   ├── PreferencesWindowController.swift
│   │   └── LaunchAtLogin.swift              # SMAppService wrapper
│   └── Resources/
│       └── Assets.xcassets/
└── SpaceRenamerTests/
    ├── NameStoreTests.swift
    ├── SpacesPlistParserTests.swift
    ├── SwitcherEngineTests.swift
    └── Fixtures/
        ├── spaces-1.plist
        ├── spaces-3.plist
        ├── spaces-9.plist
        └── spaces-reordered.plist
```

---

## Task 1: Project Scaffolding via xcodegen

**Files:**
- Create: `project.yml`
- Create: `SpaceRenamer/App/Info.plist`
- Create: `SpaceRenamer/Resources/Assets.xcassets/Contents.json`
- Create: `.gitignore`

- [ ] **Step 1: Install xcodegen if absent**

```bash
which xcodegen || brew install xcodegen
```

Expected: prints a path or installs the binary.

- [ ] **Step 2: Write `.gitignore`**

```
.DS_Store
build/
DerivedData/
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
xcuserdata/
Package.resolved
.swiftpm/
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
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0

targets:
  SpaceRenamer:
    type: application
    platform: macOS
    sources:
      - path: SpaceRenamer
    resources:
      - SpaceRenamer/Resources/Assets.xcassets
    info:
      path: SpaceRenamer/App/Info.plist
      properties:
        CFBundleName: Space Renamer
        CFBundleDisplayName: Space Renamer
        LSUIElement: true
        NSHumanReadableCopyright: ""
        NSSupportsAutomaticTermination: false
        NSSupportsSuddenTermination: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.saint.SpaceRenamer
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.9"
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
    dependencies:
      - package: KeyboardShortcuts

  SpaceRenamerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SpaceRenamerTests
    dependencies:
      - target: SpaceRenamer
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.9"
```

- [ ] **Step 4: Create stub Info.plist**

`SpaceRenamer/App/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

(xcodegen fills in the actual keys from `project.yml`.)

- [ ] **Step 5: Create stub Assets.xcassets**

`SpaceRenamer/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 6: Generate the Xcode project**

```bash
cd /Users/saint/projects/rnd
xcodegen generate
```

Expected: prints `Generated project successfully`. Creates `SpaceRenamer.xcodeproj/`.

- [ ] **Step 7: Verify build works (will fail — no Swift sources yet, that's OK)**

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: fails with "no Swift source files" or similar. The project itself is valid.

- [ ] **Step 8: Commit**

```bash
git add .gitignore project.yml SpaceRenamer/
git commit -m "chore: scaffold Xcode project with xcodegen and KeyboardShortcuts dep"
```

---

## Task 2: Minimal AppDelegate That Builds and Launches

**Files:**
- Create: `SpaceRenamer/App/AppDelegate.swift`

- [ ] **Step 1: Write the AppDelegate**

```swift
import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Components wired in later tasks.
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
```

- [ ] **Step 2: Regenerate Xcode project (picks up new file)**

```bash
xcodegen generate
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Launch and verify it stays running (LSUIElement = no Dock icon)**

```bash
APP="$(xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{d=$2}/WRAPPER_NAME/{w=$2}END{print d"/"w}')"
open "$APP"
sleep 2
pgrep -x SpaceRenamer && echo "RUNNING"
```

Expected: prints a PID and `RUNNING`. No Dock icon should appear.

- [ ] **Step 5: Quit the app**

```bash
pkill -x SpaceRenamer
```

- [ ] **Step 6: Commit**

```bash
git add SpaceRenamer/App/AppDelegate.swift
git commit -m "feat: minimal AppDelegate, accessory-app launch verified"
```

---

## Task 3: NameStore — Test-Drive UserDefaults Wrapper

**Files:**
- Create: `SpaceRenamer/Core/NameStore.swift`
- Create: `SpaceRenamerTests/NameStoreTests.swift`

`NameStore`'s job: persist Space-UUID→custom-name and a mapping from Space-UUID to the `KeyboardShortcuts.Name` it's registered under. Also remember whether we've shown the "Mission Control shortcuts disabled" warning.

- [ ] **Step 1: Write failing test file**

```swift
// SpaceRenamerTests/NameStoreTests.swift
import XCTest
@testable import SpaceRenamer

final class NameStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: NameStore!

    override func setUp() {
        super.setUp()
        let suiteName = "NameStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = NameStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
        super.tearDown()
    }

    func test_unknownUUID_returnsDefaultNameUsingOrdinal() {
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 3), "Desktop 3")
    }

    func test_setName_persists() {
        store.setName("uuid-abc", "Research")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 1), "Research")
    }

    func test_setName_emptyString_revertsToDefault() {
        store.setName("uuid-abc", "Research")
        store.setName("uuid-abc", "")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 2), "Desktop 2")
    }

    func test_forget_removesName() {
        store.setName("uuid-abc", "Research")
        store.forget("uuid-abc")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 5), "Desktop 5")
    }

    func test_namesSurviveStoreReconstruction() {
        store.setName("uuid-abc", "Research")
        let reborn = NameStore(defaults: defaults)
        XCTAssertEqual(reborn.name(for: "uuid-abc", defaultOrdinal: 1), "Research")
    }

    func test_systemShortcutsWarningFlag_defaultsFalse_thenPersists() {
        XCTAssertFalse(store.didWarnAboutSystemShortcuts)
        store.didWarnAboutSystemShortcuts = true
        let reborn = NameStore(defaults: defaults)
        XCTAssertTrue(reborn.didWarnAboutSystemShortcuts)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail (no NameStore yet)**

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: build failure, `cannot find 'NameStore' in scope`.

- [ ] **Step 3: Write NameStore**

```swift
// SpaceRenamer/Core/NameStore.swift
import Foundation

final class NameStore {
    private let defaults: UserDefaults

    private enum Key {
        static let names = "SpaceRenamer.names"               // [UUID: String]
        static let warned = "SpaceRenamer.didWarnSystemShortcuts"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var names: [String: String] {
        get { (defaults.dictionary(forKey: Key.names) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.names) }
    }

    func name(for uuid: String, defaultOrdinal: Int) -> String {
        if let custom = names[uuid], !custom.isEmpty { return custom }
        return "Desktop \(defaultOrdinal)"
    }

    func setName(_ uuid: String, _ name: String) {
        var dict = names
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: uuid)
        } else {
            dict[uuid] = trimmed
        }
        names = dict
    }

    func forget(_ uuid: String) {
        var dict = names
        dict.removeValue(forKey: uuid)
        names = dict
    }

    var didWarnAboutSystemShortcuts: Bool {
        get { defaults.bool(forKey: Key.warned) }
        set { defaults.set(newValue, forKey: Key.warned) }
    }
}
```

- [ ] **Step 4: Regenerate project and run tests — verify they pass**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `Test Suite 'NameStoreTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add SpaceRenamer/Core/NameStore.swift SpaceRenamerTests/NameStoreTests.swift
git commit -m "feat: NameStore with UserDefaults-backed UUID→name + warning flag"
```

---

## Task 4: Capture Real Plist Fixtures

The plist parser is pure but we need real data to validate it against, since `com.apple.spaces.plist` schema is undocumented and varies slightly across macOS versions.

**Files:**
- Create: `SpaceRenamerTests/Fixtures/spaces-current.plist` (copy of user's actual current plist)
- Create: `SpaceRenamerTests/Fixtures/README.md`

- [ ] **Step 1: Copy current plist as XML**

```bash
mkdir -p SpaceRenamerTests/Fixtures
plutil -convert xml1 -o SpaceRenamerTests/Fixtures/spaces-current.plist ~/Library/Preferences/com.apple.spaces.plist
```

Expected: file created. Inspect it:

```bash
head -80 SpaceRenamerTests/Fixtures/spaces-current.plist
```

You should see a `SpacesDisplayConfiguration` → `Management Data` → `Monitors` array with each Monitor containing `Display Identifier`, `Spaces` (array of dicts with `uuid` keys), and `Current Space` (dict with a `uuid`).

- [ ] **Step 2: Sanitize — replace personal identifiers**

Open `spaces-current.plist` and replace:
- Any display identifier matching a serial number with `Main`.
- Each Space UUID with `uuid-1`, `uuid-2`, ... in document order.
- Save.

- [ ] **Step 3: Generate additional fixtures**

Manually create three more fixtures by duplicating and editing `spaces-current.plist`:

- `spaces-1.plist` — Monitors[0].Spaces has exactly 1 entry (`uuid-1`), Current Space `uuid-1`.
- `spaces-3.plist` — three entries (`uuid-1`, `uuid-2`, `uuid-3`), Current Space `uuid-2`.
- `spaces-9.plist` — nine entries (`uuid-1` … `uuid-9`), Current Space `uuid-5`.
- `spaces-reordered.plist` — same UUIDs as `spaces-3.plist` but in order `uuid-3`, `uuid-1`, `uuid-2`, Current Space `uuid-1`.

- [ ] **Step 4: Write Fixtures/README.md**

```markdown
# Plist Fixtures

Sanitized copies of `com.apple.spaces.plist` representing common Space configurations.

- `spaces-current.plist` — sanitized copy of dev's current plist (reference).
- `spaces-1.plist` — single Space.
- `spaces-3.plist` — three Spaces, active = middle.
- `spaces-9.plist` — nine Spaces, active = 5th.
- `spaces-reordered.plist` — three Spaces reordered relative to `spaces-3`, active = uuid-1.

All Space UUIDs are dummy values (`uuid-1` … `uuid-N`).
```

- [ ] **Step 5: Add fixtures to the test bundle**

Edit `project.yml`, in the `SpaceRenamerTests` target add:

```yaml
    resources:
      - SpaceRenamerTests/Fixtures
```

Full updated `SpaceRenamerTests` block:

```yaml
  SpaceRenamerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: SpaceRenamerTests
    resources:
      - SpaceRenamerTests/Fixtures
    dependencies:
      - target: SpaceRenamer
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.9"
```

Regenerate:

```bash
xcodegen generate
```

- [ ] **Step 6: Commit**

```bash
git add SpaceRenamerTests/Fixtures project.yml
git commit -m "test: add sanitized spaces.plist fixtures"
```

---

## Task 5: SpacesPlistParser — Test-Drive Pure Parser

**Files:**
- Create: `SpaceRenamer/Core/SpacesPlistParser.swift`
- Create: `SpaceRenamerTests/SpacesPlistParserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// SpaceRenamerTests/SpacesPlistParserTests.swift
import XCTest
@testable import SpaceRenamer

final class SpacesPlistParserTests: XCTestCase {

    private func loadFixture(_ name: String) -> [String: Any] {
        let url = Bundle(for: SpacesPlistParserTests.self).url(forResource: name, withExtension: "plist")!
        let data = try! Data(contentsOf: url)
        return try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    }

    func test_singleSpace_isParsed() throws {
        let result = try SpacesPlistParser.parse(loadFixture("spaces-1"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-1"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1])
        XCTAssertEqual(result.activeUUID, "uuid-1")
    }

    func test_threeSpaces_activeIsMiddle() throws {
        let result = try SpacesPlistParser.parse(loadFixture("spaces-3"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-1", "uuid-2", "uuid-3"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeUUID, "uuid-2")
    }

    func test_nineSpaces_fifthActive() throws {
        let result = try SpacesPlistParser.parse(loadFixture("spaces-9"))
        XCTAssertEqual(result.spaces.count, 9)
        XCTAssertEqual(result.activeUUID, "uuid-5")
    }

    func test_reorderedSpaces_ordinalsReflectNewOrder() throws {
        let result = try SpacesPlistParser.parse(loadFixture("spaces-reordered"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-3", "uuid-1", "uuid-2"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeUUID, "uuid-1")
    }

    func test_emptyPlist_throws() {
        XCTAssertThrowsError(try SpacesPlistParser.parse([:]))
    }

    func test_missingMonitors_throws() {
        let bad: [String: Any] = ["SpacesDisplayConfiguration": ["Management Data": [String: Any]()]]
        XCTAssertThrowsError(try SpacesPlistParser.parse(bad))
    }
}
```

- [ ] **Step 2: Run tests — verify they fail (no parser yet)**

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `cannot find 'SpacesPlistParser' in scope`.

- [ ] **Step 3: Write the parser**

```swift
// SpaceRenamer/Core/SpacesPlistParser.swift
import Foundation

struct ParsedSpace: Equatable {
    let uuid: String
    let ordinal: Int  // 1-based
}

struct ParsedSpaces: Equatable {
    let spaces: [ParsedSpace]
    let activeUUID: String?
}

enum SpacesPlistError: Error, Equatable {
    case missingConfiguration
    case noMonitors
    case malformedSpaceEntry
}

enum SpacesPlistParser {

    static func parse(_ plist: [String: Any]) throws -> ParsedSpaces {
        guard let config = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = config["Management Data"] as? [String: Any] else {
            throw SpacesPlistError.missingConfiguration
        }
        guard let monitors = managementData["Monitors"] as? [[String: Any]],
              let primary = monitors.first else {
            throw SpacesPlistError.noMonitors
        }
        let spacesArray = (primary["Spaces"] as? [[String: Any]]) ?? []
        let parsed: [ParsedSpace] = try spacesArray.enumerated().map { idx, dict in
            guard let uuid = dict["uuid"] as? String else {
                throw SpacesPlistError.malformedSpaceEntry
            }
            return ParsedSpace(uuid: uuid, ordinal: idx + 1)
        }
        let activeUUID = (primary["Current Space"] as? [String: Any])?["uuid"] as? String
        return ParsedSpaces(spaces: parsed, activeUUID: activeUUID)
    }
}
```

- [ ] **Step 4: Regenerate and run tests — verify pass**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' test 2>&1 | tail -15
```

Expected: `Test Suite 'SpacesPlistParserTests' passed` with 6 tests.

- [ ] **Step 5: Commit**

```bash
git add SpaceRenamer/Core/SpacesPlistParser.swift SpaceRenamerTests/SpacesPlistParserTests.swift
git commit -m "feat: pure plist parser for spaces.plist"
```

---

## Task 6: SpaceMonitor — Live Reader + NSWorkspace Listener

**Files:**
- Create: `SpaceRenamer/Core/SpaceMonitor.swift`

This thin layer ties the parser to the real file + the `activeSpaceDidChangeNotification`. It's hard to unit-test (depends on a real `~/Library/Preferences` file and live workspace), so we validate via manual smoke checks.

- [ ] **Step 1: Write SpaceMonitor**

```swift
// SpaceRenamer/Core/SpaceMonitor.swift
import AppKit
import Combine

final class SpaceMonitor {
    @Published private(set) var spaces: [ParsedSpace] = []
    @Published private(set) var activeUUID: String?

    private let plistURL: URL
    private var observer: NSObjectProtocol?

    init(plistURL: URL? = nil) {
        self.plistURL = plistURL
            ?? FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
        reload()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Reread the plist and republish.
    func reload() {
        CFPreferencesAppSynchronize("com.apple.spaces" as CFString)
        do {
            let data = try Data(contentsOf: plistURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] ?? [:]
            let parsed = try SpacesPlistParser.parse(plist)
            self.spaces = parsed.spaces
            self.activeUUID = parsed.activeUUID
        } catch {
            NSLog("SpaceMonitor: failed to read plist: \(error)")
        }
    }

    func ordinal(for uuid: String) -> Int? {
        spaces.first(where: { $0.uuid == uuid })?.ordinal
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual smoke check via a temporary debug print**

Edit `AppDelegate.swift` temporarily:

```swift
import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: SpaceMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let m = SpaceMonitor()
        monitor = m
        NSLog("Active UUID: \(m.activeUUID ?? "nil")")
        NSLog("Spaces: \(m.spaces)")
    }
}
```

Build and run:

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
APP="$(xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{d=$2}/WRAPPER_NAME/{w=$2}END{print d"/"w}')"
"$APP/Contents/MacOS/SpaceRenamer" &
sleep 2
pkill -x SpaceRenamer
```

Expected: NSLog output prints actual Space UUIDs and an active UUID matching whichever Space was active.

- [ ] **Step 4: Revert AppDelegate to minimal form**

```swift
// SpaceRenamer/App/AppDelegate.swift
import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {}
    func applicationWillTerminate(_ notification: Notification) {}
}
```

- [ ] **Step 5: Commit**

```bash
git add SpaceRenamer/Core/SpaceMonitor.swift SpaceRenamer/App/AppDelegate.swift
git commit -m "feat: SpaceMonitor wraps plist parser + NSWorkspace notif"
```

---

## Task 7: KeystrokeSynthesizer — Protocol + Real Impl

**Files:**
- Create: `SpaceRenamer/Core/KeystrokeSynthesizer.swift`

Tiny abstraction so `SwitcherEngine` can be tested.

- [ ] **Step 1: Write the file**

```swift
// SpaceRenamer/Core/KeystrokeSynthesizer.swift
import Foundation
import CoreGraphics

protocol KeystrokeSynthesizing {
    /// Posts a Ctrl + <digit> keystroke (1...9).
    /// Throws if `digit` is out of range.
    func postControlDigit(_ digit: Int) throws
}

enum KeystrokeError: Error {
    case digitOutOfRange
    case eventSourceUnavailable
}

struct CGKeystrokeSynthesizer: KeystrokeSynthesizing {
    func postControlDigit(_ digit: Int) throws {
        guard (1...9).contains(digit) else { throw KeystrokeError.digitOutOfRange }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw KeystrokeError.eventSourceUnavailable
        }
        // Virtual key codes for digits 1..9 on US layout: 18, 19, 20, 21, 23, 22, 26, 28, 25.
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
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SpaceRenamer/Core/KeystrokeSynthesizer.swift
git commit -m "feat: KeystrokeSynthesizer protocol and CGEvent implementation"
```

---

## Task 8: SwitcherEngine — UUID → Ctrl+N

**Files:**
- Create: `SpaceRenamer/Core/SwitcherEngine.swift`
- Create: `SpaceRenamerTests/SwitcherEngineTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// SpaceRenamerTests/SwitcherEngineTests.swift
import XCTest
@testable import SpaceRenamer

final class SwitcherEngineTests: XCTestCase {

    private final class FakeSynthesizer: KeystrokeSynthesizing {
        var posted: [Int] = []
        func postControlDigit(_ digit: Int) throws {
            posted.append(digit)
        }
    }

    private final class FakeOrdinalLookup: OrdinalLookup {
        var table: [String: Int] = [:]
        func ordinal(for uuid: String) -> Int? { table[uuid] }
    }

    func test_switch_postsCtrlDigitForKnownUUID() throws {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        lookup.table = ["uuid-a": 1, "uuid-b": 3]
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)

        try engine.switch(to: "uuid-b")

        XCTAssertEqual(synth.posted, [3])
    }

    func test_switch_unknownUUID_throws() {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)
        XCTAssertThrowsError(try engine.switch(to: "uuid-missing")) { err in
            XCTAssertEqual(err as? SwitcherError, .unknownSpace)
        }
        XCTAssertTrue(synth.posted.isEmpty)
    }

    func test_switch_ordinalOver9_throws() {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        lookup.table = ["uuid-a": 10]
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)
        XCTAssertThrowsError(try engine.switch(to: "uuid-a")) { err in
            XCTAssertEqual(err as? SwitcherError, .ordinalOutOfRange)
        }
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `cannot find type 'SwitcherEngine'`.

- [ ] **Step 3: Write SwitcherEngine and OrdinalLookup**

```swift
// SpaceRenamer/Core/SwitcherEngine.swift
import Foundation

protocol OrdinalLookup: AnyObject {
    func ordinal(for uuid: String) -> Int?
}

extension SpaceMonitor: OrdinalLookup {}

enum SwitcherError: Error, Equatable {
    case unknownSpace
    case ordinalOutOfRange
}

final class SwitcherEngine {
    private let synthesizer: KeystrokeSynthesizing
    private weak var lookup: OrdinalLookup?

    init(synthesizer: KeystrokeSynthesizing = CGKeystrokeSynthesizer(),
         lookup: OrdinalLookup) {
        self.synthesizer = synthesizer
        self.lookup = lookup
    }

    func `switch`(to uuid: String) throws {
        guard let lookup else { throw SwitcherError.unknownSpace }
        guard let ordinal = lookup.ordinal(for: uuid) else { throw SwitcherError.unknownSpace }
        guard (1...9).contains(ordinal) else { throw SwitcherError.ordinalOutOfRange }
        try synthesizer.postControlDigit(ordinal)
    }
}
```

- [ ] **Step 4: Regenerate and run tests — verify pass**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `Test Suite 'SwitcherEngineTests' passed` with 3 tests.

- [ ] **Step 5: Commit**

```bash
git add SpaceRenamer/Core/SwitcherEngine.swift SpaceRenamerTests/SwitcherEngineTests.swift
git commit -m "feat: SwitcherEngine resolves UUID to Ctrl+N keystroke"
```

---

## Task 9: HotkeyManager — KeyboardShortcuts Wrapper

**Files:**
- Create: `SpaceRenamer/Core/HotkeyManager.swift`

The `KeyboardShortcuts` package lets us define named shortcuts at runtime. For each Space UUID we'll allocate a `KeyboardShortcuts.Name("space.\(uuid)")`. A single Name `"openMenu"` handles the open-menu hotkey.

- [ ] **Step 1: Write HotkeyManager**

```swift
// SpaceRenamer/Core/HotkeyManager.swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openMenu = Self("openMenu")
    static func space(_ uuid: String) -> Self { Self("space.\(uuid)") }
}

final class HotkeyManager {
    /// Callback fired when a Space's hotkey is pressed. Argument is the Space UUID.
    var onSpaceHotkey: ((String) -> Void)?
    /// Callback fired when the open-menu hotkey is pressed.
    var onOpenMenu: (() -> Void)?

    private var registeredUUIDs: Set<String> = []

    init() {
        KeyboardShortcuts.onKeyUp(for: .openMenu) { [weak self] in
            self?.onOpenMenu?()
        }
    }

    /// Ensure each currently-known UUID has its keyUp handler registered.
    /// Safe to call repeatedly; registration is idempotent per UUID.
    func sync(knownUUIDs: [String]) {
        for uuid in knownUUIDs where !registeredUUIDs.contains(uuid) {
            let name = KeyboardShortcuts.Name.space(uuid)
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                self?.onSpaceHotkey?(uuid)
            }
            registeredUUIDs.insert(uuid)
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED` (KeyboardShortcuts package resolves on first build).

- [ ] **Step 3: Commit**

```bash
git add SpaceRenamer/Core/HotkeyManager.swift
git commit -m "feat: HotkeyManager wraps KeyboardShortcuts for per-Space + open-menu"
```

---

## Task 10: SystemShortcutChecker — Detect Mission Control Shortcuts

**Files:**
- Create: `SpaceRenamer/Core/SystemShortcutChecker.swift`

Reads `com.apple.symbolichotkeys` and checks that the "Switch to Desktop N" shortcuts (symbolic hotkey IDs 118..126) are enabled.

- [ ] **Step 1: Write the checker**

```swift
// SpaceRenamer/Core/SystemShortcutChecker.swift
import Foundation

enum SystemShortcutChecker {
    /// Returns true if at least one "Switch to Desktop N" symbolic hotkey is enabled.
    /// IDs 118..126 = Switch to Desktop 1..9.
    static func switchToDesktopShortcutsEnabled() -> Bool {
        guard let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any] else {
            // Default state: shortcuts are enabled on a fresh install.
            return true
        }
        for id in 118...126 {
            if let entry = raw[String(id)] as? [String: Any],
               let enabled = entry["enabled"] as? Bool,
               enabled {
                return true
            }
        }
        // None of the entries were present-and-enabled. On most systems an
        // absent entry means default-enabled, so also treat "no entries at all"
        // as enabled to avoid false negatives.
        let anyEntry = (118...126).contains { raw[String($0)] != nil }
        return !anyEntry
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SpaceRenamer/Core/SystemShortcutChecker.swift
git commit -m "feat: detect whether Mission Control Switch-to-Desktop shortcuts are enabled"
```

---

## Task 11: MenuBarController — Status Item + Menu

**Files:**
- Create: `SpaceRenamer/UI/MenuBarController.swift`

This is the visible UI. Hard to unit-test; we validate via manual smoke.

- [ ] **Step 1: Write MenuBarController**

```swift
// SpaceRenamer/UI/MenuBarController.swift
import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: SpaceMonitor
    private let names: NameStore
    private let switcher: SwitcherEngine
    private let openPreferences: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private weak var rightClickTargetItem: NSMenuItem?

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

        // React to space changes.
        monitor.$spaces.combineLatest(monitor.$activeUUID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.rebuild() }
            .store(in: &cancellables)
        rebuild()
    }

    func openMenu() {
        statusItem.button?.performClick(nil)
    }

    private func rebuild() {
        let menu = NSMenu()
        menu.delegate = self

        for space in monitor.spaces {
            let title = names.name(for: space.uuid, defaultOrdinal: space.ordinal)
            let item = NSMenuItem(title: title, action: #selector(spaceClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = space.uuid
            if space.uuid == monitor.activeUUID {
                item.state = .on
            }
            if space.ordinal > 9 {
                item.toolTip = "Shortcut unavailable (more than 9 Spaces)"
                item.isEnabled = false
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(prefsClicked), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let quit = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu

        // Bar title reflects the active Space.
        if let activeUUID = monitor.activeUUID,
           let active = monitor.spaces.first(where: { $0.uuid == activeUUID }) {
            statusItem.button?.title = names.name(for: active.uuid, defaultOrdinal: active.ordinal)
        } else {
            statusItem.button?.title = "Desktop"
        }
    }

    @objc private func spaceClicked(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        do {
            try switcher.switch(to: uuid)
        } catch {
            NSLog("Switch failed: \(error)")
        }
    }

    @objc private func prefsClicked() {
        openPreferences()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add SpaceRenamer/UI/MenuBarController.swift
git commit -m "feat: MenuBarController renders status item and menu"
```

---

## Task 12: Wire Everything in AppDelegate

**Files:**
- Modify: `SpaceRenamer/App/AppDelegate.swift`

- [ ] **Step 1: Replace AppDelegate**

```swift
// SpaceRenamer/App/AppDelegate.swift
import Cocoa
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: SpaceMonitor!
    private var names: NameStore!
    private var switcher: SwitcherEngine!
    private var hotkeys: HotkeyManager!
    private var menuBar: MenuBarController!
    private var prefsController: PreferencesWindowController?
    private var spaceObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        names = NameStore()
        monitor = SpaceMonitor()
        switcher = SwitcherEngine(lookup: monitor)
        hotkeys = HotkeyManager()

        menuBar = MenuBarController(
            monitor: monitor,
            names: names,
            switcher: switcher,
            openPreferences: { [weak self] in self?.showPreferences() }
        )

        hotkeys.onSpaceHotkey = { [weak self] uuid in
            try? self?.switcher.switch(to: uuid)
        }
        hotkeys.onOpenMenu = { [weak self] in
            self?.menuBar.openMenu()
        }

        // Keep HotkeyManager registrations in sync with the current Space set.
        spaceObserver = monitor.$spaces.sink { [weak self] spaces in
            self?.hotkeys.sync(knownUUIDs: spaces.map { $0.uuid })
        }

        warnIfMissionControlShortcutsDisabled()
    }

    func applicationWillTerminate(_ notification: Notification) {}

    private func showPreferences() {
        if prefsController == nil {
            prefsController = PreferencesWindowController(
                monitor: monitor,
                names: names
            )
        }
        prefsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func warnIfMissionControlShortcutsDisabled() {
        guard !names.didWarnAboutSystemShortcuts else { return }
        guard !SystemShortcutChecker.switchToDesktopShortcutsEnabled() else { return }
        names.didWarnAboutSystemShortcuts = true

        let alert = NSAlert()
        alert.messageText = "Enable Mission Control shortcuts"
        alert.informativeText = "Space Renamer needs the “Switch to Desktop N” keyboard shortcuts to be enabled in System Settings → Keyboard → Shortcuts → Mission Control. Without them, clicking a desktop in the menu won't switch Spaces."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate; build will fail because `PreferencesWindowController` doesn't exist yet**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: error `cannot find 'PreferencesWindowController' in scope` — we'll add it in Task 14.

- [ ] **Step 3: Commit (intentional broken state, fixed in Task 14)**

Actually do NOT commit a broken build. Defer the commit until Task 14 builds successfully.

---

## Task 13: Inline Rename via NSAlert (right-click)

**Files:**
- Modify: `SpaceRenamer/UI/MenuBarController.swift`

`NSMenu` doesn't have a native right-click on items. The conventional approach for menu-bar apps is **option-click** (or modifier-click) for rename, since right-click on a status item itself opens a separate menu. We'll use option-click on a row to open the rename dialog. Add a small hint as the menu's title row.

- [ ] **Step 1: Augment MenuBarController**

Two edits to `MenuBarController.swift`:

**Edit A** — inside `rebuild()`, replace the existing `for space in monitor.spaces { ... menu.addItem(item) }` loop with the version below. (Adds an alternate menu item per row that appears when ⌥ is held.)

```swift
        for space in monitor.spaces {
            let title = names.name(for: space.uuid, defaultOrdinal: space.ordinal)
            let item = NSMenuItem(title: title, action: #selector(spaceClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = space.uuid
            if space.uuid == monitor.activeUUID {
                item.state = .on
            }
            if space.ordinal > 9 {
                item.toolTip = "Shortcut unavailable (more than 9 Spaces)"
                item.isEnabled = false
            }
            menu.addItem(item)

            // Alternate item shown when ⌥ is held — same row, different action.
            let renameAlt = NSMenuItem(title: "Rename “\(title)”…",
                                       action: #selector(renameClicked(_:)),
                                       keyEquivalent: "")
            renameAlt.target = self
            renameAlt.representedObject = space.uuid
            renameAlt.keyEquivalentModifierMask = .option
            renameAlt.isAlternate = true
            menu.addItem(renameAlt)
        }
```

**Edit B** — add this action method anywhere inside the `MenuBarController` class (e.g., just below `spaceClicked(_:)`):

```swift
    @objc private func renameClicked(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String,
              let space = monitor.spaces.first(where: { $0.uuid == uuid }) else { return }
        let current = names.name(for: uuid, defaultOrdinal: space.ordinal)

        let alert = NSAlert()
        alert.messageText = "Rename Desktop"
        alert.informativeText = "Enter a new name for this Space. Leave blank to revert to “Desktop \(space.ordinal)”."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            names.setName(uuid, field.stringValue)
            // NameStore changes don't fire Combine; rebuild explicitly.
            rebuild()
        }
    }
```

- [ ] **Step 2: Regenerate; still won't build until Task 14**

```bash
xcodegen generate
```

- [ ] **Step 3: No commit yet — chained with next task**

---

## Task 14: PreferencesWindowController + LaunchAtLogin

**Files:**
- Create: `SpaceRenamer/UI/PreferencesWindowController.swift`
- Create: `SpaceRenamer/UI/LaunchAtLogin.swift`

- [ ] **Step 1: Write LaunchAtLogin wrapper**

```swift
// SpaceRenamer/UI/LaunchAtLogin.swift
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("LaunchAtLogin toggle failed: \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: Write PreferencesWindowController**

```swift
// SpaceRenamer/UI/PreferencesWindowController.swift
import AppKit
import KeyboardShortcuts
import Combine

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private let monitor: SpaceMonitor
    private let names: NameStore
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let openMenuRecorder = KeyboardShortcuts.RecorderCocoa(for: .openMenu)
    private var cancellables: Set<AnyCancellable> = []

    init(monitor: SpaceMonitor, names: NameStore) {
        self.monitor = monitor
        self.names = names

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Space Renamer Preferences"
        super.init(window: window)

        setupContent()
        monitor.$spaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.table.reloadData() }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let openMenuLabel = NSTextField(labelWithString: "Open menu hotkey:")
        let launchAtLogin = NSButton(checkboxWithTitle: "Launch at Login",
                                     target: self,
                                     action: #selector(toggleLaunchAtLogin(_:)))
        launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off

        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = "Desktop"
        nameColumn.width = 200

        let hotkeyColumn = NSTableColumn(identifier: .init("hotkey"))
        hotkeyColumn.title = "Hotkey"
        hotkeyColumn.width = 220

        table.addTableColumn(nameColumn)
        table.addTableColumn(hotkeyColumn)
        table.dataSource = self
        table.delegate = self
        table.headerView = NSTableHeaderView()
        table.rowHeight = 32

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let stack = NSStackView(views: [openMenuLabel, openMenuRecorder, scroll, launchAtLogin])
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
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            scroll.widthAnchor.constraint(equalToConstant: 420)
        ])
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        LaunchAtLogin.isEnabled = (sender.state == .on)
    }

    // MARK: NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int { monitor.spaces.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let space = monitor.spaces[row]
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        switch id {
        case "name":
            let name = names.name(for: space.uuid, defaultOrdinal: space.ordinal)
            let cell = NSTextField(labelWithString: name)
            return cell
        case "hotkey":
            let recorder = KeyboardShortcuts.RecorderCocoa(for: .space(space.uuid))
            return recorder
        default:
            return nil
        }
    }
}
```

- [ ] **Step 3: Regenerate, build, and run**

```bash
xcodegen generate
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit the chain from Tasks 12 + 13 + 14**

```bash
git add SpaceRenamer/App/AppDelegate.swift \
        SpaceRenamer/UI/MenuBarController.swift \
        SpaceRenamer/UI/PreferencesWindowController.swift \
        SpaceRenamer/UI/LaunchAtLogin.swift
git commit -m "feat: wire app — AppDelegate, inline rename, Preferences window, LaunchAtLogin"
```

---

## Task 15: Manual Smoke Test — End-to-End Pass

This is a manual checklist. Run through each item; if any fails, fix and re-run.

- [ ] **Step 1: Build a Release product**

```bash
xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2: Run it**

```bash
APP="$(xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer -configuration Release -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{d=$2}/WRAPPER_NAME/{w=$2}END{print d"/"w}')"
open "$APP"
```

- [ ] **Step 3: Walk the checklist**

For each item, mark pass/fail in this list (edit the plan file inline):

1. [ ] Menu bar shows the active Space's name (e.g. "Desktop 1").
2. [ ] Clicking the menu bar item drops down a menu listing all Spaces.
3. [ ] The active Space has a checkmark.
4. [ ] Option-clicking a Space row opens a rename dialog.
5. [ ] After renaming Desktop 2 to "Research", the menu shows "Research" and the bar title updates if active.
6. [ ] Quit and relaunch — "Research" name persists.
7. [ ] Click a different Space row — screen switches to that Space.
8. [ ] Add a new Space in Mission Control — menu auto-adds it on next open.
9. [ ] Reorder Spaces in Mission Control — names still attached to original Spaces (UUID tracking).
10. [ ] Open Preferences → assign `⌃⌥D` to "Research" — press from any app — switches.
11. [ ] Open Preferences → assign `⌃⌥M` to "Open menu" — press from any app — menu opens.
12. [ ] Enable "Launch at Login" in Preferences — `osascript -e 'tell application "System Events" to get every login item'` includes Space Renamer (or check `SMAppService.mainApp.status` in a debugger).
13. [ ] Disable Mission Control "Switch to Desktop N" shortcuts in System Settings → relaunch → see one-shot alert; choose "Open Keyboard Settings" — Settings opens to the right pane.
14. [ ] With Accessibility permission denied (System Settings → Privacy & Security → Accessibility), clicking a Space silently fails — `Console.app` shows the `Switch failed` log line.

- [ ] **Step 4: For any failed item, file an issue or fix and commit**

```bash
git commit -am "fix: <description of fix>"
```

- [ ] **Step 5: Tag v0.1**

```bash
git tag v0.1.0
```

- [ ] **Step 6: Final commit of plan annotations**

```bash
git add docs/superpowers/plans/2026-05-15-space-renamer.md
git commit -m "chore: mark smoke-test checklist passed for v0.1"
```

---

## Self-Review Notes

The following spec items map to the listed tasks:

| Spec section | Implemented in |
|---|---|
| Goal: active name in menu bar | Task 11 (`MenuBarController.rebuild` sets `statusItem.button.title`) |
| Goal: menu of named Spaces, click-to-switch | Tasks 11, 12 |
| Goal: per-Space + open-menu hotkeys | Tasks 9, 12, 14 |
| Goal: names persist across reorders | Tasks 3, 5, 6 (UUID-keyed) |
| Goal: public APIs only | Tasks 7, 8 (CGEvent), 9 (KeyboardShortcuts), 10 (SystemShortcutChecker) |
| D1 UUID identification | Task 5 |
| D2 Ctrl+N synthesis | Tasks 7, 8 |
| D3 Carbon hotkeys (via KeyboardShortcuts) | Task 9 |
| D4 Inline rename via NSAlert | Task 13 |
| D5 Preferences window for hotkey assignment | Task 14 |
| D6 Swift + AppKit | Tasks 1, 2, 11, 14 |
| D7 Bar title = active name | Task 11 |
| D8 macOS 13+ | Task 1 (deploymentTarget) |
| Edge: >9 Spaces | Task 11 (disabled menu items) |
| Edge: Ctrl+N disabled | Tasks 10, 12 |
| Edge: plist unreadable | Task 6 (logs and falls through to empty list) |
| Edge: hotkey conflict | Handled by `KeyboardShortcuts` package's built-in conflict UI |
| Edge: Accessibility denied | Task 12 launch flow + manual smoke item 14 |
| Multi-display limitation | Task 5 (parser uses `monitors.first`) |
| Launch at Login | Task 14 |
| Unit tests: NameStore, parser, SwitcherEngine | Tasks 3, 5, 8 |
| Manual smoke checklist | Task 15 |
