import Cocoa

final class ProjectsSheet: SheetWindow {
    private static let title = NSLocalizedString("Projects switcher", comment: "")
    private static let enable = NSLocalizedString("Enable Projects", comment: "")
    private static let followDesktop = NSLocalizedString("Switch active Project when switching Desktops", comment: "")
    private static let scope = NSLocalizedString("Show from active Project", comment: "")
    private static let allLocations = NSLocalizedString("All Spaces/Screens", comment: "")
    private static let currentLocation = NSLocalizedString("Current Space/Screen", comment: "")
    private static let hold = NSLocalizedString("Hold", comment: "")
    private static let next = NSLocalizedString("Select next project", comment: "")
    private static let previous = NSLocalizedString("Select previous project", comment: "")
    private static let style = NSLocalizedString("On release", comment: "")
    private static let preset = NSLocalizedString("Use ⌘ / ⌥ / ⌃ layout", comment: "")
    private static let spaceLabels = NSLocalizedString("Space labels", comment: "Space label controls")
    private static let showLabels = NSLocalizedString("Show Space Labels", comment: "Space label menu action")
    private static let closeLabels = NSLocalizedString("Close All Space Labels", comment: "Space label menu action")
    private static let raiseLabels = NSLocalizedString("Bring Space Labels to Front", comment: "Space label menu action")
    private static let minimizeLabels = NSLocalizedString("Minimize All Space Labels", comment: "Space label menu action")
    private static let revealLabels = NSLocalizedString("Show label after switching Spaces", comment: "Space label reveal duration setting")
    private static let revealHelp = NSLocalizedString("0 ms disables the automatic reveal. Closed or minimized labels stay hidden.", comment: "Space label reveal duration help")
    static let searchableStrings = [title, enable, scope, allLocations, currentLocation, followDesktop, hold, next, previous, style, preset, spaceLabels, showLabels, raiseLabels, minimizeLabels, closeLabels, revealLabels, revealHelp] + ShortcutStylePreference.allCases.map { $0.localizedString }
    private var groups: NSStackView?
    private var warning: NSTextField?
    private var warningRow: TableGroupView.RowInfo?
    private var preferencesObserver: NSObjectProtocol?

    deinit {
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
    }

