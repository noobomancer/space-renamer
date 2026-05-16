# Plist Fixtures

Synthetic XML plists matching the shape of `~/Library/Preferences/com.apple.spaces.plist`.
Per-Space identity is the integer `ManagedSpaceID` (see design spec D1 / 2026-05-15 revision);
`uuid` is included for realism and is intentionally empty (`""`) for default desktops.

- `spaces-1.plist` — single Space, ManagedSpaceID 1 (empty uuid), active = 1.
- `spaces-3.plist` — three Spaces MSID 1,2,3, active = 2 (middle).
- `spaces-9.plist` — nine Spaces MSID 1..9, active = 5.
- `spaces-reordered.plist` — Spaces in slot order MSID 3,1,2, active = 1.
- `spaces-real.plist` — captured-shape: 4 spaces; default desktop (slot 0) has empty uuid + ManagedSpaceID 1 and is active; others MSID 3,4,5 with real-looking UUIDs.

Used by `SpacesPlistParserTests`.
