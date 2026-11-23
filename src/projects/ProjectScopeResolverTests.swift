import XCTest

final class ProjectScopeResolverTests: XCTestCase {
    private func shown(project: Bool = true, member: Bool = true, spaces: [UInt64] = [2], screen: Bool = false,
                       minimized: Bool = false, phantom: Bool = false, hidden: Bool = false,
                       tabbed: Bool = false, excluded: Bool = false, visibleSpaces: [UInt64] = [1, 3]) -> Bool {
        let scope = ProjectScopeResolver.resolve(hasActiveProject: project,
            visibleOnly: true, nonVisibleOnly: false, screenOnly: true, visibleSpaceIds: visibleSpaces)
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

    private func labelShown(spaces: [UInt64], visibleSpaces: [UInt64], onScreen: Bool = true,
                            minimized: Bool = false, hidden: Bool = false, excluded: Bool = false,
                            nonVisibleOnly: Bool = false) -> Bool {
        let scope = ProjectScopeResolver.resolve(hasActiveProject: false, isDesktopLabel: true,
            visibleOnly: !nonVisibleOnly, nonVisibleOnly: nonVisibleOnly, screenOnly: true, visibleSpaceIds: visibleSpaces)
        let window = WindowState(id: "label", isPhantom: false, isWindowlessApp: false, isFullscreen: false,
            isMinimized: minimized, isTabbed: false, isOnAllSpaces: false, spaceIds: spaces, spaceIndexes: [],
            lastFocusOrder: 0, creationOrder: 0, title: "Desktop 1")
        let app = ApplicationState(pid: 1, bundleIdentifier: "com.example", localizedName: nil, isHidden: hidden)
        let exceptions = excluded ? [ExceptionEntry(bundleIdentifier: "com.example", hide: .always, ignore: .none)] : []
        return WindowFilterResolver.shouldShow(window, app, hideHidden: true, hideMinimized: true,
            onlyVisibleSpaces: scope.visibleOnly, onlyNonVisibleSpaces: scope.nonVisibleOnly,
            onlyPreferredScreen: scope.screenOnly, visibleSpaceIds: scope.spaceIds,
            exceptions: exceptions, isOnPreferredScreen: onScreen)
    }

    func testDesktopOneLabelRemainsAvailableAfterCreatingAndEnteringDesktopTwo() {
        XCTAssertTrue(labelShown(spaces: [1], visibleSpaces: [1, 3]))
        XCTAssertTrue(labelShown(spaces: [1], visibleSpaces: [2, 3]))
        XCTAssertFalse(shown(project: false, spaces: [1], screen: true, visibleSpaces: [2, 3]))
    }

    func testDesktopLabelsStillRespectThePreferredMonitor() {
        XCTAssertFalse(labelShown(spaces: [3], visibleSpaces: [2, 3], onScreen: false))
    }

    func testDesktopLabelsRemainAvailableWithNonVisibleSpaceFilter() {
        XCTAssertTrue(labelShown(spaces: [1], visibleSpaces: [1, 3], nonVisibleOnly: true))
        XCTAssertTrue(labelShown(spaces: [1], visibleSpaces: [2, 3], nonVisibleOnly: true))
    }

    func testDesktopLabelsHonorOrdinaryWindowExclusions() {
        XCTAssertFalse(labelShown(spaces: [1], visibleSpaces: [2, 3], minimized: true))
        XCTAssertFalse(labelShown(spaces: [1], visibleSpaces: [2, 3], hidden: true))
        XCTAssertFalse(labelShown(spaces: [1], visibleSpaces: [2, 3], excluded: true))
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
