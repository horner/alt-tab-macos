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
        alert.informativeText = String(format: NSLocalizedString("%d selected window(s) already belong to: %@. Move removes them from those Projects and moves them to this Project's Desktop. Keep in Both adds them without changing their Desktop or existing memberships.", comment: ""), conflicts.count, sources.map { $0.resolvedName }.joined(separator: ", "))
        alert.addButton(withTitle: NSLocalizedString("Move", comment: "Project membership action")).keyEquivalent = "\r"
        alert.addButton(withTitle: NSLocalizedString("Keep in Both", comment: "Project membership action"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "")).keyEquivalent = "\u{1b}"
        ProjectPrompt.present(alert, from: parent) { response in
            Logger.debug { "projects assignment prompt target=\(project.id) conflicts=\(conflicts.sorted()) response=\(response.rawValue)" }
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            Projects.assign(liveIds(windows).intersection(ids), to: project, move: response == .alertFirstButtonReturn)
        }
    }

    static func moveToDesktop(_ windows: [Window], project: Project) {
        let home = project.homeSpaceUuid
        // Sheet completion may share the dismissal turn; let that frame commit before moving windows.
        DispatchQueue.main.async {
            guard Projects.isEnabled, Projects.byId[project.id] === project, project.homeSpaceUuid == home else { return }
            let live = windows.filter { window in
                Windows.list.contains { $0 === window } && project.members.contains(window.tracked.id)
            }
            let desktops = Dictionary(uniqueKeysWithValues: Projects.spaces.filter { $0.desktopNumber > 0 }.map { ($0.spaceId, $0.uuid) })
            var remaining = live.count
            var failures = [ProjectRestoreNotice.Row]()
            let name = project.resolvedName
            for window in live {
                let title = ProjectNameResolver.normalized(window.title) ?? window.application.localizedName ?? NSLocalizedString("Unknown window", comment: "Project Desktop move failure")
                let target = ProjectRestoreNotice.WindowTarget(window)
                let complete: (String?) -> Void = { reason in
                    if let reason { failures.append(.init(title: title, detail: reason, target: target)) }
                    remaining -= 1
                    guard remaining == 0, !failures.isEmpty else { return }
                    let rows = failures
                    DispatchQueue.main.async {
                        ProjectRestoreNotice.showSummary(title: String(format: NSLocalizedString("Assigned to %@; Desktop move incomplete", comment: "Project Desktop move failure"), name), rows: rows)
                    }
                }
                moveToDesktop(window, home: home, desktops: desktops, completion: complete)
            }
        }
    }

    private static func moveToDesktop(_ window: Window, home: String, desktops: [UInt64: String], completion: @escaping (String?) -> Void) {
        let decision = WindowDesktopRestoreResolver.decision(isEligible: WindowDesktopMove.isEligible(window),
            spaces: window.spaceIds, projectHomes: [home], desktops: desktops)
        switch decision {
        case .alreadyHome: completion(nil)
        case .move(let destination):
            WindowDesktopMove.restore(window, to: destination) { succeeded in
                completion(succeeded ? nil : NSLocalizedString("Desktop move could not be confirmed", comment: "Project Desktop move failure"))
            }
        case .missingDesktop:
            completion(NSLocalizedString("Project Desktop unavailable", comment: "Project Desktop move failure"))
        default:
            completion(NSLocalizedString("Desktop move unavailable for this window", comment: "Project Desktop move failure"))
        }
    }

    private static func liveIds(_ windows: [Window]) -> Set<String> {
        let live = Set(Windows.list.map { ObjectIdentifier($0) })
        return Set(windows.filter { live.contains(ObjectIdentifier($0)) && canAssign($0) }.map { $0.tracked.id })
    }
}
