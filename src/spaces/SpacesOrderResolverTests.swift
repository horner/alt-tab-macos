import XCTest

/// Pins the Spaces switcher's list order and selection movement (`SpacesOrderResolver`). Pure data in,
/// pure data out — no WindowServer, no AppKit. `SpacesList` is the thin adapter that feeds these inputs
/// from `CGSCopyManagedDisplaySpaces` and the visit history.
///
/// Groups: A `.desktopOrder` · B `.recentlyFocused` · C initial selection · D cycling.
final class SpacesOrderResolverTests: XCTestCase {

    private func space(_ id: SpacesOrderResolver.SpaceId, desktop: Int, rank: Int) -> SpacesOrderResolver.Space {
        SpacesOrderResolver.Space(id: id, desktopNumber: desktop, enumerationRank: rank)
    }

    private func ids(_ spaces: [SpacesOrderResolver.Space]) -> [SpacesOrderResolver.SpaceId] {
        spaces.map { $0.id }
    }

    // MARK: - A. .desktopOrder

    func testDesktopOrderSortsByDesktopNumber() {
        let spaces = [space(30, desktop: 3, rank: 2), space(10, desktop: 1, rank: 0), space(20, desktop: 2, rank: 1)]
        XCTAssertEqual(ids(SpacesOrderResolver.sorted(spaces, mru: [], by: .desktopOrder)), [10, 20, 30])
    }

    func testDesktopOrderPutsFullscreenSpacesLast() {
        let spaces = [space(99, desktop: 0, rank: 0), space(10, desktop: 1, rank: 1), space(20, desktop: 2, rank: 2)]
        XCTAssertEqual(ids(SpacesOrderResolver.sorted(spaces, mru: [], by: .desktopOrder)), [10, 20, 99])
    }

    func testDesktopOrderBreaksTiesByEnumerationRank() {
        let spaces = [space(98, desktop: 0, rank: 5), space(99, desktop: 0, rank: 3)]
        XCTAssertEqual(ids(SpacesOrderResolver.sorted(spaces, mru: [], by: .desktopOrder)), [99, 98])
    }

    // MARK: - B. .recentlyFocused

    func testRecentlyFocusedFollowsMruOrder() {
        let spaces = [space(10, desktop: 1, rank: 0), space(20, desktop: 2, rank: 1), space(30, desktop: 3, rank: 2)]
        XCTAssertEqual(ids(SpacesOrderResolver.sorted(spaces, mru: [30, 10, 20], by: .recentlyFocused)), [30, 10, 20])
    }

    func testRecentlyFocusedPutsUnvisitedSpacesAfterVisitedOnes() {
        let spaces = [space(10, desktop: 1, rank: 0), space(20, desktop: 2, rank: 1), space(30, desktop: 3, rank: 2)]
        XCTAssertEqual(ids(SpacesOrderResolver.sorted(spaces, mru: [30], by: .recentlyFocused)), [30, 10, 20])
    }

    func testRecentlyFocusedOrdersUnvisitedSpacesByEnumerationRank() {
        let spaces = [space(30, desktop: 3, rank: 2), space(10, desktop: 1, rank: 0), space(20, desktop: 2, rank: 1)]
        XCTAssertEqual(ids(SpacesOrderResolver.sorted(spaces, mru: [], by: .recentlyFocused)), [10, 20, 30])
    }

    // MARK: - C. initialSelection

    func testInitialSelectionPicksTheSpaceAfterTheCurrentOne() {
        XCTAssertEqual(SpacesOrderResolver.initialSelection(count: 3, currentIndex: 0), 1)
    }

    func testInitialSelectionWrapsPastTheLastSpace() {
        XCTAssertEqual(SpacesOrderResolver.initialSelection(count: 3, currentIndex: 2), 0)
    }

    func testInitialSelectionStaysPutWithASingleSpace() {
        XCTAssertEqual(SpacesOrderResolver.initialSelection(count: 1, currentIndex: 0), 0)
    }

    func testInitialSelectionFallsBackToZeroWhenCurrentIsUnknown() {
        XCTAssertEqual(SpacesOrderResolver.initialSelection(count: 3, currentIndex: nil), 0)
        XCTAssertEqual(SpacesOrderResolver.initialSelection(count: 3, currentIndex: 7), 0)
    }

    func testInitialSelectionIsZeroForAnEmptyList() {
        XCTAssertEqual(SpacesOrderResolver.initialSelection(count: 0, currentIndex: nil), 0)
    }

    // MARK: - D. cycle

    func testCycleAdvancesForward() {
        XCTAssertEqual(SpacesOrderResolver.cycle(selected: 0, step: 1, count: 3), 1)
    }

    func testCycleWrapsForwardPastTheEnd() {
        XCTAssertEqual(SpacesOrderResolver.cycle(selected: 2, step: 1, count: 3), 0)
    }

    func testCycleWrapsBackwardBelowZero() {
        XCTAssertEqual(SpacesOrderResolver.cycle(selected: 0, step: -1, count: 3), 2)
    }

    func testCycleIsZeroForAnEmptyList() {
        XCTAssertEqual(SpacesOrderResolver.cycle(selected: 0, step: 1, count: 0), 0)
    }

    // MARK: - E. gridColumns

    func testGridColumnsKeepsEverythingOnOneRowWhenItFits() {
        XCTAssertEqual(SpacesOrderResolver.gridColumns(count: 5, maxColumns: 11), 5)
    }

    func testGridColumnsBalancesRowsWhenItWraps() {
        XCTAssertEqual(SpacesOrderResolver.gridColumns(count: 13, maxColumns: 11), 7)
    }

    func testGridColumnsBalancesAcrossThreeRows() {
        XCTAssertEqual(SpacesOrderResolver.gridColumns(count: 25, maxColumns: 11), 9)
    }

    func testGridColumnsNeverExceedsTheMeasuredMaximum() {
        for count in 1...60 {
            for maxColumns in 1...12 {
                XCTAssertLessThanOrEqual(
                    SpacesOrderResolver.gridColumns(count: count, maxColumns: maxColumns), maxColumns,
                    "count:\(count) maxColumns:\(maxColumns)")
            }
        }
    }

    func testGridColumnsIsOneForAnEmptyOrDegenerateGrid() {
        XCTAssertEqual(SpacesOrderResolver.gridColumns(count: 0, maxColumns: 11), 1)
        XCTAssertEqual(SpacesOrderResolver.gridColumns(count: 3, maxColumns: 0), 1)
    }
}
