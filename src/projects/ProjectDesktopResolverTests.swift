import XCTest

final class ProjectDesktopResolverTests: XCTestCase {
    func testAssigningOwnerClearsDisplacedAssignmentAndPreservesOtherProjects() {
        let assignments: [ProjectDesktopResolver.Assignment] = [
            .init(id: "resident", desktopUuid: "desktop-1"),
            .init(id: "incoming", desktopUuid: "desktop-2"),
            .init(id: "other", desktopUuid: "desktop-3")]
        let result = ProjectDesktopResolver.assigning("incoming", to: "desktop-1", among: assignments)
        XCTAssertEqual(result, [.init(id: "resident", desktopUuid: ""),
            .init(id: "incoming", desktopUuid: "desktop-1"), .init(id: "other", desktopUuid: "desktop-3")])
        XCTAssertEqual(result.map { $0.id }, assignments.map { $0.id })
    }

    func testUnassigningDesktopClearsOwnerHome() {
        let assignments: [ProjectDesktopResolver.Assignment] = [
            .init(id: "resident", desktopUuid: "desktop-1"), .init(id: "other", desktopUuid: "desktop-2")]
        XCTAssertEqual(ProjectDesktopResolver.assigning(nil, to: "desktop-1", among: assignments),
            [.init(id: "resident", desktopUuid: ""), .init(id: "other", desktopUuid: "desktop-2")])
    }

    func testExplicitAssignmentRepairsAllConflictingOwners() {
        let assignments: [ProjectDesktopResolver.Assignment] = [
            .init(id: "first", desktopUuid: "desktop-1"), .init(id: "second", desktopUuid: "desktop-1"),
            .init(id: "incoming", desktopUuid: "")]
        let result = ProjectDesktopResolver.assigning("incoming", to: "desktop-1", among: assignments)
        XCTAssertEqual(result.filter { $0.desktopUuid == "desktop-1" }.map { $0.id }, ["incoming"])
        XCTAssertEqual(result.count, assignments.count)
    }

    func testInvalidAssignmentsDoNotUnassignExistingOwner() {
        let assignments: [ProjectDesktopResolver.Assignment] = [.init(id: "resident", desktopUuid: "desktop-1")]
        XCTAssertEqual(ProjectDesktopResolver.assigning("missing", to: "desktop-1", among: assignments), assignments)
        XCTAssertEqual(ProjectDesktopResolver.assigning("resident", to: "", among: assignments), assignments)
    }

    func testReassigningCurrentOwnerIsIdempotent() {
        let assignments: [ProjectDesktopResolver.Assignment] = [.init(id: "resident", desktopUuid: "desktop-1")]
        XCTAssertEqual(ProjectDesktopResolver.assigning("resident", to: "desktop-1", among: assignments), assignments)
    }

    func testDesktopArrivalSelectsOwnerEvenWhenAnotherProjectWasSelected() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "other", customProjects: ["owner", "other"], desktop: "desktop",
            linkedProjects: ["owner"], followsDesktop: true, changedDesktop: true), "owner")
    }

    func testRoutineRefreshPreservesAnExplicitProjectChoice() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "unassigned", customProjects: ["owner", "unassigned"], desktop: "desktop",
            linkedProjects: ["owner"], followsDesktop: true, changedDesktop: false), "unassigned")
    }

    func testDesktopFollowingCanStillBeDisabled() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "elsewhere", customProjects: ["owner", "elsewhere"], desktop: "desktop",
            linkedProjects: ["owner"], followsDesktop: false, changedDesktop: true), "elsewhere")
    }

    func testStartupAndDeletedSelectionUseOwnerOrDesktop() {
        XCTAssertEqual(ProjectDesktopResolver.selection(current: nil, customProjects: ["owner"], desktop: "desktop",
            linkedProjects: ["owner"], followsDesktop: true, changedDesktop: false), "owner")
        XCTAssertEqual(ProjectDesktopResolver.selection(current: "deleted", customProjects: [], desktop: "desktop",
            linkedProjects: [], followsDesktop: true, changedDesktop: false), "desktop")
    }
}
