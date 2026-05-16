import XCTest
@testable import SpaceRenamerCore

final class NameStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: NameStore!

    override func setUp() {
        super.setUp()
        suiteName = "NameStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = NameStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_unknownUUID_returnsDefaultNameUsingOrdinal() {
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 3), "Desktop 3")
    }

    func test_setName_persists() {
        store.setName("uuid-abc", "Research")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 1), "Research")
    }

    func test_setName_emptyString_revertsToDefault() {
        store.setName("uuid-abc", "Research")
        store.setName("uuid-abc", "")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 2), "Desktop 2")
    }

    func test_setName_whitespaceOnly_revertsToDefault() {
        store.setName("uuid-abc", "   ")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 4), "Desktop 4")
    }

    func test_forget_removesName() {
        store.setName("uuid-abc", "Research")
        store.forget("uuid-abc")
        XCTAssertEqual(store.name(for: "uuid-abc", defaultOrdinal: 5), "Desktop 5")
    }

    func test_namesSurviveStoreReconstruction() {
        store.setName("uuid-abc", "Research")
        let reborn = NameStore(defaults: defaults)
        XCTAssertEqual(reborn.name(for: "uuid-abc", defaultOrdinal: 1), "Research")
    }

    func test_systemShortcutsWarningFlag_defaultsFalse_thenPersists() {
        XCTAssertFalse(store.didWarnAboutSystemShortcuts)
        store.didWarnAboutSystemShortcuts = true
        let reborn = NameStore(defaults: defaults)
        XCTAssertTrue(reborn.didWarnAboutSystemShortcuts)
    }
}
