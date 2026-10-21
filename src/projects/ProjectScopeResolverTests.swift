import XCTest

final class ProjectScopeResolverTests: XCTestCase {
    private func shown(project: Bool = true, member: Bool = true, spaces: [UInt64] = [2], screen: Bool = false,
                       minimized: Bool = false, phantom: Bool = false, hidden: Bool = false,
                       tabbed: Bool = false, excluded: Bool = false) -> Bool {
        let scope = ProjectScopeResolver.resolve(hasActiveProject: project,
            visibleOnly: true, nonVisibleOnly: false, screenOnly: true, visibleSpaceIds: [1, 3])
        let window = WindowState(id: "w", isPhantom: phantom, isWindowlessApp: false, isFullscreen: false,
            isMinimized: minimized, isTabbed: tabbed, isOnAllSpaces: false, spaceIds: spaces, spaceIndexes: [],
            lastFocusOrder: 0, creationOrder: 0, title: "Window")
        let app = ApplicationState(pid: 1, bundleIdentifier: "com.example", localizedName: nil, isHidden: hidden)
        let local = ProjectMembershipResolver.onDesktop(spaceId: 1, windowSpaces: ["w": spaces])
        let members = ProjectMembershipResolver.activeMembers(isEnabled: project, activeIsCustom: project,
            members: member ? ["w"] : [], currentDesktopWindows: local)
        let exceptions = excluded ? [ExceptionEntry(bundleIdentifier: "com.example", hide: .always, ignore: .none)] : []
        return WindowFilterResolver.shouldShow(window, app, hideHidden: true, hideMinimized: true,
            onlyVisibleSpaces: scope.visibleOnly, onlyNonVisibleSpaces: scope.nonVisibleOnly,
            onlyPreferredScreen: scope.screenOnly, visibleSpaceIds: scope.spaceIds,
            exceptions: exceptions, activeProjectMembers: members, isOnPreferredScreen: screen)
    }

    func testRemoteProjectMemberIgnoresSpaceAndScreenFilters() {
        XCTAssertTrue(shown())
        XCTAssertTrue(shown(spaces: [], screen: false))
    }

    func testCurrentDesktopNonmemberAppearsRegardlessOfScreen() {
        XCTAssertTrue(shown(member: false, spaces: [1], screen: true))
        XCTAssertTrue(shown(member: false, spaces: [1], screen: false))
    }

    func testRemoteNonmemberAndOtherDisplaysDesktopStayExcluded() {
        XCTAssertFalse(shown(member: false))
        XCTAssertFalse(shown(member: false, spaces: [3], screen: true))
        XCTAssertFalse(shown(member: false, spaces: []))
        XCTAssertTrue(shown(member: false, spaces: [1, 3]))
    }

    func testProjectUnionHonorsOrdinaryWindowExclusions() {
        for member in [false, true] {
            XCTAssertFalse(shown(member: member, spaces: [1], minimized: true))
            XCTAssertFalse(shown(member: member, spaces: [1], phantom: true))
            XCTAssertFalse(shown(member: member, spaces: [1], hidden: true))
            XCTAssertFalse(shown(member: member, spaces: [1], tabbed: true))
            XCTAssertFalse(shown(member: member, spaces: [1], excluded: true))
        }
    }

    func testNoActiveProjectPreservesNormalLocationFilters() {
        XCTAssertFalse(shown(project: false))
        XCTAssertFalse(shown(project: false, spaces: [1], screen: false))
        XCTAssertTrue(shown(project: false, spaces: [3], screen: true))
    }

    func testProjectOverridesNonVisibleSpaceSettingWithoutQueryingScreen() {
        let scope = ProjectScopeResolver.resolve(hasActiveProject: true,
            visibleOnly: false, nonVisibleOnly: true, screenOnly: true, visibleSpaceIds: [1])
        XCTAssertFalse(scope.visibleOnly || scope.nonVisibleOnly || scope.screenOnly)
        var screenQueries = 0
        func isOnScreen() -> Bool {
            screenQueries += 1
            return false
        }
        let window = WindowState(id: "w", isPhantom: false, isWindowlessApp: false, isFullscreen: false,
            isMinimized: false, isTabbed: false, isOnAllSpaces: false, spaceIds: [1], spaceIndexes: [],
            lastFocusOrder: 0, creationOrder: 0, title: "Window")
        let app = ApplicationState(pid: 1, bundleIdentifier: nil, localizedName: nil, isHidden: false)
        XCTAssertTrue(WindowFilterResolver.shouldShow(window, app,
            onlyVisibleSpaces: scope.visibleOnly, onlyNonVisibleSpaces: scope.nonVisibleOnly,
            onlyPreferredScreen: scope.screenOnly, visibleSpaceIds: scope.spaceIds,
            activeProjectMembers: ["w"], isOnPreferredScreen: isOnScreen()))
        XCTAssertEqual(screenQueries, 0)
    }
}
