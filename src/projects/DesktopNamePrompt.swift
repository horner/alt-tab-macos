import Cocoa

enum DesktopNamePrompt {
    private static var panel: Panel?

    static func present(_ desktop: Project) {
        DispatchQueue.main.async {
            if let panel, panel.isVisible, panel.desktop === desktop { panel.makeKeyAndOrderFront(nil); return }
            panel?.close()
            let next = Panel(desktop)
            panel = next
            next.center()
            next.makeKeyAndOrderFront(nil)
        }
    }

    private final class Panel: NSPanel {
        let desktop: Project
        private let field = NSTextField(frame: .zero)
        private var choices = [NSButton]()
        private let create = NSButton(checkboxWithTitle: NSLocalizedString("Create a new Project", comment: ""), target: nil, action: nil)
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        init(_ desktop: Project) {
            self.desktop = desktop
            // Taking key focus without activating AltTab avoids raising its windows on another Desktop.
            super.init(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            title = NSLocalizedString("Name this Desktop…", comment: "Desktop menu action")
            collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            isFloatingPanel = true
            hidesOnDeactivate = false
            isReleasedWhenClosed = false
            isExcludedFromWindowsMenu = true
            setAccessibilitySubrole(.floatingWindow)
            field.maximumNumberOfLines = 1
            field.cell?.isScrollable = true
            field.stringValue = desktop.resolvedName
            field.setAccessibilityLabel(title)
            makeChoices()
            makeContent()
            initialFirstResponder = field
        }

        private func makeChoices() {
            choices = Projects.list.filter { $0.isCustom }.map { project in
                let choice = NSButton(checkboxWithTitle: project.resolvedName, target: nil, action: nil)
                choice.identifier = NSUserInterfaceItemIdentifier(project.id)
                choice.state = desktop.linkedProjectIds.contains(project.id) ? .on : .off
                if let other = Projects.list.first(where: { $0 !== desktop && $0.linkedProjectIds.contains(project.id) }) {
                    choice.title = "\(project.resolvedName) — \(other.resolvedName)"
                    choice.isEnabled = false
                }
                return choice
            }
        }

        private func makeContent() {
            let rows = choices + [create]
            let document = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: rows.count * 28))
            for (index, choice) in rows.enumerated() {
                choice.frame = NSRect(x: 0, y: (rows.count - index - 1) * 28, width: 340, height: 24)
                choice.lineBreakMode = .byTruncatingTail
                choice.toolTip = choice.title
                document.addSubview(choice)
            }
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 60, width: 360, height: min(220, document.frame.height)))
            scroll.documentView = document
            scroll.hasVerticalScroller = document.frame.height > 220
            scroll.drawsBackground = false
            let heading = NSTextField(labelWithString: NSLocalizedString("Projects on this Desktop", comment: "Multiple Projects linked to one Desktop"))
            heading.frame = NSRect(x: 20, y: scroll.frame.maxY + 8, width: 360, height: 20)
            field.frame = NSRect(x: 20, y: heading.frame.maxY + 12, width: 360, height: 24)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: field.frame.maxY + 20))
            let save = NSButton(title: NSLocalizedString("Save", comment: "Project name prompt"), target: self, action: #selector(save))
            let cancel = NSButton(title: NSLocalizedString("Cancel", comment: ""), target: self, action: #selector(cancelOperation(_:)))
            for (index, button) in [cancel, save].enumerated() {
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 204 + index * 92, y: 16, width: 84, height: 32)
            }
            save.keyEquivalent = "\r"
            cancel.keyEquivalent = "\u{1b}"
            defaultButtonCell = save.cell as? NSButtonCell
            [field, heading, scroll, cancel, save].forEach { view.addSubview($0) }
            setContentSize(view.frame.size)
            contentView = view
        }

        override func cancelOperation(_ sender: Any?) { close() }

        @objc private func save() {
            let name = ProjectNameResolver.normalized(field.stringValue)
            let ids = choices.filter { $0.state == .on }.compactMap { $0.identifier?.rawValue }
            let shouldCreate = create.state == .on
            close()
            DispatchQueue.main.async { [desktop] in
                guard Projects.byId[desktop.id] === desktop, !desktop.isCustom,
                      Projects.spaces.contains(where: { $0.uuid == desktop.homeSpaceUuid }) else { return }
                desktop.name = name
                var selected = ids.compactMap { Projects.byId[$0] }
                if !selected.isEmpty || shouldCreate { Preferences.set("projectsEnabled", "true") }
                let created = shouldCreate ? Projects.createCustom(homeSpaceUuid: desktop.homeSpaceUuid) : nil
                if let created { created.name = desktop.resolvedName; selected.append(created) }
                guard Projects.link(desktop, toProjects: selected) else {
                    if let created { Projects.delete(id: created.id) }
                    return
                }
                SpaceLabelWindows.show(on: desktop.homeSpaceUuid)
            }
        }
    }
}
