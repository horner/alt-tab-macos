import XCTest

final class ProjectStripLayoutResolverTests: XCTestCase {
    func testSmallProjectListUsesOneCompactRow() {
        let layout = layout([80, 100])
        XCTAssertEqual(layout.width, 284)
        XCTAssertEqual(layout.height, 30)
        XCTAssertEqual(layout.buttonFrames, [CGRect(x: 0, y: 2, width: 80, height: 24), CGRect(x: 86, y: 2, width: 100, height: 24)])
        XCTAssertEqual(layout.allProjectsFrame, CGRect(x: 192, y: 2, width: 92, height: 24))
    }

    func testManyProjectsUseFullAvailableWidthAndTwoRows() {
        let widths: [CGFloat] = [82, 100, 58, 62, 58, 90, 145, 90, 58, 58, 94, 122, 58, 95, 110, 132, 104]
        let layout = layout(widths)
        XCTAssertEqual(layout.width, 1287)
        XCTAssertEqual(layout.height, 60)
        XCTAssertEqual(layout.buttonFrames.compactMap { $0 }.count, widths.count)
        XCTAssertEqual(Set(layout.buttonFrames.compactMap { $0?.minY }), [2, 32])
        assertContainedAndSeparated(layout)
    }

    func testExactFitStaysOnOneRow() {
        let layout = layout([80, 100], maximumWidth: 284)
        XCTAssertEqual(layout.height, 30)
        XCTAssertEqual(layout.allProjectsFrame.maxX, layout.width)
    }

    func testTwoRowsBalanceProjectsWithTheAllProjectsButton() {
        let layout = layout(Array(repeating: 80, count: 15))
        XCTAssertEqual(layout.height, 60)
        XCTAssertEqual(layout.buttonFrames.compactMap { $0 }.filter { $0.minY == 32 }.count, 8)
        XCTAssertEqual(layout.buttonFrames.compactMap { $0 }.filter { $0.minY == 2 }.count, 7)
        assertContainedAndSeparated(layout)
    }

    func testOverflowKeepsAllProjectsReachableWithinTwoRows() {
        let layout = layout(Array(repeating: 160, count: 40))
        XCTAssertEqual(layout.height, 60)
        XCTAssertEqual(layout.buttonFrames.compactMap { $0 }.count, 14)
        XCTAssertEqual(layout.allProjectsFrame.width, 92)
        XCTAssertLessThanOrEqual(layout.allProjectsFrame.maxX, layout.width)
        assertContainedAndSeparated(layout)
    }

    func testEmptyProjectListStillOffersAllProjects() {
        let layout = layout([])
        XCTAssertEqual(layout.width, 92)
        XCTAssertEqual(layout.height, 30)
        XCTAssertTrue(layout.buttonFrames.isEmpty)
        assertContainedAndSeparated(layout)
    }

    func testRightToLeftMirrorsButtonsWithoutChangingOrderOrRows() {
        let widths = Array(repeating: CGFloat(100), count: 17)
        let leftToRight = layout(widths)
        let rightToLeft = layout(widths, rightToLeft: true)
        XCTAssertEqual(leftToRight.width, rightToLeft.width)
        XCTAssertEqual(leftToRight.height, rightToLeft.height)
        for (left, right) in zip(leftToRight.buttonFrames, rightToLeft.buttonFrames) {
            XCTAssertEqual(right?.minX, left.map { leftToRight.width - $0.maxX })
            XCTAssertEqual(right?.minY, left?.minY)
        }
        XCTAssertEqual(rightToLeft.allProjectsFrame.minX, leftToRight.width - leftToRight.allProjectsFrame.maxX)
        assertContainedAndSeparated(rightToLeft)
    }

    func testNarrowAndZeroWidthLayoutsStayWithinScreenBounds() {
        for width: CGFloat in [0, 40, 180, 320] {
            let layout = layout([160, 120, 100], maximumWidth: width)
            XCTAssertLessThanOrEqual(layout.width, width)
            assertContainedAndSeparated(layout)
        }
    }

    func testFractionalMetricsRoundWithoutOverflow() {
        let layout = layout([80.2, 100.1], maximumWidth: 285.9)
        XCTAssertEqual(layout.width, 285)
        XCTAssertEqual(layout.height, 60)
        XCTAssertEqual(layout.buttonFrames[0]?.width, 81)
        assertContainedAndSeparated(layout)
    }

    private func layout(_ widths: [CGFloat], maximumWidth: CGFloat = 1287, rightToLeft: Bool = false) -> ProjectStripLayoutResolver.Layout {
        ProjectStripLayoutResolver.layout(buttonWidths: widths, allProjectsWidth: 92, maximumWidth: maximumWidth, rightToLeft: rightToLeft)
    }

    private func assertContainedAndSeparated(_ layout: ProjectStripLayoutResolver.Layout, file: StaticString = #filePath, line: UInt = #line) {
        let frames = layout.buttonFrames.compactMap { $0 } + [layout.allProjectsFrame]
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThanOrEqual(frame.minX, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, layout.width, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, layout.height, file: file, line: line)
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(other), file: file, line: line)
            }
        }
    }
}
