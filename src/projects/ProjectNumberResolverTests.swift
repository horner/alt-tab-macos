import XCTest

final class ProjectNumberResolverTests: XCTestCase {
    func testTopRowDigitsMatchTheirLabels() {
        XCTAssertEqual([29, 18, 19, 20, 21, 23, 22, 26, 28, 25].compactMap { ProjectNumberResolver.index(keyCode: $0) }, Array(0...9))
    }

    func testKeypadDigitsMatchTheirLabels() {
        XCTAssertEqual([82, 83, 84, 85, 86, 87, 88, 89, 91, 92].compactMap { ProjectNumberResolver.index(keyCode: $0) }, Array(0...9))
    }

    func testOtherKeysAreNotProjectChoices() {
        XCTAssertNil(ProjectNumberResolver.index(keyCode: 48))
        XCTAssertNil(ProjectNumberResolver.index(keyCode: 53))
        XCTAssertNil(ProjectNumberResolver.index(keyCode: 0))
    }
}
