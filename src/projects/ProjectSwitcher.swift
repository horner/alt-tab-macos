import Cocoa

enum ProjectSwitcher: AuxiliarySwitcher {
    static let label = NSLocalizedString("Projects switcher", comment: "")
    static let holdShortcutId = "holdProjectsShortcut"
    static let nextShortcutId = "nextProjectShortcut"
    static let previousShortcutId = "previousProjectShortcut"
    static private(set) var isActive = false
    static var isEnabled: Bool { Projects.isEnabled && Preferences.shortcut(holdShortcutId) != nil }
    private static var items = [ProjectTileItem]()
    private static var selectedIndex = 0
    private static var mru = [String]()

    static func shouldTrigger(_ id: String, _ triggerPhase: ShortcutTriggerPhase) -> Bool {
        guard isEnabled else { return false }
        guard triggerPhase == .down else {
            return isActive && (UserDefaults.standard.string(forKey: "projectsShortcutStyle") ?? ShortcutStylePreference.focusOnRelease.indexAsString) == ShortcutStylePreference.focusOnRelease.indexAsString
        }
        guard !SwitcherSession.isActive, !SpacesSwitcher.isActive else { return false }
        return id != previousShortcutId || isActive
    }

    static func showOrCycle() {
        guard isEnabled, !SwitcherSession.isActive, !SpacesSwitcher.isActive else { return }
        guard !isActive else { cycle(1); return }
        let desktop = Projects.spaces.first { $0.isCurrent }
        let desktopId = desktop.map { Projects.forSpace(uuid: $0.uuid).id }
        let ids = ProjectsOrderResolver.sorted(currentDesktopId: desktopId,
            customProjectIds: Projects.list.filter { $0.isCustom }.map { $0.id }, mru: mru)
        items = ids.compactMap { id in Projects.byId[id].map { ProjectTileItem(project: $0, desktopNumber: desktop?.desktopNumber ?? 0) } }
        guard !items.isEmpty else { return }
        selectedIndex = SpacesOrderResolver.initialSelection(count: items.count, currentIndex: items.firstIndex { $0.project === Projects.active })
        NSScreen.updatePreferred()
        Appearance.update()
        isActive = true
        ProjectsPanel.shared.show(items, selectedIndex)
    }

    static func cycle(_ step: Int) {
        guard isActive else { return }
        selectedIndex = SpacesOrderResolver.cycle(selected: selectedIndex, step: step, count: items.count)
        ProjectsPanel.shared.refreshHighlight(items, selectedIndex)
    }

    static func focusSelected() {
        guard isActive, items.indices.contains(selectedIndex) else { return }
        let project = items[selectedIndex].project
        hide()
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        Projects.active = project
        if project.isCustom {
            mru.removeAll { $0 == project.id }
            mru.insert(project.id, at: 0)
        }
        // AppKit commits the panel dismissal at the end of this turn; focus may block on another process.
        DispatchQueue.main.async {
            guard Projects.isEnabled, !isActive, Projects.active === project, Projects.byId[project.id] === project, project.isCustom else { return }
            Windows.list.filter { !$0.isWindowlessApp && project.members.contains($0.id) }
                .min { $0.lastFocusOrder < $1.lastFocusOrder }?.focus()
        }
    }

    static func hide() {
        guard isActive else { return }
        isActive = false
        ProjectsPanel.shared.orderOut(nil)
        items.removeAll(keepingCapacity: true)
    }
}
