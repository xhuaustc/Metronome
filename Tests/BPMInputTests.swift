import XCTest
@testable import MetronomeCore

final class BPMInputTests: XCTestCase {

    func testAcceptsInRangeValues() {
        XCTAssertEqual(BPMInput.parse("96"), 96)
        XCTAssertEqual(BPMInput.parse("20"), 20)
        XCTAssertEqual(BPMInput.parse("400"), 400)
        XCTAssertEqual(BPMInput.parse("  120  "), 120, "首尾空白应被忽略")
    }

    func testClampsOutOfRange() {
        XCTAssertEqual(BPMInput.parse("999"), 400)
        XCTAssertEqual(BPMInput.parse("0"), 20)
        XCTAssertEqual(BPMInput.parse("12"), 20)
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(BPMInput.parse(""))
        XCTAssertNil(BPMInput.parse("   "))
        XCTAssertNil(BPMInput.parse("abc"))
        XCTAssertNil(BPMInput.parse("9 6"))
        XCTAssertNil(BPMInput.parse("96.5"))
    }

    func testNegativeValuesClampLikeAnyOtherOutOfRange() {
        XCTAssertEqual(BPMInput.parse("-120"), 20)
    }

    func testHorizontalDragMovesRulerWithFinger() {
        XCTAssertEqual(BPMInput.value(afterHorizontalDrag: 20, from: 96), 76)
        XCTAssertEqual(BPMInput.value(afterHorizontalDrag: -20, from: 96), 116)
        XCTAssertEqual(BPMInput.value(afterHorizontalDrag: 60, from: 96), 46)
        XCTAssertEqual(BPMInput.value(afterHorizontalDrag: 500, from: 96), 20)
        XCTAssertEqual(BPMInput.value(afterHorizontalDrag: -1000, from: 96), 400)
        XCTAssertEqual(BPMInput.value(afterHorizontalDrag: .nan, from: 96), 96)
    }

    func testClampHelper() {
        XCTAssertEqual(BPMInput.clamp(10), 20)
        XCTAssertEqual(BPMInput.clamp(500), 400)
        XCTAssertEqual(BPMInput.clamp(96), 96)
    }
}
