import Cocoa
import Carbon.HIToolbox.Events

final class AppPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private static var current: AppPicker?
    private static var opening = false
    private static var generation = 0
    private static var cached = [AppCatalogItem]()
    private static let worker = DispatchQueue(label: "appPicker", qos: .userInitiated)
    private static let iconWorker = DispatchQueue(label: "appPicker.icons", qos: .userInitiated)
    private static let icons: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 256
        return cache
    }()
    static var isActive: Bool { opening || current != nil }
    private let panel = AppPickerPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
        styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
    private let field = NSSearchField(frame: NSRect(x: 24, y: 452, width: 512, height: 44))
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let openButton = NSButton(title: NSLocalizedString("Open", comment: "App picker action"), target: nil, action: nil)
    private var items = [AppCatalogItem]()
    private var results = [AppCatalogItem]()
    private var duplicateNames = Set<String>()
    private var revision = 0
    private var loading = true
    private var filtering = true
    private var pendingChoice: Int?
    private var recentlyUsed = [URL: TimeInterval]()
    private var frequencyScores = [URL: Double]()
    private var requestedIcons = Set<URL>()
    private var userSelectedResult = false

    static func handleKeyDown(_ event: NSEvent?) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        if let current { return current.handle(event) }
        if opening {
            if event.keyCode == kVK_Escape { opening = false; generation += 1 }
            return true
        }
        guard let session = SwitcherSession.current, TilesPanel.shared.isKeyWindow,
              !ContextMenuEvents.isMenuOpen, TilesPanel.shared.attachedSheet == nil, !TilesView.hasMarkedText() else { return false }
        let hold = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", session.shortcutIndex)]?.shortcut.modifierFlags ?? []
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let conflict = ControlsTab.shortcuts.values.contains { shortcut in
            guard shortcut.triggerPhase == .down, shortcut.shortcut.carbonKeyCode == UInt32(event.keyCode),
                  shortcut.shouldTrigger() else { return false }
            let binding = shortcut.shortcut.modifierFlags.intersection([.command, .option, .control, .shift])
            return modifiers == binding || modifiers == binding.union(hold)
        }
        guard AppPickerResolver.isEntryKey(characters: event.charactersIgnoringModifiers, command: modifiers.contains(.command),
            extraModifiers: !modifiers.subtracting(hold.union(.command)).isEmpty, hasConflict: conflict) else { return false }
        if !event.isARepeat { present() }
        return true
    }

    private static func present() {
        guard !isActive, let session = SwitcherSession.current else { return }
        opening = true
        generation += 1
        let request = generation
        let origin = TilesPanel.shared.frame
        let effectKind = requiredEffectViewKind()
        let appearance = TilesPanel.shared.appearance
        let recentWindows = AppUsage.windowSnapshot()
        session.forceDoNothingOnRelease = true
        ControlsTab.shortcuts.keys.forEach { KeyRepeatTimer.stopTimerForRepeatingKey($0) }
        App.hideUi()
        DispatchQueue.main.async {
            guard opening, generation == request, !SwitcherSession.isActive else { opening = false; return }
            let picker = AppPicker(effectKind: effectKind, appearance: appearance, recentWindows: recentWindows)
            current = picker
            opening = false
            picker.show(near: origin)
        }
    }

    private init(effectKind: EffectViewKind, appearance: NSAppearance?, recentWindows: [URL: TimeInterval]) {
        super.init()
        panel.delegate = self
        panel.title = NSLocalizedString("New app window or message", comment: "App picker title")
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = Appearance.enablePanelShadow
        panel.appearance = appearance
        let background = makeEffectView(for: effectKind)
        background.frame = panel.contentView!.bounds
        let content = background.hostView
        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        panel.contentView = background
        recentlyUsed = recentWindows
        configureField()
        configureTable()
        configureButtons()
    }

    private func configureField() {
        field.placeholderString = NSLocalizedString("Search apps", comment: "App picker placeholder")
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.usesSingleLineMode = true
        field.bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) { field.controlSize = .extraLarge }
        else if #available(macOS 11.0, *) { field.controlSize = .large }
        field.font = NSFont.systemFont(ofSize: 18)
        content.addSubview(field)
        status.frame = NSRect(x: 24, y: 240, width: 512, height: 40)
        status.alignment = .center
        status.textColor = .secondaryLabelColor
        content.addSubview(status)
    }

    private func configureTable() {
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 80, width: 512, height: 360))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.width = 512
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 60
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.focusRingType = .none
        if #available(macOS 11.0, *) { table.style = .plain }
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(choose)
        table.setAccessibilityLabel(NSLocalizedString("Applications", comment: "App picker results"))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        content.addSubview(scroll, positioned: .below, relativeTo: status)
    }

    private func configureButtons() {
        let cancel = NSButton(title: NSLocalizedString("Cancel", comment: ""), target: self, action: #selector(dismiss))
        cancel.frame = NSRect(x: 330, y: 24, width: 90, height: 32)
        cancel.bezelStyle = .rounded
        content.addSubview(cancel)
        openButton.frame = NSRect(x: 428, y: 24, width: 108, height: 32)
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(choose)
        openButton.isEnabled = false
        content.addSubview(openButton)
        let hint = NSTextField(labelWithString: "↑ ↓   ·   ↩   ·   esc")
        hint.frame = NSRect(x: 32, y: 30, width: 260, height: 20)
        hint.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hint.textColor = .secondaryLabelColor
        content.addSubview(hint)
    }

    private func show(near origin: NSRect) {
        MainThreadStall.step()
        let visible = NSScreen.screens.first { $0.frame.intersects(origin) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? origin
        let x = min(max(origin.midX - panel.frame.width / 2, visible.minX), visible.maxX - panel.frame.width)
        let y = min(max(origin.midY - panel.frame.height / 2, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        items = Self.cached
        apply(AppCatalog.matching("", in: items, recentlyUsed: recentlyUsed))
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, Self.current === self else { return }
            MainMenu.toggle(false)
            MainMenu.toggleEditMenu(true)
            self.panel.makeFirstResponder(self.field)
        }
        let recentWindows = recentlyUsed
        Self.worker.async { [weak self] in
            let usage = AppUsage.snapshot(seeding: recentWindows)
            let apps = AppCatalog.scan()
            DispatchQueue.main.async {
                Self.cached = apps
                guard let self, Self.current === self else { return }
                self.loading = false
                self.items = apps
                self.recentlyUsed = usage.lastUsed
                self.frequencyScores = usage.frequency
                self.filter(preserveSelection: true)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        userSelectedResult = false
        filter()
    }

    private func filter(preserveSelection: Bool = false) {
        let waitingToChoose = preserveSelection && pendingChoice != nil
        revision += 1
        filtering = true
        pendingChoice = waitingToChoose ? revision : nil
        openButton.isEnabled = false
        let request = revision
        let query = field.stringValue
        let snapshot = items
        let usage = recentlyUsed
        let frequencies = frequencyScores
        Self.worker.async { [weak self] in
            let matches = AppCatalog.matching(query, in: snapshot, recentlyUsed: usage, frequencyScores: frequencies)
            DispatchQueue.main.async {
                guard let self, Self.current === self, self.revision == request else { return }
                let shouldChoose = self.pendingChoice == request
                self.filtering = false
                self.pendingChoice = nil
                self.apply(matches, preserveSelection: preserveSelection && self.userSelectedResult)
                if shouldChoose { self.choose() }
            }
        }
    }

    private func apply(_ matches: [AppCatalogItem], preserveSelection: Bool = false) {
        let previous = preserveSelection ? selected?.url : nil
        results = matches
        duplicateNames = Set(Dictionary(grouping: results, by: { $0.name }).filter { $0.value.count > 1 }.keys)
        table.reloadData()
        if let index = AppPickerResolver.selection(previous: previous, in: results.map { $0.url }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        }
        status.stringValue = loading ? NSLocalizedString("Finding applications…", comment: "App picker loading")
            : NSLocalizedString("No matching applications", comment: "App picker empty state")
        status.isHidden = !results.isEmpty
        updateButton()
    }

    private var selected: AppCatalogItem? { results.indices.contains(table.selectedRow) ? results[table.selectedRow] : nil }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: dismiss(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if !event.isARepeat {
                if filtering { pendingChoice = revision } else { choose() }
            }
            return true
        case kVK_UpArrow: move(-1); return true
        case kVK_DownArrow: move(1); return true
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "n" { return true }
            if field.currentEditor() == nil { panel.makeFirstResponder(field) }
            return false
        }
    }

    private func move(_ step: Int) {
        guard !results.isEmpty else { return }
        userSelectedResult = true
        let index = min(max(table.selectedRow + step, 0), results.count - 1)
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    @objc private func choose() {
        guard Self.current === self, !filtering, let item = selected else { return }
        let request = Self.generation
        dismiss()
        DispatchQueue.main.async {
            AppAction.perform(item) { error in
                if error == nil { AppUsage.record(item.url, pickerOpen: true) }
                guard let error, Self.generation == request, !Self.isActive, !SwitcherSession.isActive else { return }
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Could not complete the action", comment: "App picker error")
                alert.informativeText = error
                alert.runModal()
            }
        }
    }

    @objc private func dismiss() {
        guard Self.current === self else { return }
        Self.current = nil
        revision += 1
        panel.orderOut(nil)
        DispatchQueue.main.async { [self] in
            panel.close()
            if !Self.isActive, !SwitcherSession.isActive { MainMenu.toggle(true) }
        }
    }

    func windowWillClose(_ notification: Notification) { dismiss() }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        if NSApp.currentEvent?.type == .leftMouseDown { userSelectedResult = true }
        updateButton()
    }

    private func updateButton() {
        openButton.isEnabled = !filtering && selected != nil
        openButton.title = selected?.action.title ?? NSLocalizedString("Open", comment: "App picker action")
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: AppPickerRow.reuseIdentifier, owner: self) as? AppPickerRow
            ?? AppPickerRow(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: tableView.rowHeight))
        let item = results[row]
        let icon = Self.icons.object(forKey: item.url as NSURL)
        cell.update(item, duplicate: duplicateNames.contains(item.name), icon: icon ?? NSImage(named: NSImage.applicationIconName))
        if icon == nil { loadIcon(item.url) }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { AppPickerSelection() }

    private var content: NSView { (panel.contentView as! EffectView).hostView }

    private func loadIcon(_ url: URL) {
        guard requestedIcons.insert(url).inserted else { return }
        Self.iconWorker.async { [weak self] in
            let source = NSWorkspace.shared.icon(forFile: url.path)
            var rect = NSRect(x: 0, y: 0, width: 128, height: 128)
            let image = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            DispatchQueue.main.async {
                guard let image else { return }
                let icon = NSImage(cgImage: image, size: NSSize(width: 48, height: 48))
                Self.icons.setObject(icon, forKey: url as NSURL)
                guard let self, Self.current === self else { return }
                for (row, item) in self.results.enumerated() where item.url == url {
                    (self.table.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppPickerRow)?.imageView?.image = icon
                }
            }
        }
    }
}

private final class AppPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
