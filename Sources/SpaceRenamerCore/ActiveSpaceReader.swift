import Foundation

/// Reads the currently-active Space's identity (`ManagedSpaceID` as a decimal
/// string), or `nil` if it cannot be determined. macOS does not keep
/// `com.apple.spaces.plist`'s `Current Space` live (see design D2 / Revision
/// 2026-05-17), so the live source is the read-only private SkyLight SPI.
public protocol ActiveSpaceReading {
    func currentActiveSpaceID() -> String?
}

/// Read-only private SkyLight implementation. Resolves the SPI via `dlsym`
/// (no link-time dependency on a private framework). Verified live on a real
/// machine. The single private-SPI call site in the codebase.
public final class SkyLightActiveSpaceReader: ActiveSpaceReading {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let mainConn: MainConnFn?
    private let copyDisplaySpaces: CopyDisplaySpacesFn?

    public init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let mc = dlsym(handle, "CGSMainConnectionID"),
              let cds = dlsym(handle, "CGSCopyManagedDisplaySpaces") else {
            self.mainConn = nil
            self.copyDisplaySpaces = nil
            return
        }
        self.mainConn = unsafeBitCast(mc, to: MainConnFn.self)
        self.copyDisplaySpaces = unsafeBitCast(cds, to: CopyDisplaySpacesFn.self)
    }

    public func currentActiveSpaceID() -> String? {
        guard let mainConn, let copyDisplaySpaces else { return nil }
        guard let displays = copyDisplaySpaces(mainConn())?.takeRetainedValue() as? [[String: Any]],
              let primary = displays.first,
              let current = primary["Current Space"] as? [String: Any],
              let msid = current["ManagedSpaceID"] as? Int else {
            return nil
        }
        return String(msid)
    }
}
