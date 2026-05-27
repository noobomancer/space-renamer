# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning is [SemVer](https://semver.org/)-ish (`0.1.x` while pre-1.0).

## [Unreleased]

## [0.1.4] — 2026-05-26

### Changed
- **Swift 6 strict concurrency** adopted at both layers. `Package.swift` declares `swift-tools-version: 6.0` with `.swiftLanguageMode(.v6)` per-target; the app target uses `SWIFT_VERSION: "6.0"`. Build is clean under strict checking — the existing `@MainActor` isolation (D9) was already correct. Two small fixes were needed: `SpaceMonitor.observer` is now `nonisolated(unsafe)` (non-`Sendable` `NSObjectProtocol` read from nonisolated `deinit` at ARC tear-down), and `NameStoreTests` overrides the `async throws` variants of `setUp`/`tearDown` so they inherit the `@MainActor` class's isolation (#26).
- First-run alerts (Accessibility prompt + Mission Control shortcuts warning) are now deferred off the synchronous launch path via `DispatchQueue.main.async`, so the menu-bar status item appears before any modal (#31).

### Fixed
- `xcodegen generate` was silently resetting `CFBundleShortVersionString`/`CFBundleVersion` in `Info.plist` on every run, dropping committed version bumps. Both keys are now pinned in `project.yml`'s `info.properties` so the version survives regeneration.

## [0.1.3] — 2026-05-26

### Added
- Read-only hotkey hint in the status menu: each desktop's assigned global shortcut (set in Preferences) is shown to the right of its name (#50).
- User-selectable switch mode in Preferences: *Use shortcut mode (9 desktops max)* toggles between relative-arrow navigation (default, any desktop) and `Ctrl+1–9` (instant but capped at 9). Modes are runtime-switchable; no relaunch needed (#42).

### Fixed
- Launch-time warning now checks the **active mode's** prerequisite (`Move left/right a space` for arrow mode, `Switch to Desktop N` for shortcut mode) instead of always the latter, which became wrong after the 0.1.2 mechanism pivot.

### Removed
- Dead capacity code left over from the 0.1.2 cap-removal: `ParsedSpace.maxShortcutOrdinal` / `isShortcutAvailable` and the unused desktop-shortcut checker entry points. (The desktop checker was reintroduced cleanly alongside the user-selectable mode in 0.1.3.)

## [0.1.2] — 2026-05-18

### Added
- **Switching is no longer capped at 9 desktops.** The menu lists every desktop and switches to any of them via relative `Ctrl+arrow` ("Move left/right a space") navigation, driven by the live SkyLight reader's ordinal delta (#41).
- Display (monitor) SF Symbol before the active desktop name in the menu bar (#39).
- Preferences window opens centered on screen (#40).

### Notes
- A direct SkyLight write SPI (`CGSManagedDisplaySetCurrentSpace`) was tried first and rejected on real-machine evidence: it only updates the WindowServer's bookkeeping without performing the visible space transition. The relative-arrow mechanism shipped instead uses public Mission Control hotkeys and performs the real animated transition. The full reasoning, including the `Ctrl+Fn` modifier-mask root cause that initially made the arrow path appear broken, is recorded in *Design Revision 2026-05-17c*.

## [0.1.1] — 2026-05-17

### Fixed
- Rows for desktops whose `Ctrl+N` is disabled in System Settings are now greyed with a guidance tooltip instead of silently no-op'ing on click (#38).
- Status menu correctly applies disabled state on items (`NSMenu.autoenablesItems = false`) — AppKit was silently re-enabling manually-disabled items.

## [0.1.0] — 2026-05-17

### Added
- Initial release. Custom desktop names (persisted by `ManagedSpaceID`), click-to-switch from the menu bar, active-desktop name in the menu bar, ⌥-click rename, per-desktop and open-menu global hotkeys, Launch at Login, mode-aware launch warning.
- Active-Space detection via the read-only private SkyLight SPI `CGSCopyManagedDisplaySpaces` (#33).
- Stable self-signed code-signing required for the Accessibility grant to persist across builds (`scripts/create-signing-cert.sh`) (#35).
- Synthesized switch keystrokes posted to `.cghidEventTap` so they reach the WindowServer symbolic-hotkey handler (#36).