    override func makeContentView() -> NSView {
        let groups = StackView([], .vertical)
        self.groups = groups
        if preferencesObserver == nil {
            preferencesObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.refreshWarning() }
            }
        }
        rebuildRows()
        return groups
    }

    private func rebuildRows() {
        guard let groups else { return }
        groups.arrangedSubviews.forEach { groups.removeArrangedSubview($0); $0.removeFromSuperview() }
        warning = nil
        warningRow = nil
        let table = TableGroupView(title: Self.title, width: SheetWindow.width)
        let toggle = Switch(Preferences.projectsEnabled)
        toggle.target = self
        toggle.action = #selector(toggleEnabled(_:))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.enable, rightViews: [toggle]))
        if Projects.isEnabled {
            let show = NSButton(title: Self.showLabels, target: self, action: #selector(showSpaceLabels))
            let close = NSButton(title: Self.closeLabels, target: self, action: #selector(closeSpaceLabels))
            _ = table.addRow(TableGroupView.Row(leftTitle: Self.spaceLabels, rightViews: [show, close]))
            let raise = NSButton(title: Self.raiseLabels, target: self, action: #selector(raiseSpaceLabels))
            let minimize = NSButton(title: Self.minimizeLabels, target: self, action: #selector(minimizeSpaceLabels))
            _ = table.addRow(leftViews: [], rightViews: [raise, minimize])
            addRevealDuration(table)
            let scope = NSPopUpButton()
            scope.addItems(withTitles: [Self.allLocations, Self.currentLocation])
            scope.selectItem(at: Preferences.projectsCurrentSpaceOnly ? 1 : 0)
            scope.onAction = { control in Preferences.set("projectsCurrentSpaceOnly", (control as! NSPopUpButton).indexOfSelectedItem == 1 ? "true" : "false") }
            _ = table.addRow(TableGroupView.Row(leftTitle: Self.scope, rightViews: [scope]))
            let follow = Switch(Preferences.projectsFollowDesktop)
            follow.onAction = { control in Preferences.set("projectsFollowDesktop", (control as! NSButton).state == .on ? "true" : "false") }
            _ = table.addRow(TableGroupView.Row(leftTitle: Self.followDesktop, rightViews: [follow]))
            addRecorder(table, Self.hold, ProjectSwitcher.holdShortcutId)
            let note = NSTextField(wrappingLabelWithString: "")
            note.preferredMaxLayoutWidth = SheetWindow.width - 40
            note.setContentCompressionResistancePriority(.required, for: .vertical)
            note.textColor = .systemRed
            note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            note.widthAnchor.constraint(equalToConstant: SheetWindow.width - 40).isActive = true
            warning = note
            warningRow = table.addRow(leftViews: [], rightViews: [], secondaryViews: [note], secondaryViewsAlignment: .right)
            refreshWarning()
            addRecorder(table, Self.next, ProjectSwitcher.nextShortcutId)
            addRecorder(table, Self.previous, ProjectSwitcher.previousShortcutId)
            _ = table.addRow(TableGroupView.Row(leftTitle: Self.style, rightViews: [LabelAndControl.makeDropdown("projectsShortcutStyle", ShortcutStylePreference.allCases)]))
        }
        let preset = NSButton(title: Self.preset, target: self, action: #selector(applyPreset))
        groups.addArrangedSubview(TableGroupSetView(originalViews: [table], toolsViews: Projects.isEnabled ? [preset] : [], padding: 0))
    }

    private func addRecorder(_ table: TableGroupView, _ label: String, _ key: String) {
        _ = table.addRow(TableGroupView.Row(leftTitle: label, rightViews: [
            LabelAndControl.makeLabelWithRecorder(label, key, Preferences.shortcut(key), labelPosition: .right)[0],
        ]))
    }

    private func addRevealDuration(_ table: TableGroupView) {
        let controls = LabelAndControl.makeLabelWithSlider("", "spaceLabelRevealDuration", 0, 3000, 31, true, "ms", width: 140)
        controls[1].toolTip = Self.revealHelp
        let indicator = controls[2] as! NSTextField
        indicator.alignment = .right
        indicator.fit(64, indicator.fittingSize.height)
        let help = NSTextField(wrappingLabelWithString: Self.revealHelp)
        help.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = SheetWindow.width - 40
        _ = table.addRow(leftViews: [LabelAndControl.makeLabel(Self.revealLabels)], rightViews: [controls[1], indicator], secondaryViews: [help])
    }

    private func refreshWarning() {
        guard let warning, let hold = Preferences.shortcut(ProjectSwitcher.holdShortcutId) else {
            warning?.stringValue = ""
            warningRow?.view.isHidden = true
            warningRow?.previousSeparator?.isHidden = true
            return
        }
        var clashes = (0..<Preferences.shortcutCount).compactMap { index -> String? in
            guard hold.isEqual(Preferences.shortcut(Preferences.indexToName("holdShortcut", index))) else { return nil }
            return String(format: NSLocalizedString("Window shortcut %d", comment: ""), index + 1)
        }
        if hold.isEqual(Preferences.holdSpacesShortcut) { clashes.append(NSLocalizedString("Spaces switcher", comment: "")) }
        warningRow?.view.isHidden = clashes.isEmpty
        warningRow?.previousSeparator?.isHidden = clashes.isEmpty
        warning.stringValue = clashes.isEmpty ? "" : String(format: NSLocalizedString("Hold key conflicts with %@. Choose a different hold key or use the layout preset.", comment: ""), clashes.joined(separator: ", "))
    }

    @objc private func applyPreset() {
        let alert = NSAlert()
        alert.messageText = Self.preset
        alert.informativeText = NSLocalizedString("Change Window shortcut 1 hold to ⌘, Window shortcut 2 hold to ⌘, Projects hold to ⌥, and Spaces hold to ⌃? Shortcut 3 and all next/previous keys stay unchanged.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Apply", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Preferences.setShortcut(Preferences.indexToName("holdShortcut", 0), keyEquivalent: "⌘")
        Preferences.setShortcut(Preferences.indexToName("holdShortcut", 1), keyEquivalent: "⌘")
        Preferences.setShortcut(SpacesSwitcher.holdShortcutId, keyEquivalent: "⌃")
        Preferences.setShortcut(ProjectSwitcher.holdShortcutId, keyEquivalent: "⌥")
        DispatchQueue.main.async { [weak self] in self?.rebuildRows() }
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        Preferences.set("projectsEnabled", sender.state == .on ? "true" : "false")
        SpaceLabelWindows.synchronizeEnabled()
        if Projects.isEnabled {
            _ = ProjectsPanel.shared
        } else {
            ProjectSwitcher.hide()
            Projects.active = Projects.spaces.first { $0.isCurrent }.map { Projects.forSpace(uuid: $0.uuid) }
        }
        DispatchQueue.main.async { [weak self] in self?.rebuildRows() }
    }

    @objc private func showSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.showAll() }
    }

    @objc private func closeSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.closeAll() }
    }

    @objc private func raiseSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.bringAllToFront() }
    }

    @objc private func minimizeSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.minimizeAll() }
    }
}
