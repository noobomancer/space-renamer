# Contributing

Thanks for considering a contribution.

## Dev setup

- macOS 13+, Xcode 15+.
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- A stable self-signed code-signing identity in your login keychain: `./scripts/create-signing-cert.sh` (run once per machine). This is required even for development: ad-hoc signing produces no stable Designated Requirement, so macOS TCC won't honor the Accessibility grant the app needs to synthesize switch keystrokes, and switching will silently fail.

## Build & run

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SpaceRenamer.xcodeproj -scheme SpaceRenamer \
             -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/SpaceRenamer-*/Build/Products/Debug/SpaceRenamer.app
```

Always launch via `open` (or by double-clicking the `.app`) — exec'ing the binary directly poisons TCC attribution (the responsible process becomes your terminal), and Accessibility checks return `false` confusingly.

## Tests

Pure logic in `SpaceRenamerCore` is unit-tested (~60 tests, milliseconds):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The `DEVELOPER_DIR` prefix is required — the Command Line Tools' bundled Swift toolchain lacks XCTest, so plain `swift test` fails.

The keystroke-effect end of switching can only be verified on a real machine; the testable seams (delta math, fallback selection, symbolic-hotkey parsing, name store, plist parser) are.

## Code style

Follow the existing patterns in the codebase:

- **`Sources/SpaceRenamerCore`** holds pure, AppKit-free logic. Stateless types stay non-isolated; stateful types (`NameStore`, `SpaceMonitor`, `SwitcherEngine`) are `@MainActor`-isolated. See *Design Decision D9* in the design spec.
- **`SpaceRenamerApp/`** is the Xcode app target — `AppDelegate`, `MenuBarController`, `PreferencesWindowController`, `HotkeyManager`. It depends on the local `SpaceRenamerCore` package.
- Match the comment density and naming of surrounding code.

## Design changes

The design spec lives at [`docs/superpowers/specs/2026-05-15-space-renamer-design.md`](docs/superpowers/specs/2026-05-15-space-renamer-design.md). It records decisions (D1–D9) and revisions chronologically, including rejected approaches with the real-machine evidence that ruled them out.

Non-trivial behavioral changes should record a similar dated "Design Revision YYYY-MM-DD" entry, especially when superseding or refining an earlier decision. This is how the project's identity choice (`ManagedSpaceID`, D1), the active-Space mechanism (D2 / 2026-05-17), the switch delivery (Design Revision 2026-05-17c), and the user-selectable mode (Design Revision 2026-05-18) all stayed honest.

## Commit conventions

- Short imperative subject (e.g. `feat: …`, `fix: …`, `docs: …`, `ci: …`).
- Reference an issue/PR number where applicable (`#N`).
- This project uses AI-assisted development; commits authored with that assistance carry a `Co-Authored-By: Claude` trailer. Human-only contributions don't need one.

## Bundle identifier

If you fork and ship under your own namespace, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and regenerate the project. macOS TCC keys Accessibility grants by bundle ID, so a fork with a different bundle ID needs its own grant.

## Reporting issues

Use the GitHub bug-report template — it asks for the few facts (macOS version, desktop count, active switch mode, which Mission Control shortcuts are enabled) that close most issues quickly.
