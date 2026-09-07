import XCTest

final class ProjectsOrderResolverTests: XCTestCase {
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
}
