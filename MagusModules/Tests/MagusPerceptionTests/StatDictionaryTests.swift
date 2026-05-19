import XCTest
@testable import MagusCore

final class StatDictionaryTests: XCTestCase {

    private func makeDict() -> StatDictionary {
        StatDictionary(referenceEntries: [
            (StatKind(characteristicId: 11), "Vitalité"),
            (StatKind(characteristicId: 12), "Force"),
            (StatKind(characteristicId: 1), "PA"),
            (StatKind(characteristicId: 16), "Sagesse"),
        ])
    }

    func testExactLookup() {
        let dict = makeDict()
        XCTAssertEqual(dict.lookup("Vitalité")?.characteristicId, 11)
        XCTAssertEqual(dict.lookup("Force")?.characteristicId, 12)
    }

    func testCaseInsensitive() {
        let dict = makeDict()
        XCTAssertEqual(dict.lookup("vitalité")?.characteristicId, 11)
        XCTAssertEqual(dict.lookup("VITALITÉ")?.characteristicId, 11)
        XCTAssertEqual(dict.lookup("  ViTalité  ")?.characteristicId, 11)
    }

    func testDiacriticInsensitive() {
        let dict = makeDict()
        XCTAssertEqual(dict.lookup("Vitalite")?.characteristicId, 11)
    }

    func testAliases() {
        let dict = makeDict()
        // "Vita" est un alias de "Vitalité"
        XCTAssertEqual(dict.lookup("Vita")?.characteristicId, 11)
        // "fo" est un alias de "Force"
        XCTAssertEqual(dict.lookup("fo")?.characteristicId, 12)
        // "sa" pour Sagesse
        XCTAssertEqual(dict.lookup("sa")?.characteristicId, 16)
    }

    func testFuzzyMatch() {
        let dict = makeDict()
        // Avec une faute (Vitalitï au lieu de Vitalité)
        XCTAssertEqual(dict.lookupFuzzy("Vitalitï")?.characteristicId, 11)
        // Faute plus grosse
        XCTAssertEqual(dict.lookupFuzzy("Vitaliite")?.characteristicId, 11)
    }

    func testFuzzyMatchToleranceLimit() {
        let dict = makeDict()
        // String très loin → nil
        XCTAssertNil(dict.lookupFuzzy("xyzabcdef"))
    }

    func testUnknown() {
        let dict = makeDict()
        XCTAssertNil(dict.lookup("Stat qui n'existe pas"))
    }
}
