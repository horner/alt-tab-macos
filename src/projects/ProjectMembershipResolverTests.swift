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
}
