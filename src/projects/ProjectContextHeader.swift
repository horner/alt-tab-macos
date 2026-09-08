import Cocoa

enum ProjectContextHeader {
    private static let label = NSTextField(labelWithString: "")
    private static let strip = NSView()
    private static let allButton = NSButton(title: NSLocalizedString("All Projects", comment: ""), target: nil, action: nil)
    private static var buttons = [NSButton]()
    private static var projectIds = [String]()
    private static let popover = NSPopover()
    private static weak var pressedButton: NSButton?
    private static var titleHeight: CGFloat { Appearance.fontHeight + Appearance.intraCellPadding }
    static var height: CGFloat { titleHeight + (Projects.isEnabled ? 30 : 0) }

    static func handleNumberKey(_ event: NSEvent?) -> Bool {
        guard Projects.isEnabled, SwitcherSession.isActive, !TilesView.isSearchEditing,
              let event, event.type == .keyDown,
              let index = ProjectNumberResolver.index(keyCode: event.keyCode), projectIds.indices.contains(index) else { return false }
        if event.isARepeat { return true }
        select(projectIds[index])
        return true
    }

    static func isPointerInsidePopover(at location: CGPoint) -> Bool {
        guard popover.isShown, let view = popover.contentViewController?.view, let window = view.window else { return false }
        return ProjectPointerResolver.contains(view.convert(window.convertPoint(fromScreen: cocoaPoint(location)), from: nil), bounds: view.bounds, visibleRect: view.visibleRect)
    }

    static func handleMouseButton(down: Bool, at location: CGPoint) -> Bool {
        guard Projects.isEnabled, SwitcherSession.isActive else { return false }
        let target = buttonUnderPointer(at: location)
        if down {
            guard let target else { return false }
            pressedButton = target
            target.highlight(true)
            return true
        }
        guard let pressed = pressedButton else { return false }
        pressedButton = nil
        pressed.highlight(false)
        guard target === pressed else { return true }
        // Mouse events are intercepted by the switcher's tap. Dispatch the action after the tap returns.
        DispatchQueue.main.async {
            guard Projects.isEnabled, SwitcherSession.isActive else { return }
            Logger.debug { "projects header pointer click button=\(pressed.title)" }
            pressed.performClick(nil)
        }
        return true
    }

    private static func cocoaPoint(_ location: CGPoint) -> NSPoint {
        NSPoint(x: location.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - location.y)
    }

    private static func buttonUnderPointer(at location: CGPoint) -> NSButton? {
        let candidates: [NSButton]
        if isPointerInsidePopover(at: location) {
            candidates = (popover.contentViewController?.view as? NSScrollView)?.documentView?.subviews.compactMap { $0 as? NSButton } ?? []
        } else {
            candidates = buttons + [allButton]
        }
        return candidates.first { button in
            guard button.isEnabled, !button.isHiddenOrHasHiddenAncestor, let window = button.window, window.isVisible else { return false }
            return ProjectPointerResolver.contains(button.convert(window.convertPoint(fromScreen: cocoaPoint(location)), from: nil), bounds: button.bounds, visibleRect: button.visibleRect)
        }
    }

    private static func select(_ id: String) {
        guard Projects.isEnabled, SwitcherSession.isActive, let project = Projects.byId[id] else { return }
        popover.close()
        Projects.active = project
        Logger.debug { "projects header select project=\(id)" }
        DispatchQueue.main.async {
            guard SwitcherSession.isActive, Projects.active === project else { return }
            App.refreshOpenUiImmediatelyAfterExternalEvent([])
        }
    }

