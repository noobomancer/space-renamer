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
| D1 | **Identify Spaces by UUID** read from `~/Library/Preferences/com.apple.spaces.plist` | Identify by ordinal index (1, 2, 3…) | Names must survive Space reorders. UUIDs are stable; indices are not. |
| D2 | **Switch Spaces by synthesizing `Ctrl+N` `CGEvent`s** | Private SkyLight `CGSManagedDisplaySetCurrentSpace` | Public API only; survives macOS updates. Trade-off: requires user to keep "Switch to Desktop N" shortcuts enabled in System Settings. |
| D3 | **Custom global hotkeys via Carbon `RegisterEventHotKey`** | NSEvent local monitor (only works in-app), CGEventTap (more invasive, needs more permissions) | Standard pattern; works system-wide; reliable. |
| D4 | **Inline rename via right-click → `NSAlert` text-field popover** | Dedicated rename window | Lowest-friction UX; user explicitly chose minimal inline. |
| D5 | **Mini Preferences window for hotkey assignment** | Inline hotkey recording in the menu | `NSMenu` dismisses on modifier keypress, making in-menu recording unreliable. |
| D6 | **Swift + AppKit** (`NSStatusItem`, `NSMenu`, `NSAlert`, AppKit window) | SwiftUI `MenuBarExtra` | AppKit gives finer control over status-item and menu quirks; SwiftUI's menu bar API is less mature. |
| D7 | **Bar title shows the active Space's custom name** | Just an icon | User requested name; gives at-a-glance feedback even when menu is closed. |
| D8 | **macOS 13+ minimum** | Older macOS | Allows `SMAppService` for Launch-at-Login and modern Swift concurrency. |

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
│ activeSpaceDid │   │  (UUIDs +    │   │  (NSStatusItem,  │  │
│ ChangeNotif.   │   │   ordinals)  │   │   NSMenu)        │  │
└────────────────┘   └──────┬───────┘   └────────┬─────────┘  │
                            │                    │            │ click
                            │                    ▼            │
                            │             ┌──────────────┐    │
                            │             │  NameStore   │◀───┘
                            │             │ (UserDefaults│
                            │             │  UUID→name,  │
                            │             │  UUID→hotkey)│
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
  - `Spaces` array → ordered list of Space dicts; each has a `uuid` field. Ordinal = array index + 1.
  - `Current Space` → dict whose `uuid` field is the currently-active Space.
- Exposes `currentSpaces: [(uuid: String, ordinal: Int)]` and `activeSpaceUUID: String?`.
- Subscribes to `NSWorkspace.shared.notificationCenter` `activeSpaceDidChangeNotification`; re-reads the plist on each fire (the notification doesn't carry the new Space's identity directly).
- Note: macOS caches this plist in memory and may not flush to disk immediately. `SpaceMonitor` calls `CFPreferencesAppSynchronize("com.apple.spaces")` before each read to force a fresh copy.
- Publishes changes via a delegate / Combine subject so other components react.

**NameStore**
- Persists three maps in `UserDefaults`:
  - `UUID → customName: String`
  - `UUID → hotkey: KeyCombo` (where `KeyCombo` is a small struct: keyCode + modifier flags)
  - `openMenuHotkey: KeyCombo?`
- Provides `name(for: UUID, defaultIndex: Int) -> String` returning the custom name or `"Desktop \(defaultIndex)"` fallback.
- Offers `forget(uuid:)` to remove a Space's stored name and hotkey (used when a Space no longer exists and the user wants to clean up).

**MenuBarController**
- Owns the `NSStatusItem`. Sets `button.title` to the active Space's name; updates on every `SpaceMonitor` change.
- Builds the `NSMenu` from `SpaceMonitor.currentSpaces` zipped with `NameStore`:
  - One `NSMenuItem` per Space, showing the custom name. Active Space gets a checkmark.
  - Right-click on a row opens a context menu with **Rename…** and **Forget Name** actions.
  - Separator, then **Preferences…**, **Launch at Login** (toggle), **Quit**.
- Click on a row → `SwitcherEngine.switch(to: uuid)`.

