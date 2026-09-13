import XCTest

final class ProjectMembershipResolverTests: XCTestCase {
    func testDisabledFiltersNothing() {
        XCTAssertNil(ProjectMembershipResolver.activeMembers(isEnabled: false, activeIsCustom: true, members: ["wid-1"]))
    }

    func testDesktopFiltersNothing() {
        XCTAssertNil(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: false, members: []))
    }

    func testCustomKeepsOnlyMembers() {
        let members = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-1"])
        XCTAssertEqual(["wid-1", "wid-2"].filter { members?.contains($0) ?? true }, ["wid-1"])
    }

    func testGoneWindowDoesNotCreateACandidate() {
        let members = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-1", "wid-2"])
        XCTAssertEqual(["wid-2", "wid-3"].filter { members?.contains($0) ?? true }, ["wid-2"])
    }

    func testEmptyCustomKeepsNothing() {
        let members = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: [])
        XCTAssertEqual(members, Set<String>())
        XCTAssertEqual(["wid-1"].filter { members?.contains($0) ?? true }, [])
    }

    func testWindowMayBelongToSeveralProjects() {
        let first = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-1", "wid-2"])
        let second = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["wid-2", "wid-3"])
        XCTAssertEqual(first?.intersection(second ?? []), ["wid-2"])
        XCTAssertEqual(first, ["wid-1", "wid-2"])
        XCTAssertEqual(second, ["wid-2", "wid-3"])
    }

    func testCustomIncludesMembersAndUnassignedDesktopWindows() {
        let local = ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3,
            windowSpaces: ["member": [8], "settings": [3], "other-project": [3], "other-desktop": [4]],
            assigned: ["member", "other-project"])
        let members = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true,
            members: ["member"], unassignedOnDesktop: local)
        XCTAssertEqual(members, ["member", "settings"])
    }

    func testLateSpaceInformationMakesUnassignedWindowEligible() {
        XCTAssertEqual(ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3,
            windowSpaces: ["settings": []], assigned: []), [])
        XCTAssertEqual(ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3,
            windowSpaces: ["settings": [3]], assigned: []), ["settings"])
    }

    func testOtherVisibleDesktopDoesNotCountAsCurrentDesktop() {
        XCTAssertEqual(ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3,
            windowSpaces: ["current": [3], "second-display": [4], "all-spaces": [3, 4]], assigned: []),
            ["current", "all-spaces"])
    }

    func testRepairedMembershipKeepsWindowVisible() {
        let spaces: [String: [UInt64]] = ["settings": [3]]
        let before = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: [],
            unassignedOnDesktop: ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3, windowSpaces: spaces, assigned: []))
        let after = ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: true, members: ["settings"],
            unassignedOnDesktop: ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3, windowSpaces: spaces, assigned: ["settings"]))
        XCTAssertEqual(before, ["settings"])
        XCTAssertEqual(after, before)
    }

    func testMovedUnassignedWindowLeavesOldDesktopFallback() {
        let spaces: [String: [UInt64]] = ["settings": [4]]
        XCTAssertEqual(ProjectMembershipResolver.unassignedOnDesktop(spaceId: 3, windowSpaces: spaces, assigned: []), [])
        XCTAssertEqual(ProjectMembershipResolver.unassignedOnDesktop(spaceId: 4, windowSpaces: spaces, assigned: []), ["settings"])
    }

    func testDesktopAndDisabledProjectsIgnoreFallbackMembership() {
        XCTAssertNil(ProjectMembershipResolver.activeMembers(isEnabled: false, activeIsCustom: true,
            members: ["member"], unassignedOnDesktop: ["settings"]))
        XCTAssertNil(ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: false,
            members: [], unassignedOnDesktop: ["settings"]))
    }
}
