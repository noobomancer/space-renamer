# Plist Fixtures

Synthetic XML plists matching the shape of `~/Library/Preferences/com.apple.spaces.plist`.
All Space UUIDs are dummy values (`uuid-1` … `uuid-N`).

- `spaces-1.plist` — single Space, active = uuid-1.
- `spaces-3.plist` — three Spaces, active = uuid-2 (middle).
- `spaces-9.plist` — nine Spaces, active = uuid-5.
- `spaces-reordered.plist` — same UUIDs as `spaces-3.plist` but in order `uuid-3, uuid-1, uuid-2`, active = uuid-1.

Used by `SpacesPlistParserTests`.
