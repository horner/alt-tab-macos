import Cocoa

enum ProjectContextHeader {
    private static let label = NSTextField(labelWithString: "")
    static var height: CGFloat { Appearance.fontHeight + Appearance.intraCellPadding }

    static func layout(in host: NSView, width: CGFloat, top: CGFloat) {
        let title = contextTitle()
        label.stringValue = title
        label.toolTip = title
        label.font = NSFont.systemFont(ofSize: Appearance.font.pointSize, weight: .semibold)
        label.textColor = Appearance.fontColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        if label.superview !== host { host.addSubview(label) }
        label.frame = NSRect(x: Appearance.windowPadding, y: top - height,
            width: max(0, width - Appearance.windowPadding * 2), height: height)
    }

    private static func contextTitle() -> String {
        if Projects.isEnabled, let project = Projects.active, project.isCustom {
            return String(format: NSLocalizedString("Project: %@", comment: "Window switcher context"), project.resolvedName)
        }
        let space = Projects.spaces.first { $0.isCurrent }
        let name = space.flatMap { ProjectNameResolver.normalized(Projects.byId["desktop-\($0.uuid)"]?.name) }
        let desktop = name ?? space.map { String(format: NSLocalizedString("Desktop %d", comment: ""), $0.desktopNumber) }
            ?? NSLocalizedString("Desktop", comment: "")
        switch Preferences.spacesToShow[SwitcherSession.activeShortcutIndex] {
        case .all:
            return String(format: NSLocalizedString("All Desktops · %@", comment: "Window switcher context; current Desktop"), desktop)
        case .nonVisible:
            return NSLocalizedString("Other Desktops", comment: "Window switcher context")
        case .visible:
            return Spaces.visibleSpaces.count > 1
                ? String(format: NSLocalizedString("Visible Desktops · %@", comment: "Window switcher context; current Desktop"), desktop) : desktop
        }
    }
}
