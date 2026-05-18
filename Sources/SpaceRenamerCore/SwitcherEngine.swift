import Foundation

@MainActor public protocol OrdinalLookup: AnyObject {
    func ordinal(for id: String) -> Int?
}

extension SpaceMonitor: OrdinalLookup {}

public enum SwitcherError: Error, Equatable {
    case unknownSpace
    /// The switch could not be attempted (live ordinals unavailable / event
    /// source unavailable). Replaces the old `ordinalOutOfRange` — switching is
    /// no longer ordinal-capped; see *Design Revision 2026-05-17c*.
    case switchUnavailable
    case lookupUnavailable
}

@MainActor public final class SwitcherEngine {
    private let spaceSwitcher: SpaceSwitching
    private weak var lookup: OrdinalLookup?

    /// - Important: the engine holds `lookup` **weakly** to avoid a retain cycle
    ///   when one owner holds both the lookup and the engine. The caller MUST
    ///   retain `lookup` for the engine's lifetime; if it has been deallocated,
    ///   `switch(to:)` throws ``SwitcherError/lookupUnavailable`` (distinct from
    ///   ``SwitcherError/unknownSpace``, which means the lookup is alive but does
    ///   not know that Space ID).
    public init(spaceSwitcher: SpaceSwitching = RelativeArrowSpaceSwitcher(),
                lookup: OrdinalLookup) {
        self.spaceSwitcher = spaceSwitcher
        self.lookup = lookup
    }

    /// Switches to the Space `id` (a `ManagedSpaceID`) via relative Ctrl+arrow
    /// navigation — uncapped (no 9-desktop limit). The `lookup` check validates
    /// the id is a known Space and preserves the weak-retention contract; the
    /// switcher itself derives the ordinal delta from a fresh SkyLight snapshot.
    public func `switch`(to id: String) throws {
        guard let lookup else { throw SwitcherError.lookupUnavailable }
        guard lookup.ordinal(for: id) != nil else { throw SwitcherError.unknownSpace }

        if spaceSwitcher.setCurrentSpace(managedSpaceID: id) { return }
        throw SwitcherError.switchUnavailable
    }
}