**SwitcherEngine**
- Single method: `switch(to uuid: String) throws`.
- Looks up the UUID's current ordinal via `SpaceMonitor`. If not found → throws `unknownSpace`.
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
1. User clicks "Research" → `MenuBarController` → `SwitcherEngine.switch(to: researchUUID)`.
2. `SwitcherEngine` resolves UUID → ordinal (say, 2) → posts `Ctrl+2`.
3. macOS switches Space → `activeSpaceDidChangeNotification` fires → `SpaceMonitor` re-reads → `MenuBarController` updates title to "Research" + checkmark.

### Switching by hotkey
Same as above, but entry point is `HotkeyManager`'s callback for that Space's `KeyCombo`.

### User adds / removes / reorders Spaces in Mission Control
1. macOS posts `activeSpaceDidChangeNotification` (it also fires for layout changes, not just active-space changes).
2. `SpaceMonitor` re-reads plist. New UUIDs appear; missing UUIDs vanish from `currentSpaces`.
3. `MenuBarController` rebuilds the menu. New Spaces show default names (`Desktop N`). Removed Spaces disappear from the menu but their stored name/hotkey **stay** in `NameStore` (the user can "Forget" them manually).

### Inline rename
1. Right-click row → "Rename…" → `NSAlert` with text field, pre-filled with current name.
2. On OK → `NameStore.setName(uuid, newName)` → menu rebuilds, bar title updates if affected.

### Hotkey assignment
1. User opens Preferences, focuses the recorder cell for a Space, presses `⌃⌥D`.
2. Recorder captures keyCode + modifiers → `NameStore.setHotkey(uuid, combo)`.
3. `HotkeyManager` unregisters any previous combo for that Space and registers the new one.

## Edge Cases & Error Handling

| Case | Behavior |
|---|---|
| `Ctrl+N` shortcuts disabled in System Settings | On launch, read `com.apple.symbolichotkeys.plist`; if disabled, show a one-shot alert with a "Open Keyboard Settings" deep link (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`). Persist a "warned" flag in `UserDefaults` so we don't nag. |
| More than 9 Spaces | Show all in the menu, but rows for ordinals 10+ are visually marked "(shortcut unavailable)" and disabled. Hotkeys still work because the OS shortcut for that ordinal doesn't exist either. |
| Plist unreadable or schema unrecognized | `SpaceMonitor` falls back to degraded mode: lists `Desktop 1..N` based on `NSScreen` heuristics; UUID persistence is disabled (warning logged via `os_log`). |
| Hotkey conflict (`eventHotKeyExistsErr`) | Preferences row shows red ⚠ inline; the new combo is NOT persisted until registration succeeds. |
| Accessibility permission denied | `AXIsProcessTrustedWithOptions(prompt: true)` on first launch. If denied, menu still renders and renames work; switch attempts show a tooltip "Grant Accessibility access in System Settings → Privacy & Security." |
| Multi-display, "Displays have separate Spaces" ON | v1: read only the primary display's Spaces from the plist. Document in README. v2 candidate: full multi-display support with per-display sections in the menu. |
| Wake from sleep / display reconnect | `activeSpaceDidChangeNotification` typically fires on these; if not, the menu is still correct because click-handlers always re-resolve the ordinal at the moment of the click. |

## Testing

### Unit (XCTest, runs in CI)
- **`NameStoreTests`** — round-trip name and hotkey persistence; default-name generation; `forget(uuid:)` removes both name and hotkey.
- **`SpacesPlistParserTests`** — fixture-driven: feed captured plists (1 Space, 3 Spaces, 9 Spaces, reordered Spaces) and assert the parser produces the expected `[(uuid, ordinal)]` list.
- **`SwitcherEngineTests`** — inject a fake `KeystrokeSynthesizing`; assert that given UUID X at ordinal 3, the engine requests `Ctrl+3` keyDown/keyUp.
- **`HotkeyManagerTests`** — fake the Carbon-wrapping protocol; verify register/unregister calls track `NameStore` mutations.

### Manual smoke checklist (cannot run in CI — needs real Spaces)
1. Launch → active Space's name visible in menu bar.
2. Menu lists all current Spaces with default names.
3. Rename "Desktop 2" → "Research" → name appears in menu and bar.
4. Click a non-active row → screen switches; bar title updates.
5. Add a Space in Mission Control → menu auto-adds it.
6. Reorder Spaces in Mission Control → renamed Space keeps its name (UUID tracking).
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
