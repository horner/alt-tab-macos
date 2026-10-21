import Foundation

enum ProjectStripLayoutResolver {
    static let gap: CGFloat = 6
    static let rowHeight: CGFloat = 30

    struct Layout {
        let width: CGFloat
        let height: CGFloat
        let buttonFrames: [CGRect?]
        let allProjectsFrame: CGRect
    }

    static func layout(buttonWidths: [CGFloat], allProjectsWidth: CGFloat, maximumWidth: CGFloat,
                       rightToLeft: Bool = false) -> Layout {
        let limit = max(0, maximumWidth.rounded(.down))
        let allWidth = min(limit, max(0, allProjectsWidth.rounded(.up)))
        let widths = buttonWidths.map { min(limit, max(0, $0.rounded(.up))) }
        let requiredWidth = widths.reduce(allWidth, +) + CGFloat(widths.count) * gap
        let width = min(limit, requiredWidth)
        let rows = requiredWidth > width ? 2 : 1
        let split = rows == 2 ? balancedSplit(widths, width: width, requiredWidth: requiredWidth) : nil
        var row = 0
        var x: CGFloat = 0
        var frames = [CGRect?]()
        for (index, buttonWidth) in widths.enumerated() {
            if row == 0 && rows == 2 && (split.map { index == $0 } ?? (x + buttonWidth > width)) {
                row = 1
                x = 0
            }
            let availableWidth = row == rows - 1 ? max(0, width - allWidth - gap) : width
            let fits = x + buttonWidth <= availableWidth && buttonWidth > 0
            let rect = CGRect(x: x, y: CGFloat(rows - row - 1) * rowHeight + 2, width: buttonWidth, height: 24)
            frames.append(fits ? rect : nil)
            x += buttonWidth + gap
        }
        let lastRowEnd = frames.compactMap { $0 }.filter { $0.minY == 2 }.last.map { $0.maxX + gap } ?? 0
        let allFrame = CGRect(x: min(max(0, width - allWidth), lastRowEnd), y: 2, width: allWidth, height: 24)
        return centeredLayout(frames, allFrame: allFrame, width: width, rows: rows, rightToLeft: rightToLeft)
    }

    private static func centeredLayout(_ frames: [CGRect?], allFrame: CGRect, width: CGFloat, rows: Int, rightToLeft: Bool) -> Layout {
        var rowWidths = Array(repeating: CGFloat.zero, count: rows)
        for frame in frames.compactMap({ $0 }) + [allFrame] {
            let row = Int((frame.minY - 2) / rowHeight)
            rowWidths[row] = max(rowWidths[row], frame.maxX)
        }
        return Layout(width: width, height: CGFloat(rows) * rowHeight,
            buttonFrames: frames.map { $0.map { position($0, width: width, rowWidths: rowWidths, rightToLeft: rightToLeft) } },
            allProjectsFrame: position(allFrame, width: width, rowWidths: rowWidths, rightToLeft: rightToLeft))
    }

    private static func balancedSplit(_ widths: [CGFloat], width: CGFloat, requiredWidth: CGFloat) -> Int? {
        var firstWidth: CGFloat = 0
        var best: (index: Int, difference: CGFloat)?
        for (index, buttonWidth) in widths.enumerated() {
            firstWidth += buttonWidth + (index == 0 ? 0 : gap)
            let secondWidth = requiredWidth - firstWidth - gap
            guard firstWidth <= width, secondWidth <= width else { continue }
            let difference = abs(firstWidth - secondWidth)
            if best == nil || difference < best!.difference { best = (index + 1, difference) }
        }
        return best?.index
    }

    private static func position(_ frame: CGRect, width: CGFloat, rowWidths: [CGFloat], rightToLeft: Bool) -> CGRect {
        let row = Int((frame.minY - 2) / rowHeight)
        let centered = frame.offsetBy(dx: ((width - rowWidths[row]) / 2).rounded(.down), dy: 0)
        guard rightToLeft else { return centered }
        return CGRect(x: width - centered.maxX, y: centered.minY, width: centered.width, height: centered.height)
    }
}
