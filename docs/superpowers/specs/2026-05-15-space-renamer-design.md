# Space Renamer — Design

A macOS menu-bar app that gives Mission Control Spaces human-readable names, shows the active Space's custom name in the menu bar, lets the user switch Spaces by clicking a menu entry or pressing a global hotkey, and persists names across reorders and reboots.

## Problem

macOS Spaces are always labeled "Desktop 1", "Desktop 2", … in Mission Control, and the label cannot be changed through any public Apple API. Users who organize work across multiple Spaces (e.g. "Research", "Email", "Code") have no way to see or jump to a Space by name.

## Goals

- Show the **active Space's custom name** in the menu bar at all times.
- Present a **menu** listing every Space with its custom name; clicking a row switches to that Space.
- Support **global keyboard shortcuts** — both per-Space (jump directly) and a single one to open the menu.
- **Persist names across Space reorders** (a renamed Space stays renamed even if dragged to a different position in Mission Control).
- **No private APIs.** App must remain functional across macOS point updates without code changes.

## Non-Goals (v1)

- Renaming the label that appears *inside* Mission Control itself. (Impossible without private SkyLight APIs.)
- Per-display Space stacks when "Displays have separate Spaces" is enabled — v1 tracks the primary display only.
- Cross-Mac sync of names (iCloud / settings sync).
- App Sandbox / App Store distribution. (Reading `com.apple.spaces.plist` and registering global hotkeys are not sandbox-friendly.)

## Key Decisions

| # | Decision | Alternative considered | Why |
|---|---|---|---|
| D1 | **Identify Spaces by `ManagedSpaceID`** (the integer space id) read from `~/Library/Preferences/com.apple.spaces.plist` | Identify by `uuid` (original choice); by ordinal index (1, 2, 3…) | Names must survive Space reorders, so the key must be position-independent. The `uuid` field was the original choice but the real plist shows macOS leaves it **empty (`""`) for the default desktop** (and only assigns UUIDs to additional spaces); `ManagedSpaceID`/`id64` is non-empty, unique, and present for every space including the default and in `Current Space`. Indices are not stable across reorders. See *Design Revision 2026-05-15*. |
| D2 | **Switch Spaces by synthesizing `Ctrl+N` `CGEvent`s** (public); **detect the active Space via read-only private SkyLight `CGSCopyManagedDisplaySpaces`** | Switching: private SkyLight `CGSManagedDisplaySetCurrentSpace`. Active detection: read `Current Space` from `com.apple.spaces.plist` (original choice). | *Switching* stays public CGEvent (trade-off: user must keep "Switch to Desktop N" shortcuts enabled). *Active-Space detection* originally read the plist, but macOS does **not** update `com.apple.spaces.plist`'s `Current Space` on switch (proven on a real machine: notification fires, file unchanged, value frozen across switches) — so a read-only private SkyLight call is required to track the active Space live (user-approved). See *Design Revision 2026-05-17*. |
| D3 | **Custom global hotkeys via Carbon `RegisterEventHotKey`** | NSEvent local monitor (only works in-app), CGEventTap (more invasive, needs more permissions) | Standard pattern; works system-wide; reliable. |
| D4 | **Inline rename via right-click → `NSAlert` text-field popover** | Dedicated rename window | Lowest-friction UX; user explicitly chose minimal inline. |
| D5 | **Mini Preferences window for hotkey assignment** | Inline hotkey recording in the menu | `NSMenu` dismisses on modifier keypress, making in-menu recording unreliable. |
| D6 | **Swift + AppKit** (`NSStatusItem`, `NSMenu`, `NSAlert`, AppKit window) | SwiftUI `MenuBarExtra` | AppKit gives finer control over status-item and menu quirks; SwiftUI's menu bar API is less mature. |
| D7 | **Bar title shows the active Space's custom name** | Just an icon | User requested name; gives at-a-glance feedback even when menu is closed. |
| D8 | **macOS 13+ minimum** | Older macOS | Allows `SMAppService` for Launch-at-Login and modern Swift concurrency. |
| D9 | **`@MainActor`-isolate the stateful Core** (`NameStore`, `SpaceMonitor`, `SwitcherEngine`, `OrdinalLookup`); pure/stateless types (`SpacesPlistParser`, `KeystrokeSynthesizing`, `SystemShortcutChecker`) stay non-isolated | `os_unfair_lock`/serial-queue locking; `actor` types | App is a main-thread-driven AppKit menu-bar app. `@MainActor` compiler-enforces "`reload()` & `@Published` mutation are main-only", serializes `NameStore`'s non-atomic UserDefaults read-modify-write, and keeps Combine→AppKit observation correct — least complexity. Locks over-engineer it; `actor`s fight `@Published` + synchronous menu builds. Swift 5 language mode retained; Swift 6 strict-concurrency deferred to app-target creation. See *Design Revision 2026-05-16*. |

