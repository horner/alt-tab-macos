import XCTest

final class ProjectArchivePolicyTests: XCTestCase {
    func testSnapshotOnlyNeverClosesWindowsOrRemovesDesktop() {
        let states: [Set<String>] = [[], ["first"], ["first", "second"]]
        for live in states {
            XCTAssertEqual(ProjectArchivePolicy.next(mode: .snapshotOnly, saved: true, contextValid: true,
                pending: nil, remaining: ["first", "second"], live: live, local: live), .stop)
        }
    }

    func testNoCloseBeforeDurableSnapshot() {
        XCTAssertEqual(decision(saved: false), .stop)
    }

    func testSuccessfulCloseRequestStillWaitsForDestruction() {
        XCTAssertEqual(decision(pending: "first"), .wait)
    }

    func testDestroyedWindowAdvancesToNextCapturedWindow() {
        XCTAssertEqual(decision(pending: "first", live: ["second"], local: ["second"]), .close("second"))
    }

    func testNewWindowPreventsDesktopRemoval() {
        XCTAssertEqual(decision(live: ["new"], local: ["new"]), .stop)
    }

    func testMovedWindowStopsClosing() {
        XCTAssertEqual(decision(local: ["second"]), .stop)
    }

    func testProjectChangeStopsClosing() {
        XCTAssertEqual(decision(context: false), .stop)
    }

    func testEmptyDesktopCanBeRemovedOnlyAfterSnapshot() {
        XCTAssertEqual(decision(live: [], local: []), .removeDesktop)
        XCTAssertEqual(decision(saved: false, live: [], local: []), .stop)
    }

    private func decision(saved: Bool = true, context: Bool = true, pending: String? = nil,
                          live: Set<String> = ["first", "second"], local: Set<String> = ["first", "second"]) -> ProjectArchivePolicy.Decision {
        ProjectArchivePolicy.next(saved: saved, contextValid: context, pending: pending, remaining: ["first", "second"], live: live, local: local)
    }
}
