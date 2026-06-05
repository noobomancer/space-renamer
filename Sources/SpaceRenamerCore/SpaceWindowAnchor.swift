import Foundation

/// Pins an existing window to a specific Space by `ManagedSpaceID`. Used by
/// the Mission Control overlay-label feature: each per-Space label window is
/// created on the active Space (where NSWindow lands by default), then anchored
/// to its target Space so it appears only in *that* Space's Mission Control
/// thumbnail. See *Design Revision 2026-06-04*.
public protocol SpaceWindowAnchoring {
    /// Anchor `windowNumber` to `managedSpaceID`: add to the target Space, and
    /// remove from the Space the window currently lives on if different.
    /// Returns `true` iff the private SPI resolved and the calls were issued
    /// (a knowable, synchronous outcome — NOT a statement about whether the
    /// window subsequently rendered correctly; that's a real-machine check).
    func anchor(windowNumber: Int, toSpaceID managedSpaceID: String) -> Bool
}

/// Private SkyLight implementation. Resolves the SPI via `dlsym`; same
/// PrivateFramework as the read-only `SkyLightActiveSpaceReader`, just
/// extended with the `CGSAddWindowsToSpaces` / `CGSRemoveWindowsFromSpaces`
/// write calls that the window-anchoring trick depends on. These two writes
/// are the known-stable window-placement use of the CGS family (yabai et al.
/// rely on them) — distinct from the `CGSManagedDisplaySetCurrentSpace` write
/// that we rejected for *switching* (it only updated bookkeeping). See
/// *Design Revision 2026-06-04*.
public final class CGSSpaceWindowAnchor: SpaceWindowAnchoring {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    /// `CGSAddWindowsToSpaces(int cid, CFArrayRef windowIDs, CFArrayRef spaceIDs)`.
    private typealias AddOrRemoveFn = @convention(c) (Int32, CFArray, CFArray) -> Void

    private let mainConn: MainConnFn?
    private let copyDisplaySpaces: CopyDisplaySpacesFn?
    private let addWindowsToSpaces: AddOrRemoveFn?
    private let removeWindowsFromSpaces: AddOrRemoveFn?

    public init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mc = dlsym(handle, "CGSMainConnectionID"),
              let cds = dlsym(handle, "CGSCopyManagedDisplaySpaces"),
              let add = dlsym(handle, "CGSAddWindowsToSpaces"),
              let rem = dlsym(handle, "CGSRemoveWindowsFromSpaces") else {
            self.mainConn = nil
            self.copyDisplaySpaces = nil
            self.addWindowsToSpaces = nil
            self.removeWindowsFromSpaces = nil
            return
        }
        self.mainConn = unsafeBitCast(mc, to: MainConnFn.self)
        self.copyDisplaySpaces = unsafeBitCast(cds, to: CopyDisplaySpacesFn.self)
        self.addWindowsToSpaces = unsafeBitCast(add, to: AddOrRemoveFn.self)
        self.removeWindowsFromSpaces = unsafeBitCast(rem, to: AddOrRemoveFn.self)
    }

    public func anchor(windowNumber: Int, toSpaceID managedSpaceID: String) -> Bool {
        guard let mainConn, let copyDisplaySpaces, let addWindowsToSpaces, let removeWindowsFromSpaces,
              let target = Int(managedSpaceID) else { return false }
        let cid = mainConn()

        // Find the display that owns the target Space, and read that display's
        // "Current Space" — the Space the freshly-created NSWindow lands on by
        // default. We need to remove from `current` (if different from target)
        // so the window doesn't end up on both.
        var current: Int?
        if let unmanaged = copyDisplaySpaces(cid) {
            let displays = unmanaged.takeRetainedValue() as? [[String: Any]] ?? []
            for display in displays {
                let spaces = (display["Spaces"] as? [[String: Any]]) ?? []
                let owns = spaces.contains { ($0["ManagedSpaceID"] as? Int) == target }
                if owns {
                    current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
                    break
                }
            }
        }

        let winIDs = [NSNumber(value: windowNumber)] as CFArray
        let targetIDs = [NSNumber(value: target)] as CFArray
        addWindowsToSpaces(cid, winIDs, targetIDs)
        if let current, current != target {
            removeWindowsFromSpaces(cid, winIDs, [NSNumber(value: current)] as CFArray)
        }
        return true
    }
}
