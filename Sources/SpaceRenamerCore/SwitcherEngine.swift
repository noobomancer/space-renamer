import Foundation

public protocol OrdinalLookup: AnyObject {
    func ordinal(for uuid: String) -> Int?
}

extension SpaceMonitor: OrdinalLookup {}

public enum SwitcherError: Error, Equatable {
    case unknownSpace
    case ordinalOutOfRange
}

public final class SwitcherEngine {
    private let synthesizer: KeystrokeSynthesizing
    private weak var lookup: OrdinalLookup?

    public init(synthesizer: KeystrokeSynthesizing = CGKeystrokeSynthesizer(),
                lookup: OrdinalLookup) {
        self.synthesizer = synthesizer
        self.lookup = lookup
    }

    public func `switch`(to uuid: String) throws {
        guard let lookup else { throw SwitcherError.unknownSpace }
        guard let ordinal = lookup.ordinal(for: uuid) else { throw SwitcherError.unknownSpace }
        guard (1...9).contains(ordinal) else { throw SwitcherError.ordinalOutOfRange }
        try synthesizer.postControlDigit(ordinal)
    }
}
