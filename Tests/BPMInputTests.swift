import XCTest
@testable import MetronomeCore

final class BPMInputTests: XCTestCase {

    func testAcceptsInRangeValues() {
        XCTAssertEqual(BPMInput.parse("96"), 96)
        XCTAssertEqual(BPMInput.parse("30"), 30)
        XCTAssertEqual(BPMInput.parse("240"), 240)
        XCTAssertEqual(BPMInput.parse("  120  "), 120, "首尾空白应被忽略")
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(BPMInput.parse("999"), 240)
        XCTAssertEqual(BPMInput.parse("0"), 30)
        XCTAssertEqual(BPMInput.parse("12"), 30)
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(BPMInput.parse(""))
        XCTAssertNil(BPMInput.parse("   "))
        XCTAssertNil(BPMInput.parse("abc"))
        XCTAssertNil(BPMInput.parse("9 6"))
        XCTAssertNil(BPMInput.parse("96.5"))
    }

    func testNegativeValuesClampLikeAnyOtherOutOfRange() {
        XCTAssertEqual(BPMInput.parse("-120"), 30)
    }

    func testClampHelper() {
        XCTAssertEqual(BPMInput.clamp(10), 30)
        XCTAssertEqual(BPMInput.clamp(500), 240)
        XCTAssertEqual(BPMInput.clamp(96), 96)
    }
}
