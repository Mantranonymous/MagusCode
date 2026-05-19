import XCTest
@testable import MagusPerception

final class JobLevelParserTests: XCTestCase {

    func testParseLevelOnly() {
        let parser = JobLevelParser()
        let out = parser.parse(text: "Niveau 158")
        XCTAssertEqual(out.level, 158)
    }

    func testParseLevelWithJobName() {
        let parser = JobLevelParser()
        let out = parser.parse(text: "Forgemagie Niveau 158")
        XCTAssertEqual(out.level, 158)
        XCTAssertEqual(out.jobName, "Forgemagie")
    }

    func testParseLevelMultiline() {
        let parser = JobLevelParser()
        let out = parser.parse(text: """
        Forgemagie
        Niveau 200
        """)
        XCTAssertEqual(out.level, 200)
        XCTAssertEqual(out.jobName, "Forgemagie")
    }

    func testRejectInvalidLevel() {
        let parser = JobLevelParser()
        // 300 hors range (1-200)
        let out = parser.parse(text: "Niveau 300")
        XCTAssertNil(out.level)
    }

    func testEmptyText() {
        let parser = JobLevelParser()
        let out = parser.parse(text: "")
        XCTAssertNil(out.level)
        XCTAssertNil(out.jobName)
    }
}
