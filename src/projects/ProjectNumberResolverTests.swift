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

    func testSharedDesktopUsesItsFirstClaimForBothDigitKeyboards() {
        let choices = ProjectNumberResolver.choices([.init(id: "older-arrival", desktopNumber: 2, claimIndex: 1),
            .init(id: "resident", desktopNumber: 2, claimIndex: 0), .init(id: "unlinked", desktopNumber: 2)], desktopCount: 3)
        XCTAssertEqual(choices.map { $0.id }, ["resident", "older-arrival", "unlinked"])
        XCTAssertEqual(choices.map { $0.label }, ["2", "2", "2"])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 19, choices: choices), "resident")
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 84, choices: choices), "resident")
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 18, choices: choices))
    }

    func testDesktopNumbersAboveNineStayVisibleAndZeroSelectsTen() {
        let choices = ProjectNumberResolver.choices([.init(id: "eleven", desktopNumber: 11),
            .init(id: "ten", desktopNumber: 10)], desktopCount: 11)
        XCTAssertEqual(choices.map { $0.label }, ["10", "11"])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 29, choices: choices), "ten")
        XCTAssertNil(choices.last?.shortcutIndex)
    }

    func testSharedDesktopDigitsCycleInDisplayOrderAndWrap() {
        let choices = ProjectNumberResolver.choices([.init(id: "second", desktopNumber: 1, claimIndex: 1),
            .init(id: "other", desktopNumber: 2), .init(id: "first", desktopNumber: 1, claimIndex: 0),
            .init(id: "third", desktopNumber: 1)], desktopCount: 2)
        for keyCode: UInt16 in [18, 83] {
            var selected: String?
            for expected in ["first", "second", "third", "first", "second"] {
                selected = ProjectNumberResolver.projectId(keyCode: keyCode, choices: choices, currentProjectId: selected)
                XCTAssertEqual(selected, expected)
            }
        }
    }

    func testDigitStartsAtFirstMatchWhenCurrentProjectIsElsewhereOrMissing() {
        let choices = ProjectNumberResolver.choices([.init(id: "first", desktopNumber: 1),
            .init(id: "second", desktopNumber: 1), .init(id: "other", desktopNumber: 2)], desktopCount: 2)
        for current in ["other", "deleted"] {
            XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 18, choices: choices, currentProjectId: current), "first")
        }
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 20, choices: choices, currentProjectId: "first"))
        XCTAssertNil(ProjectNumberResolver.projectId(keyCode: 18, choices: [], currentProjectId: "deleted"))
    }

    func testSingleDesktopKeepsUniqueProjectDigitsInCreationOrder() {
        let entries = (0..<12).map { ProjectNumberResolver.Entry(id: "p\($0)", desktopNumber: 1, claimIndex: 11 - $0) }
        let choices = ProjectNumberResolver.choices(entries, desktopCount: 1)
        XCTAssertEqual(choices.map { $0.id }, entries.map { $0.id })
        XCTAssertEqual(choices.compactMap { $0.label }, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 21, choices: choices), "p3")
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 21, choices: choices, currentProjectId: "p3"), "p3")
        XCTAssertEqual(ProjectNumberResolver.projectId(keyCode: 29, choices: choices), "p9")
        XCTAssertNil(choices[10].shortcutIndex)
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
