import XCTest

final class ProjectNumberResolverTests: XCTestCase {
    func testTopRowDigitsMatchTheirLabels() {
        XCTAssertEqual([18, 19, 20, 21, 23, 22, 26, 28, 25, 29].compactMap { ProjectNumberResolver.index(keyCode: $0) }, Array(0...9))
    }

    func testKeypadDigitsMatchTheirLabels() {
        XCTAssertEqual([83, 84, 85, 86, 87, 88, 89, 91, 92, 82].compactMap { ProjectNumberResolver.index(keyCode: $0) }, Array(0...9))
    }

    func testOtherKeysAreNotProjectChoices() {
        XCTAssertNil(ProjectNumberResolver.index(keyCode: 48))
        XCTAssertNil(ProjectNumberResolver.index(keyCode: 53))
        XCTAssertNil(ProjectNumberResolver.index(keyCode: 0))
    }
    func testLabelsFollowKeyboardOrderAndStopAfterTen() {
        XCTAssertEqual((0...9).compactMap { ProjectNumberResolver.label(index: $0) }, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        XCTAssertNil(ProjectNumberResolver.label(index: 10))
        XCTAssertNil(ProjectNumberResolver.label(index: 19))
        XCTAssertNil(ProjectNumberResolver.label(index: -1))
    }
}
