import Cocoa

final class ProjectWindowPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let windows: [Window]
    private var selected = Set<Int>()
    private weak var addButton: NSButton?

    private init(_ windows: [Window]) {
        self.windows = windows
    }

    static func present(for project: Project, from parent: NSWindow? = nil) {
        guard Projects.isEnabled, project.isCustom, Projects.byId[project.id] === project else { return }
        let windows = Windows.list.filter { ProjectAssignmentPrompt.canAssign($0) && !project.members.contains($0.tracked.id) }
            .sorted { $0.lastFocusOrder < $1.lastFocusOrder }
        let picker = ProjectWindowPicker(windows)
        picker.present(for: project, from: parent)
    }

    private func present(for project: Project, from parent: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Add Windows to %@", comment: "Project window picker"), project.resolvedName)
        guard !windows.isEmpty else {
            alert.informativeText = NSLocalizedString("There are no other open windows to add to this project.", comment: "Project window picker empty state")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            ProjectPrompt.present(alert, from: parent) { _ in }
            return
        }
        alert.informativeText = NSLocalizedString("Choose the windows to add. Windows from other Desktops are included.", comment: "Project window picker")
        alert.accessoryView = makeTable()
        let add = alert.addButton(withTitle: NSLocalizedString("Add", comment: "Project window picker action"))
        add.isEnabled = false
        addButton = add
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: parent) { [self] response in
            guard response == .alertFirstButtonReturn else { return }
            let selection = selected.sorted().map { windows[$0] }
            DispatchQueue.main.async { ProjectAssignmentPrompt.add(selection, to: project, from: parent) }
        }
    }

    private func makeTable() -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: CGFloat(min(280, windows.count * 28))))
        let table = NSTableView(frame: scroll.bounds)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.width = 500
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 26
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int { windows.count }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("window-choice")
        let button = tableView.makeView(withIdentifier: identifier, owner: self) as? NSButton
            ?? NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
        let window = windows[row]
        let app = window.application.localizedName ?? ""
        let title = ProjectNameResolver.normalized(window.title) ?? app
        button.identifier = identifier
        button.title = app.isEmpty || title == app ? title : "\(app) — \(title)"
        button.toolTip = button.title
        button.setAccessibilityLabel(button.title)
        button.lineBreakMode = .byTruncatingTail
        button.tag = row
        button.state = selected.contains(row) ? .on : .off
        return button
    }

    @objc private func toggle(_ sender: NSButton) {
        if sender.state == .on { selected.insert(sender.tag) } else { selected.remove(sender.tag) }
        addButton?.isEnabled = !selected.isEmpty
    }
}
