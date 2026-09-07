import Cocoa

final class ProjectsSheet: SheetWindow {
    private static let title = NSLocalizedString("Projects switcher", comment: "")
    private static let enable = NSLocalizedString("Enable Projects", comment: "")
    private static let hold = NSLocalizedString("Hold", comment: "")
    private static let next = NSLocalizedString("Select next project", comment: "")
    private static let previous = NSLocalizedString("Select previous project", comment: "")
    private static let style = NSLocalizedString("On release", comment: "")
    static let searchableStrings = [title, enable, hold, next, previous, style] + ShortcutStylePreference.allCases.map { $0.localizedString }
    private var groups: NSStackView?

    override func makeContentView() -> NSView {
        let groups = StackView([], .vertical)
        self.groups = groups
        rebuildRows()
        return groups
    }

    private func rebuildRows() {
        guard let groups else { return }
        groups.arrangedSubviews.forEach { groups.removeArrangedSubview($0); $0.removeFromSuperview() }
        let table = TableGroupView(title: Self.title, width: SheetWindow.width)
        let toggle = Switch(Preferences.projectsEnabled)
        toggle.target = self
        toggle.action = #selector(toggleEnabled(_:))
        _ = table.addRow(TableGroupView.Row(leftTitle: Self.enable, rightViews: [toggle]))
        if Projects.isEnabled {
            addRecorder(table, Self.hold, ProjectSwitcher.holdShortcutId)
            addRecorder(table, Self.next, ProjectSwitcher.nextShortcutId)
            addRecorder(table, Self.previous, ProjectSwitcher.previousShortcutId)
            _ = table.addRow(TableGroupView.Row(leftTitle: Self.style, rightViews: [LabelAndControl.makeDropdown("projectsShortcutStyle", ShortcutStylePreference.allCases)]))
        }
        groups.addArrangedSubview(TableGroupSetView(originalViews: [table], padding: 0))
    }

    private func addRecorder(_ table: TableGroupView, _ label: String, _ key: String) {
        _ = table.addRow(TableGroupView.Row(leftTitle: label, rightViews: [
            LabelAndControl.makeLabelWithRecorder(label, key, Preferences.shortcut(key), labelPosition: .right)[0],
        ]))
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        Preferences.set("projectsEnabled", sender.state == .on ? "true" : "false")
        if Projects.isEnabled {
            _ = ProjectsPanel.shared
        } else {
            ProjectSwitcher.hide()
            Projects.active = Projects.spaces.first { $0.isCurrent }.map { Projects.forSpace(uuid: $0.uuid) }
        }
        DispatchQueue.main.async { [weak self] in self?.rebuildRows() }
    }
}
