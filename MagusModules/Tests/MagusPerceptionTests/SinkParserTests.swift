import XCTest
@testable import MagusPerception
@testable import MagusCore

final class SinkParserTests: XCTestCase {

    func testParseSimplePercent() {
        let parser = SinkParser()
        XCTAssertEqual(parser.parse(text: "87 %")?.percent, 87)
        XCTAssertEqual(parser.parse(text: "0%")?.percent, 0)
        XCTAssertEqual(parser.parse(text: "100%")?.percent, 100)
    }

    func testParseWithLabel() {
        let parser = SinkParser()
        XCTAssertEqual(parser.parse(text: "Sink 87%")?.percent, 87)
        XCTAssertEqual(parser.parse(text: "  Sink:  42 %")?.percent, 42)
    }

    func testParseWithoutPercentSign() {
        let parser = SinkParser()
        // Si pas de %, mais nombre dans 0-100, on prend
        XCTAssertEqual(parser.parse(text: "87"), Sink(percent: 87))
    }

    func testRejectOutOfRange() {
        let parser = SinkParser()
        // 150% — hors range
        XCTAssertNil(parser.parse(text: "150 %"))
    }

    func testOCRSubstitution() {
        let parser = SinkParser()
        // "8O%" → "80%"
        XCTAssertEqual(parser.parse(text: "8O%")?.percent, 80)
        // "1OO%" → "100%"
        XCTAssertEqual(parser.parse(text: "1OO%")?.percent, 100)
    }

    func testSinkClampedToRange() {
        let sink = Sink(percent: 250)
        XCTAssertEqual(sink.percent, 100)
        let neg = Sink(percent: -10)
        XCTAssertEqual(neg.percent, 0)
    }
}
