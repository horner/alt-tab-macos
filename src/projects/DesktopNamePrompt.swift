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
        private let choices = NSPopUpButton(frame: .zero)
        private let detail = NSTextField(wrappingLabelWithString: "")
        private let projects: [Project]
        private let originalOwnerId: String?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        init(_ desktop: Project) {
            self.desktop = desktop
            projects = Projects.list.filter { $0.isCustom }
            originalOwnerId = Projects.owner(for: desktop.homeSpaceUuid)?.id
            // Taking key focus without activating AltTab avoids raising its windows on another Desktop.
            super.init(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            title = NSLocalizedString("Project for This Desktop", comment: "Choose the Project owning a Desktop")
            collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            isFloatingPanel = true
            hidesOnDeactivate = false
            isReleasedWhenClosed = false
            isExcludedFromWindowsMenu = true
            setAccessibilitySubrole(.floatingWindow)
            field.maximumNumberOfLines = 1
            field.cell?.isScrollable = true
            field.setAccessibilityLabel(NSLocalizedString("Project name", comment: "Project name field"))
            choices.addItems(withTitles: [NSLocalizedString("No Project", comment: "Unassigned Desktop"), NSLocalizedString("Create a New Project", comment: "Create the Desktop owner")])
            for project in projects {
                let number = Projects.spaces.first { $0.uuid == project.homeSpaceUuid && $0.desktopNumber > 0 }?.desktopNumber
                choices.addItem(withTitle: number.map { "\(project.resolvedName) · Desktop \($0)" } ?? project.resolvedName)
            }
            choices.target = self
            choices.action = #selector(selectionChanged)
            choices.setAccessibilityLabel(NSLocalizedString("Project", comment: "Desktop owner picker"))
            choices.selectItem(at: originalOwnerId.flatMap { id in projects.firstIndex { $0.id == id }.map { $0 + 2 } } ?? 1)
            makeContent()
            selectionChanged()
            initialFirstResponder = field
        }

        private var selectedProject: Project? {
            let index = choices.indexOfSelectedItem - 2
            return projects.indices.contains(index) ? projects[index] : nil
        }

        private func makeContent() {
            let heading = NSTextField(labelWithString: NSLocalizedString("Project", comment: "Desktop owner picker label"))
            heading.frame = NSRect(x: 20, y: 224, width: 360, height: 20)
            choices.frame = NSRect(x: 20, y: 192, width: 360, height: 28)
            let name = NSTextField(labelWithString: NSLocalizedString("Project name", comment: "Project name field label"))
            name.frame = NSRect(x: 20, y: 165, width: 360, height: 20)
            field.frame = NSRect(x: 20, y: 137, width: 360, height: 24)
            detail.frame = NSRect(x: 20, y: 60, width: 360, height: 64)
            detail.textColor = .secondaryLabelColor
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 264))
            let save = NSButton(title: NSLocalizedString("Save", comment: "Project name prompt"), target: self, action: #selector(save))
            let cancel = NSButton(title: NSLocalizedString("Cancel", comment: ""), target: self, action: #selector(cancelOperation(_:)))
            for (index, button) in [cancel, save].enumerated() {
                button.bezelStyle = .rounded
                button.frame = NSRect(x: 204 + index * 92, y: 16, width: 84, height: 32)
            }
            save.keyEquivalent = "\r"
            cancel.keyEquivalent = "\u{1b}"
            defaultButtonCell = save.cell as? NSButtonCell
            [heading, choices, name, field, detail, cancel, save].forEach { view.addSubview($0) }
            setContentSize(view.frame.size)
            contentView = view
        }

        @objc private func selectionChanged() {
            let selected = selectedProject
            let creating = choices.indexOfSelectedItem == 1
            field.isEnabled = choices.indexOfSelectedItem != 0
            field.stringValue = selected?.resolvedName ?? (creating ? Projects.availableProjectName("Project") : "")
            if let owner = Projects.owner(for: desktop.homeSpaceUuid), owner !== selected {
                detail.stringValue = String(format: NSLocalizedString("%@ will stay open without a Desktop. Its windows and history are kept.", comment: "Replacing the Desktop owner"), owner.resolvedName)
            } else if let selected, !selected.homeSpaceUuid.isEmpty, selected.homeSpaceUuid != desktop.homeSpaceUuid {
                detail.stringValue = NSLocalizedString("This Project will use this Desktop. Its windows stay where they are until you move them.", comment: "Reassigning a Project Desktop")
            } else {
                detail.stringValue = NSLocalizedString("The Desktop label uses its Project’s name. Renaming the Project updates the label.", comment: "Desktop name follows its owner")
            }
        }

        override func cancelOperation(_ sender: Any?) { close() }

        @objc private func save() {
            let selected = selectedProject
            let creating = choices.indexOfSelectedItem == 1
            let proposed = field.stringValue
            if choices.indexOfSelectedItem != 0, let error = ProjectNameResolver.validationError(proposed, existing: Projects.projectNames(excluding: selected?.id)) {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Choose a different project name", comment: "Duplicate project name")
                alert.informativeText = error
                alert.beginSheetModal(for: self)
                return
            }
            let expectedOwner = originalOwnerId
            close()
            DispatchQueue.main.async { [desktop] in
                guard Projects.byId[desktop.id] === desktop, !desktop.isCustom,
                      Projects.spaces.contains(where: { $0.uuid == desktop.homeSpaceUuid && $0.desktopNumber > 0 }),
                      Projects.owner(for: desktop.homeSpaceUuid)?.id == expectedOwner,
                      selected.map({ Projects.byId[$0.id] === $0 }) ?? true else { return }
                if selected != nil || creating { Preferences.set("projectsEnabled", "true") }
                let created = creating ? Projects.createCustom(homeSpaceUuid: "") : nil
                guard !creating || created != nil else { return }
                let owner = selected ?? created
                guard Projects.link(desktop, to: owner) else {
                    if let created { Projects.delete(id: created.id) }
                    return
                }
                owner?.name = ProjectNameResolver.normalized(proposed)
                SpaceLabelWindows.show(on: desktop.homeSpaceUuid)
            }
        }
    }
}
