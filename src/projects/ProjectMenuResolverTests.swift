import XCTest

final class ProjectMenuResolverTests: XCTestCase {
    private final class Candidate {
        let id: String
        let order: Int
        let eligible: Bool
        let focused: Bool

        init(_ id: String, order: Int, eligible: Bool = true, focused: Bool = false) {
            self.id = id
            self.order = order
            self.eligible = eligible
            self.focused = focused
        }
    }

    private func currentWindow(_ windows: [Candidate]) -> Candidate? {
        ProjectMenuResolver.currentWindow(in: windows, isEligible: { $0.eligible }, isFocused: { $0.focused }, focusOrder: { $0.order })
    }

    func testCurrentWindowPrefersTheFocusedAppWindowOverStaleRanks() {
        let recent = Candidate("recent", order: 0)
        let focused = Candidate("focused", order: 3, focused: true)
        XCTAssertTrue(currentWindow([recent, focused]) === focused)
    }

    func testCurrentWindowSurvivesLabelAndSettingsFocus() {
        let recent = Candidate("editor", order: 2)
        let older = Candidate("browser", order: 3)
        let label = Candidate("label", order: 0, eligible: false, focused: true)
        let settings = Candidate("settings", order: 1, eligible: false)
        XCTAssertTrue(currentWindow([older, label, settings, recent]) === recent)
    }

    func testCurrentWindowIsEmptyWithoutAnEligibleAppWindow() {
        XCTAssertNil(currentWindow([]))
        XCTAssertNil(currentWindow([Candidate("label", order: 0, eligible: false, focused: true)]))
    }

    func testMoveKeepsCapturedWindowWhenFocusChanges() {
        let captured = Candidate("editor", order: 4)
        let newlyFocused = Candidate("browser", order: 0, focused: true)
        XCTAssertTrue(ProjectMenuResolver.liveTarget(captured, in: [newlyFocused, captured], isEligible: { $0.eligible }) === captured)
    }

    func testClosedMoveTargetCannotBeReplacedByAReusedWindowId() {
        let captured = Candidate("same-id", order: 1)
        let replacement = Candidate("same-id", order: 0)
        XCTAssertNil(ProjectMenuResolver.liveTarget(captured, in: [replacement], isEligible: { $0.eligible }))
        XCTAssertNil(ProjectMenuResolver.liveTarget(captured, in: [captured], isEligible: { _ in false }))
    }

    func testMoveAllowsUnassignedAndMultipleMembershipsButDisablesSoleOwner() {
        XCTAssertTrue(ProjectMenuResolver.canMove(to: "a", memberships: []))
        XCTAssertTrue(ProjectMenuResolver.canMove(to: "a", memberships: ["b"]))
        XCTAssertTrue(ProjectMenuResolver.canMove(to: "a", memberships: ["a", "b"]))
        XCTAssertFalse(ProjectMenuResolver.canMove(to: "a", memberships: ["a"]))
    }

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
