import AppKit
import Combine
import os

@MainActor public final class SpaceMonitor {
    @Published public private(set) var spaces: [ParsedSpace] = []
    @Published public private(set) var activeID: String?

    /// `nil` when the last `reload()` succeeded. When non-nil, the most recent
    /// plist read/parse failed and `spaces`/`activeID` retain their previous
    /// (possibly empty) values — the UI can keep showing stale data while
    /// indicating a degraded state. Phase B renders the spec'd degraded
    /// fallback (plain "Desktop N" rows) when this is set.
    @Published public private(set) var lastLoadError: String?

    private static let logger = Logger(subsystem: "SpaceRenamerCore", category: "SpaceMonitor")

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
            // The Task hop is what guarantees @MainActor isolation for reload();
            // it's deferred one main hop, so if self is gone the reload is harmlessly skipped.
            Task { @MainActor in self?.reload() }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Re-read the plist and republish. On failure `lastLoadError` is set and
    /// the previously published `spaces`/`activeID` are left unchanged (stale).
    public func reload() {
        CFPreferencesAppSynchronize("com.apple.spaces" as CFString)
        do {
            let data = try Data(contentsOf: plistURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] ?? [:]
            let parsed = try SpacesPlistParser.parse(plist)
            self.spaces = parsed.spaces
            self.activeID = parsed.activeID
            self.lastLoadError = nil
        } catch {
            self.lastLoadError = String(describing: error)
            Self.logger.error("SpaceMonitor: failed to read plist: \(String(describing: error), privacy: .public)")
        }
    }

    public func ordinal(for id: String) -> Int? {
        spaces.first(where: { $0.id == id })?.ordinal
    }
}
