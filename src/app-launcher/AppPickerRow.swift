import Cocoa

final class AppPickerRow: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("app-result")
    private let logo = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.reuseIdentifier
        logo.frame = NSRect(x: 12, y: 6, width: 48, height: 48)
        logo.imageScaling = .scaleProportionallyDown
        logo.setAccessibilityElement(false)
        imageView = logo
        addSubview(logo)
        name.frame = NSRect(x: 72, y: 31, width: max(0, frame.width - 84), height: 22)
        name.font = NSFont.systemFont(ofSize: max(15, Appearance.fontHeight), weight: .medium)
        name.textColor = Appearance.fontColor
        name.lineBreakMode = .byTruncatingTail
        name.autoresizingMask = [.width]
        textField = name
        addSubview(name)
        detail.frame = NSRect(x: 72, y: 10, width: max(0, frame.width - 84), height: 18)
        detail.font = NSFont.systemFont(ofSize: 12)
        detail.textColor = Appearance.fontColor.withAlphaComponent(0.6)
        detail.lineBreakMode = .byTruncatingMiddle
        detail.autoresizingMask = [.width]
        addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

    func update(_ item: AppCatalogItem, duplicate: Bool, icon: NSImage?) {
        name.stringValue = item.name
        detail.stringValue = duplicate ? "\(item.action.title) · \(item.url.path)" : item.action.title
        logo.image = icon
        toolTip = item.url.path
        setAccessibilityLabel("\(item.name), \(detail.stringValue)")
    }
}

final class AppPickerSelection: NSTableRowView {
    private let radius = min(Appearance.cellCornerRadius, 16)
    private let borderWidth = Appearance.highlightBorderWidth
    private let fill = Appearance.highlightFocusedBackgroundColor
    private let border = Appearance.highlightFocusedBorderColor

    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: borderWidth / 2 + 2, dy: borderWidth / 2 + 2),
            xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
