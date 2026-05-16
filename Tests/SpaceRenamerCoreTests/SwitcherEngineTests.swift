import XCTest
@testable import SpaceRenamerCore

final class SwitcherEngineTests: XCTestCase {

    private final class FakeSynthesizer: KeystrokeSynthesizing {
        var posted: [Int] = []
        func postControlDigit(_ digit: Int) throws {
            posted.append(digit)
        }
    }

    private final class FakeOrdinalLookup: OrdinalLookup {
        var table: [String: Int] = [:]
        func ordinal(for uuid: String) -> Int? { table[uuid] }
    }

    func test_switch_postsCtrlDigitForKnownUUID() throws {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        lookup.table = ["uuid-a": 1, "uuid-b": 3]
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)

        try engine.switch(to: "uuid-b")

        XCTAssertEqual(synth.posted, [3])
    }

    func test_switch_unknownUUID_throws() {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)
        XCTAssertThrowsError(try engine.switch(to: "uuid-missing")) { err in
            XCTAssertEqual(err as? SwitcherError, .unknownSpace)
        }
        XCTAssertTrue(synth.posted.isEmpty)
    }

    func test_switch_ordinalOver9_throws() {
        let synth = FakeSynthesizer()
        let lookup = FakeOrdinalLookup()
        lookup.table = ["uuid-a": 10]
        let engine = SwitcherEngine(synthesizer: synth, lookup: lookup)
        XCTAssertThrowsError(try engine.switch(to: "uuid-a")) { err in
            XCTAssertEqual(err as? SwitcherError, .ordinalOutOfRange)
        }
        XCTAssertTrue(synth.posted.isEmpty)
    }
}
