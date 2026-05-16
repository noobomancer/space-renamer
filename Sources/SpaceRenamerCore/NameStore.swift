import Foundation

public final class NameStore {
    private let defaults: UserDefaults

    private enum Key {
        static let names = "SpaceRenamer.names"               // [UUID: String]
        static let warned = "SpaceRenamer.didWarnSystemShortcuts"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var names: [String: String] {
        get { (defaults.dictionary(forKey: Key.names) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: Key.names) }
    }

    public func name(for uuid: String, defaultOrdinal: Int) -> String {
        if let custom = names[uuid], !custom.isEmpty { return custom }
        return "Desktop \(defaultOrdinal)"
    }

    public func setName(_ uuid: String, _ name: String) {
        var dict = names
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: uuid)
        } else {
            dict[uuid] = trimmed
        }
        names = dict
    }

    public func forget(_ uuid: String) {
        var dict = names
        dict.removeValue(forKey: uuid)
        names = dict
    }

    public var didWarnAboutSystemShortcuts: Bool {
        get { defaults.bool(forKey: Key.warned) }
        set { defaults.set(newValue, forKey: Key.warned) }
    }
}
