import Foundation

public struct ParsedSpace: Equatable {
    /// Runtime handle: decimal string of the plist `ManagedSpaceID`. Valid for
    /// the current session only — macOS renumbers MSIDs across logout/restart,
    /// so this must never be used as a persistence key (it was, until the
    /// 2026-06-09 revision; see `storageID`). Switching and window anchoring
    /// SPIs take this.
    public let id: String
    public let ordinal: Int  // 1-based
    /// The space's `uuid` plist field. Persisted by macOS in
    /// `com.apple.spaces.plist` and stable across logout/restart (it is the
    /// identity macOS itself keys per-desktop wallpapers by). Empty for the
    /// primary desktop.
    public let uuid: String

    /// Restart-stable persistence key: the `uuid`, or the `"primary"` sentinel
    /// for the primary desktop (whose uuid is empty). Names and per-desktop
    /// hotkeys are stored under this.
    public var storageID: String { uuid.isEmpty ? "primary" : uuid }

    public init(id: String, ordinal: Int, uuid: String = "") {
        self.id = id
        self.ordinal = ordinal
        self.uuid = uuid
    }
}

public struct ParsedSpaces: Equatable {
    public let spaces: [ParsedSpace]
    public let activeID: String?

    public init(spaces: [ParsedSpace], activeID: String?) {
        self.spaces = spaces
        self.activeID = activeID
    }
}

public enum SpacesPlistError: Error, Equatable {
    case missingConfiguration
    case noMonitors
    case malformedSpaceEntry
}

public enum SpacesPlistParser {

    public static func parse(_ plist: [String: Any]) throws -> ParsedSpaces {
        guard let config = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = config["Management Data"] as? [String: Any] else {
            throw SpacesPlistError.missingConfiguration
        }
        // Primary monitor only; multi-display handling is tracked as a separate Phase B concern.
        guard let monitors = managementData["Monitors"] as? [[String: Any]],
              let primary = monitors.first else {
            throw SpacesPlistError.noMonitors
        }
        let spacesArray = (primary["Spaces"] as? [[String: Any]]) ?? []
        let parsed: [ParsedSpace] = try spacesArray.enumerated().map { idx, dict in
            guard let managedID = dict["ManagedSpaceID"] as? Int, managedID > 0 else {
                throw SpacesPlistError.malformedSpaceEntry
            }
            let uuid = (dict["uuid"] as? String) ?? ""
            return ParsedSpace(id: String(managedID), ordinal: idx + 1, uuid: uuid)
        }
        let activeID = (primary["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        return ParsedSpaces(spaces: parsed, activeID: activeID.map(String.init))
    }
}