    private static func makeButton(_ index: Int, _ id: String) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.controlSize = .small
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 11)
        button.lineBreakMode = .byTruncatingTail
        button.onAction = { _ in select(id) }
        return button
    }

    private static func update(_ button: NSButton, _ index: Int, _ id: String) {
        guard let project = Projects.byId[id] else { return }
        button.title = ProjectNumberResolver.label(index: index).map { "\($0)–\(project.resolvedName)" } ?? project.resolvedName
        button.toolTip = button.title
        button.setAccessibilityLabel(button.title)
        button.bezelColor = project === Projects.active ? .controlAccentColor : nil
    }

    private static func layoutStrip(in host: NSView, width: CGFloat, top: CGFloat) {
        guard Projects.isEnabled else { strip.removeFromSuperview(); popover.close(); return }
        let desktop = Projects.spaces.first { $0.isCurrent }.map { Projects.forSpace(uuid: $0.uuid).id }
        let ids = (desktop.map { [$0] } ?? []) + Projects.list.filter { $0.isCustom }.map { $0.id }
        if ids != projectIds {
            buttons.forEach { $0.removeFromSuperview() }
            projectIds = ids
            buttons = ids.enumerated().map { makeButton($0.offset, $0.element) }
            buttons.forEach { strip.addSubview($0) }
        }
        if strip.superview !== host { host.addSubview(strip) }
        strip.frame = NSRect(x: Appearance.windowPadding, y: top - height, width: max(0, width - Appearance.windowPadding * 2), height: 26)
        allButton.controlSize = .small
        allButton.bezelStyle = .rounded
        allButton.font = NSFont.systemFont(ofSize: 11)
        allButton.onAction = { _ in showAll() }
        if allButton.superview !== strip { strip.addSubview(allButton) }
        allButton.frame = NSRect(x: max(0, strip.bounds.width - 92), y: 0, width: 92, height: 24)
        var x: CGFloat = 0
        for (index, button) in buttons.enumerated() {
            update(button, index, projectIds[index])
            let buttonWidth = min(112, max(58, button.intrinsicContentSize.width))
            button.isHidden = x + buttonWidth > allButton.frame.minX - 4
            button.frame = NSRect(x: x, y: 0, width: buttonWidth, height: 24)
            x += buttonWidth + 4
        }
    }

    private static func showAll() {
        guard Projects.isEnabled, SwitcherSession.isActive else { return }
        if popover.isShown { popover.close(); return }
        SwitcherSession.current?.forceDoNothingOnRelease = true
        let columns = min(4, max(1, projectIds.count))
        let rows = (projectIds.count + columns - 1) / columns
        let view = NSView(frame: NSRect(x: 0, y: 0, width: columns * 150 + 16, height: rows * 44 + 16))
        for (index, id) in projectIds.enumerated() {
            let button = makeButton(index, id)
            update(button, index, id)
            button.image = NSImage(named: Projects.byId[id]?.isCustom == true ? NSImage.folderName : NSImage.computerName)
            button.imagePosition = .imageLeft
            button.imageScaling = .scaleProportionallyDown
            button.frame = NSRect(x: 8 + (index % columns) * 150, y: 8 + (rows - 1 - index / columns) * 44, width: 144, height: 38)
            view.addSubview(button)
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: min(320, view.frame.height)))
        scroll.documentView = view
        scroll.hasVerticalScroller = view.frame.height > 320
        scroll.drawsBackground = false
        let controller = NSViewController()
        controller.view = scroll
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: NSRect(x: strip.bounds.midX, y: 0, width: 1, height: 24), of: strip, preferredEdge: .minY)
    }

    static func layout(in host: NSView, width: CGFloat, top: CGFloat) {
        let title = contextTitle()
        label.stringValue = title
        label.toolTip = title
        label.font = NSFont.systemFont(ofSize: Appearance.font.pointSize, weight: .semibold)
        label.textColor = Appearance.fontColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        if label.superview !== host { host.addSubview(label) }
        label.frame = NSRect(x: Appearance.windowPadding, y: top - titleHeight,
            width: max(0, width - Appearance.windowPadding * 2), height: titleHeight)
        layoutStrip(in: host, width: width, top: top)
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
