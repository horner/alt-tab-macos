import Cocoa

final class DesktopDestinationBadge: FlippedView {
    private var text = NSAttributedString(string: "")
    var reservedWidth: CGFloat { isHidden ? 0 : frame.width + Appearance.intraCellPadding }
    private(set) var destinationHelp: String?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ window: Window) {
        let destination = DesktopNavigation.destination(for: window)
        isHidden = destination == nil
        destinationHelp = nil
        guard let destination else { return }
        let title = destination.isFullscreen ? NSLocalizedString("↗ Fullscreen", comment: "Window tile Desktop destination badge")
            : String(format: NSLocalizedString("↗ D:%d", comment: "Window tile Desktop destination badge"), destination.desktopNumber)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: max(10, Appearance.font.pointSize * 0.8), weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        let size = text.size()
        frame.size = NSSize(width: ceil(size.width) + 8, height: ceil(size.height) + 4)
        destinationHelp = String(format: NSLocalizedString("Switches to %@", comment: "Window tile Desktop destination tooltip"), DesktopNavigation.name(of: destination))
        toolTip = destinationHelp
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        text.draw(in: bounds.insetBy(dx: 4, dy: 2))
    }

    func limitWidth(to width: CGFloat) {
        frame.size.width = min(frame.width, max(0, width))
    }
}
