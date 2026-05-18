import Foundation

@MainActor
public final class NameStore {
    private let defaults: UserDefaults

    private enum Key {
        static let names = "SpaceRenamer.names"               // [SpaceID: String]
        static let warned = "SpaceRenamer.didWarnSystemShortcuts"
        static let switchMode = "SpaceRenamer.switchMode"     // SwitchMode.rawValue
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
    }

    public func forget(_ spaceID: String) {
        var dict = names
        dict.removeValue(forKey: spaceID)
        names = dict
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
}
