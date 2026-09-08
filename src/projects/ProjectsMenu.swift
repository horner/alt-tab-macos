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
    private static var navigationObserver: NSObjectProtocol?
    private static var navigationTimeout: DispatchWorkItem?
    private static var navigationId = UUID()

    private final class WindowSelection: NSObject {
        let projectId: String
        weak var window: Window?

        init(_ project: Project, _ window: Window) {
            projectId = project.id
            self.window = window
        }
    }

    static func install(in menu: NSMenu) {
        desktopItem = item(NSLocalizedString("Name this Desktop…", comment: "Desktop menu action"), #selector(nameDesktop))
        projectsItem = item(NSLocalizedString("Projects", comment: "Projects menu"), nil)
        projectsItem.submenu = NSMenu()
        projectsItem.isHidden = !Projects.isEnabled
        activeItem = item("", nil)
        addFocusedItem = item(NSLocalizedString("Add this Window to Active Project", comment: ""), #selector(addWindow))
        addVisibleItem = item("", #selector(addVisibleWindows))
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
        activeItem.isEnabled = true
        activeItem.submenu = makeActiveMenu(active)
        addVisibleItem.title = active.map { String(format: NSLocalizedString("Add all visible to: %@", comment: ""), $0.resolvedName) }
            ?? NSLocalizedString("Add all visible to: No Active Project", comment: "")
        for entry in [activeItem!, addFocusedItem!, addVisibleItem!] { entry.isHidden = !Projects.isEnabled }
        addFocusedItem.representedObject = active?.id
        addVisibleItem.representedObject = active?.id
        addFocusedItem.isEnabled = active != nil && focusedWindow != nil
        addVisibleItem.isEnabled = active != nil && !visibleWindows.isEmpty
    }

    private static func makeActiveMenu(_ active: Project?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let desktop = item(NSLocalizedString("Use Desktop (No Project)", comment: ""), #selector(selectDesktop))
        desktop.state = active == nil ? .on : .off
        menu.addItem(desktop)
        if let active {
            menu.addItem(.separator())
            addWindows(of: active, to: menu)
        }
        let others = item(NSLocalizedString("Other Projects", comment: ""), nil)
        let projects = NSMenu()
        projects.autoenablesItems = false
        for project in Projects.list where project.isCustom && project !== active {
            let entry = item(project.resolvedName, nil)
            let windows = NSMenu()
            windows.autoenablesItems = false
            let select = item(NSLocalizedString("Activate Project", comment: ""), #selector(selectProject))
            select.representedObject = project.id
            windows.addItem(select)
            windows.addItem(.separator())
            addWindows(of: project, to: windows)
            entry.submenu = windows
            projects.addItem(entry)
        }
        others.submenu = projects
        others.isEnabled = !projects.items.isEmpty
        menu.addItem(.separator())
        menu.addItem(others)
        menu.addItem(item(NSLocalizedString("New Project…", comment: ""), #selector(createEmptyProject)))
        return menu
    }

    private static func addWindows(of project: Project, to menu: NSMenu) {
        let windows = Windows.list.filter { !$0.isWindowlessApp && !$0.isPhantom && !$0.isTabbed && project.members.contains($0.tracked.id) }
            .sorted { $0.lastFocusOrder < $1.lastFocusOrder }
        for window in windows {
            let title = ProjectNameResolver.normalized(window.title) ?? window.application.localizedName ?? ""
            let entry = item(title, #selector(selectWindow))
            entry.representedObject = WindowSelection(project, window)
            if let icon = window.icon { entry.image = NSImage(cgImage: icon, size: NSSize(width: 16, height: 16)) }
            menu.addItem(entry)
        }
        if windows.isEmpty {
            let empty = item(NSLocalizedString("No Open Windows", comment: ""), nil)
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    @objc private static func selectDesktop() {
        cancelNavigation()
        guard Projects.isEnabled else { return }
        Projects.active = currentDesktop
    }

    @objc private static func selectProject(_ sender: NSMenuItem) {
        cancelNavigation()
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        Projects.active = project
    }

    @objc private static func selectWindow(_ sender: NSMenuItem) {
        cancelNavigation()
        guard Projects.isEnabled, let selection = sender.representedObject as? WindowSelection,
              let window = selection.window, Windows.list.contains(where: { $0 === window }),
              let project = Projects.byId[selection.projectId], project.members.contains(window.tracked.id) else { return }
        Projects.active = project
        let id = navigationId
        // Focus waits until menu tracking ends so its dismissal reaches the screen before IPC.
        DispatchQueue.main.async {
            guard navigationId == id, Projects.isEnabled, Projects.active === project,
                  Windows.list.contains(where: { $0 === window }), project.members.contains(window.tracked.id) else { return }
            preserveMenuSelection(project, window, id)
            window.focus()
        }
    }

    /// Only this menu navigation may restore its selected Project after its requested Space transition.
    /// The observer ends on the first transition or timeout; unrelated later Space changes are unaffected.
    private static func preserveMenuSelection(_ project: Project, _ window: Window, _ id: UUID) {
        guard !window.spaceIds.contains(Spaces.currentSpaceId) else { return }
        navigationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            if let observer = navigationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            navigationObserver = nil
            navigationTimeout?.cancel()
            navigationTimeout = nil
            DispatchQueue.main.async {
                guard navigationId == id, Projects.isEnabled, Projects.byId[project.id] === project,
                      Projects.active === project || Projects.active?.isCustom != true,
                      Windows.list.contains(where: { $0 === window }), project.members.contains(window.tracked.id),
                      window.spaceIds.contains(Spaces.currentSpaceId) else { return }
                Projects.active = project
            }
        }
        let timeout = DispatchWorkItem { if navigationId == id { cancelNavigation() } }
        navigationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    private static func cancelNavigation() {
        navigationId = UUID()
        if let observer = navigationObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        navigationObserver = nil
        navigationTimeout?.cancel()
        navigationTimeout = nil
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
