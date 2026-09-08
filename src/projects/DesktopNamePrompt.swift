import Cocoa

enum DesktopNamePrompt {
    static func present(_ desktop: Project) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Name this Desktop…", comment: "Desktop menu action")
        let field = NSTextField(frame: NSRect(x: 0, y: 86, width: 360, height: 24))
        field.stringValue = desktop.resolvedName
        let link = NSButton(checkboxWithTitle: NSLocalizedString("Link this Desktop to a Project", comment: ""), target: nil, action: nil)
        link.frame = NSRect(x: 0, y: 56, width: 360, height: 24)
        link.state = Projects.linkedProject(for: desktop) == nil ? .off : .on
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 26, width: 360, height: 26))
        picker.autoenablesItems = false
        picker.addItem(withTitle: NSLocalizedString("Create a new Project", comment: ""))
        for project in Projects.list where project.isCustom {
            picker.addItem(withTitle: project.resolvedName)
            let item = picker.lastItem!
            item.representedObject = project.id
            if let other = Projects.list.first(where: { $0 !== desktop && $0.linkedProjectId == project.id }) {
                item.title = "\(project.resolvedName) — \(other.resolvedName)"
                item.isEnabled = false
            }
            if desktop.linkedProjectId == project.id { picker.select(item) }
        }
        picker.isEnabled = link.state == .on
        link.onAction = { _ in picker.isEnabled = link.state == .on }
        let note = NSTextField(wrappingLabelWithString: NSLocalizedString("Linking enables Projects and includes existing and future windows on this Desktop.", comment: ""))
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 0, y: -16, width: 360, height: 38)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 130))
        [field, link, picker, note].forEach { $0.frame.origin.y += 16; view.addSubview($0) }
        alert.accessoryView = view
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Project name prompt"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        Logger.debug { "projects name prompt response=\(response.rawValue)" }
        guard response == .alertFirstButtonReturn, Projects.byId[desktop.id] === desktop else { return }
        desktop.name = ProjectNameResolver.normalized(field.stringValue)
        guard link.state == .on else { Projects.link(desktop, to: nil); return }
        Preferences.set("projectsEnabled", "true")
        let selected = (picker.selectedItem?.representedObject as? String).flatMap { Projects.byId[$0] }
        let project = selected ?? Projects.createCustom(homeSpaceUuid: desktop.homeSpaceUuid)
        guard let project else { return }
        if selected == nil { project.name = desktop.resolvedName }
        if !Projects.link(desktop, to: project), selected == nil { Projects.delete(id: project.id) }
    }
}
