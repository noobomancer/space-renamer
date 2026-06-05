import XCTest
@testable import SpaceRenamerCore

@MainActor final class NameStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: NameStore!

    // `setUp()` / `tearDown()` on a `@MainActor` XCTestCase: use the
    // `async throws` overrides so the body inherits the class's main-actor
    // isolation (sync overrides are nonisolated on the base and can't touch
    // @MainActor properties). The base implementations are empty, and calling
    // `try await super.setUp()` from this @MainActor override would send `self`
    // across to the nonisolated base — a Swift 6 "sending" error that fires on
    // some toolchain versions (Swift 6.0 in CI). Skipping super is the
    // cross-version-safe fix.
    override func setUp() async throws {
        suiteName = "NameStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = NameStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_unknownSpaceID_returnsDefaultNameUsingOrdinal() {
        XCTAssertEqual(store.name(for: "42", defaultOrdinal: 3), "Desktop 3")
    }

    func test_setName_persists() {
        store.setName("42", "Research")
        XCTAssertEqual(store.name(for: "42", defaultOrdinal: 1), "Research")
    }

    func test_setName_emptyString_revertsToDefault() {
        store.setName("42", "Research")
        store.setName("42", "")
        XCTAssertEqual(store.name(for: "42", defaultOrdinal: 2), "Desktop 2")
    }

    func test_setName_whitespaceOnly_revertsToDefault() {
        store.setName("42", "   ")
        XCTAssertEqual(store.name(for: "42", defaultOrdinal: 4), "Desktop 4")
    }

    func test_forget_removesName() {
        store.setName("42", "Research")
        store.forget("42")
        XCTAssertEqual(store.name(for: "42", defaultOrdinal: 5), "Desktop 5")
    }

    func test_namesSurviveStoreReconstruction() {
        store.setName("42", "Research")
        let reborn = NameStore(defaults: defaults)
        XCTAssertEqual(reborn.name(for: "42", defaultOrdinal: 1), "Research")
    }

    func test_systemShortcutsWarningFlag_defaultsFalse_thenPersists() {
        XCTAssertFalse(store.didWarnAboutSystemShortcuts)
        store.didWarnAboutSystemShortcuts = true
        let reborn = NameStore(defaults: defaults)
        XCTAssertTrue(reborn.didWarnAboutSystemShortcuts)
    }

    func test_switchMode_defaultsToArrow() {
        XCTAssertEqual(store.switchMode, .arrow)
        XCTAssertEqual(SwitchMode.default, .arrow)
    }

    func test_switchMode_roundTripsAcrossReconstruction() {
        store.switchMode = .ctrlDigit
        let reborn = NameStore(defaults: defaults)
        XCTAssertEqual(reborn.switchMode, .ctrlDigit)
    }

    func test_switchMode_invalidStoredValue_fallsBackToDefault() {
        defaults.set("bogus", forKey: "SpaceRenamer.switchMode")
        XCTAssertEqual(NameStore(defaults: defaults).switchMode, .arrow)
    }

    func test_showMissionControlOverlay_defaultsTrue_thenPersistsExplicitFalse() {
        // Default is on; opt-out by writing false must survive reconstruction.
        XCTAssertTrue(store.showMissionControlOverlay)
        store.showMissionControlOverlay = false
        let reborn = NameStore(defaults: defaults)
        XCTAssertFalse(reborn.showMissionControlOverlay)
    }
}
