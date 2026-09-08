import Cocoa

enum ProjectAssignmentPrompt {
    static func add(_ windows: [Window], to project: Project) {
        guard Projects.isEnabled, project.isCustom, Projects.byId[project.id] === project else { return }
        let ids = Set(windows.filter { window in Windows.list.contains(where: { $0 === window }) }.map { $0.tracked.id })
        let sources = Projects.list.filter { $0.isCustom && $0 !== project && !$0.members.isDisjoint(with: ids) }
        guard !sources.isEmpty else { Projects.assign(ids, to: project, move: false); return }
        let conflicts = sources.reduce(into: Set<String>()) { $0.formUnion($1.members.intersection(ids)) }
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Move windows to %@?", comment: "Project assignment conflict"), project.resolvedName)
        alert.informativeText = String(format: NSLocalizedString("%d selected window(s) already belong to: %@. Move removes them from those Projects. Keep in Both adds them without removing existing memberships.", comment: ""), conflicts.count, sources.map { $0.resolvedName }.joined(separator: ", "))
        alert.addButton(withTitle: NSLocalizedString("Move", comment: "Project membership action")).keyEquivalent = "\r"
        alert.addButton(withTitle: NSLocalizedString("Keep in Both", comment: "Project membership action"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        Logger.debug { "projects assignment prompt target=\(project.id) conflicts=\(conflicts.sorted()) response=\(response.rawValue)" }
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
        Projects.assign(ids, to: project, move: response == .alertFirstButtonReturn)
    }
}
