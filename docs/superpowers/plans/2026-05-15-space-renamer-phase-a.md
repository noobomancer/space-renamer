# Space Renamer Implementation Plan — Phase A (SwiftPM Core)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the testable core of Space Renamer as a Swift Package Manager library — `NameStore`, `SpacesPlistParser`, `SpaceMonitor`, `KeystrokeSynthesizer`, `SwitcherEngine`, `HotkeyManager`, `SystemShortcutChecker` — with unit tests for the pure components. Defer the AppKit shell (menu bar, Preferences window, AppDelegate) to Phase B.

**Why Phase A first:** The dev machine has only Command Line Tools, not Xcode.app, so we cannot build a Mac `.app` bundle yet. Pure SwiftPM only needs `swift` and lets us TDD the entire core. Phase B (the app shell) will be unblocked once Xcode is installed.

**Architecture:** Single SwiftPM library target `SpaceRenamerCore` containing six Core components (the seventh, `HotkeyManager`, is deferred to Phase B because its `KeyboardShortcuts` dependency requires full Xcode to build — `#Preview` macros in that package can't compile under Command Line Tools alone). A test target `SpaceRenamerCoreTests` covers the three pure components.

**Tech Stack:** Swift 5.10+, AppKit (for `NSWorkspace`), CoreGraphics, Combine, XCTest, macOS 13+ deployment target. **No KeyboardShortcuts dependency in Phase A** — added in Phase B with the rest of the app shell.

**Reference:** Original full plan with Phase B tasks at `docs/superpowers/plans/2026-05-15-space-renamer.md`. Design spec at `docs/superpowers/specs/2026-05-15-space-renamer-design.md`.

---

## File Structure (after Phase A)

```
rnd/
├── Package.swift
├── Sources/
│   └── SpaceRenamerCore/
│       ├── NameStore.swift
│       ├── SpacesPlistParser.swift
│       ├── SpaceMonitor.swift
│       ├── KeystrokeSynthesizer.swift
│       ├── SwitcherEngine.swift
│       └── SystemShortcutChecker.swift
└── Tests/
    └── SpaceRenamerCoreTests/
        ├── NameStoreTests.swift
        ├── SpacesPlistParserTests.swift
        ├── SwitcherEngineTests.swift
        └── Fixtures/
            ├── spaces-1.plist
            ├── spaces-3.plist
            ├── spaces-9.plist
            └── spaces-reordered.plist
```

`HotkeyManager` (Task A8 in the old numbering) is deferred to Phase B — see note on that task below.

---

## Task A1: SwiftPM Package Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/SpaceRenamerCore/Placeholder.swift` (temporary so target has at least one source)
- Create: `Tests/SpaceRenamerCoreTests/PlaceholderTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

```
.DS_Store
.build/
.swiftpm/
Package.resolved
DerivedData/
```

- [ ] **Step 2: Write `Package.swift`**

No external dependencies — KeyboardShortcuts is deferred to Phase B because its `#Preview` macros require full Xcode.

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpaceRenamerCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SpaceRenamerCore",
            targets: ["SpaceRenamerCore"]
        ),
    ],
    targets: [
        .target(
            name: "SpaceRenamerCore"
        ),
        .testTarget(
            name: "SpaceRenamerCoreTests",
            dependencies: ["SpaceRenamerCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
```

- [ ] **Step 3: Write a placeholder source so `swift build` doesn't complain about an empty target**

`Sources/SpaceRenamerCore/Placeholder.swift`:

```swift
// Temporary placeholder. Deleted in Task A2 when NameStore lands.
enum _Placeholder {}
```

- [ ] **Step 4: Write a smoke test so the test target compiles**

`Tests/SpaceRenamerCoreTests/PlaceholderTests.swift`:

```swift
import XCTest
@testable import SpaceRenamerCore

final class PlaceholderTests: XCTestCase {
    func test_packageBuilds() {
        XCTAssertNotNil(_Placeholder.self)
    }
}
```

- [ ] **Step 5: Create empty `Fixtures` directory so the resource declaration resolves**

```bash
mkdir -p Tests/SpaceRenamerCoreTests/Fixtures
touch Tests/SpaceRenamerCoreTests/Fixtures/.gitkeep
```

- [ ] **Step 6: Resolve dependencies and build**

```bash
swift package resolve 2>&1 | tail -5
swift build 2>&1 | tail -10
```

Expected: `swift package resolve` is a no-op (no deps); `swift build` succeeds with `Build complete!`.

- [ ] **Step 7: Run tests**

```bash
swift test 2>&1 | tail -10
```

Expected: `Test Suite 'PlaceholderTests' passed`, 1 test.

- [ ] **Step 8: Commit**

```bash
git add .gitignore Package.swift Sources Tests
git commit -m "chore: scaffold SwiftPM package for SpaceRenamerCore"
```

---

## Task A2: NameStore — TDD UserDefaults Wrapper

**Files:**
- Create: `Sources/SpaceRenamerCore/NameStore.swift`
- Create: `Tests/SpaceRenamerCoreTests/NameStoreTests.swift`
- Delete: `Sources/SpaceRenamerCore/Placeholder.swift`
- Delete: `Tests/SpaceRenamerCoreTests/PlaceholderTests.swift`

`NameStore` persists Space-UUID → custom-name in `UserDefaults`, plus a "did warn about system shortcuts" flag.

- [ ] **Step 1: Write the failing test file**

```swift
// Tests/SpaceRenamerCoreTests/NameStoreTests.swift
import XCTest
@testable import SpaceRenamerCore

final class NameStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: NameStore!

    override func setUp() {
        super.setUp()
        suiteName = "NameStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = NameStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
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

    func test_setName_whitespaceOnly_revertsToDefault() {
        store.setName("uuid-abc", "   ")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 4), "Desktop 4")
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

- [ ] **Step 2: Delete the placeholder files**

```bash
rm Sources/SpaceRenamerCore/Placeholder.swift
rm Tests/SpaceRenamerCoreTests/PlaceholderTests.swift
```

- [ ] **Step 3: Run tests — verify they fail (no NameStore yet)**

```bash
swift test 2>&1 | tail -10
```

Expected: build failure, `cannot find 'NameStore' in scope`.

- [ ] **Step 4: Write `NameStore`**

```swift
// Sources/SpaceRenamerCore/NameStore.swift
import Foundation

public final class NameStore {
    private let defaults: UserDefaults

    private enum Key {
        static let names = "SpaceRenamer.names"               // [UUID: String]
        static let warned = "SpaceRenamer.didWarnSystemShortcuts"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var names: [String: String] {
        get { (defaults.dictionary(forKey: Key.names) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.names) }
    }

    public func name(for uuid: String, defaultOrdinal: Int) -> String {
        if let custom = names[uuid], !custom.isEmpty { return custom }
        return "Desktop \(defaultOrdinal)"
    }

    public func setName(_ uuid: String, _ name: String) {
        var dict = names
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: uuid)
        } else {
            dict[uuid] = trimmed
        }
        names = dict
    }

    public func forget(_ uuid: String) {
        var dict = names
        dict.removeValue(forKey: uuid)
        names = dict
    }

    public var didWarnAboutSystemShortcuts: Bool {
        get { defaults.bool(forKey: Key.warned) }
        set { defaults.set(newValue, forKey: Key.warned) }
    }
}
```

- [ ] **Step 5: Run tests — verify pass**

```bash
swift test 2>&1 | tail -10
```

Expected: `Test Suite 'NameStoreTests' passed` with 7 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpaceRenamerCore/NameStore.swift \
        Tests/SpaceRenamerCoreTests/NameStoreTests.swift \
        Sources/SpaceRenamerCore/Placeholder.swift \
        Tests/SpaceRenamerCoreTests/PlaceholderTests.swift
git commit -m "feat: NameStore with UserDefaults-backed UUID→name + warning flag"
```

(`git add` of deleted files records the removal.)

---

## Task A3: Capture Real Plist Fixtures

**Files:**
- Create: `Tests/SpaceRenamerCoreTests/Fixtures/spaces-1.plist`
- Create: `Tests/SpaceRenamerCoreTests/Fixtures/spaces-3.plist`
- Create: `Tests/SpaceRenamerCoreTests/Fixtures/spaces-9.plist`
- Create: `Tests/SpaceRenamerCoreTests/Fixtures/spaces-reordered.plist`
- Create: `Tests/SpaceRenamerCoreTests/Fixtures/README.md`

- [ ] **Step 1: Copy current plist as XML for inspection**

```bash
mkdir -p Tests/SpaceRenamerCoreTests/Fixtures
plutil -convert xml1 -o /tmp/spaces-current.plist ~/Library/Preferences/com.apple.spaces.plist
```

Inspect it:

```bash
head -120 /tmp/spaces-current.plist
```

Note the schema: there should be a top-level `<key>SpacesDisplayConfiguration</key>` with nested `Management Data` → `Monitors` (array). Each monitor dict has `Display Identifier`, `Spaces` (array of Space dicts each with a `uuid` key), and `Current Space` (a dict with a `uuid` key naming the active Space).

- [ ] **Step 2: Write `spaces-1.plist` — single Space**

`Tests/SpaceRenamerCoreTests/Fixtures/spaces-1.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SpacesDisplayConfiguration</key>
  <dict>
    <key>Management Data</key>
    <dict>
      <key>Monitors</key>
      <array>
        <dict>
          <key>Display Identifier</key>
          <string>Main</string>
          <key>Spaces</key>
          <array>
            <dict>
              <key>uuid</key><string>uuid-1</string>
              <key>type</key><integer>0</integer>
            </dict>
          </array>
          <key>Current Space</key>
          <dict>
            <key>uuid</key><string>uuid-1</string>
          </dict>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
</plist>
```

- [ ] **Step 3: Write `spaces-3.plist` — three Spaces, active = middle**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SpacesDisplayConfiguration</key>
  <dict>
    <key>Management Data</key>
    <dict>
      <key>Monitors</key>
      <array>
        <dict>
          <key>Display Identifier</key>
          <string>Main</string>
          <key>Spaces</key>
          <array>
            <dict><key>uuid</key><string>uuid-1</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-2</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-3</string><key>type</key><integer>0</integer></dict>
          </array>
          <key>Current Space</key>
          <dict>
            <key>uuid</key><string>uuid-2</string>
          </dict>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
</plist>
```

- [ ] **Step 4: Write `spaces-9.plist` — nine Spaces, active = 5th**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SpacesDisplayConfiguration</key>
  <dict>
    <key>Management Data</key>
    <dict>
      <key>Monitors</key>
      <array>
        <dict>
          <key>Display Identifier</key>
          <string>Main</string>
          <key>Spaces</key>
          <array>
            <dict><key>uuid</key><string>uuid-1</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-2</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-3</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-4</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-5</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-6</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-7</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-8</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-9</string><key>type</key><integer>0</integer></dict>
          </array>
          <key>Current Space</key>
          <dict>
            <key>uuid</key><string>uuid-5</string>
          </dict>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
</plist>
```

- [ ] **Step 5: Write `spaces-reordered.plist` — same three UUIDs reordered**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SpacesDisplayConfiguration</key>
  <dict>
    <key>Management Data</key>
    <dict>
      <key>Monitors</key>
      <array>
        <dict>
          <key>Display Identifier</key>
          <string>Main</string>
          <key>Spaces</key>
          <array>
            <dict><key>uuid</key><string>uuid-3</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-1</string><key>type</key><integer>0</integer></dict>
            <dict><key>uuid</key><string>uuid-2</string><key>type</key><integer>0</integer></dict>
          </array>
          <key>Current Space</key>
          <dict>
            <key>uuid</key><string>uuid-1</string>
          </dict>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
</plist>
```

- [ ] **Step 6: Verify each fixture parses as valid plist**

```bash
for f in Tests/SpaceRenamerCoreTests/Fixtures/spaces-*.plist; do
  plutil -lint "$f" || { echo "INVALID: $f"; exit 1; }
done
```

Expected: each file reports `OK`.

- [ ] **Step 7: Write Fixtures README**

`Tests/SpaceRenamerCoreTests/Fixtures/README.md`:

```markdown
# Plist Fixtures

Synthetic XML plists matching the shape of `~/Library/Preferences/com.apple.spaces.plist`.
All Space UUIDs are dummy values (`uuid-1` … `uuid-N`).

- `spaces-1.plist` — single Space, active = uuid-1.
- `spaces-3.plist` — three Spaces, active = uuid-2 (middle).
- `spaces-9.plist` — nine Spaces, active = uuid-5.
- `spaces-reordered.plist` — same UUIDs as `spaces-3.plist` but in order `uuid-3, uuid-1, uuid-2`, active = uuid-1.

Used by `SpacesPlistParserTests`.
```

- [ ] **Step 8: Remove `.gitkeep` if present, commit**

```bash
rm -f Tests/SpaceRenamerCoreTests/Fixtures/.gitkeep
git add Tests/SpaceRenamerCoreTests/Fixtures
git commit -m "test: add synthetic spaces.plist fixtures"
```

---

## Task A4: SpacesPlistParser — TDD Pure Parser

**Files:**
- Create: `Sources/SpaceRenamerCore/SpacesPlistParser.swift`
- Create: `Tests/SpaceRenamerCoreTests/SpacesPlistParserTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SpaceRenamerCoreTests/SpacesPlistParserTests.swift
import XCTest
@testable import SpaceRenamerCore

final class SpacesPlistParserTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
    }

    func test_singleSpace_isParsed() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-1"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-1"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1])
        XCTAssertEqual(result.activeUUID, "uuid-1")
    }

    func test_threeSpaces_activeIsMiddle() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-3"))
        XCTAssertEqual(result.spaces.map { $0.uuid }, ["uuid-1", "uuid-2", "uuid-3"])
        XCTAssertEqual(result.spaces.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.activeUUID, "uuid-2")
    }

    func test_nineSpaces_fifthActive() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-9"))
        XCTAssertEqual(result.spaces.count, 9)
        XCTAssertEqual(result.activeUUID, "uuid-5")
    }

    func test_reorderedSpaces_ordinalsReflectNewOrder() throws {
        let result = try SpacesPlistParser.parse(try loadFixture("spaces-reordered"))
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

- [ ] **Step 2: Run tests — verify they fail**

```bash
swift test 2>&1 | tail -15
```

Expected: `cannot find 'SpacesPlistParser' in scope`.

- [ ] **Step 3: Write the parser**

```swift
// Sources/SpaceRenamerCore/SpacesPlistParser.swift
import Foundation

public struct ParsedSpace: Equatable {
    public let uuid: String
    public let ordinal: Int  // 1-based

    public init(uuid: String, ordinal: Int) {
        self.uuid = uuid
        self.ordinal = ordinal
    }
}

public struct ParsedSpaces: Equatable {
    public let spaces: [ParsedSpace]
    public let activeUUID: String?

    public init(spaces: [ParsedSpace], activeUUID: String?) {
        self.spaces = spaces
        self.activeUUID = activeUUID
    }
}

public enum SpacesPlistError: Error, Equatable {
    case missingConfiguration
    case noMonitors
    case malformedSpaceEntry
}

public enum SpacesPlistParser {

    public static func parse(_ plist: [String: Any]) throws -> ParsedSpaces {
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

- [ ] **Step 4: Run tests — verify pass**

```bash
swift test 2>&1 | tail -15
```

Expected: `Test Suite 'SpacesPlistParserTests' passed` with 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpaceRenamerCore/SpacesPlistParser.swift \
        Tests/SpaceRenamerCoreTests/SpacesPlistParserTests.swift
git commit -m "feat: pure plist parser for spaces.plist"
```

---

## Task A5: SpaceMonitor — Plist Reader + NSWorkspace Listener

**Files:**
- Create: `Sources/SpaceRenamerCore/SpaceMonitor.swift`

Note: this component is hard to unit-test (depends on the real plist and a live NSApplication). Verify it compiles cleanly; behavior gets exercised in Phase B's manual smoke test.

- [ ] **Step 1: Write SpaceMonitor**

```swift
// Sources/SpaceRenamerCore/SpaceMonitor.swift
import AppKit
import Combine

public final class SpaceMonitor {
    @Published public private(set) var spaces: [ParsedSpace] = []
    @Published public private(set) var activeUUID: String?

    private let plistURL: URL
    private var observer: NSObjectProtocol?

    public init(plistURL: URL? = nil) {
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

    /// Re-read the plist and republish.
    public func reload() {
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

    public func ordinal(for uuid: String) -> Int? {
        spaces.first(where: { $0.uuid == uuid })?.ordinal
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`.

- [ ] **Step 3: Run tests to confirm nothing regressed**

```bash
swift test 2>&1 | tail -10
```

Expected: all existing test suites still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/SpaceRenamerCore/SpaceMonitor.swift
git commit -m "feat: SpaceMonitor wraps plist parser + NSWorkspace notif"
```

---

## Task A6: KeystrokeSynthesizer — Protocol + CGEvent Implementation

**Files:**
- Create: `Sources/SpaceRenamerCore/KeystrokeSynthesizer.swift`

- [ ] **Step 1: Write the file**

```swift
// Sources/SpaceRenamerCore/KeystrokeSynthesizer.swift
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
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources/SpaceRenamerCore/KeystrokeSynthesizer.swift
git commit -m "feat: KeystrokeSynthesizer protocol and CGEvent implementation"
```

---

## Task A7: SwitcherEngine — TDD UUID → Ctrl+N

**Files:**
- Create: `Sources/SpaceRenamerCore/SwitcherEngine.swift`
- Create: `Tests/SpaceRenamerCoreTests/SwitcherEngineTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SpaceRenamerCoreTests/SwitcherEngineTests.swift
import XCTest
@testable import SpaceRenamerCore

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
swift test 2>&1 | tail -15
```

Expected: `cannot find type 'SwitcherEngine'`.

- [ ] **Step 3: Write SwitcherEngine + OrdinalLookup**

```swift
// Sources/SpaceRenamerCore/SwitcherEngine.swift
import Foundation

public protocol OrdinalLookup: AnyObject {
    func ordinal(for uuid: String) -> Int?
}

extension SpaceMonitor: OrdinalLookup {}

public enum SwitcherError: Error, Equatable {
    case unknownSpace
    case ordinalOutOfRange
}

public final class SwitcherEngine {
    private let synthesizer: KeystrokeSynthesizing
    private weak var lookup: OrdinalLookup?

    public init(synthesizer: KeystrokeSynthesizing = CGKeystrokeSynthesizer(),
                lookup: OrdinalLookup) {
        self.synthesizer = synthesizer
        self.lookup = lookup
    }

    public func `switch`(to uuid: String) throws {
        guard let lookup else { throw SwitcherError.unknownSpace }
        guard let ordinal = lookup.ordinal(for: uuid) else { throw SwitcherError.unknownSpace }
        guard (1...9).contains(ordinal) else { throw SwitcherError.ordinalOutOfRange }
        try synthesizer.postControlDigit(ordinal)
    }
}
```

- [ ] **Step 4: Run tests — verify pass**

```bash
swift test 2>&1 | tail -15
```

Expected: `Test Suite 'SwitcherEngineTests' passed` with 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpaceRenamerCore/SwitcherEngine.swift \
        Tests/SpaceRenamerCoreTests/SwitcherEngineTests.swift
git commit -m "feat: SwitcherEngine resolves UUID to Ctrl+N keystroke"
```

---

## Task A8: HotkeyManager — DEFERRED TO PHASE B

`HotkeyManager` depends on the KeyboardShortcuts Swift Package, which uses SwiftUI `#Preview` macros that fail to compile under Command Line Tools alone (they need the full Xcode `PreviewsMacros` plugin). Since the rest of Phase A doesn't need it and the entire UI layer is already deferred to Phase B, `HotkeyManager` ships with Phase B alongside `MenuBarController` / `PreferencesWindowController`. Skip this task; see the original full plan at `docs/superpowers/plans/2026-05-15-space-renamer.md` Task 9 for the implementation.

---

## Task A9: SystemShortcutChecker — Detect Mission Control Shortcuts

**Files:**
- Create: `Sources/SpaceRenamerCore/SystemShortcutChecker.swift`

- [ ] **Step 1: Write the checker**

```swift
// Sources/SpaceRenamerCore/SystemShortcutChecker.swift
import Foundation

public enum SystemShortcutChecker {
    /// Returns true if at least one "Switch to Desktop N" symbolic hotkey is enabled.
    /// IDs 118..126 = Switch to Desktop 1..9.
    public static func switchToDesktopShortcutsEnabled() -> Bool {
        guard let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any] else {
            // No prefs at all — defaults apply, shortcuts are enabled.
            return true
        }
        for id in 118...126 {
            if let entry = raw[String(id)] as? [String: Any],
               let enabled = entry["enabled"] as? Bool,
               enabled {
                return true
            }
        }
        // None of the entries were present-and-enabled. If no entries exist at
        // all in this range, treat as default-enabled (absent entry == default).
        let anyEntry = (118...126).contains { raw[String($0)] != nil }
        return !anyEntry
    }
}
```

- [ ] **Step 2: Build and run all tests**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -10
```

Expected: `Build complete!` and all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/SpaceRenamerCore/SystemShortcutChecker.swift
git commit -m "feat: detect whether Mission Control Switch-to-Desktop shortcuts are enabled"
```

---

## Phase A Complete

All seven Core components compile and the three pure ones (`NameStore`, `SpacesPlistParser`, `SwitcherEngine`) are covered by XCTest unit tests. The other four (`SpaceMonitor`, `KeystrokeSynthesizer`, `HotkeyManager`, `SystemShortcutChecker`) integrate with system APIs and will be exercised by Phase B's manual smoke test.

**Next:** Once Xcode is installed (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` after App Store install), pick up Phase B from `docs/superpowers/plans/2026-05-15-space-renamer.md` starting at Task 1 (xcodegen scaffold for the app target that depends on this `SpaceRenamerCore` package), Task 2 (AppDelegate), and Tasks 11–15 (UI + smoke).
