import XCTest

/// Pins the supersede-and-repair rule that keeps a slow focus operation from raising its window after a
/// faster one already switched. See FocusIntentPolicySpecs.md.
final class FocusIntentPolicyTests: XCTestCase {
    private let safari: pid_t = 500
    private let terminal: pid_t = 600
    private let finder: pid_t = 700

    /// The fast alt-tab, in one line. Both operations are in flight; only the newest may act.
    func testANewerRequestSupersedesTheOlderOne() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        let second = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertFalse(policy.mayProceed(first), "a superseded operation was still allowed to touch the screen")
        XCTAssertTrue(policy.mayProceed(second))
    }

    /// A backlog collapses to its last member rather than replaying every switch the user passed through.
    func testTheNewestRequestAlwaysProceeds() {
        var policy = FocusIntentPolicy()
        let generations = (0..<5).map { policy.request(wid: CGWindowID($0), pid: safari, now: Double($0) * 0.2) }
        for generation in generations.dropLast() {
            XCTAssertFalse(policy.mayProceed(generation))
        }
        XCTAssertTrue(policy.mayProceed(generations.last!))
    }

    /// **The case a bail alone misses.** Safari's raise was posted before Terminal was ever requested, and a
    /// posted event cannot be recalled: it lands late and puts Safari back on top of Terminal. The stale
    /// operation has to re-assert the current intent on its way out.
    func testASupersededOpThatAlreadyReorderedAsksForARepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        let second = policy.request(wid: 2, pid: terminal, now: 0.2)
        let repair = policy.finish(first, wid: 1, now: 0.5)
        XCTAssertEqual(repair?.generation, second, "the stale raise landed and nothing re-asserted the switch")
        XCTAssertEqual(repair?.wid, 2)
        XCTAssertEqual(repair?.pid, terminal)
    }

    /// It stopped at a checkpoint before fronting or raising anything, so the screen is already right and a
    /// repair would be a redundant re-front.
    func testASupersededOpThatNeverReorderedAsksForNoRepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        _ = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertNil(policy.finish(first, wid: 1, now: 0.5))
    }

    /// The ordinary single switch: nobody overtook it, so it owes nothing.
    func testTheCurrentOpAsksForNoRepair() {
        var policy = FocusIntentPolicy()
        let only = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(only, now: 0.01)
        XCTAssertNil(policy.finish(only, wid: 1, now: 0.02))
    }

    /// Past the horizon the user has had a second to click somewhere themselves. Re-asserting then would take
    /// the front away from them, which is worse than the stale raise it repairs.
    func testARepairIsRefusedOnceTheIntentIsStale() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        _ = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertNil(policy.finish(first, wid: 1, now: 0.2 + FocusIntentPolicy.repairHorizon + 0.01))
    }

    /// Both stale operations clobbered the same intent, and the first repair already re-asserted it.
    func testTwoStaleOpsProduceOneRepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        let second = policy.request(wid: 2, pid: terminal, now: 0.1)
        policy.noteReordered(second, now: 0.11)
        _ = policy.request(wid: 3, pid: safari, now: 0.2)
        XCTAssertNotNil(policy.finish(first, wid: 1, now: 0.5))
        XCTAssertNil(policy.finish(second, wid: 2, now: 0.6), "the intent was re-asserted twice for one clobber")
    }

    /// An operation reports its outcome once, so the re-assert cannot start another round of repairs.
    func testARepairDoesNotCascade() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        _ = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertNotNil(policy.finish(first, wid: 1, now: 0.5))
        XCTAssertNil(policy.finish(first, wid: 1, now: 0.6))
    }

    /// The generation is per request, not per window: holding the shortcut through a window and back still
    /// leaves the older operation superseded.
    func testARepeatedFocusOfTheSameWindowStillSupersedes() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        let second = policy.request(wid: 1, pid: safari, now: 0.2)
        XCTAssertFalse(policy.mayProceed(first))
        XCTAssertTrue(policy.mayProceed(second))
    }

    /// Its late raise lands on the very window the newest intent wants on top. Re-fronting would be work for
    /// a screen that is already right, and a synthetic mouse-down posted into an app for nothing.
    func testAStaleOpAimedAtTheCurrentTargetAsksForNoRepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        _ = policy.request(wid: 1, pid: safari, now: 0.2)
        XCTAssertNil(policy.finish(first, wid: 1, now: 0.5))
    }

    /// **What "one repair per intent" is allowed to swallow.** Terminal's operation fronted at 0.03 and its
    /// raise did not land until 0.6, after Safari's repair at 0.3 — so that repair covers the front and not
    /// the raise, and Terminal still owes one. Stamping only the first touch reads 0.03 here, decides the
    /// repair already covered it, and leaves Terminal's window on top of Finder.
    func testTheLastTouchIsWhatTheOneRepairRuleCompares() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        let second = policy.request(wid: 2, pid: terminal, now: 0.02)
        policy.noteReordered(second, now: 0.03)
        _ = policy.request(wid: 3, pid: finder, now: 0.1)
        XCTAssertNotNil(policy.finish(first, wid: 1, now: 0.3))
        policy.noteReordered(second, now: 0.6)
        XCTAssertEqual(policy.finish(second, wid: 2, now: 0.65)?.wid, 3,
                       "the raise landed after the repair that was supposed to cover it, and nothing re-asserted")
    }

    /// AltTab's own window and a windowless app: `Window.focus()` gets there with no target wid, so pending
    /// operations must stop even though there is nothing to re-assert them to.
    func testSupersedingWithoutATargetStopsPendingOpsAndOwesNoRepair() {
        var policy = FocusIntentPolicy()
        let pending = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(pending, now: 0.01)
        policy.supersede()
        XCTAssertFalse(policy.mayProceed(pending), "an operation kept acting after a focus it cannot repair to")
        XCTAssertNil(policy.finish(pending, wid: 1, now: 0.3))
    }

    func testWindowlessLaunchHasAGenerationWithoutARepairTarget() {
        var policy = FocusIntentPolicy()
        let pending = policy.supersede()
        XCTAssertTrue(policy.mayProceed(pending))
        XCTAssertNil(policy.current)
    }

    func testWindowAndDesktopChoicesShareOneGenerationSequence() {
        var policy = FocusIntentPolicy()
        let firstWindow = policy.request(wid: 1, pid: safari, now: 0)
        let windowless = policy.supersede()
        let desktop = policy.supersede()
        let nextWindow = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertLessThan(firstWindow, windowless)
        XCTAssertLessThan(windowless, desktop)
        XCTAssertLessThan(desktop, nextWindow)
        XCTAssertFalse(policy.mayProceed(firstWindow))
        XCTAssertFalse(policy.mayProceed(windowless))
        XCTAssertFalse(policy.mayProceed(desktop))
        XCTAssertTrue(policy.mayProceed(nextWindow))
    }

    func testNewWindowChoiceCancelsDelayedWindowlessSuccessAndFallback() {
        assertDelayedWindowlessCompletionsCancelled { intents in
            _ = intents.request(wid: 2, pid: self.terminal)
        }
    }

    func testNewDesktopChoiceCancelsDelayedWindowlessSuccessAndFallback() {
        assertDelayedWindowlessCompletionsCancelled { intents in
            intents.supersede()
        }
    }

    private func assertDelayedWindowlessCompletionsCancelled(choosing next: (FocusIntents) -> Void) {
        let intents = FocusIntents()
        let pending = intents.supersede()
        XCTAssertTrue(intents.mayProceed(pending))
        let release = DispatchSemaphore(value: 0)
        let completions = ["successful launch", "failed launch fallback"].map { outcome in
            let completed = expectation(description: outcome)
            DispatchQueue.global(qos: .userInitiated).async {
                guard release.wait(timeout: .now() + 5) == .success else {
                    XCTFail("launch completion was never released")
                    completed.fulfill()
                    return
                }
                XCTAssertFalse(intents.mayProceed(pending), "\(outcome) could reactivate the superseded app")
                completed.fulfill()
            }
            return completed
        }
        next(intents)
        completions.forEach { _ in release.signal() }
        wait(for: completions, timeout: 5)
    }
}
