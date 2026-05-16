import Foundation

public struct ParsedSpace: Equatable {
    public let uuid: String
    public let ordinal: Int  // 1-based

    public init(uuid: String, ordinal: Int) {
        self.uuid = uuid
        self.ordinal = ordinal
    }
}

public struct ParsedSpaces: Equatable {
    public let spaces: [ParsedSpace]
    public let activeUUID: String?

    public init(spaces: [ParsedSpace], activeUUID: String?) {
        self.spaces = spaces
        self.activeUUID = activeUUID
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
        guard let monitors = managementData["Monitors"] as? [[String: Any]],
              let primary = monitors.first else {
            throw SpacesPlistError.noMonitors
        }
        let spacesArray = (primary["Spaces"] as? [[String: Any]]) ?? []
        let parsed: [ParsedSpace] = try spacesArray.enumerated().map { idx, dict in
            guard let uuid = dict["uuid"] as? String else {
                throw SpacesPlistError.malformedSpaceEntry
            }
            return ParsedSpace(uuid: uuid, ordinal: idx + 1)
        }
        let activeUUID = (primary["Current Space"] as? [String: Any])?["uuid"] as? String
        return ParsedSpaces(spaces: parsed, activeUUID: activeUUID)
    }
}
