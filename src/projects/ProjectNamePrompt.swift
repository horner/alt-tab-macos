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
        let alert = makeAlert(project, title: title)
        ProjectPrompt.present(alert, from: window) { response in
            completion(save(project, from: alert, response: response))
        }
    }

    static func rename(_ project: Project, from window: NSWindow?) {
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        present(project, title: NSLocalizedString("Rename Project", comment: "Projects submenu"), from: window) { _ in }
    }

    private static func makeAlert(_ project: Project, title: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = project.resolvedName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Project name prompt"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        return alert
    }

    private static func save(_ project: Project, from alert: NSAlert, response: NSApplication.ModalResponse) -> Bool {
        Logger.debug { "projects name prompt response=\(response.rawValue)" }
        guard response == .alertFirstButtonReturn, Projects.isEnabled, Projects.byId[project.id] === project,
              let field = alert.accessoryView as? NSTextField else { return false }
        project.name = ProjectNameResolver.normalized(field.stringValue)
        return true
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
