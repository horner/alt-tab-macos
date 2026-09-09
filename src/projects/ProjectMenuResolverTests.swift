import XCTest

final class ProjectMenuResolverTests: XCTestCase {
    func testLabelTargetsItsOwnProjectWhenAnotherProjectIsActive() {
        let context = ProjectMenuResolver.context(labelId: "label-a", desktopUuid: "desktop-a", activeProjectId: "b",
            currentDesktopUuid: "desktop-b", projectLabels: ["label-a": "a", "label-b": "b"])
        XCTAssertEqual(context, .init(projectId: "a", desktopUuid: "desktop-a", fromLabel: true))
    }

    func testLabelsOnTheSameDesktopKeepSeparateTargets() {
        let labels = ["label-a": "a", "label-b": "b"]
        let a = ProjectMenuResolver.context(labelId: "label-a", desktopUuid: "desktop", activeProjectId: "b",
            currentDesktopUuid: "desktop", projectLabels: labels)
        let b = ProjectMenuResolver.context(labelId: "label-b", desktopUuid: "desktop", activeProjectId: "a",
            currentDesktopUuid: "desktop", projectLabels: labels)
        XCTAssertEqual(a.projectId, "a")
        XCTAssertEqual(b.projectId, "b")
    }

    func testUnlinkedOrDeletedLabelNeverFallsBackToActiveProject() {
        let context = ProjectMenuResolver.context(labelId: "desktop-a", desktopUuid: "desktop-a", activeProjectId: "b",
            currentDesktopUuid: "desktop-b", projectLabels: ["label-b": "b"])
        XCTAssertNil(context.projectId)
        XCTAssertEqual(context.desktopUuid, "desktop-a")
        XCTAssertTrue(context.fromLabel)
    }

    func testMenubarUsesCurrentProjectAndDesktop() {
        let context = ProjectMenuResolver.context(labelId: nil, desktopUuid: nil, activeProjectId: "a",
            currentDesktopUuid: "desktop-a", projectLabels: [:])
        XCTAssertEqual(context, .init(projectId: "a", desktopUuid: "desktop-a", fromLabel: false))
    }

    func testLabelWindowsCannotBeAssignedRegardlessOfSwitcherPreference() {
        for visible in [true, false] {
            XCTAssertFalse(ProjectMenuResolver.canAssign(isWindowless: false, isPhantom: false, isTabbed: false, labelVisibility: visible))
        }
        XCTAssertTrue(ProjectMenuResolver.canAssign(isWindowless: false, isPhantom: false, isTabbed: false, labelVisibility: nil))
    }

    func testWindowlessPhantomAndTabbedEntriesCannotBeAssigned() {
        XCTAssertFalse(ProjectMenuResolver.canAssign(isWindowless: true, isPhantom: false, isTabbed: false, labelVisibility: nil))
        XCTAssertFalse(ProjectMenuResolver.canAssign(isWindowless: false, isPhantom: true, isTabbed: false, labelVisibility: nil))
        XCTAssertFalse(ProjectMenuResolver.canAssign(isWindowless: false, isPhantom: false, isTabbed: true, labelVisibility: nil))
    }
}
