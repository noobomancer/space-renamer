import Foundation

@MainActor public protocol OrdinalLookup: AnyObject {
    func ordinal(for id: String) -> Int?
}

extension SpaceMonitor: OrdinalLookup {}

public enum SwitcherError: Error, Equatable {
    case unknownSpace
    case ordinalOutOfRange
    case lookupUnavailable
}

@MainActor public final class SwitcherEngine {
    private let synthesizer: KeystrokeSynthesizing
    private weak var lookup: OrdinalLookup?

    /// - Important: the engine holds `lookup` **weakly** to avoid a retain cycle
    ///   when one owner holds both the lookup and the engine. The caller MUST
    ///   retain `lookup` for the engine's lifetime; if it has been deallocated,
    ///   `switch(to:)` throws ``SwitcherError/lookupUnavailable`` (distinct from
    ///   ``SwitcherError/unknownSpace``, which means the lookup is alive but does
    ///   not know that Space ID).
    public init(synthesizer: KeystrokeSynthesizing = CGKeystrokeSynthesizer(),
                lookup: OrdinalLookup) {
        self.synthesizer = synthesizer
        self.lookup = lookup
    }

    public func `switch`(to id: String) throws {
        guard let lookup else { throw SwitcherError.lookupUnavailable }
        guard let ordinal = lookup.ordinal(for: id) else { throw SwitcherError.unknownSpace }
        guard (1...ParsedSpace.maxShortcutOrdinal).contains(ordinal) else { throw SwitcherError.ordinalOutOfRange }
        try synthesizer.postControlDigit(ordinal)
    }
}