### Design Revision — 2026-05-15 (identity model)

The original design (and brainstorm) chose **`uuid`** as the per-Space identity key (then "Option B"). During Phase A implementation, inspection of the real `~/Library/Preferences/com.apple.spaces.plist` revealed that macOS does **not** assign a UUID to the primary/default desktop — its `uuid` is the empty string `""`, and `Current Space.uuid` is `""` whenever the default desktop is active. Only *additional* spaces receive UUIDs. Keying custom names by `uuid` therefore breaks the feature for the default desktop (no stable name; active-state undetectable).

Empirical capture (4 spaces, default desktop active):

| slot | `uuid` | `ManagedSpaceID` / `id64` |
|---|---|---|
| 0 (default, active) | `''` | 1 |
| 1 | `9DD24797-…` | 3 |
| 2 | `8B3CC061-…` | 4 |
| 3 | `B39FF9FA-…` | 5 |

**Resolution (user-approved):** the per-Space identity key is now the **decimal-string form of `ManagedSpaceID`** (e.g. `"1"`, `"3"`). It is non-empty, unique, present for every space and in `Current Space`, and position-independent (still survives reorders — the original Option-B goal). It is stored as a `String` so `NameStore` and the rest of the pipeline stay string-keyed with minimal churn.

**Open verification (deferred to Phase B smoke test):** confirm `ManagedSpaceID` stability across logout/reboot and space delete-then-recreate.

The Architecture, Components, Data Flow, and Testing sections below have been updated in-place to the new terminology (`ParsedSpace.id`, `activeID`, `spaceID`, `ManagedSpaceID`); no read-through substitution is required. Any remaining literal "uuid" refers to the raw plist field (now unused for identity) or unrelated contexts (e.g. test-suite name randomizers).

### Design Revision — 2026-05-16 (threading model)

Phase A left the Core's threading contract undefined (the final Phase A review flagged `SpaceMonitor.reload()`/`@Published` mutable from any thread and `NameStore`'s non-atomic UserDefaults read-modify-write). Resolved in Phase B task #18 (see D9): `NameStore`, `SpaceMonitor`, `SwitcherEngine`, and the `OrdinalLookup` protocol are `@MainActor`; `SpacesPlistParser`, `KeystrokeSynthesizing`/`CGKeystrokeSynthesizer`, `SystemShortcutChecker` stay non-isolated (pure/stateless — callable from `@MainActor` safely). `SpaceMonitor`'s notification observer hops via `Task { @MainActor in … }` (macOS-13-safe; no `MainActor.assumeIsolated`). Consequences for Phase B: construct `NameStore`/`SpaceMonitor`/`SwitcherEngine` in a main-actor context, and inject a named `UserDefaults` suite into `NameStore` (concrete suite name fixed with the app bundle id; `.standard` default retained only for tests). `swift-tools-version: 5.10` / Swift 5 language mode retained; full Swift 6 strict-concurrency adoption (incl. the `deinit`-touches-isolated-`observer` and unstructured-`Task` gaps) is deferred to the Xcode app-target task and separately tracked.

### Design Revision — 2026-05-17 (active-Space detection)

