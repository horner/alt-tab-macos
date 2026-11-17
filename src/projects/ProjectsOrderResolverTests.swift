import XCTest

final class ProjectsOrderResolverTests: XCTestCase {
    func testOwnerPickerSortsProjectNamesAlphabeticallyIgnoringCase() {
        let names = ["Chevron eCase", "LakeHouse", "artipod", "agent-skills", "cloud", "chimeraSQL", "AltTabProjects", "alt-tab-projects", "TIMS", "agent-identity"]
        XCTAssertEqual(ProjectsOrderResolver.alphabetical(names, name: { $0 }),
            ["agent-identity", "agent-skills", "alt-tab-projects", "AltTabProjects", "artipod", "Chevron eCase", "chimeraSQL", "cloud", "LakeHouse", "TIMS"])
    }

    func testOwnerPickerSortUsesNamesBeforeDesktopAnnotations() {
        let projects = [(name: "Project 10", desktop: 1), (name: "Project 2", desktop: 7), (name: "Project 1", desktop: 9)]
        let sorted = ProjectsOrderResolver.alphabetical(projects, name: { $0.name })
        XCTAssertEqual(sorted.map { $0.name }, ["Project 1", "Project 2", "Project 10"])
        XCTAssertEqual(sorted.map { $0.desktop }, [9, 7, 1])
    }

    func testOwnerPickerSortPreservesEqualNamesAndEmptyLists() {
        let projects = [(name: "Work", id: "first"), (name: "Work", id: "second")]
        XCTAssertEqual(ProjectsOrderResolver.alphabetical(projects, name: { $0.name }).map { $0.id }, ["first", "second"])
        XCTAssertEqual(ProjectsOrderResolver.alphabetical([String](), name: { $0 }), [])
    }

    func testCurrentDesktopAlwaysComesFirst() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", customProjectIds: ["a", "b"], mru: ["b", "desktop", "a"]), ["desktop", "b", "a"])
    }

    func testActivatedProjectsFollowRecency() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: nil, customProjectIds: ["a", "b", "c"], mru: ["c", "a", "b"]), ["c", "a", "b"])
    }

    func testNeverActivatedProjectsKeepCreationOrder() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", customProjectIds: ["b", "a", "c"], mru: []), ["desktop", "b", "a", "c"])
    }

    func testActivatedProjectsPrecedeNeverActivatedProjects() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", customProjectIds: ["a", "b", "c"], mru: ["b"]), ["desktop", "b", "a", "c"])
    }

    func testDesktopRemainsWhenThereAreNoCustomProjects() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", customProjectIds: [], mru: []), ["desktop"])
    }

    func testMissingDesktopDoesNotHideCustomProjects() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: nil, customProjectIds: ["a"], mru: []), ["a"])
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: nil, customProjectIds: [], mru: []), [])
    }

    func testDeletedProjectsInHistoryAreIgnored() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", customProjectIds: ["a", "b"], mru: ["deleted", "b"]), ["desktop", "b", "a"])
    }

    func testLinkedDesktopAppearsOnlyAsItsProjectInCreationOrder() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", linkedProjectId: "b",
            customProjectIds: ["a", "b", "c"], mru: []), ["a", "b", "c"])
    }

    func testLinkedDesktopAppearsOnlyAsItsProjectInRecencyOrder() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", linkedProjectId: "b",
            customProjectIds: ["a", "b", "c"], mru: ["c", "desktop", "b"]), ["c", "b", "a"])
    }

    func testDeletedLinkedProjectRestoresDesktopEntry() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", linkedProjectId: "deleted",
            customProjectIds: ["a"], mru: ["deleted"]), ["desktop", "a"])
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", linkedProjectId: "deleted",
            customProjectIds: [], mru: []), ["desktop"])
    }

    func testUnlinkingRestoresSeparateDesktopEntry() {
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", linkedProjectId: "a",
            customProjectIds: ["a"], mru: []), ["a"])
        XCTAssertEqual(ProjectsOrderResolver.sorted(currentDesktopId: "desktop", linkedProjectId: nil,
            customProjectIds: ["a"], mru: []), ["desktop", "a"])
    }
}
