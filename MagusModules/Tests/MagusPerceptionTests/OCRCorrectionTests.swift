import XCTest
@testable import MagusPerception

final class OCRCorrectionTests: XCTestCase {

    func testParseIntDirect() {
        XCTAssertEqual(OCRCorrection.parseInt("180"), 180)
        XCTAssertEqual(OCRCorrection.parseInt(" 42 "), 42)
        XCTAssertEqual(OCRCorrection.parseInt("87"), 87)
    }

    func testParseIntWithSubstitutions() {
        // "lOO" devrait devenir "100" via l→1, O→0
        XCTAssertEqual(OCRCorrection.parseInt("lOO"), 100)
        // "S0" → "50"
        XCTAssertEqual(OCRCorrection.parseInt("S0"), 50)
        // "8" reste 8
        XCTAssertEqual(OCRCorrection.parseInt("8"), 8)
    }

    func testParseIntWithRangeConstraint() {
        // Si la value brute "5OO" est lue, on devrait obtenir 500
        XCTAssertEqual(OCRCorrection.parseInt("5OO"), 500)
        // Si on attend 0-100, "5OO" sera hors range donc nil (sauf si la correction réduit)
        XCTAssertEqual(OCRCorrection.parseInt("87", expectedRange: 0...100), 87)
    }

    func testFirstInt() {
        XCTAssertEqual(OCRCorrection.firstInt(in: "Vitalité 180 (150-200)"), 180)
        XCTAssertEqual(OCRCorrection.firstInt(in: "Niveau 158"), 158)
        XCTAssertEqual(OCRCorrection.firstInt(in: "+5 Force"), 5)
        XCTAssertNil(OCRCorrection.firstInt(in: "Pas de chiffre"))
    }

    func testStripNonDigits() {
        XCTAssertEqual(OCRCorrection.stripNonDigits("123 abc 456"), "123456")
        XCTAssertEqual(OCRCorrection.stripNonDigits("+87%"), "+87")
        XCTAssertEqual(OCRCorrection.stripNonDigits("-12"), "-12")
    }
}
