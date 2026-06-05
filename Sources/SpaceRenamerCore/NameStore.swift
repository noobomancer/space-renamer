import Foundation

public extension Notification.Name {
    /// Posted by `NameStore` on every name change (rename or forget). Userinfo
    /// `["id": String]` carries the affected `ManagedSpaceID`. Subscribers can
    /// re-query `name(for:defaultOrdinal:)` without coupling through specific
    /// UI controllers.
    static let spaceRenamerNameDidChange = Notification.Name("SpaceRenamer.nameDidChange")
}

@MainActor
public final class NameStore {
    private let defaults: UserDefaults

    private enum Key {
        static let names = "SpaceRenamer.names"               // [SpaceID: String]
        static let warned = "SpaceRenamer.didWarnSystemShortcuts"
        static let switchMode = "SpaceRenamer.switchMode"     // SwitchMode.rawValue
        static let missionControlOverlay = "SpaceRenamer.showMissionControlOverlay"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var names: [String: String] {
        get { (defaults.dictionary(forKey: Key.names) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.names) }
    }

    public func name(for spaceID: String, defaultOrdinal: Int) -> String {
        if let custom = names[spaceID], !custom.isEmpty { return custom }
        return "Desktop \(defaultOrdinal)"
    }

    public func setName(_ spaceID: String, _ name: String) {
        var dict = names
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: spaceID)
        } else {
            dict[spaceID] = trimmed
        }
        names = dict
        NotificationCenter.default.post(name: .spaceRenamerNameDidChange,
                                        object: nil, userInfo: ["id": spaceID])
    }

    public func forget(_ spaceID: String) {
        var dict = names
        dict.removeValue(forKey: spaceID)
        names = dict
        NotificationCenter.default.post(name: .spaceRenamerNameDidChange,
                                        object: nil, userInfo: ["id": spaceID])
    }

    public var didWarnAboutSystemShortcuts: Bool {
        get { defaults.bool(forKey: Key.warned) }
        set { defaults.set(newValue, forKey: Key.warned) }
    }

    /// Desktop-switch delivery mechanism. Missing/invalid → `SwitchMode.default`.
    public var switchMode: SwitchMode {
        get { defaults.string(forKey: Key.switchMode).flatMap(SwitchMode.init(rawValue:)) ?? .default }
        set { defaults.set(newValue.rawValue, forKey: Key.switchMode) }
    }

    /// Per-Space label window visible (huge) in Mission Control thumbnails.
    /// Off by default (existing users opt in); see *Design Revision 2026-06-04*.
    public var showMissionControlOverlay: Bool {
        get { defaults.bool(forKey: Key.missionControlOverlay) }
        set { defaults.set(newValue, forKey: Key.missionControlOverlay) }
    }
}
