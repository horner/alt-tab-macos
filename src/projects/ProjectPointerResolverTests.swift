import XCTest

final class ProjectPointerResolverTests: XCTestCase {
    func testLillyClickDoesNotHitDesktopWithOversizedVisibleRect() {
        XCTAssertFalse(ProjectPointerResolver.contains(CGPoint(x: 851.8984375, y: 10.640625),
            bounds: CGRect(x: 0, y: 0, width: 65, height: 24),
            visibleRect: CGRect(x: -28, y: -53, width: 1121, height: 460)))
        XCTAssertTrue(ProjectPointerResolver.contains(CGPoint(x: 38.3984375, y: 10.640625),
            bounds: CGRect(x: 0, y: 0, width: 58, height: 24),
            visibleRect: CGRect(x: -841.5, y: -53, width: 1121, height: 460)))
    }

    func testClippedPopoverButtonOnlyAcceptsVisiblePart() {
        let bounds = CGRect(x: 0, y: 0, width: 144, height: 38)
        let visible = CGRect(x: 0, y: 20, width: 144, height: 18)
        XCTAssertFalse(ProjectPointerResolver.contains(CGPoint(x: 72, y: 10), bounds: bounds, visibleRect: visible))
        XCTAssertTrue(ProjectPointerResolver.contains(CGPoint(x: 72, y: 30), bounds: bounds, visibleRect: visible))
    }

    func testFullyClippedButtonDoesNotAcceptClick() {
        XCTAssertFalse(ProjectPointerResolver.contains(CGPoint(x: 30, y: 12),
            bounds: CGRect(x: 0, y: 0, width: 58, height: 24), visibleRect: .zero))
    }
}
