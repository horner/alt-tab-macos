import Cocoa

enum ProjectAssignmentPrompt {
    static func canAssign(_ window: Window) -> Bool {
        ProjectMenuResolver.canAssign(isWindowless: window.isWindowlessApp, isPhantom: window.isPhantom, isTabbed: window.isTabbed,
            labelVisibility: SpaceLabelWindows.switcherVisibility(windowId: window.cgWindowId, pid: window.application.pid))
    }

    static func add(_ windows: [Window], to project: Project, from parent: NSWindow? = nil) {
        guard Projects.isEnabled, project.isCustom, Projects.byId[project.id] === project else { return }
        let ids = liveIds(windows)
        guard !ids.isEmpty else { return }
        let sources = Projects.list.filter { $0.isCustom && $0 !== project && !$0.members.isDisjoint(with: ids) }
        guard !sources.isEmpty else { Projects.assign(ids, to: project, move: false); return }
        let conflicts = sources.reduce(into: Set<String>()) { $0.formUnion($1.members.intersection(ids)) }
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Move windows to %@?", comment: "Project assignment conflict"), project.resolvedName)
        alert.informativeText = String(format: NSLocalizedString("%d selected window(s) already belong to: %@. Move removes them from those Projects. Keep in Both adds them without removing existing memberships.", comment: ""), conflicts.count, sources.map { $0.resolvedName }.joined(separator: ", "))
        alert.addButton(withTitle: NSLocalizedString("Move", comment: "Project membership action")).keyEquivalent = "\r"
        alert.addButton(withTitle: NSLocalizedString("Keep in Both", comment: "Project membership action"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: parent) { response in
            Logger.debug { "projects assignment prompt target=\(project.id) conflicts=\(conflicts.sorted()) response=\(response.rawValue)" }
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            Projects.assign(liveIds(windows).intersection(ids), to: project, move: response == .alertFirstButtonReturn)
        }
    }

    private static func liveIds(_ windows: [Window]) -> Set<String> {
        let live = Set(Windows.list.map { ObjectIdentifier($0) })
        return Set(windows.filter { live.contains(ObjectIdentifier($0)) && canAssign($0) }.map { $0.tracked.id })
    }
}
