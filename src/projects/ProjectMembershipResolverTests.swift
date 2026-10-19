import XCTest

final class ProjectMembershipResolverTests: XCTestCase {
    func testDisabledFiltersNothing() {
        XCTAssertNil(ProjectMembershipResolver.activeMembers(isEnabled: false, activeIsCustom: true,
            members: ["member"], currentDesktopWindows: ["local"]))
    }

    func testDesktopFiltersNothing() {
        XCTAssertNil(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: false,
            members: [], currentDesktopWindows: ["local"]))
    }

    func testCustomIncludesRemoteMembersAndEveryCurrentDesktopWindow() {
        let local = ProjectMembershipResolver.onDesktop(spaceId: 3,
            windowSpaces: ["member": [8], "unassigned": [3], "other-project": [3], "other-desktop": [4]])
        let members = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: ["member"], currentDesktopWindows: local)
        XCTAssertEqual(members, ["member", "unassigned", "other-project"])
    }

    func testSelectingDifferentProjectsRetainsCurrentDesktopWindowsWithoutChangingMembership() {
        let first: Set<String> = ["first-remote"]
        let second: Set<String> = ["second-remote"]
        let local: Set<String> = ["first-local", "second-local", "unassigned"]
        XCTAssertEqual(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: first, currentDesktopWindows: local), first.union(local))
        XCTAssertEqual(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: second, currentDesktopWindows: local), second.union(local))
        XCTAssertEqual(first, ["first-remote"])
        XCTAssertEqual(second, ["second-remote"])
    }

    func testGoneWindowDoesNotCreateACandidate() {
        let members = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-1", "wid-2"])
        XCTAssertEqual(["wid-2", "wid-3"].filter { members?.contains($0) ?? true }, ["wid-2"])
    }

    func testEmptyCustomShowsOnlyCurrentDesktopWindows() {
        XCTAssertEqual(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: [], currentDesktopWindows: ["local"]), ["local"])
        XCTAssertEqual(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: []), Set<String>())
    }

    func testWindowMayBelongToSeveralProjects() {
        let first = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-1", "wid-2"])
        let second = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-2", "wid-3"])
        XCTAssertEqual(first?.intersection(second ?? []), ["wid-2"])
        XCTAssertEqual(first, ["wid-1", "wid-2"])
        XCTAssertEqual(second, ["wid-2", "wid-3"])
    }

    func testAutomaticAssignmentCandidatesExcludeOtherProjectsMembers() {
        let spaces: [String: [UInt64]] = ["unassigned": [3], "other-project": [3], "remote": [4]]
        XCTAssertEqual(ProjectMembershipResolver.onDesktop(spaceId: 3, windowSpaces: spaces), ["unassigned", "other-project"])
        XCTAssertEqual(ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3, windowSpaces: spaces,
            assigned: ["other-project"]), ["unassigned"])
    }

    func testLateSpaceInformationMakesWindowEligible() {
        XCTAssertEqual(ProjectMembershipResolver.onDesktop(spaceId: 3, windowSpaces: ["settings": []]), [])
        XCTAssertEqual(ProjectMembershipResolver.onDesktop(spaceId: 3, windowSpaces: ["settings": [3]]), ["settings"])
    }

    func testOtherVisibleDesktopDoesNotCountAsCurrentDesktop() {
        XCTAssertEqual(ProjectMembershipResolver.onDesktop(spaceId: 3,
            windowSpaces: ["current": [3], "second-display": [4], "all-spaces": [3, 4]]),
            ["current", "all-spaces"])
    }

    func testMovingNonmemberChangesVisibilityWithoutChangingProject() {
        let project: Set<String> = ["member"]
        let before = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: project,
            currentDesktopWindows: ProjectMembershipResolver.onDesktop(spaceId: 3, windowSpaces: ["local": [3]]))
        let after = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: project,
            currentDesktopWindows: ProjectMembershipResolver.onDesktop(spaceId: 3, windowSpaces: ["local": [4]]))
        XCTAssertEqual(before, ["member", "local"])
        XCTAssertEqual(after, ["member"])
        XCTAssertEqual(project, ["member"])
    }

    func testRepairedMembershipKeepsWindowVisible() {
        let local: Set<String> = ["settings"]
        let before = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: [], currentDesktopWindows: local)
        let after = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: ["settings"], currentDesktopWindows: local)
        XCTAssertEqual(before, ["settings"])
        XCTAssertEqual(after, before)
    }
}
