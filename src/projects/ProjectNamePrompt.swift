import Cocoa

extension Project {
    var resolvedName: String {
        let desktopNumber = isCustom ? nil : Projects.spaces.first { $0.uuid == homeSpaceUuid }?.desktopNumber ?? 0
        let projectNumber = (Projects.list.filter { $0.isCustom }.firstIndex { $0 === self } ?? 0) + 1
        return ProjectNameResolver.resolved(name: name, autoName: autoName, desktopNumber: desktopNumber, projectNumber: projectNumber)
    }
}

enum ProjectNamePrompt {
    static func present(_ project: Project, title: String, from window: NSWindow?, completion: @escaping (Bool) -> Void) {
        present(project, title: title, value: project.resolvedName, error: nil, from: window, completion: completion)
    }

    private static func present(_ project: Project, title: String, value: String, error: String?, from window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let alert = makeAlert(title: title, value: value, error: error)
        ProjectPrompt.present(alert, from: window) { response in
            guard response == .alertFirstButtonReturn, Projects.isEnabled, Projects.byId[project.id] === project,
                  let field = alert.accessoryView as? NSTextField else { completion(false); return }
            let proposed = field.stringValue
            if let error = ProjectNameResolver.validationError(proposed, existing: Projects.projectNames(excluding: project.id)) {
                DispatchQueue.main.async {
                    present(project, title: title, value: proposed, error: error, from: window, completion: completion)
                }
                return
            }
            project.name = ProjectNameResolver.normalized(proposed)
            completion(true)
        }
    }

    static func rename(_ project: Project, from window: NSWindow?) {
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        present(project, title: NSLocalizedString("Rename Project", comment: "Projects submenu"), from: window) { _ in }
    }

    private static func makeAlert(title: String, value: String, error: String?) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error ?? ""
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Project name prompt"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        return alert
    }

}

enum ProjectPrompt {
    // App activation can raise AltTab windows on another Desktop; label prompts stay attached to their source.
    static func present(_ alert: NSAlert, from window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        completion(alert.runModal())
    }
}
