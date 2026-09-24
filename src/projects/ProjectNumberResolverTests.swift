import XCTest

final class ProjectNumberResolverTests: XCTestCase {
    func testProjectNumbersFollowDesktopOrderInsteadOfCreationOrder() {
        let choices = ProjectNumberResolver.choices([.init(id: "old", desktopNumber: 3),
            .init(id: "new-one", desktopNumber: 1), .init(id: "new-two", desktopNumber: 2)], desktopCount: 3)
        XCTAssertEqual(choices.map { $0.id }, ["new-one", "new-two", "old"])
        XCTAssertEqual(choices.map { $0.label }, ["1", "2", "3"])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 18, choices: choices), "new-one")
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 20, choices: choices), "old")
    }

    func testUnassignedProjectCannotClaimOwnedDesktopNumber() {
        let choices = ProjectNumberResolver.choices([.init(id: "unassigned", desktopNumber: nil),
            .init(id: "owner", desktopNumber: 2)], desktopCount: 3)
        XCTAssertEqual(choices.map { $0.id }, ["owner", "unassigned"])
        XCTAssertEqual(choices.map { $0.label }, ["2", nil])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 19, choices: choices), "owner")
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 84, choices: choices), "owner")
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 18, choices: choices))
    }

    func testDesktopNumbersAboveNineStayVisibleAndZeroSelectsTen() {
        let choices = ProjectNumberResolver.choices([.init(id: "eleven", desktopNumber: 11),
            .init(id: "ten", desktopNumber: 10)], desktopCount: 11)
        XCTAssertEqual(choices.map { $0.label }, ["10", "11"])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 29, choices: choices), "ten")
        XCTAssertNil(choices.last?.shortcutIndex)
    }

    func testDigitSelectsItsOwnerRegardlessOfCurrentSelection() {
        let choices = ProjectNumberResolver.choices([.init(id: "first", desktopNumber: 1),
            .init(id: "other", desktopNumber: 2), .init(id: "unassigned", desktopNumber: nil)], desktopCount: 2)
        for current in ["first", "other", "unassigned", "deleted"] {
            XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 18, choices: choices, currentProjectId: current), "first")
        }
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 20, choices: choices, currentProjectId: "first"))
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 18, choices: [], currentProjectId: "deleted"))
    }

    func testSingleDesktopDoesNotInventNumbersForUnassignedProjects() {
        let choices = ProjectNumberResolver.choices([.init(id: "unassigned", desktopNumber: nil),
            .init(id: "owner", desktopNumber: 1), .init(id: "missing", desktopNumber: nil)], desktopCount: 1)
        XCTAssertEqual(choices.map { $0.id }, ["owner", "unassigned", "missing"])
        XCTAssertEqual(choices.map { $0.label }, ["1", nil, nil])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 18, choices: choices), "owner")
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 19, choices: choices))
    }

    func testUnknownTopologyLeavesAllProjectsUnnumbered() {
        let choices = ProjectNumberResolver.choices([.init(id: "first", desktopNumber: nil),
            .init(id: "second", desktopNumber: nil)], desktopCount: 0)
        XCTAssertEqual(choices.map { $0.label }, [nil, nil])
        XCTAssertTrue(choices.allSatisfy { $0.shortcutIndex == nil })
    }

    func testDesktopRenumberingUpdatesLabelsAndDigitDestinations() {
        let before = ProjectNumberResolver.choices([.init(id: "a", desktopNumber: 1), .init(id: "b", desktopNumber: 2)], desktopCount: 2)
        let after = ProjectNumberResolver.choices([.init(id: "a", desktopNumber: 2), .init(id: "b", desktopNumber: 1)], desktopCount: 2)
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 18, choices: before), "a")
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 18, choices: after), "b")
    }

    func testUnknownDesktopsRemainUnnumberedAndCannotStealDigits() {
        let choices = ProjectNumberResolver.choices([.init(id: "missing", desktopNumber: nil),
            .init(id: "live", desktopNumber: 2)], desktopCount: 2)
        XCTAssertEqual(choices.map { $0.id }, ["live", "missing"])
        XCTAssertNil(choices.last?.label)
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 19, choices: choices), "live")
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 18, choices: choices))
    }

    func testFunctionKeysRemainDesktopShortcuts() {
        let choices = ProjectNumberResolver.choices([.init(id: "a", desktopNumber: 1)], desktopCount: 2)
        for key: UInt16 in [122, 120, 99, 118] { XCTAssertNil(ProjectNumberResolver.projectId(keyCode: key, choices: choices)) }
    }

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
