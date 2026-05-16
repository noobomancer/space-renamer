import Foundation

public struct ParsedSpace: Equatable {
    /// Stable, position-independent identity: decimal string of the plist
    /// `ManagedSpaceID`. (The `uuid` field is empty for default desktops — see
    /// design spec D1 / 2026-05-15 revision.)
    public let id: String
    public let ordinal: Int  // 1-based

    public init(id: String, ordinal: Int) {
        self.id = id
        self.ordinal = ordinal
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
            return ParsedSpace(id: String(managedID), ordinal: idx + 1)
        }
        let activeID = (primary["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        return ParsedSpaces(spaces: parsed, activeID: activeID.map(String.init))
    }
}
