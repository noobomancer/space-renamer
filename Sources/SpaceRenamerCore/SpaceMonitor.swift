import AppKit
import Combine

public final class SpaceMonitor {
    @Published public private(set) var spaces: [ParsedSpace] = []
    @Published public private(set) var activeUUID: String?

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
            self?.reload()
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// Re-read the plist and republish.
    public func reload() {
        CFPreferencesAppSynchronize("com.apple.spaces" as CFString)
        do {
            let data = try Data(contentsOf: plistURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] ?? [:]
            let parsed = try SpacesPlistParser.parse(plist)
            self.spaces = parsed.spaces
            self.activeUUID = parsed.activeUUID
        } catch {
            NSLog("SpaceMonitor: failed to read plist: \(error)")
        }
    }

    public func ordinal(for uuid: String) -> Int? {
        spaces.first(where: { $0.uuid == uuid })?.ordinal
    }
}
