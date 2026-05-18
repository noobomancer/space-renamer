import XCTest
@testable import SpaceRenamerCore

@MainActor final class SwitcherEngineTests: XCTestCase {

    /// Stands in for the relative-arrow switcher. `available` models whether the
    /// switch could be attempted (live ordinals resolved + keystrokes posted) —
    /// NOT whether the view animated, which only the real machine confirms.
    private final class FakeSpaceSwitcher: SpaceSwitching {
        var available = true
        var requested: [String] = []
        func setCurrentSpace(managedSpaceID: String) -> Bool {
            requested.append(managedSpaceID)
            return available
        }
    }

    @MainActor private final class FakeOrdinalLookup: OrdinalLookup {
        var table: [String: Int] = [:]
        func ordinal(for id: String) -> Int? { table[id] }
    }

    func test_switch_delegatesToSpaceSwitcherForKnownID() throws {
        let switcher = FakeSpaceSwitcher()
        let lookup = FakeOrdinalLookup(); lookup.table = ["1": 1, "3": 3]
        let engine = SwitcherEngine(spaceSwitcher: switcher, lookup: lookup)

        try engine.switch(to: "3")

        XCTAssertEqual(switcher.requested, ["3"])
    }

    func test_switch_over9_works_noThrow() throws {
        // Headline of Design Revision 2026-05-17c: desktop 12 is switchable.
        let switcher = FakeSpaceSwitcher()
        let lookup = FakeOrdinalLookup(); lookup.table = ["132": 12]
        let engine = SwitcherEngine(spaceSwitcher: switcher, lookup: lookup)

        try engine.switch(to: "132")

        XCTAssertEqual(switcher.requested, ["132"])
    }

    func test_switch_unknownID_throws_noSwitcherCall() {
        let switcher = FakeSpaceSwitcher()
        let lookup = FakeOrdinalLookup()
        let engine = SwitcherEngine(spaceSwitcher: switcher, lookup: lookup)

        XCTAssertThrowsError(try engine.switch(to: "999")) { err in
            XCTAssertEqual(err as? SwitcherError, .unknownSpace)
        }
        XCTAssertTrue(switcher.requested.isEmpty)
    }

    func test_switch_deallocatedLookup_throwsLookupUnavailable() {
        let switcher = FakeSpaceSwitcher()
        var lookup: FakeOrdinalLookup? = FakeOrdinalLookup()
        lookup!.table = ["1": 1]
        let engine = SwitcherEngine(spaceSwitcher: switcher, lookup: lookup!)
        lookup = nil  // release the only strong reference; engine holds it weakly

        XCTAssertThrowsError(try engine.switch(to: "1")) { err in
            XCTAssertEqual(err as? SwitcherError, .lookupUnavailable)
        }
        XCTAssertTrue(switcher.requested.isEmpty)
    }

    func test_switch_switcherUnavailable_throwsSwitchUnavailable() {
        let switcher = FakeSpaceSwitcher(); switcher.available = false
        let lookup = FakeOrdinalLookup(); lookup.table = ["132": 12]
        let engine = SwitcherEngine(spaceSwitcher: switcher, lookup: lookup)

        XCTAssertThrowsError(try engine.switch(to: "132")) { err in
            XCTAssertEqual(err as? SwitcherError, .switchUnavailable)
        }
        XCTAssertEqual(switcher.requested, ["132"])  // attempted, then failed
    }
}
