import XCTest

final class ProjectVisibilityResolverTests: XCTestCase {
    private typealias Resolver = ProjectVisibilityResolver
    private let activeA = Resolver.Context(enabled: true, spaceId: 1, projectId: "A")
    private let activeB = Resolver.Context(enabled: true, spaceId: 1, projectId: "B")

    private func window(_ id: String, _ projects: Set<String>, spaces: [UInt64] = [1], minimized: Bool = false,
                        eligible: Bool = true) -> Resolver.Window {
        Resolver.Window(id: id, spaceIds: spaces, projectIds: projects, isMinimized: minimized, isEligible: eligible)
    }

    func testSwitchMinimizesOnlyOtherProjectsOnCurrentDesktop() {
        var session = Resolver.Session()
        let windows = [window("a", ["A"]), window("b", ["B"]), window("c", ["C"]), window("remote", ["B"], spaces: [2])]
        let commands = session.plan(windows, activeA)
        XCTAssertEqual(Set(commands.map { $0.windowId }), ["b", "c"])
        XCTAssertTrue(commands.allSatisfy { $0.minimize })
    }

    func testSwitchBackRestoresOnlyAutomaticallyMinimizedWindows() {
        var session = Resolver.Session()
        let windows = [window("a", ["A"]), window("b", ["B"]), window("manual", ["B"], minimized: true)]
        let minimize = session.plan(windows, activeA).first!
        session.complete(minimize, .changed)
        let commands = session.plan(windows, activeB)
        XCTAssertEqual(commands.map { $0.windowId }, ["b", "a"])
        XCTAssertEqual(commands.map { $0.minimize }, [false, true])
    }

    func testSharedAndUnassignedWindowsStayVisible() {
        var session = Resolver.Session()
        XCTAssertTrue(session.plan([window("shared", ["A", "B"]), window("unassigned", [])], activeA).isEmpty)
    }

    func testBroughtWindowStaysVisibleUntilItsExceptionIsCleared() {
        var session = Resolver.Session()
        var brought = window("b", ["B"])
        brought.isExplicitlyVisible = true
        XCTAssertTrue(session.plan([brought], activeA).isEmpty)
        brought.isExplicitlyVisible = false
        XCTAssertEqual(session.plan([brought], activeA).map { $0.minimize }, [true])
    }

    func testBringCompensatesAnAlreadyIssuedAutomaticMinimize() {
        var session = Resolver.Session()
        var brought = window("b", ["B"])
        let minimize = session.plan([brought], activeA).first!
        brought.isExplicitlyVisible = true
        XCTAssertTrue(session.plan([brought], activeA).isEmpty)
        XCTAssertTrue(minimize.isCancelled)
        XCTAssertTrue(session.complete(minimize, .changed))
        XCTAssertEqual(session.plan([brought], activeA).map { $0.minimize }, [false])
    }

