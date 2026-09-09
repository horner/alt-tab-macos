import Cocoa

final class SpaceLabelWindow: NSWindow, NSWindowDelegate {
    private final class Label: NSTextField {
        override var mouseDownCanMoveWindow: Bool { true }
    }

    private final class Button: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    var onClose: (() -> Void)?
    var onInteraction: (() -> Void)?
    private let textLabel = Label(labelWithString: "")
    private var buttons = [NSButton]()
    private var projectButtons = [NSButton]()
    private var renderedLabel: SpaceLabelResolver.Label?
    private var renderedSize = NSSize.zero
    private var position: SpaceLabelResolver.Position?
    private let positionKey: String
    private var positioning = false
    private var positionSave: DispatchWorkItem?
    private var controlsHeight = CGFloat.zero
    var savedDisplayIdentifier: String? { position?.displayIdentifier }
    override var canBecomeMain: Bool { false }

    init(uuid: String) {
        positionKey = "spaceLabelPosition.\(uuid)"
        if let data = UserDefaults.standard.data(forKey: positionKey) {
            position = try? JSONDecoder().decode(SpaceLabelResolver.Position.self, from: data)
        }
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        level = .normal
        // Managed windows participate in Exposé; stationary windows are desktop overlays.
        collectionBehavior = [.managed, .ignoresCycle, .fullScreenAuxiliary]
        delegate = self
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.zoomButton)?.isHidden = true
        appearance = NSAppearance(named: .darkAqua)
        synchronizeSwitcherVisibility()
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        isMovable = true
        isMovableByWindowBackground = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        contentView = view
        textLabel.alignment = .center
        textLabel.textColor = .white
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        view.addSubview(textLabel)
        projectButtons = [
            addButton(NSLocalizedString("Project Windows", comment: "Project windows menu"),
                help: NSLocalizedString("Open this project's window list", comment: "Project label button help"), action: #selector(openWindows(_:))),
            addButton(NSLocalizedString("History", comment: "Project window history"),
                help: NSLocalizedString("Open this project's window history", comment: "Project label button help"), action: #selector(openHistory(_:))),
        ]
        addButton(NSLocalizedString("Rename…", comment: "Project label rename button"),
            help: NSLocalizedString("Rename this Project or Desktop", comment: "Project label button help"), action: #selector(rename(_:)))
        addButton(NSLocalizedString("Menu", comment: "AltTab menu button"),
            help: NSLocalizedString("Open the AltTab menu", comment: "AltTab menu button help"), action: #selector(openMenu(_:)))
    }

    func synchronizeSwitcherVisibility() {
        setAccessibilitySubrole(Preferences.projectWindowsInSwitcher ? .standardWindow : .floatingWindow)
    }

    func update(_ label: SpaceLabelResolver.Label, on screen: NSScreen) {
        MainThreadStall.step()
        let visibleFrame = screen.visibleFrame
        if renderedLabel != label || renderedSize != visibleFrame.size {
            updateText(label, visibleSize: visibleFrame.size)
        }
        let height = textLabel.frame.height + controlsHeight + 50
        let target = SpaceLabelResolver.frame(visibleFrame: visibleFrame, height: height, position: position, stackIndex: label.stackIndex)
        positioning = true
        defer { positioning = false }
        if frame != target { setFrame(target, display: true) }
    }

    private func updateText(_ label: SpaceLabelResolver.Label, visibleSize: NSSize) {
        renderedLabel = label
        renderedSize = visibleSize
        let number = label.isFullscreen
            ? String(format: NSLocalizedString("Fullscreen · Space %d", comment: "Fullscreen Project label number"), label.number)
            : String(format: NSLocalizedString("Desktop %d", comment: "Spaces switcher tile label"), label.number)
        let name = label.name ?? NSLocalizedString("Unnamed Space", comment: "Project label without a saved name")
        title = "\(name) · \(number)"
        setAccessibilityLabel(title)
        textLabel.toolTip = title
        textLabel.setAccessibilityLabel(title)
        let prefix = label.isFullscreen ? number : String(label.number)
        let singleLineName = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        textLabel.stringValue = "\(prefix) · \(singleLineName)"
        let hasProject = ProjectsMenu.context(for: label).projectId != nil
        projectButtons.forEach { $0.isHidden = !hasProject }
        let width = (visibleSize.width / 2).rounded() - 32
        controlsHeight = layoutButtons(width: width)
        textLabel.font = fittingFont(width: width, maxHeight: visibleSize.height / 3)
        let height = ceil(textLabel.cell!.cellSize.height)
        textLabel.frame = NSRect(x: 16, y: controlsHeight + 20, width: width, height: height)
        contentView?.layer?.cornerRadius = 10
    }

    func avoidOverlap(_ occupied: [CGRect], on screen: NSScreen, migrated: Bool) {
        guard position == nil || migrated, let identifier = screen.cachedUuid() else { return }
        let target = SpaceLabelResolver.avoidingOverlap(frame, in: screen.visibleFrame, occupied: occupied)
        guard target != frame else { return }
        positioning = true
        setFrame(target, display: true)
        positioning = false
        position = SpaceLabelResolver.Position(displayIdentifier: identifier as String,
            x: target.minX - screen.visibleFrame.minX, y: target.minY - screen.visibleFrame.minY)
        savePosition()
    }

    @discardableResult
    private func addButton(_ title: String, help: String, action: Selector) -> NSButton {
        let button = Button(title: title, target: self, action: action)
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.bezelStyle = .rounded
        button.toolTip = help
        button.setAccessibilityLabel(help)
        button.sizeToFit()
        buttons.append(button)
        contentView?.addSubview(button)
        return button
    }

    private func layoutButtons(width: CGFloat) -> CGFloat {
        var x = CGFloat.zero
        var y = CGFloat.zero
        let height = buttons.map { $0.frame.height }.max() ?? 24
        for button in buttons where !button.isHidden {
            let buttonWidth = min(width, button.intrinsicContentSize.width)
            if x > 0 && x + buttonWidth > width { x = 0; y += height + 6 }
            button.frame = NSRect(x: 16 + x, y: 12 + y, width: buttonWidth, height: height)
            x += buttonWidth + 8
        }
        return y + height
    }

    func windowWillMove(_ notification: Notification) {
        guard !positioning else { return }
        onInteraction?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onInteraction?()
    }

    func windowDidMove(_ notification: Notification) {
        guard !positioning, renderedLabel != nil, let screen,
              let identifier = screen.cachedUuid() else { return }
        let visibleFrame = screen.visibleFrame
        position = SpaceLabelResolver.Position(displayIdentifier: identifier as String,
            x: frame.minX - visibleFrame.minX, y: frame.minY - visibleFrame.minY)
        positionSave?.cancel()
        let save = DispatchWorkItem { [weak self] in self?.savePosition() }
        positionSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: save)
    }

    private func savePosition() {
        positionSave?.cancel()
        positionSave = nil
        guard let position, let data = try? JSONEncoder().encode(position),
              UserDefaults.standard.data(forKey: positionKey) != data else { return }
        UserDefaults.standard.set(data, forKey: positionKey)
    }

    override func close() {
        savePosition()
        super.close()
    }

    @objc private func openWindows(_ sender: NSButton) {
        performFromLabel(sender) { context, button in
            guard let id = context.projectId else { return }
            ProjectsMenu.showWindows(for: id, from: button)
        }
    }

    @objc private func openHistory(_ sender: NSButton) {
        performFromLabel(sender) { context, button in
            guard let id = context.projectId else { return }
            ProjectsMenu.showHistory(for: id, from: button)
        }
    }

    @objc private func rename(_ sender: NSButton) {
        performFromLabel(sender) { context, button in
            guard let window = button.window else { return }
            ProjectsMenu.rename(context, from: window)
        }
    }

    @objc private func openMenu(_ sender: NSButton) {
        performFromLabel(sender) { context, button in Menubar.popUpMenu(from: button, context: context) }
    }

    private func performFromLabel(_ sender: NSButton, action: @escaping (ProjectMenuResolver.Context, NSButton) -> Void) {
        guard let label = renderedLabel else { return }
        let context = ProjectsMenu.context(for: label)
        onInteraction?()
        // Button actions retain the clicked label's target across menu tracking and focus changes.
        DispatchQueue.main.async { [weak self, weak sender] in
            guard let self, self.renderedLabel?.id == label.id, let sender, sender.window?.isVisible == true else { return }
            action(context, sender)
        }
    }

    private func fittingFont(width: CGFloat, maxHeight: CGFloat) -> NSFont {
        var lower = max(24, width * 0.06)
        var upper = max(lower, min(width, maxHeight))
        for _ in 0..<12 {
            let size = (lower + upper) / 2
            textLabel.font = NSFont.systemFont(ofSize: size, weight: .bold)
            // NSString sizing omits the native text cell's padding and can cause premature truncation.
            let bounds = textLabel.cell!.cellSize
            if bounds.width <= width - 1 && bounds.height <= maxHeight {
                lower = size
            } else {
                upper = size
            }
        }
        return NSFont.systemFont(ofSize: lower, weight: .bold)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let onClose else { return true }
        onClose()
        return false
    }

    /// Only our own windows are assigned; no compatibility IDs or other apps' windows are mutated.
    static func assign(_ windowId: CGWindowID, to spaceId: CGSSpaceID, thenMain: @escaping (Bool) -> Void) {
        CGSCallScheduler.run {
            guard let previous = CGSCallScheduler.windowSpaces(windowId) else {
                DispatchQueue.main.async { thenMain(false) }
                return
            }
            let windows = [windowId] as CFArray
            spaceLabelAddWindows(CGS_CONNECTION, windows, [spaceId] as CFArray)
            let others = previous.filter { $0 != spaceId }
            if !others.isEmpty { spaceLabelRemoveWindows(CGS_CONNECTION, windows, others as CFArray) }
            let assigned = CGSCallScheduler.windowSpaces(windowId) == [spaceId]
            DispatchQueue.main.async { thenMain(assigned) }
        }
    }
}

// CGSSpace.h: https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h
// Both return void; membership readback is the success signal.
@_silgen_name("CGSAddWindowsToSpaces")
private func spaceLabelAddWindows(_ connection: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func spaceLabelRemoveWindows(_ connection: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)