Phase B real-machine debugging proved that macOS does **not** update `~/Library/Preferences/com.apple.spaces.plist`'s `Current Space` on a Space switch: `activeSpaceDidChangeNotification` fires, `SpaceMonitor.reload()` runs, the file mtime stays frozen, and the parsed active id never changes across multiple real switches. The plist's `Current Space` is written only lazily (space add/remove/logout). So the original plan to derive the active Space from the plist (D1/D2) cannot satisfy D7 (menu-bar shows the active desktop's name). There is no robust *public* API for the current Space id.

**Resolution (user-approved):** revise D2. *Switching* stays public (synthesized `Ctrl+digit`). *Active-Space detection* uses the **read-only private SkyLight SPI** `CGSCopyManagedDisplaySpaces(CGSMainConnectionID())` (resolved via `dlsym` on `/System/Library/PrivateFrameworks/SkyLight.framework`), which was empirically verified to reflect the active Space's `ManagedSpaceID` in real time (probe: it tracked `4 → 1 → 4` in lockstep with switches while the plist stayed `4`). It is isolated behind an `ActiveSpaceReading` protocol (one SPI call site; unit-tested via a fake). The plist `Spaces` array is still used for the Space *list/order* (it *is* updated on structural changes). Accepted trade-off: SkyLight SPI is private and could change across major macOS releases (the app is already non-sandboxed / non-App-Store per Non-Goals and already synthesizes input events, so this is consistent with its nature).

### Design Revision — 2026-05-17b (switching delivery + signing)

Phase B real-machine debugging found desktop switching had three stacked causes (all fixed): (1) the app never requested Accessibility — now `AppDelegate` calls `AXIsProcessTrustedWithOptions(prompt:)` at launch and guides the user (the spec's Accessibility Edge Case, now implemented); (2) **ad-hoc signing** (`CODE_SIGN_IDENTITY "-"`) gives no stable Designated Requirement, so macOS TCC never honors the Accessibility grant and synthesized events are silently dropped — the app is now signed with a **stable self-signed identity** (`"SpaceRenamer Dev"`; `project.yml` `CODE_SIGN_STYLE Manual`; recreate the keychain cert with `scripts/create-signing-cert.sh`), giving a cert-anchored DR so the grant survives rebuilds; (3) keystrokes were posted to `.cgAnnotatedSessionEventTap`, which is **downstream of the WindowServer "Switch to Desktop N" symbolic-hotkey handler** — `CGKeystrokeSynthesizer` now posts to **`.cghidEventTap`** so the synthesized Ctrl+digit is processed like a real keypress and triggers the shortcut (D2's CGEvent approach stays public; only the tap changed). Verified end-to-end on a real machine.

## Architecture

Six components, each owning one concern. All communicate via a small set of well-defined inputs/outputs; no shared mutable state.

```
                ┌──────────────────────┐
                │  com.apple.spaces    │
                │       .plist         │
                └──────────┬───────────┘
                           │ read on change
                           ▼
┌────────────────┐   ┌──────────────┐   ┌──────────────────┐
│ NSWorkspace    │──▶│ SpaceMonitor │──▶│ MenuBarController│──┐
│ activeSpaceDid │   │  (IDs +      │   │  (NSStatusItem,  │  │
│ ChangeNotif.   │   │   ordinals)  │   │   NSMenu)        │  │
└────────────────┘   └──────┬───────┘   └────────┬─────────┘  │
                            │                    │            │ click
                            │                    ▼            │
                            │             ┌──────────────┐    │
                            │             │  NameStore   │◀───┘
                            │             │ (UserDefaults│
                            │             │  ID→name,    │
                            │             │  ID→hotkey)  │
                            │             └──────┬───────┘
                            │                    │
                            ▼                    ▼
                     ┌──────────────┐    ┌──────────────┐
                     │ Switcher     │◀───│ Hotkey       │
                     │ Engine       │    │ Manager      │
                     │ (CGEvent     │    │ (Carbon hot- │
                     │  Ctrl+N)     │    │  key regs)   │
                     └──────────────┘    └──────────────┘
                            │                    ▲
                            │                    │
                            │            ┌──────────────────┐
                            │            │ Preferences      │
                            │            │ Window (hotkey   │
                            │            │  recorder, L@L)  │
                            │            └──────────────────┘
```

### Components

**SpaceMonitor**
- Reads `~/Library/Preferences/com.apple.spaces.plist` and parses the `SpacesDisplayConfiguration → Management Data → Monitors[0]` dict:
  - `Spaces` array → ordered list of Space dicts; identity = the integer `ManagedSpaceID` (rendered as a decimal string; see D1 / Design Revision). Ordinal = array index + 1.
  - `Current Space` in the plist is **ignored** — macOS does not update it on switch (see D2 / Design Revision 2026-05-17).
- The Spaces *list/order* is parsed by the pure `SpacesPlistParser` into `ParsedSpace { id: String, ordinal: Int }` (the plist's `Spaces` array *is* updated on add/remove/reorder). `ParsedSpace` also exposes `static let maxShortcutOrdinal = 9` and `var isShortcutAvailable: Bool` — the single source of truth for the ">9 Spaces have no Ctrl+digit" rule, which `SwitcherEngine`'s ordinal guard derives from too. The **active Space** comes from an injected `ActiveSpaceReading` (read-only private SkyLight `CGSCopyManagedDisplaySpaces`), not the plist. `SpaceMonitor` exposes `@Published spaces: [ParsedSpace]`, `@Published activeID: String?` (from the SkyLight reader), `@Published lastLoadError: String?` (`nil` = healthy; non-`nil` = the last plist read/parse failed and `spaces` is retained stale), and `ordinal(for id: String) -> Int?`.
- Subscribes to `NSWorkspace.shared.notificationCenter` `activeSpaceDidChangeNotification`; on each fire it refreshes `activeID` from the SkyLight reader (and re-reads the plist list). The notification doesn't carry the new Space's identity directly.
- Note: macOS caches this plist in memory and may not flush to disk immediately. `SpaceMonitor` calls `CFPreferencesAppSynchronize("com.apple.spaces")` before each read to force a fresh copy.
- Publishes changes via a delegate / Combine subject so other components react.

**NameStore**
- Persists, keyed by Space ID (decimal `ManagedSpaceID`), in `UserDefaults`:
  - `SpaceID → customName: String`
  - `SpaceID → hotkey: KeyCombo` (Phase B; `KeyCombo` = keyCode + modifier flags)
  - `openMenuHotkey: KeyCombo?` (Phase B)
- Provides `name(for spaceID: String, defaultOrdinal: Int) -> String` returning the custom name or `"Desktop \(defaultOrdinal)"` fallback.
- Offers `forget(_ spaceID:)` to remove a Space's stored name (and, in Phase B, hotkey) — used when a Space no longer exists and the user wants to clean up.

**MenuBarController**
- Owns the `NSStatusItem`. Sets `button.title` to the active Space's name; updates on every `SpaceMonitor` change.
- Builds the `NSMenu` from `SpaceMonitor.currentSpaces` zipped with `NameStore`:
  - One `NSMenuItem` per Space, showing the custom name. Active Space gets a checkmark.
  - Right-click on a row opens a context menu with **Rename…** and **Forget Name** actions.
  - Separator, then **Preferences…**, **Launch at Login** (toggle), **Quit**.
- Click on a row → `SwitcherEngine.switch(to: id)`.

**SwitcherEngine**
- Single method: `switch(to id: String) throws`.
- Looks up the Space ID's current ordinal via `SpaceMonitor` (an injected `OrdinalLookup`). If not found → throws `unknownSpace`.
- If ordinal > 9 → throws `ordinalOutOfRange` (only `Ctrl+1`..`Ctrl+9` exist).
- Otherwise synthesizes `Ctrl+<digit>` via `CGEvent(keyboardEventSource:virtualKey:keyDown:)` for both keyDown and keyUp, posts on `cgAnnotatedSessionEventTap`.
- Behind a `KeystrokeSynthesizing` protocol so tests can verify intent without posting real events.

**HotkeyManager**
- Wraps Carbon `RegisterEventHotKey` / `UnregisterEventHotKey`.
- On launch: reads `NameStore` and registers one hotkey per assigned Space, plus the "open menu" hotkey if set.
- Exposes `register(keyCombo:, action: () -> Void) -> HotkeyHandle` and `unregister(_ handle: HotkeyHandle)`.
- Listens for `NameStore` changes (via notification or Combine) to add/remove registrations as the user edits hotkeys.

**PreferencesWindowController**
- Plain AppKit window opened from the menu.
- A `NSTableView` with one row per detected Space: name (read-only label — renaming happens inline in the menu), key-recorder cell that captures a new shortcut on focus + keypress.
- Separate field at the top: "Open menu" hotkey.
- "Launch at Login" checkbox bound to `SMAppService.mainApp`.

## Data Flow

### Boot
1. `LSUIElement = true` in Info.plist → no Dock icon.
2. App delegate instantiates `NameStore`, `SpaceMonitor`, `SwitcherEngine`, `HotkeyManager`, `MenuBarController`.
3. `SpaceMonitor` does initial plist read; `HotkeyManager` registers hotkeys from `NameStore`.
4. `MenuBarController` paints the menu and sets bar title to active Space's name.

### Switching by menu click
1. User clicks "Research" → `MenuBarController` → `SwitcherEngine.switch(to: researchID)`.
2. `SwitcherEngine` resolves Space ID → ordinal (say, 2) → posts `Ctrl+2`.
3. macOS switches Space → `activeSpaceDidChangeNotification` fires → `SpaceMonitor` re-reads → `MenuBarController` updates title to "Research" + checkmark.

### Switching by hotkey
Same as above, but entry point is `HotkeyManager`'s callback for that Space's `KeyCombo`.

### User adds / removes / reorders Spaces in Mission Control
1. macOS posts `activeSpaceDidChangeNotification` (it also fires for layout changes, not just active-space changes).
2. `SpaceMonitor` re-reads plist. New Space IDs appear; missing IDs vanish from `spaces`.
3. `MenuBarController` rebuilds the menu. New Spaces show default names (`Desktop N`). Removed Spaces disappear from the menu but their stored name/hotkey **stay** in `NameStore` (the user can "Forget" them manually).

### Inline rename
1. Right-click row → "Rename…" → `NSAlert` with text field, pre-filled with current name.
2. On OK → `NameStore.setName(spaceID, newName)` → menu rebuilds, bar title updates if affected.

### Hotkey assignment
1. User opens Preferences, focuses the recorder cell for a Space, presses `⌃⌥D`.
2. Recorder captures keyCode + modifiers → `NameStore.setHotkey(spaceID, combo)`.
3. `HotkeyManager` unregisters any previous combo for that Space and registers the new one.

## Edge Cases & Error Handling

| Case | Behavior |
|---|---|
| `Ctrl+N` shortcuts disabled in System Settings | On launch, read `com.apple.symbolichotkeys.plist`; if disabled, show a one-shot alert with a "Open Keyboard Settings" deep link (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`). Persist a "warned" flag in `UserDefaults` so we don't nag. |
| More than 9 Spaces | Menu shows all Spaces; rows where `ParsedSpace.isShortcutAvailable == false` (ordinal ≥ 10) are marked "(shortcut unavailable)" and disabled. The Core exposes this flag so the menu doesn't re-derive the rule; `SwitcherEngine.switch(to:)` throws `.ordinalOutOfRange` for those Spaces. |
| Plist unreadable or schema unrecognized | Core: `SpaceMonitor.reload()` sets `@Published lastLoadError` (non-`nil`), **keeps the previously published `spaces`/`activeID` (stale-but-shown)**, and logs via the unified `os.Logger`. App shell (Phase B): when `lastLoadError != nil` it renders the degraded fallback — plain `Desktop 1..N` rows from `NSScreen` heuristics — and disables Space-ID persistence. (Rendering the fallback is app UI; the Core only signals.) |
| Hotkey conflict (`eventHotKeyExistsErr`) | Preferences row shows red ⚠ inline; the new combo is NOT persisted until registration succeeds. |
| Accessibility permission denied | `AXIsProcessTrustedWithOptions(prompt: true)` on first launch. If denied, menu still renders and renames work; switch attempts show a tooltip "Grant Accessibility access in System Settings → Privacy & Security." |
| Multi-display, "Displays have separate Spaces" ON | v1: read only the primary display's Spaces from the plist. Document in README. v2 candidate: full multi-display support with per-display sections in the menu. |
| Wake from sleep / display reconnect | `activeSpaceDidChangeNotification` typically fires on these; if not, the menu is still correct because click-handlers always re-resolve the ordinal at the moment of the click. |

## Testing

### Unit (XCTest, runs in CI)
- **`NameStoreTests`** — round-trip name persistence (hotkeys: Phase B); default-name generation; `forget(_ spaceID:)` removes the stored name; warned-flag persistence.
- **`SpacesPlistParserTests`** — fixture-driven: feed synthetic plists (1 Space, 3 Spaces, 9 Spaces, reordered, and a real-capture fixture with an empty-`uuid` default desktop) and assert the parser produces the expected `[(id, ordinal)]` list + `activeID`, plus negative cases (missing/non-positive `ManagedSpaceID`, missing config/monitors).
- **`SwitcherEngineTests`** — inject a fake `KeystrokeSynthesizing` + fake `OrdinalLookup`; assert that a Space ID at ordinal 3 makes the engine request `Ctrl+3`, that an unknown ID throws `unknownSpace`, and an ordinal > 9 throws `ordinalOutOfRange` — with no keystroke posted on either error path.
- **`HotkeyManagerTests`** — fake the Carbon-wrapping protocol; verify register/unregister calls track `NameStore` mutations.

### Manual smoke checklist (cannot run in CI — needs real Spaces)
1. Launch → active Space's name visible in menu bar.
2. Menu lists all current Spaces with default names.
3. Rename "Desktop 2" → "Research" → name appears in menu and bar.
4. Click a non-active row → screen switches; bar title updates.
5. Add a Space in Mission Control → menu auto-adds it.
6. Reorder Spaces in Mission Control → renamed Space keeps its name (`ManagedSpaceID` tracking).
7. Quit and relaunch → names and hotkeys persist.
8. Assign `⌃⌥D` to "Research" → press from any app → switches.
9. Disable "Switch to Desktop N" in System Settings → relaunch → one-shot warning alert appears.
10. Revoke Accessibility permission → switch attempt → tooltip explains.

## Future Work (Out of Scope for v1)

- Multi-display Spaces (separate Spaces per monitor).
- iCloud sync of names and hotkeys.
- "Move active window to Space X" hotkey.
- Visual HUD overlay on Space switch (similar to volume HUD).
- App Sandbox / Mac App Store distribution (would require dropping `com.apple.spaces.plist` reads and finding a sandbox-safe alternative — likely not possible).

## Project Layout

```
SpaceRenamer/
├── SpaceRenamer.xcodeproj
├── SpaceRenamer/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── Info.plist                  (LSUIElement = YES)
│   ├── Core/
│   │   ├── SpaceMonitor.swift
│   │   ├── SpacesPlistParser.swift
│   │   ├── NameStore.swift
│   │   ├── SwitcherEngine.swift
│   │   ├── KeystrokeSynthesizer.swift
│   │   └── HotkeyManager.swift
│   ├── UI/
│   │   ├── MenuBarController.swift
│   │   ├── RenameAlert.swift
│   │   ├── PreferencesWindowController.swift
│   │   └── KeyComboRecorderView.swift
│   └── Resources/
│       └── Assets.xcassets
└── SpaceRenamerTests/
    ├── NameStoreTests.swift
    ├── SpacesPlistParserTests.swift
    ├── SwitcherEngineTests.swift
    ├── HotkeyManagerTests.swift
    └── Fixtures/
        ├── spaces-1.plist
        ├── spaces-3.plist
        ├── spaces-9.plist
        └── spaces-reordered.plist
```