    func testManuallyMinimizedInactiveWindowIsNeverClaimed() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"], minimized: true)]
        XCTAssertTrue(session.plan(windows, activeA).isEmpty)
        XCTAssertTrue(session.plan(windows, activeB).isEmpty)
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testLiveReadProtectsManualMinimizeAfterSnapshot() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"])]
        let command = session.plan(windows, activeA).first!
        session.complete(command, .unchanged(true))
        XCTAssertTrue(session.managed.isEmpty)
        XCTAssertTrue(session.plan(windows, activeB).isEmpty)
        XCTAssertTrue(session.plan(windows, activeA).isEmpty)
    }

    func testDisabledOptionRestoresManagedWindowsAcrossDesktops() {
        var session = Resolver.Session()
        session.recover("a")
        session.recover("b")
        let windows = [window("a", ["A"], minimized: true), window("b", ["B"], spaces: [2], minimized: true),
                       window("manual", ["B"], minimized: true)]
        let commands = session.plan(windows, Resolver.Context(enabled: false, spaceId: 1, projectId: "A"))
        XCTAssertEqual(Set(commands.map { $0.windowId }), ["a", "b"])
        XCTAssertTrue(commands.allSatisfy { !$0.minimize })
    }

    func testNormalDesktopScopeRestoresOnlyCurrentDesktop() {
        var session = Resolver.Session()
        session.recover("a")
        session.recover("b")
        let commands = session.plan([window("a", ["A"], minimized: true), window("b", ["B"], spaces: [2], minimized: true)],
            Resolver.Context(enabled: true, spaceId: 1, projectId: nil))
        XCTAssertEqual(commands.map { $0.windowId }, ["a"])
        XCTAssertFalse(commands[0].minimize)
    }

    func testAllSpacesAndUnknownLocationsAreNotMinimized() {
        var session = Resolver.Session()
        XCTAssertTrue(session.plan([window("sticky", ["B"], spaces: [1, 2]), window("unknown", ["B"], spaces: [])], activeA).isEmpty)
        XCTAssertTrue(session.plan([window("b", ["B"])], Resolver.Context(enabled: true, spaceId: nil, projectId: "A")).isEmpty)
    }

    func testSelectingRemoteProjectLeavesOriginDesktopAlone() {
        var session = Resolver.Session()
        session.recover("b")
        let windows = [window("a", ["A"]), window("b", ["B"], minimized: true)]
        let context = Resolver.Context(enabled: true, spaceId: 1, projectId: "C", projectIsLocal: false)
        XCTAssertTrue(session.plan(windows, context).isEmpty)
        XCTAssertEqual(session.managed, ["b"])
    }

    func testIneligibleWindowsAreExcludedEvenDuringCleanup() {
        var session = Resolver.Session()
        session.recover("fullscreen")
        let windows = ["fullscreen", "label", "tab-group", "phantom", "no-ax"].map { window($0, ["B"], eligible: false) }
        XCTAssertTrue(session.plan(windows, activeA).isEmpty)
        XCTAssertTrue(session.plan(windows, Resolver.Context(enabled: false, spaceId: 1, projectId: nil)).isEmpty)
    }

    func testRemovingMembershipRestoresManagedWindow() {
        var session = Resolver.Session()
        session.recover("b")
        let commands = session.plan([window("b", [], minimized: true)], activeA)
        XCTAssertEqual(commands.map { $0.minimize }, [false])
    }

    func testAddingActiveMembershipRestoresSharedWindow() {
        var session = Resolver.Session()
        session.recover("b")
        let commands = session.plan([window("b", ["A", "B"], minimized: true)], activeA)
        XCTAssertEqual(commands.map { $0.minimize }, [false])
    }

    func testQueuedMinimizeIsCancelledByNewSelection() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"])]
        let old = session.plan(windows, activeA).first!
        XCTAssertTrue(session.plan(windows, activeB).isEmpty)
        XCTAssertTrue(old.isCancelled)
        XCTAssertTrue(session.complete(old, .cancelled))
        XCTAssertTrue(session.plan(windows, activeB).isEmpty)
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testIssuedMinimizeIsRestoredAfterSelectionChanges() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"])]
        let old = session.plan(windows, activeA).first!
        _ = session.plan(windows, activeB)
        XCTAssertTrue(session.complete(old, .changed))
        let restore = session.plan(windows, activeB).first!
        XCTAssertFalse(restore.minimize)
        session.complete(restore, .changed)
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testIssuedMinimizeIsUndoneAfterLeavingItsDesktop() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"])]
        let old = session.plan(windows, activeA).first!
        let remote = Resolver.Context(enabled: true, spaceId: 2, projectId: "C")
        _ = session.plan(windows, remote)
        session.complete(old, .changed)
        XCTAssertEqual(session.plan(windows, remote).map { $0.minimize }, [false])
    }

    func testReturningToOriginalSelectionKeepsCompletedMinimize() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"])]
        let old = session.plan(windows, activeA).first!
        _ = session.plan(windows, activeB)
        _ = session.plan(windows, activeA)
        session.complete(old, .changed)
        XCTAssertTrue(session.plan(windows, activeA).isEmpty)
        XCTAssertEqual(session.managed, ["b"])
        XCTAssertTrue(session.plan(windows, Resolver.Context(enabled: true, spaceId: 2, projectId: "C")).isEmpty)
    }

    func testIssuedRestoreIsCorrectedDespiteStaleMinimizedSnapshot() {
        var session = Resolver.Session()
        session.recover("b")
        let windows = [window("b", ["B"], minimized: true)]
        let restore = session.plan(windows, activeB).first!
        _ = session.plan(windows, activeA)
        XCTAssertTrue(session.complete(restore, .changed))
        XCTAssertEqual(session.plan(windows, activeA).map { $0.minimize }, [true])
    }

    func testOneCommandPerWindowWhileOtherWindowsProgress() {
        var session = Resolver.Session()
        let b = window("b", ["B"])
        let old = session.plan([b], activeA).first!
        let next = session.plan([b, window("c", ["C"])], activeA)
        XCTAssertEqual(next.map { $0.windowId }, ["c"])
        XCTAssertTrue(session.pending["b"] === old)
        XCTAssertFalse(old.isCancelled)
    }

    func testFailedMinimizeDoesNotClaimWindowOrRequestRetry() {
        var session = Resolver.Session()
        let command = session.plan([window("b", ["B"])], activeA).first!
        XCTAssertFalse(session.complete(command, .failed))
        XCTAssertTrue(session.managed.isEmpty)
        XCTAssertTrue(session.pending.isEmpty)
    }

    func testFailedRestoreRetainsRecoveryOwnershipWithoutRetry() {
        var session = Resolver.Session()
        session.recover("b")
        let command = session.plan([window("b", ["B"], minimized: true)], activeB).first!
        XCTAssertFalse(session.complete(command, .failed))
        XCTAssertEqual(session.managed, ["b"])
        XCTAssertTrue(session.pending.isEmpty)
    }

    func testNativeRestoreRelinquishesOwnershipBeforeManualMinimize() {
        var session = Resolver.Session()
        session.recover("b")
        session.observed("b", minimized: false)
        session.observed("b", minimized: true)
        XCTAssertTrue(session.plan([window("b", ["B"], minimized: true)], activeB).isEmpty)
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testManualActionRelinquishesPendingOwnership() {
        var session = Resolver.Session()
        let command = session.plan([window("b", ["B"])], activeA).first!
        session.release("b")
        XCTAssertTrue(command.isCancelled)
        XCTAssertFalse(session.complete(command, .changed))
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testNativeRestoreDuringMinimizeRelinquishesPendingOwnership() {
        var session = Resolver.Session()
        let command = session.plan([window("b", ["B"])], activeA).first!
        session.observed("b", minimized: true)
        session.observed("b", minimized: false)
        XCTAssertTrue(command.isCancelled)
        session.complete(command, .changed)
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testNativeMinimizeDuringRestorePreservesManualChoice() {
        var session = Resolver.Session()
        session.recover("b")
        let windows = [window("b", ["B"], minimized: true)]
        let command = session.plan(windows, activeB).first!
        session.observed("b", minimized: false)
        session.observed("b", minimized: true)
        XCTAssertTrue(command.isCancelled)
        session.complete(command, .changed)
        XCTAssertTrue(session.plan(windows, activeB).isEmpty)
        XCTAssertTrue(session.managed.isEmpty)
    }

    func testClosedWindowCannotTransferOwnershipToReusedId() {
        var session = Resolver.Session()
        let old = session.plan([window("b", ["B"])], activeA).first!
        session.forget("b")
        let new = session.plan([window("b", ["B"])], activeA).first!
        XCTAssertFalse(session.complete(old, .changed))
        XCTAssertTrue(session.managed.isEmpty)
        XCTAssertTrue(session.pending["b"] === new)
    }

    func testOwnershipSurvivesExpectedNotificationsDuringCommands() {
        var session = Resolver.Session()
        let windows = [window("b", ["B"])]
        let minimize = session.plan(windows, activeA).first!
        session.observed("b", minimized: true)
        session.complete(minimize, .changed)
        let restore = session.plan(windows, activeB).first!
        session.observed("b", minimized: false)
        XCTAssertEqual(session.managed, ["b"])
        session.complete(restore, .changed)
        XCTAssertTrue(session.managed.isEmpty)
    }
}
