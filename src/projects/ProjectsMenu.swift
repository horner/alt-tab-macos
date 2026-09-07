import Cocoa

final class ProjectsMenu: NSObject {
    private static var desktopItem: NSMenuItem!
    private static var projectsItem: NSMenuItem!
    private static weak var focusedWindow: Window?
    private static var activeItem: NSMenuItem!
    private static var addFocusedItem: NSMenuItem!
    private static var addVisibleItem: NSMenuItem!
    private static var desktopUuid: String?
    private static var visibleWindows = [Window]()

    static func install(in menu: NSMenu) {
        desktopItem = item(NSLocalizedString("Name this Desktop…", comment: "Desktop menu action"), #selector(nameDesktop))
        projectsItem = item(NSLocalizedString("Projects", comment: "Projects menu"), nil)
        projectsItem.submenu = NSMenu()
        projectsItem.isHidden = !Projects.isEnabled
        activeItem = item("", nil)
        addFocusedItem = item(NSLocalizedString("Add this Window to Active Project", comment: ""), #selector(addWindow))
        addVisibleItem = item(NSLocalizedString("Add All Visible Windows to Active Project", comment: ""), #selector(addVisibleWindows))
        [activeItem!, addFocusedItem!, addVisibleItem!].forEach { $0.isHidden = !Projects.isEnabled; menu.addItem($0) }
        menu.addItem(desktopItem)
        menu.addItem(projectsItem)
    }

    static func refresh(_ menu: NSMenu) {
        guard desktopItem?.menu === menu else { return }
        focusedWindow = Windows.list.first {
            !$0.isWindowlessApp && $0.application.pid == Applications.frontmostPid && $0.application.focusedWindow === $0
        }
        desktopUuid = Projects.spaces.first { $0.isCurrent }?.uuid
        visibleWindows = Windows.list.filter { isVisibleOnDesktop($0) }
        refreshActiveItems()
        desktopItem.isEnabled = currentDesktop != nil
        projectsItem.isHidden = !Projects.isEnabled
        guard Projects.isEnabled, let submenu = projectsItem.submenu else { return }
        submenu.autoenablesItems = false
        submenu.removeAllItems()
        let empty = item(NSLocalizedString("New Project…", comment: ""), #selector(createEmptyProject))
        empty.isEnabled = currentDesktop != nil
        submenu.addItem(empty)
        let all = item(NSLocalizedString("New Project from All Visible Windows…", comment: ""), #selector(createVisibleProject))
        all.isEnabled = currentDesktop != nil && !visibleWindows.isEmpty
        submenu.addItem(all)
        let create = item(NSLocalizedString("New Project from this Window…", comment: "Projects menu action"), #selector(createProject))
        create.isEnabled = focusedWindow != nil && currentDesktop != nil
        submenu.addItem(create)
        addProjects(to: submenu, title: NSLocalizedString("Add this Window to Project", comment: "Projects submenu"),
            action: #selector(addWindow), enabled: focusedWindow != nil)
        addProjects(to: submenu, title: NSLocalizedString("Rename Project", comment: "Projects submenu"), action: #selector(renameProject))
        addProjects(to: submenu, title: NSLocalizedString("Delete Project", comment: "Projects submenu"), action: #selector(deleteProject))
    }

    @objc static func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === addFocusedItem || menuItem === addVisibleItem { return Projects.isEnabled && menuItem.representedObject != nil && menuItem.isEnabled }
        return menuItem.isEnabled
    }

    private static var currentDesktop: Project? {
        Projects.spaces.first { $0.isCurrent }.map { Projects.forSpace(uuid: $0.uuid) }
    }

    private static func addProjects(to menu: NSMenu, title: String, action: Selector, enabled: Bool = true) {
        let parent = item(title, nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for project in Projects.list where project.isCustom {
            let child = item(project.resolvedName, action)
            child.representedObject = project.id
            child.isEnabled = enabled
            submenu.addItem(child)
        }
        parent.submenu = submenu
        parent.isEnabled = enabled && !submenu.items.isEmpty
        menu.addItem(parent)
    }

    private static func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private static func nameDesktop() {
        guard let project = currentDesktop else { return }
        ProjectNamePrompt.present(project, title: NSLocalizedString("Name this Desktop…", comment: "Desktop menu action"))
    }

    private static func refreshActiveItems() {
        let active = Projects.active.flatMap { $0.isCustom ? $0 : nil }
        activeItem.title = active.map { String(format: NSLocalizedString("Active Project: %@", comment: ""), $0.resolvedName) }
            ?? NSLocalizedString("No Active Project", comment: "")
        activeItem.isEnabled = false
        for entry in [activeItem!, addFocusedItem!, addVisibleItem!] { entry.isHidden = !Projects.isEnabled }
        addFocusedItem.representedObject = active?.id
        addVisibleItem.representedObject = active?.id
        addFocusedItem.isEnabled = active != nil && focusedWindow != nil
        addVisibleItem.isEnabled = active != nil && !visibleWindows.isEmpty
    }

    /// Visible means a live, non-minimized destination on this Desktop, including covered windows.
    /// Project membership and the window switcher's user filters must not narrow this capture.
    private static func isVisibleOnDesktop(_ window: Window) -> Bool {
        guard let space = Projects.spaces.first(where: { $0.uuid == desktopUuid }) else { return false }
        return !window.isWindowlessApp && !window.isMinimized && !window.isHidden && !window.isPhantom
            && !window.isTabbed && window.spaceIds.contains(space.spaceId)
    }

    @objc private static func createEmptyProject() {
        createNamedProject(with: [], title: NSLocalizedString("New Project…", comment: ""))
    }

    @objc private static func createVisibleProject() {
        createNamedProject(with: visibleWindows.filter { isVisibleOnDesktop($0) },
            title: NSLocalizedString("New Project from All Visible Windows…", comment: ""))
    }

    @objc private static func createProject() {
        guard let window = focusedWindow else { return }
        createNamedProject(with: [window], title: NSLocalizedString("New Project from this Window…", comment: "Projects menu action"))
    }

    private static func createNamedProject(with windows: [Window], title: String) {
        guard Projects.isEnabled, let uuid = desktopUuid,
              let project = Projects.createCustom(homeSpaceUuid: uuid) else { return }
        project.autoName = windows.first.flatMap { ProjectNameResolver.claim(name: nil, autoName: nil, appName: $0.application.localizedName) }
        guard ProjectNamePrompt.present(project, title: title) else { Projects.delete(id: project.id); return }
        guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
        for window in windows where Windows.list.contains(where: { $0 === window }) {
            Projects.add(windowId: window.tracked.id, to: project)
        }
        Projects.active = project
    }

    @objc private static func addVisibleWindows(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        for window in visibleWindows where Windows.list.contains(where: { $0 === window }) && isVisibleOnDesktop(window) {
            Projects.add(windowId: window.tracked.id, to: project)
        }
    }

    @objc private static func addWindow(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let window = focusedWindow, Windows.list.contains(where: { $0 === window }),
              let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        Projects.add(windowId: window.tracked.id, to: project)
    }

    @objc private static func renameProject(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        ProjectNamePrompt.present(project, title: NSLocalizedString("Rename Project", comment: "Projects submenu"))
    }

    @objc private static func deleteProject(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let id = sender.representedObject as? String else { return }
        Projects.delete(id: id)
    }
}
