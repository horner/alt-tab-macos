import XCTest

final class ProjectScopeResolverTests: XCTestCase {
    private func shown(project: Bool = true, current: Bool = false, member: Bool = true, space: UInt64 = 2,
                       screen: Bool = false, minimized: Bool = false, phantom: Bool = false, unassigned: Bool = false) -> Bool {
        let scope = ProjectScopeResolver.resolve(hasActiveProject: project, currentOnly: current,
            visibleOnly: true, nonVisibleOnly: false, screenOnly: true, visibleSpaceIds: [1, 3], currentSpaceId: 1)
        let window = WindowState(id: "w", isPhantom: phantom, isWindowlessApp: false, isFullscreen: false,
            isMinimized: minimized, isTabbed: false, isOnAllSpaces: false, spaceIds: [space], spaceIndexes: [],
            lastFocusOrder: 0, creationOrder: 0, title: "Window")
        let app = ApplicationState(pid: 1, bundleIdentifier: nil, localizedName: nil, isHidden: false)
        let local = ProjectMembershipResolver.unassignedOnDesktop(spaceId: 1,
            windowSpaces: ["w": [space]], assigned: unassigned ? [] : ["w"])
        let members = ProjectMembershipResolver.activeMembers(isEnabled: project, activeIsCustom: project,
            members: member ? ["w"] : [], unassignedOnDesktop: local)
        return WindowFilterResolver.shouldShow(window, app, hideMinimized: true,
            onlyVisibleSpaces: scope.visibleOnly, onlyNonVisibleSpaces: scope.nonVisibleOnly,
            onlyPreferredScreen: scope.screenOnly, visibleSpaceIds: scope.spaceIds,
            activeProjectMembers: members, isOnPreferredScreen: screen)
    }

    func testAllLocationsIncludesOffSpaceAndOffScreenMember() {
        XCTAssertTrue(shown())
    }

    func testAllLocationsStillExcludesNonmembersAndOtherHiddenWindows() {
        XCTAssertFalse(shown(member: false))
        XCTAssertFalse(shown(minimized: true))
        XCTAssertFalse(shown(phantom: true))
    }

    func testCurrentLocationRequiresCurrentSpaceAndScreen() {
        XCTAssertTrue(shown(current: true, space: 1, screen: true))
        XCTAssertFalse(shown(current: true, space: 2, screen: true))
        XCTAssertFalse(shown(current: true, space: 1, screen: false))
        XCTAssertFalse(shown(current: true, space: 3, screen: true))
    }

    func testNoActiveProjectPreservesNormalLocationFilters() {
        XCTAssertFalse(shown(project: false))
        XCTAssertTrue(shown(project: false, space: 3, screen: true))
    }

    func testProjectOverridesNonVisibleSpaceSetting() {
        let scope = ProjectScopeResolver.resolve(hasActiveProject: true, currentOnly: false,
            visibleOnly: false, nonVisibleOnly: true, screenOnly: true, visibleSpaceIds: [1], currentSpaceId: 1)
        XCTAssertFalse(scope.visibleOnly || scope.nonVisibleOnly || scope.screenOnly)
    }

    func testUnassignedCurrentDesktopWindowPassesProjectFilter() {
        XCTAssertTrue(shown(member: false, space: 1, unassigned: true))
        XCTAssertFalse(shown(member: false, space: 2, unassigned: true))
        XCTAssertFalse(shown(member: false, space: 1, unassigned: false))
    }

    func testUnassignedFallbackStillHonorsOrdinaryFilters() {
        XCTAssertFalse(shown(member: false, space: 1, minimized: true, unassigned: true))
        XCTAssertFalse(shown(member: false, space: 1, phantom: true, unassigned: true))
        XCTAssertFalse(shown(current: true, member: false, space: 1, screen: false, unassigned: true))
        XCTAssertTrue(shown(current: true, member: false, space: 1, screen: true, unassigned: true))
    }
}
