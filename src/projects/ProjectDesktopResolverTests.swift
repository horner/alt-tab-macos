import XCTest

final class ProjectDesktopResolverTests: XCTestCase {
    func testMovedLabelUsesItsActualDesktopWhileBothDesktopsRemain() {
        let location = ProjectDesktopResolver.LabelLocation(labelId: "project", sourceUuid: "s2", spaceIds: [1])
        XCTAssertEqual(ProjectDesktopResolver.relocation(location, in: [space(1), space(2)]), space(1))
    }

    func testUnchangedAndAmbiguousLabelLocationsDoNotRelink() {
        for ids: [UInt64] in [[], [2], [1, 2], [99]] {
            XCTAssertNil(ProjectDesktopResolver.relocation(.init(labelId: "project", sourceUuid: "s2", spaceIds: ids),
                in: [space(1), space(2)]))
        }
    }

    func testLabelRelocationDoesNotOverrideDesktopDeletionOrDisconnection() {
        XCTAssertNil(ProjectDesktopResolver.relocation(.init(labelId: "project", sourceUuid: "s2", spaceIds: [1]), in: [space(1)]))
    }

    func testFullscreenLocationsDoNotRelinkProjects() {
        XCTAssertNil(ProjectDesktopResolver.relocation(.init(labelId: "project", sourceUuid: "s2", spaceIds: [1]),
            in: [space(1, fullscreen: true), space(2)]))
        XCTAssertNil(ProjectDesktopResolver.relocation(.init(labelId: "project", sourceUuid: "s1", spaceIds: [2]),
            in: [space(1, fullscreen: true), space(2)]))
    }

    func testMovingALabelToAnotherConnectedDisplayUpdatesItsDesktop() {
        let destination = space(1, "external")
        XCTAssertEqual(ProjectDesktopResolver.relocation(.init(labelId: "project", sourceUuid: "s2", spaceIds: [1]),
            in: [destination, space(2)]), destination)
    }

    func testSavingLinksKeepsClaimOrderInsteadOfCheckboxOrder() {
        XCTAssertEqual(ProjectDesktopResolver.linkOrder(existing: ["resident", "arrived"], selected: ["arrived", "resident", "new"]),
            ["resident", "arrived", "new"])
    }

    func testRemovingFirstClaimPromotesNextAndRelinkingAppends() {
        let remaining = ProjectDesktopResolver.linkOrder(existing: ["first", "second", "third"], selected: ["third", "second"])
        XCTAssertEqual(remaining, ["second", "third"])
        XCTAssertEqual(ProjectDesktopResolver.linkOrder(existing: remaining, selected: ["first", "second", "third"]), ["second", "third", "first"])
    }

    func testDesktopArrivalSelectsFirstClaimEvenWhenAnotherProjectWasSelected() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "second", customProjects: ["first", "second"], desktop: "desktop",
            linkedProjects: ["first", "second"], followsDesktop: true, changedDesktop: true), "first")
    }

    func testRoutineRefreshPreservesAnExplicitProjectChoice() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "second", customProjects: ["first", "second"], desktop: "desktop",
            linkedProjects: ["first", "second"], followsDesktop: true, changedDesktop: false), "second")
    }

    func testDesktopFollowingCanStillBeDisabled() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "elsewhere", customProjects: ["first", "elsewhere"], desktop: "desktop",
            linkedProjects: ["first"], followsDesktop: false, changedDesktop: true), "elsewhere")
    }

    func testStartupAndDeletedSelectionUseFirstClaimOrDesktop() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: nil, customProjects: ["first"], desktop: "desktop",
            linkedProjects: ["first"], followsDesktop: true, changedDesktop: true), "first")
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "deleted", customProjects: [], desktop: "desktop",
            linkedProjects: [], followsDesktop: true, changedDesktop: false), "desktop")
    }

    private func space(_ id: UInt64, _ display: String = "main", fullscreen: Bool = false) -> SpaceLabelResolver.Space {
        .init(id: id, uuid: "s\(id)", displayIdentifier: display, desktopNumber: fullscreen ? 0 : Int(id), ordinal: Int(id))
    }

    func testLabelFollowsItsActualDestinationBeforeMemberHistory() {
        XCTAssertEqual(ProjectDesktopResolver.destination(for: space(2), previous: [space(1), space(2), space(3)],
            current: [space(1), space(3)], labelSpaces: [3], memberSpaces: [1, 1]), "s3")
    }

    func testClosedLabelUsesSurvivingMemberWindows() {
        XCTAssertEqual(ProjectDesktopResolver.destination(for: space(2), previous: [space(1), space(2), space(3)],
            current: [space(1), space(3)], labelSpaces: [], memberSpaces: [3, 3, 1]), "s3")
    }

    func testEmptyProjectUsesNearestSurvivingDesktopOnSameDisplay() {
        XCTAssertEqual(ProjectDesktopResolver.destination(for: space(2), previous: [space(1), space(2), space(3)],
            current: [space(1), space(3)], labelSpaces: [], memberSpaces: []), "s1")
        XCTAssertEqual(ProjectDesktopResolver.destination(for: space(1), previous: [space(1), space(2)],
            current: [space(2)], labelSpaces: [], memberSpaces: []), "s2")
    }

    func testDisplayDisconnectionDoesNotMergeItsProjects() {
        XCTAssertNil(ProjectDesktopResolver.destination(for: space(2, "external"), previous: [space(1), space(2, "external")],
            current: [space(1)], labelSpaces: [1], memberSpaces: [1]))
    }

    func testFullscreenExitAndUnchangedDesktopDoNotMerge() {
        XCTAssertNil(ProjectDesktopResolver.destination(for: space(2, fullscreen: true), previous: [space(1), space(2, fullscreen: true)],
            current: [space(1)], labelSpaces: [1], memberSpaces: [1]))
        XCTAssertNil(ProjectDesktopResolver.destination(for: space(1), previous: [space(1)],
            current: [space(1)], labelSpaces: [], memberSpaces: []))
    }

    func testMergePreservesEveryProjectWithoutDuplicates() {
        XCTAssertEqual(ProjectDesktopResolver.merge(resident: ["b"], incoming: ["a", "c"]), ["b", "a", "c"])
        XCTAssertEqual(ProjectDesktopResolver.merge(resident: ["b", "a"], incoming: ["a", "c", "c"]), ["b", "a", "c"])
    }

    func testRepeatedDesktopClosuresKeepAllProjects() {
        let first = ProjectDesktopResolver.merge(resident: ["b"], incoming: ["a"])
        XCTAssertEqual(ProjectDesktopResolver.merge(resident: ["c"], incoming: first), ["c", "b", "a"])
    }
}
