import XCTest
@testable import MagusCore

final class MagusCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(MagusCore.version, "0.1.0")
    }
}
