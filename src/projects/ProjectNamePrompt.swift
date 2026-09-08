import Cocoa

extension Project {
    var resolvedName: String {
        let desktopNumber = isCustom ? nil : Projects.spaces.first { $0.uuid == homeSpaceUuid }?.desktopNumber ?? 0
        let projectNumber = (Projects.list.filter { $0.isCustom }.firstIndex { $0 === self } ?? 0) + 1
        return ProjectNameResolver.resolved(name: name, autoName: autoName, desktopNumber: desktopNumber, projectNumber: projectNumber)
    }
}

enum ProjectNamePrompt {
    @discardableResult
    static func present(_ project: Project, title: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = project.resolvedName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: NSLocalizedString("Save", comment: "Project name prompt"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        Logger.debug { "projects name prompt response=\(response.rawValue)" }
        guard response == .alertFirstButtonReturn else { return false }
        project.name = ProjectNameResolver.normalized(field.stringValue)
        return true
    }
}
