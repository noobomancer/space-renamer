import XCTest
@testable import SpaceRenamerCore

@MainActor final class SwitcherEngineTests: XCTestCase {

    private final class FakeSynthesizer: KeystrokeSynthesizing {
        var posted: [Int] = []
        func postControlDigit(_ digit: Int) throws {
            posted.append(digit)
        }
    }

    @MainActor private final class FakeOrdinalLookup: OrdinalLookup {
        var table: [String: Int] = [:]
        func ordinal(for id: String) -> Int? { table[id] }
    }

    func test_switch_postsCtrlDigitForKnownID() throws {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        lookup.table = ["1": 1, "3": 3]
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)

        try engine.switch(to: "3")

        XCTAssertEqual(synth.posted, [3])
    }

    func test_switch_unknownID_throws() {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)
        XCTAssertThrowsError(try engine.switch(to: "999")) { err in
            XCTAssertEqual(err as? SwitcherError, .unknownSpace)
        }
        XCTAssertTrue(synth.posted.isEmpty)
    }

    func test_switch_ordinalOver9_throws() {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        lookup.table = ["7": 10]
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)
        XCTAssertThrowsError(try engine.switch(to: "7")) { err in
            XCTAssertEqual(err as? SwitcherError, .ordinalOutOfRange)
        }
        XCTAssertTrue(synth.posted.isEmpty)
    }
}
