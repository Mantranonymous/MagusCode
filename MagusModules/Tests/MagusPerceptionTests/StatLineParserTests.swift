import XCTest
@testable import MagusPerception
@testable import MagusCore

final class StatLineParserTests: XCTestCase {

    /// Dictionnaire de test avec quelques stats canoniques.
    private func makeDictionary() -> StatDictionary {
        let entries: [(kind: StatKind, displayName: String)] = [
            (StatKind(characteristicId: 0), "Points de vie"),
            (StatKind(characteristicId: 1), "PA"),
            (StatKind(characteristicId: 2), "PM"),
            (StatKind(characteristicId: 11), "Vitalité"),
            (StatKind(characteristicId: 12), "Force"),
            (StatKind(characteristicId: 13), "Intelligence"),
            (StatKind(characteristicId: 14), "Chance"),
            (StatKind(characteristicId: 15), "Agilité"),
            (StatKind(characteristicId: 16), "Sagesse"),
        ]
        return StatDictionary(referenceEntries: entries)
    }

    func testParseSimpleStat() {
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "Vitalité 180")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.value, 180)
        XCTAssertEqual(stat?.kind.characteristicId, 11)
        XCTAssertNil(stat?.minValue)
        XCTAssertNil(stat?.maxValue)
    }

    func testParseStatWithRange() {
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "Vitalité 180 (150-200)")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.value, 180)
        XCTAssertEqual(stat?.minValue, 150)
        XCTAssertEqual(stat?.maxValue, 200)
        XCTAssertEqual(stat?.kind.characteristicId, 11)
    }

    func testParseStatWithSlashRange() {
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "Force 87 (50/100)")
        XCTAssertEqual(stat?.value, 87)
        XCTAssertEqual(stat?.minValue, 50)
        XCTAssertEqual(stat?.maxValue, 100)
    }

    func testParseAlias() {
        // "Vita" est un alias par défaut pour "vitalité"
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "Vita 100 (90-150)")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.value, 100)
        XCTAssertEqual(stat?.kind.characteristicId, 11)
    }

    func testParsePA() {
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "PA 11 (10-12)")
        XCTAssertEqual(stat?.value, 11)
        XCTAssertEqual(stat?.kind.characteristicId, 1)
        XCTAssertEqual(stat?.minValue, 10)
        XCTAssertEqual(stat?.maxValue, 12)
    }

    func testFuzzyMatch() {
        // "Vitalite" sans accent doit matcher
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "Vitalite 150")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.kind.characteristicId, 11)
    }

    func testParseAllSplitsByNewline() {
        let parser = StatLineParser(dictionary: makeDictionary())
        let text = """
        Vitalité 180 (150-200)
        Force 87 (50/100)
        PA 11 (10-12)
        """
        let stats = parser.parseAll(text: text)
        XCTAssertEqual(stats.count, 3)
        XCTAssertEqual(stats[0].kind.characteristicId, 11)
        XCTAssertEqual(stats[1].kind.characteristicId, 12)
        XCTAssertEqual(stats[2].kind.characteristicId, 1)
    }

    // MARK: - Format colonnes Dofus 3

    func testParseDofus3ColumnsRaOnly() {
        // Format réel observé : "151 200 208 Vitalité 238"
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "151 200 208 Vitalité 238")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.value, 208)
        XCTAssertEqual(stat?.minValue, 151)
        XCTAssertEqual(stat?.maxValue, 200)
        XCTAssertEqual(stat?.kind.characteristicId, 11)
        XCTAssertEqual(stat?.availability?.raCount, 238)
        XCTAssertEqual(stat?.availability?.paCount, 0)
    }

    func testParseDofus3ColumnsPaAndRa() {
        // "26 35 35 Intelligence 152 41"
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "26 35 35 Intelligence 152 41")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.value, 35)
        XCTAssertEqual(stat?.minValue, 26)
        XCTAssertEqual(stat?.maxValue, 35)
        XCTAssertEqual(stat?.kind.characteristicId, 13)
        XCTAssertEqual(stat?.availability?.paCount, 152)
        XCTAssertEqual(stat?.availability?.raCount, 41)
        XCTAssertTrue(stat?.isAtMax ?? false)
    }

    func testParseDofus3ColumnsFullTriple() {
        // "26 35 34 Chance 224 8 1101"
        let parser = StatLineParser(dictionary: makeDictionary())
        let stat = parser.parse(line: "26 35 34 Chance 224 8 1101")
        XCTAssertNotNil(stat)
        XCTAssertEqual(stat?.value, 34)
        XCTAssertEqual(stat?.kind.characteristicId, 14)
        XCTAssertEqual(stat?.availability?.baseCount, 224)
        XCTAssertEqual(stat?.availability?.paCount, 8)
        XCTAssertEqual(stat?.availability?.raCount, 1101)
    }

    func testParseDofus3ColumnsRejectIfMinGreaterThanMax() {
        let parser = StatLineParser(dictionary: makeDictionary())
        // Si min > max, c'est probablement une mauvaise lecture
        let stat = parser.parse(line: "200 150 180 Vitalité 0")
        XCTAssertNil(stat)
    }

    func testRejectInvalidLine() {
        let parser = StatLineParser(dictionary: makeDictionary())
        XCTAssertNil(parser.parse(line: ""))
        XCTAssertNil(parser.parse(line: "   "))
        XCTAssertNil(parser.parse(line: "Pas de chiffre ici"))
    }

    func testStatProgress() throws {
        let parser = StatLineParser(dictionary: makeDictionary())
        // Stat au max
        let max = parser.parse(line: "Vitalité 200 (100-200)")
        XCTAssertEqual(max?.isAtMax, true)
        XCTAssertEqual(max?.rangeProgress, 1.0)

        // Stat au min
        let min = parser.parse(line: "Vitalité 100 (100-200)")
        XCTAssertEqual(min?.isAtMin, true)
        XCTAssertEqual(min?.rangeProgress, 0.0)

        // Stat au milieu
        let mid = parser.parse(line: "Vitalité 150 (100-200)")
        let progress = try XCTUnwrap(mid?.rangeProgress)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }
}
