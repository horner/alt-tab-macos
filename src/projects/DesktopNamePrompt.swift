import Cocoa

enum DesktopNamePrompt {
    static func present(_ desktop: Project) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Name this Desktop…", comment: "Desktop menu action")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.stringValue = desktop.resolvedName
        let choices = Projects.list.filter { $0.isCustom }.map { project -> NSButton in
            let choice = NSButton(checkboxWithTitle: project.resolvedName, target: nil, action: nil)
            choice.identifier = NSUserInterfaceItemIdentifier(project.id)
            choice.state = desktop.linkedProjectIds.contains(project.id) ? .on : .off
            if let other = Projects.list.first(where: { $0 !== desktop && $0.linkedProjectIds.contains(project.id) }) {
                choice.title = "\(project.resolvedName) — \(other.resolvedName)"
                choice.isEnabled = false
            }
            return choice
        }
        let create = NSButton(checkboxWithTitle: NSLocalizedString("Create a new Project", comment: ""), target: nil, action: nil)
        let rows = choices + [create]
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: rows.count * 28))
        for (index, choice) in rows.enumerated() {
            choice.frame = NSRect(x: 0, y: (rows.count - index - 1) * 28, width: 360, height: 24)
            choice.lineBreakMode = .byTruncatingTail
            choice.toolTip = choice.title
            document.addSubview(choice)
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: min(220, document.frame.height)))
        scroll.documentView = document
        scroll.hasVerticalScroller = document.frame.height > 220
        scroll.drawsBackground = false
        let title = NSTextField(labelWithString: NSLocalizedString("Projects on this Desktop", comment: "Multiple Projects linked to one Desktop"))
        title.frame = NSRect(x: 0, y: scroll.frame.maxY + 8, width: 360, height: 20)
        field.frame.origin.y = title.frame.maxY + 12
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: field.frame.maxY))
        [field, title, scroll].forEach { view.addSubview($0) }
        alert.accessoryView = view
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Project name prompt"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, Projects.byId[desktop.id] === desktop else { return }
        desktop.name = ProjectNameResolver.normalized(field.stringValue)
        var selected = choices.filter { $0.state == .on }.compactMap { $0.identifier.flatMap { Projects.byId[$0.rawValue] } }
        if !selected.isEmpty || create.state == .on { Preferences.set("projectsEnabled", "true") }
        let created = create.state == .on ? Projects.createCustom(homeSpaceUuid: desktop.homeSpaceUuid) : nil
        if let created { created.name = desktop.resolvedName; selected.append(created) }
        if !Projects.link(desktop, toProjects: selected), let created { Projects.delete(id: created.id) }
    }
}
