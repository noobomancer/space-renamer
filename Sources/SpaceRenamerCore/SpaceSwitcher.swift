import Foundation

/// Makes a Space the current one. Switching is uncapped (no 9-desktop limit):
/// see design D2 / *Design Revision 2026-05-17c*.
public protocol SpaceSwitching {
    /// Navigate so `managedSpaceID` becomes the current Space.
    ///
    /// Returns `true` iff the switch could be **attempted** (live ordinals
    /// resolved and the keystrokes were posted, or we were already there).
    /// `false` is a knowable synchronous failure (reader unavailable, id not in
    /// the live snapshot, event source unavailable). It does not assert the
    /// view finished animating — verified live on the real machine.
    func setCurrentSpace(managedSpaceID: String) -> Bool
}

/// Relative-navigation switcher. Reads the live ordered Spaces + active Space
/// from SkyLight (read-only), computes the signed ordinal delta to the target,
/// and synthesizes that many Ctrl+← / Ctrl+→ ("Move left/right a space")
/// presses. Those go through the same WindowServer symbolic-hotkey handler as
/// a real keypress, so the switch is the real animated transition — for ANY
/// number of desktops, no SIP. (The SkyLight *write* SPI it replaced only
/// rewrote bookkeeping without moving the screen — proven on a real machine;
/// see *Design Revision 2026-05-17c*.)
public final class RelativeArrowSpaceSwitcher: SpaceSwitching {
    private let reader: ActiveSpaceReading
    private let synthesizer: KeystrokeSynthesizing
    /// Pacing between consecutive arrow presses so the WindowServer animates
    /// each hop instead of coalescing them. Injectable so tests run instantly.
    private let pace: () -> Void

    public init(reader: ActiveSpaceReading = SkyLightActiveSpaceReader(),
                synthesizer: KeystrokeSynthesizing = CGKeystrokeSynthesizer(),
                pace: @escaping () -> Void = { usleep(120_000) }) {
        self.reader = reader
        self.synthesizer = synthesizer
        self.pace = pace
    }

    public func setCurrentSpace(managedSpaceID: String) -> Bool {
        guard let snap = reader.snapshot(),
              let activeID = snap.activeID,
              let from = snap.spaces.first(where: { $0.id == activeID })?.ordinal,
              let to = snap.spaces.first(where: { $0.id == managedSpaceID })?.ordinal else {
            return false
        }

        let delta = to - from
        guard delta != 0 else { return true }   // already on the target Space

        let keyCode = delta > 0
            ? CGKeystrokeSynthesizer.rightArrowKeyCode
            : CGKeystrokeSynthesizer.leftArrowKeyCode
        let steps = abs(delta)
        for step in 1...steps {
            do {
                try synthesizer.postControlKey(keyCode)
            } catch {
                return false
            }
            if step < steps { pace() }
        }
        return true
    }
}
