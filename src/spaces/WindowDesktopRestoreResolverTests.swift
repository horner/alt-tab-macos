import XCTest

final class WindowDesktopRestoreResolverTests: XCTestCase {
    private typealias Resolver = WindowDesktopRestoreResolver
    private let desktops: [UInt64: String] = [1: "first", 2: "second", 3: "third"]

    private func decision(_ homes: [String], spaces: [UInt64] = [1], eligible: Bool = true) -> Resolver.Decision {
        Resolver.decision(isEligible: eligible, spaces: spaces, projectHomes: homes, desktops: desktops)
    }

    func testProjectHomeSelectsDestinationRegardlessOfCurrentLocation() {
        XCTAssertEqual(decision(["second"]), .move(.init(id: 2, uuid: "second")))
        XCTAssertEqual(decision(["second"], spaces: [3]), .move(.init(id: 2, uuid: "second")))
    }

    func testAlreadyHomeIsCountedWithoutMoving() {
        XCTAssertEqual(decision(["first"]), .alreadyHome)
    }

    func testUnassignedWindowDoesNotAcquireTheCurrentProject() {
        XCTAssertEqual(decision([]), .unassigned)
    }

    func testSharedProjectsWithTheSameHomeMoveOnlyOnce() {
        XCTAssertEqual(decision(["second", "second"]), .move(.init(id: 2, uuid: "second")))
    }

    func testConflictingProjectHomesNeverChooseByProjectOrder() {
        XCTAssertEqual(decision(["second", "third"]), .conflictingProjects)
        XCTAssertEqual(decision(["third", "second"]), .conflictingProjects)
        XCTAssertEqual(decision(["second", "missing"]), .conflictingProjects)
    }

    func testDeletedHomeDesktopDoesNotFallBackToItsOldNumber() {
        XCTAssertEqual(decision(["deleted-second"]), .missingDesktop)
        XCTAssertEqual(decision([""]), .missingDesktop)
    }

    func testUnknownFullscreenAndAllDesktopSourcesAreSkipped() {
        for spaces: [UInt64] in [[], [4], [1, 2]] {
            XCTAssertEqual(decision(["second"], spaces: spaces), .unsupported)
        }
        XCTAssertEqual(decision(["second"], eligible: false), .unsupported)
    }

    func testRenumberedDesktopKeepsItsStableHomeIdentity() {
        XCTAssertEqual(Resolver.decision(isEligible: true, spaces: [1], projectHomes: ["second"],
            desktops: [1: "first", 27: "second"]), .move(.init(id: 27, uuid: "second")))
    }

    func testChangedOwnershipInvalidatesACapturedDestination() {
        let original = decision(["second"])
        XCTAssertNotEqual(decision(["third"]), original)
        XCTAssertNotEqual(decision([]), original)
        XCTAssertNotEqual(decision(["second", "third"]), original)
    }

    func testSummaryDoesNotCountProposedMovesAsConfirmed() {
        var summary = Resolver.Summary()
        for result: Resolver.Decision in [.move(.init(id: 2, uuid: "second")), .alreadyHome, .unassigned,
                                          .conflictingProjects, .missingDesktop, .unsupported] {
            summary.record(result)
        }
        XCTAssertEqual(summary.moved, 0)
        XCTAssertEqual(summary.alreadyHome, 1)
        XCTAssertEqual(summary.skipped, 4)
        XCTAssertEqual(summary.failed, 0)
    }

    func testDetailsStayAttachedToTheirWindowAndReason() {
        var summary = Resolver.Summary()
        let conflict = Resolver.Detail(windowName: "Code — lilly", reason: "Conflict: Lilly (D5) / Desktop 1 (D1)")
        let unassigned = Resolver.Detail(windowName: "Finder — Desktop", reason: "No Project assigned")
        summary.record(.conflictingProjects, detail: conflict)
        summary.record(.unassigned, detail: unassigned)
        summary.fail(windowName: "Closed window", reason: "Window closed")
        XCTAssertEqual(summary.details, [conflict, unassigned, .init(windowName: "Closed window", reason: "Window closed")])
        XCTAssertEqual(summary.details.count, summary.skipped + summary.failed)
    }

    func testSuccessfulDecisionsDoNotAppearAsSkippedDetails() {
        var summary = Resolver.Summary()
        let detail = Resolver.Detail(windowName: "Window", reason: "Not a problem")
        summary.record(.move(.init(id: 2, uuid: "second")), detail: detail)
        summary.record(.alreadyHome, detail: detail)
        XCTAssertTrue(summary.details.isEmpty)
        XCTAssertEqual(summary.alreadyHome, 1)
    }

    func testIdenticalTitlesKeepDistinctWindowTargets() {
        var summary = Resolver.Summary()
        summary.record(.conflictingProjects, detail: .init(windowName: "Code — workspace", reason: "Conflict", windowId: "first"))
        summary.fail(windowName: "Code — workspace", reason: "Move could not be confirmed", windowId: "second")
        XCTAssertEqual(summary.details.map { $0.windowId }, ["first", "second"])
    }
}
