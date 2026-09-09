import XCTest

final class ProjectDesktopResolverTests: XCTestCase {
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
