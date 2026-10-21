import Cocoa
import Carbon.HIToolbox.Events

protocol GridTileItem {
    var label: String { get }
    var subtitle: String? { get }
    var maximumTileWidth: CGFloat? { get }
    var icon: NSImage? { get }
    var isCurrent: Bool { get }
}

extension GridTileItem {
    var subtitle: String? { nil }
    var maximumTileWidth: CGFloat? { nil }
}

class GridTileView: NSView {
    private let iconView = NSImageView()
    private let labelView = NSTextField(labelWithString: "")
    private let subtitleView = NSTextField(labelWithString: "")
    private static var subtitleFont: NSFont { NSFont.systemFont(ofSize: max(10, Appearance.font.pointSize - 2)) }
    private var isHighlighted = false

    /// NSTextField cell size includes the inset omitted by String.size(withAttributes:).
    private static let sizingLabel = NSTextField(labelWithString: "")

    static func tileSize(for items: [GridTileItem]) -> NSSize {
        let icon = Appearance.iconSize * 2
        let pad = Appearance.intraCellPadding
        sizingLabel.font = Appearance.font
        let widestLabel = items.map { item -> CGFloat in
            sizingLabel.stringValue = item.label
            return sizingLabel.cell?.cellSize.width ?? 0
        }.max() ?? 0
        let hasSubtitle = items.contains { $0.subtitle != nil }
        let maximumWidth = items.compactMap { $0.maximumTileWidth }.min()
        let width = max((icon * 1.6).rounded(), (widestLabel + pad * 4).rounded(.up))
        let extraHeight = hasSubtitle ? subtitleFont.pointSize + pad : 0
        return NSSize(width: maximumWidth.map { min(width, $0, NSScreen.preferred.frame.width * 0.9 - Appearance.windowPadding * 2) } ?? width,
            height: (icon + Appearance.fontHeight + pad * 3 + extraHeight).rounded())
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer!.cornerRadius = Appearance.cellCornerRadius
        layer!.borderWidth = Appearance.highlightBorderWidth
        layer!.borderColor = NSColor.clear.cgColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        labelView.alignment = .center
        labelView.lineBreakMode = .byTruncatingTail
        labelView.font = Appearance.font
        labelView.textColor = Appearance.fontColor
        labelView.backgroundColor = .clear
        addSubview(iconView)
        addSubview(labelView)
        subtitleView.alignment = .center
        subtitleView.lineBreakMode = .byTruncatingTail
        subtitleView.backgroundColor = .clear
        addSubview(subtitleView)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ item: GridTileItem, _ highlighted: Bool) {
        iconView.image = item.icon
        labelView.stringValue = item.label
        labelView.textColor = Appearance.fontColor
        labelView.font = Appearance.font
        subtitleView.stringValue = item.subtitle ?? ""
        subtitleView.font = Self.subtitleFont
        subtitleView.textColor = Appearance.fontColor.withAlphaComponent(0.75)
        subtitleView.isHidden = item.subtitle == nil
        toolTip = [item.label, item.subtitle].compactMap { $0 }.joined(separator: "\n")
        setAccessibilityLabel(toolTip)
        needsLayout = true
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
        layer!.backgroundColor = (highlighted ? Appearance.highlightFocusedBackgroundColor : .clear).cgColor
        layer!.borderColor = (highlighted ? Appearance.highlightFocusedBorderColor : .clear).cgColor
    }

    override func layout() {
        super.layout()
        let pad = Appearance.intraCellPadding
        let labelHeight = Appearance.fontHeight + pad
        let subtitleHeight = subtitleView.isHidden ? 0 : Self.subtitleFont.pointSize + pad
        subtitleView.frame = NSRect(x: pad, y: pad, width: bounds.width - pad * 2, height: subtitleHeight)
        labelView.frame = NSRect(x: pad, y: pad + subtitleHeight, width: bounds.width - pad * 2, height: labelHeight)
        iconView.frame = NSRect(x: pad, y: labelHeight + pad + subtitleHeight, width: bounds.width - pad * 2,
            height: bounds.height - labelHeight - subtitleHeight - pad * 2)
    }


}

/// A grid switcher panel. Mirrors `TilesPanel`'s window configuration — a non-activating floating
/// panel at `.popUpMenu` level that joins all Spaces — but stays a separate window: it must be able to
/// show while the window switcher is not, and its lifecycle is not tied to `SwitcherSession`.
class GridPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    private let backgroundView = NSVisualEffectView()
    private var tiles = [GridTileView]()

    init() {
        super.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        // triggering AltTab before or during a Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the panel to go on top of context menus
        level = .popUpMenu
        // helps filter out this window from the window switcher's list
        setAccessibilitySubrole(.unknown)
        setAccessibilityLabel(App.name)
        backgroundView.state = .active
        backgroundView.blendingMode = .behindWindow
        backgroundView.wantsLayer = true
        backgroundView.layer!.cornerRadius = Appearance.windowCornerRadius
        contentView = backgroundView
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ items: [GridTileItem], _ selectedIndex: Int) {
        hasShadow = Appearance.enablePanelShadow
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
        backgroundView.material = .sidebar
        backgroundView.layer!.cornerRadius = Appearance.windowCornerRadius
        caTransaction {
            layoutTiles(items, selectedIndex)
            NSScreen.preferred.repositionPanel(self)
        }
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        MainMenu.toggle(false)
    }

    func refreshHighlight(_ items: [GridTileItem], _ selectedIndex: Int) {
        caTransaction {
            for (i, tile) in tiles.enumerated() where i < items.count {
                tile.update(items[i], i == selectedIndex)
            }
        }
    }

    override func orderOut(_ sender: Any?) {
        alphaValue = 0
        super.orderOut(sender)
        MainMenu.toggle(true)
    }

    private func layoutTiles(_ items: [GridTileItem], _ selectedIndex: Int) {
        let size = GridTileView.tileSize(for: items)
        let padding = Appearance.windowPadding
        let gap = Appearance.interCellPadding
        let columns = SpacesOrderResolver.gridColumns(
            count: items.count, maxColumns: Self.maxColumns(size.width, gap, padding))
        let rows = Int((Double(items.count) / Double(columns)).rounded(.up))
        while tiles.count < items.count {
            let tile = GridTileView()
            tiles.append(tile)
            backgroundView.addSubview(tile)
        }
        for (i, tile) in tiles.enumerated() {
            tile.isHidden = i >= items.count
            guard i < items.count else { continue }
            tile.frame = NSRect(
                x: padding + CGFloat(i % columns) * (size.width + gap),
                // AppKit's origin is bottom-left, so the first row has to be laid out last to read top-down.
                y: padding + CGFloat(rows - 1 - i / columns) * (size.height + gap),
                width: size.width, height: size.height)
            tile.update(items[i], i == selectedIndex)
            tile.needsLayout = true
        }
        let perRow = CGFloat(min(items.count, columns))
        setContentSize(NSSize(
            width: (padding * 2 + perRow * size.width + max(perRow - 1, 0) * gap).rounded(),
            height: (padding * 2 + CGFloat(rows) * size.height + CGFloat(max(rows - 1, 0)) * gap).rounded()))
    }

    /// The widest row the panel may occupy. 90% of the screen rather than all of it: `repositionPanel`
    /// centres the panel, so a panel wider than the screen loses both of its ends off-screen.
    private static func maxColumns(_ tileWidth: CGFloat, _ gap: CGFloat, _ padding: CGFloat) -> Int {
        let available = NSScreen.preferred.frame.width * 0.9 - padding * 2
        return max(1, Int((available + gap) / (tileWidth + gap)))
    }
}
