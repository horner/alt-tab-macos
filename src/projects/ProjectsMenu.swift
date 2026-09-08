import Cocoa

final class ProjectsMenu: NSObject {
    private static var desktopItem: NSMenuItem!
    private static var projectsItem: NSMenuItem!
    private static weak var focusedWindow: Window?
    private static var unassignedItem: NSMenuItem!
    private static var activeItem: NSMenuItem!
    private static var addToProjectItem: NSMenuItem!
    private static var addFocusedItem: NSMenuItem!
    private static var addVisibleItem: NSMenuItem!
    private static var desktopUuid: String?
    private static var visibleWindows = [Window]()
    private static var navigationObserver: NSObjectProtocol?
    private static var navigationTimeout: DispatchWorkItem?
    private static var navigationId = UUID()

    private final class WindowSelection: NSObject {
        let projectId: String?
        weak var window: Window?

        init(_ project: Project?, _ window: Window) {
            projectId = project?.id
            self.window = window
        }
    }

    private final class HistorySelection: NSObject {
        let pattern: ProjectWindowPattern

        init(_ pattern: ProjectWindowPattern) { self.pattern = pattern }
    }

    static func install(in menu: NSMenu) {
        desktopItem = item(NSLocalizedString("Name this Desktop…", comment: "Desktop menu action"), #selector(nameDesktop))
        projectsItem = item(NSLocalizedString("Projects", comment: "Projects menu"), nil)
        projectsItem.submenu = NSMenu()
        projectsItem.isHidden = !Projects.isEnabled
        activeItem = item("", nil)
        addFocusedItem = item("", #selector(addWindow))
        addVisibleItem = item("", #selector(addVisibleWindows))
        [activeItem!, addFocusedItem!, addVisibleItem!].forEach { $0.isHidden = !Projects.isEnabled; menu.addItem($0) }
        addToProjectItem = addProjects(to: menu, title: NSLocalizedString("Add active window to", comment: "Projects submenu"), action: #selector(addWindow))
        addToProjectItem.isHidden = !Projects.isEnabled
        unassignedItem = item(NSLocalizedString("Windows without a Project", comment: ""), nil)
        unassignedItem.isHidden = !Projects.isEnabled
        menu.addItem(unassignedItem)
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
        Windows.list.forEach { ProjectBrowserURLs.refresh($0) }
        refreshActiveItems()
        addProjects(to: menu, title: addToProjectItem.title, action: #selector(addWindow), enabled: focusedWindow != nil, parent: addToProjectItem)
        addToProjectItem.isHidden = !Projects.isEnabled
        unassignedItem.isHidden = !Projects.isEnabled
        let unassigned = NSMenu()
        unassigned.autoenablesItems = false
        addWindows(of: nil, to: unassigned)
        unassignedItem.submenu = unassigned
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

    private static func logMenu(_ action: String, _ phase: String, _ sender: NSMenuItem? = nil) {
        Logger.debug {
            let target = sender?.representedObject as? String ?? (sender?.representedObject as? WindowSelection)?.projectId ?? "none"
            let window = (sender?.representedObject as? WindowSelection)?.window?.tracked.id ?? focusedWindow?.tracked.id ?? "none"
            let counts = Projects.list.filter { $0.isCustom }.map { "\($0.id):\($0.members.count)" }.joined(separator: ",")
            return "projects menu action=\(action) phase=\(phase) enabled=\(Projects.isEnabled) target=\(target) active=\(Projects.active?.id ?? "none") window=\(window) visible=\(visibleWindows.map { $0.tracked.id }) counts=[\(counts)]"
        }
    }

    @objc static func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === addFocusedItem || menuItem === addVisibleItem { return Projects.isEnabled && menuItem.representedObject != nil && menuItem.isEnabled }
        return menuItem.isEnabled
    }

    private static var currentDesktop: Project? {
        Projects.spaces.first { $0.isCurrent }.map { Projects.forSpace(uuid: $0.uuid) }
    }

    @discardableResult
    private static func addProjects(to menu: NSMenu, title: String, action: Selector, enabled: Bool = true, parent: NSMenuItem? = nil) -> NSMenuItem {
        let parent = parent ?? item(title, nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for project in Projects.list where project.isCustom {
            let child = item(project.resolvedName, action)
            child.representedObject = project.id
            child.isEnabled = enabled
            if action == #selector(addWindow), let window = focusedWindow {
                child.state = project.members.contains(window.tracked.id) ? .on : .off
            }
            submenu.addItem(child)
        }
        parent.submenu = submenu
        parent.isEnabled = enabled && !submenu.items.isEmpty
        if parent.menu == nil { menu.addItem(parent) }
        return parent
    }

    private static func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private static func nameDesktop() {
        logMenu("nameDesktop", "requested")
        defer { logMenu("nameDesktop", "finished") }
        guard let project = currentDesktop else { return }
        DesktopNamePrompt.present(project)
    }

    private static func refreshActiveItems() {
        let active = Projects.active.flatMap { $0.isCustom ? $0 : nil }
        activeItem.title = active.map { String(format: NSLocalizedString("Active Project: %@", comment: ""), $0.resolvedName) }
            ?? NSLocalizedString("No Active Project", comment: "")
        activeItem.isEnabled = true
        activeItem.submenu = makeActiveMenu(active)
        addFocusedItem.title = active.map { String(format: NSLocalizedString("Add active window to: %@", comment: ""), $0.resolvedName) }
            ?? NSLocalizedString("Add active window to: No Active Project", comment: "")
        addVisibleItem.title = active.map { String(format: NSLocalizedString("Add all visible to: %@", comment: ""), $0.resolvedName) }
            ?? NSLocalizedString("Add all visible to: No Active Project", comment: "")
        for entry in [activeItem!, addFocusedItem!, addVisibleItem!] { entry.isHidden = !Projects.isEnabled }
        addFocusedItem.representedObject = active?.id
        addVisibleItem.representedObject = active?.id
        addFocusedItem.state = focusedWindow.map { active?.members.contains($0.tracked.id) == true } == true ? .on : .off
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
            addHistory(of: active, to: menu)
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
            addHistory(of: project, to: windows)
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

    private static func addWindows(of project: Project?, to menu: NSMenu) {
        let assigned = project == nil ? Set(Projects.list.filter { $0.isCustom }.flatMap { $0.members }) : []
        let windows = Windows.list.filter { window in
            !window.isWindowlessApp && !window.isPhantom && !window.isTabbed
                && (project.map { $0.members.contains(window.tracked.id) } ?? !assigned.contains(window.tracked.id))
        }
            .sorted { $0.lastFocusOrder < $1.lastFocusOrder }
        for window in windows {
            let title = ProjectNameResolver.normalized(window.title) ?? window.application.localizedName ?? ""
            let entry = item(title, #selector(selectWindow))
            entry.representedObject = WindowSelection(project, window)
            if let icon = window.icon { entry.image = NSImage(cgImage: icon, size: NSSize(width: 16, height: 16)) }
            menu.addItem(entry)
            addURL(ProjectBrowserURLs.url(for: window), to: menu)
        }
        if windows.isEmpty {
            let empty = item(NSLocalizedString("No Open Windows", comment: ""), nil)
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    private static func addHistory(of project: Project, to menu: NSMenu) {
        let parent = item(NSLocalizedString("History", comment: "Project window history"), nil)
        let history = NSMenu()
        history.autoenablesItems = false
        let grouped = Dictionary(grouping: project.windowHistory, by: { $0.bundleIdentifier + "\u{0}" + $0.title + "\u{0}" + ($0.url ?? "") })
        let entries = grouped.values.compactMap { $0.max { ($0.lastSeenAt ?? .distantPast) < ($1.lastSeenAt ?? .distantPast) } }
            .sorted { ($0.lastSeenAt ?? .distantPast) > ($1.lastSeenAt ?? .distantPast) }
        for pattern in entries {
            let live = Windows.list.first { project.members.contains($0.tracked.id) && $0.application.bundleIdentifier == pattern.bundleIdentifier && $0.title == pattern.title && (pattern.url == nil || ProjectBrowserURLs.url(for: $0) == pattern.url) }
            let age = live == nil ? historyAge(pattern.lastSeenAt) : NSLocalizedString("Open now", comment: "Project window history")
            let title = pattern.title.count > 80 ? String(pattern.title.prefix(77)) + "…" : pattern.title
            let canReopen = ProjectBrowserURLResolver.supports(pattern.bundleIdentifier) && ProjectBrowserURLResolver.normalized(pattern.url) != nil
            let label = live == nil && canReopen ? String(format: NSLocalizedString("%@ — Reopen (%@)", comment: "Historical browser window and last seen age"), title.isEmpty ? pattern.url! : title, age) : "\(title) — \(age)"
            let entry = item(label, live != nil ? #selector(selectWindow) : canReopen ? #selector(reopenHistory) : nil)
            entry.isEnabled = live != nil || canReopen
            entry.toolTip = "\(pattern.title)\n\(pattern.bundleIdentifier)" + (pattern.lastSeenAt.map { "\n\($0)" } ?? "")
            if let live { entry.representedObject = WindowSelection(project, live) }
            else if canReopen { entry.representedObject = HistorySelection(pattern) }
            history.addItem(entry)
            addURL(pattern.url, to: history, selection: live == nil && canReopen ? HistorySelection(pattern) : nil)
        }
        if entries.isEmpty {
            let empty = item(NSLocalizedString("No window history yet", comment: "Project window history"), nil)
            empty.isEnabled = false
            history.addItem(empty)
        }
        parent.submenu = history
        menu.addItem(.separator())
        menu.addItem(parent)
    }

    private static func addURL(_ url: String?, to menu: NSMenu, selection: HistorySelection? = nil) {
        guard let url else { return }
        let address = item(url.count > 100 ? String(url.prefix(97)) + "…" : url, selection == nil ? nil : #selector(reopenHistory))
        address.isEnabled = selection != nil
        address.representedObject = selection
        address.indentationLevel = 1
        address.toolTip = url
        menu.addItem(address)
    }

    @objc private static func reopenHistory(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let selection = sender.representedObject as? HistorySelection,
              ProjectBrowserURLResolver.supports(selection.pattern.bundleIdentifier),
              let normalized = ProjectBrowserURLResolver.normalized(selection.pattern.url), let url = URL(string: normalized) else { return }
        logMenu("reopenHistory", "requested", sender)
        let bundle = selection.pattern.bundleIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            let opened = app.flatMap { try? NSWorkspace.shared.open([url], withApplicationAt: $0, options: [], configuration: [:]) } != nil
            DispatchQueue.main.async {
                Logger.debug { "projects menu action=reopenHistory phase=completed browser=\(bundle) opened=\(opened)" }
                guard !opened else { return }
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Could not reopen browser history", comment: "Project history error")
                alert.informativeText = NSLocalizedString("Make sure the original browser is installed and try again.", comment: "Project history error")
                alert.runModal()
            }
        }
    }

    private static func historyAge(_ date: Date?) -> String {
        guard let date else { return NSLocalizedString("Last seen unknown", comment: "Project window history") }
        let elapsed = max(0, Date().timeIntervalSince(date))
        guard elapsed >= 60 else { return NSLocalizedString("Just now", comment: "Project window history") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .abbreviated
        return String(format: NSLocalizedString("Last seen %@ ago", comment: "Project window history"), formatter.string(from: elapsed) ?? "")
    }

    @objc private static func selectDesktop() {
        logMenu("selectDesktop", "requested")
        defer { logMenu("selectDesktop", "finished") }
        cancelNavigation()
        guard Projects.isEnabled else { return }
        Projects.active = currentDesktop
    }

    @objc private static func selectProject(_ sender: NSMenuItem) {
        logMenu("selectProject", "requested", sender)
        defer { logMenu("selectProject", "finished", sender) }
        cancelNavigation()
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        Projects.active = project
    }

    @objc private static func selectWindow(_ sender: NSMenuItem) {
        logMenu("selectWindow", "requested", sender)
        defer { logMenu("selectWindow", "finished", sender) }
        cancelNavigation()
        guard Projects.isEnabled, let selection = sender.representedObject as? WindowSelection,
              let window = selection.window, Windows.list.contains(where: { $0 === window }) else { return }
        guard let projectId = selection.projectId else {
            let id = navigationId
            DispatchQueue.main.async {
                guard navigationId == id, Projects.isEnabled, Windows.list.contains(where: { $0 === window }) else { return }
                Logger.debug { "projects focus requested window=\(window.tracked.id) source=unassigned-menu" }
                window.focus()
            }
            return
        }
        guard let project = Projects.byId[projectId], project.members.contains(window.tracked.id) else { return }
        Projects.active = project
        let id = navigationId
        // Focus waits until menu tracking ends so its dismissal reaches the screen before IPC.
        DispatchQueue.main.async {
            guard navigationId == id, Projects.isEnabled, Projects.active === project,
                  Windows.list.contains(where: { $0 === window }), project.members.contains(window.tracked.id) else { return }
            Logger.debug { "projects focus requested window=\(window.tracked.id) project=\(project.id)" }
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
        logMenu("createEmptyProject", "requested")
        defer { logMenu("createEmptyProject", "finished") }
        createNamedProject(with: [], title: NSLocalizedString("New Project…", comment: ""))
    }

    @objc private static func createVisibleProject() {
        logMenu("createVisibleProject", "requested")
        defer { logMenu("createVisibleProject", "finished") }
        createNamedProject(with: visibleWindows.filter { isVisibleOnDesktop($0) },
            title: NSLocalizedString("New Project from All Visible Windows…", comment: ""))
    }

    @objc private static func createProject() {
        logMenu("createProject", "requested")
        defer { logMenu("createProject", "finished") }
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
        logMenu("addVisibleWindows", "requested", sender)
        defer { logMenu("addVisibleWindows", "finished", sender) }
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        ProjectAssignmentPrompt.add(visibleWindows.filter { window in
            Windows.list.contains(where: { $0 === window }) && isVisibleOnDesktop(window)
        }, to: project)
    }

    @objc private static func addWindow(_ sender: NSMenuItem) {
        logMenu("addWindow", "requested", sender)
        defer { logMenu("addWindow", "finished", sender) }
        guard Projects.isEnabled, let window = focusedWindow, Windows.list.contains(where: { $0 === window }),
              let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        ProjectAssignmentPrompt.add([window], to: project)
    }

    @objc private static func renameProject(_ sender: NSMenuItem) {
        logMenu("renameProject", "requested", sender)
        defer { logMenu("renameProject", "finished", sender) }
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        ProjectNamePrompt.present(project, title: NSLocalizedString("Rename Project", comment: "Projects submenu"))
    }

    @objc private static func deleteProject(_ sender: NSMenuItem) {
        logMenu("deleteProject", "requested", sender)
        defer { logMenu("deleteProject", "finished", sender) }
        guard Projects.isEnabled, let id = sender.representedObject as? String else { return }
        Projects.delete(id: id)
    }
}
