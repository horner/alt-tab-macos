import Foundation

enum ProjectPointerResolver {
    // A non-clipping AppKit view's visibleRect can extend beyond its bounds (observed across the entire Project strip).
    static func contains(_ point: CGPoint, bounds: CGRect, visibleRect: CGRect) -> Bool {
        bounds.intersection(visibleRect).contains(point)
    }
}
