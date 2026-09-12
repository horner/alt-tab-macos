import Cocoa

final class ProjectsMenu: NSObject {
    private static weak var installedMenu: NSMenu?
    private static var currentWindowItem: NSMenuItem!
    private static var currentProjectItem: NSMenuItem!
    private static var otherProjectsItem: NSMenuItem!
    private static var restoreDesktopsItem: NSMenuItem!
    private static var restoreResultsItem: NSMenuItem!
    private static var desktopLabelsItem: NSMenuItem!
    static var presentationContext: ProjectMenuResolver.Context?
    static weak var presentationWindow: NSWindow?
    static var presentationCurrentWindow: CurrentWindow?
    static var presentationVisibleWindows: [Window]?
    private static weak var focusedWindow: Window?
    private static var desktopUuid: String?
    private static var moveDestination: WindowDesktopMove.Destination?
    private static var visibleWindows = [Window]()
    private static var navigationObserver: NSObjectProtocol?
    private static var navigationTimeout: DispatchWorkItem?
    private static var navigationId = UUID()

    final class CurrentWindow {
        weak var window: Window?

        init(_ window: Window?) { self.window = window }
    }

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

    private final class BringSelection: NSObject {
        weak var window: Window?
        let destination: WindowDesktopMove.Destination?

        init(_ window: Window, _ destination: WindowDesktopMove.Destination?) {
            self.window = window
            self.destination = destination
        }
    }

    private final class DeferredMenu: NSMenu, NSMenuDelegate {
        private let contents: () -> NSMenu

        init(_ contents: @escaping () -> NSMenu) {
            self.contents = contents
            super.init(title: "")
            autoenablesItems = false
            delegate = self
        }

        required init(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let updated = contents()
            removeAllItems()
            for entry in updated.items {
                updated.removeItem(entry)
                addItem(entry)
            }
        }
    }

    static func install(in menu: NSMenu) {
        installedMenu = menu
        currentWindowItem = item(NSLocalizedString("Current window", comment: "Current app window menu"), nil)
        currentProjectItem = item("", nil)
        otherProjectsItem = item(NSLocalizedString("Other Projects", comment: "Other Project window lists"), nil)
        restoreDesktopsItem = item(NSLocalizedString("Restore All Windows to Project Desktops", comment: "Restore all Project window locations"), #selector(restoreProjectDesktops))
        restoreDesktopsItem.toolTip = NSLocalizedString("Return open windows to their Projects' home Desktops. Windows without a clear destination are skipped.", comment: "Restore Project Desktops help")
        restoreResultsItem = item(NSLocalizedString("Show Last Desktop Restore Results", comment: "Review Desktop restore results"), #selector(showRestoreResults))
        desktopLabelsItem = item("", nil)
        menu.addItem(currentWindowItem)
        menu.addItem(currentProjectItem)
        menu.addItem(otherProjectsItem)
        menu.addItem(restoreDesktopsItem)
        menu.addItem(restoreResultsItem)
        menu.addItem(desktopLabelsItem)
        refresh(menu)
    }

    static func context(for label: SpaceLabelResolver.Label? = nil) -> ProjectMenuResolver.Context {
        let labels = Projects.list.filter { $0.isCustom }.reduce(into: [String: String]()) { $0[$1.labelUuid ?? $1.id] = $1.id }
        return ProjectMenuResolver.context(labelId: label?.id, desktopUuid: label?.space.uuid,
            activeProjectId: Projects.active.flatMap { $0.isCustom ? $0.id : nil },
            currentDesktopUuid: Projects.spaces.first { $0.isCurrent }?.uuid, projectLabels: labels)
    }

    static func refresh(_ menu: NSMenu) {
        guard installedMenu === menu else { return }
        MainThreadStall.step()
        let context = presentationContext ?? self.context()
        desktopUuid = context.desktopUuid
        moveDestination = WindowDesktopMove.currentDestination
        focusedWindow = (presentationCurrentWindow ?? captureCurrentWindow()).window
        visibleWindows = presentationVisibleWindows ?? captureVisibleWindows(on: desktopUuid)
        let project = context.projectId.flatMap { Projects.byId[$0] }.flatMap { $0.isCustom ? $0 : nil }
        currentWindowItem.isHidden = !Projects.isEnabled
        currentWindowItem.submenu = Projects.isEnabled ? makeCurrentWindowMenu(focusedWindow, project: project) : nil
        currentProjectItem.title = String(format: NSLocalizedString("Project: %@", comment: "Current Project menu"),
            project?.resolvedName ?? NSLocalizedString("None", comment: "No active Project"))
        currentProjectItem.isHidden = !Projects.isEnabled
        currentProjectItem.submenu = Projects.isEnabled ? makeCurrentProjectMenu(project, context: context) : nil
        otherProjectsItem.isHidden = !Projects.isEnabled
        otherProjectsItem.submenu = Projects.isEnabled ? makeOtherProjectsMenu(excluding: project) : nil
        restoreDesktopsItem.isHidden = !Projects.isEnabled
        restoreDesktopsItem.isEnabled = WindowDesktopRestore.isAvailable
        restoreDesktopsItem.title = WindowDesktopRestore.isRunning
            ? NSLocalizedString("Restoring Project Desktops…", comment: "Desktop restoration in progress")
            : NSLocalizedString("Restore All Windows to Project Desktops", comment: "Restore all Project window locations")
        restoreResultsItem.isHidden = !Projects.isEnabled || !WindowDesktopRestore.hasLastResults
        restoreResultsItem.isEnabled = !WindowDesktopRestore.isRunning
        desktopLabelsItem.title = String(format: NSLocalizedString("Desktop: %@", comment: "Current Desktop menu"),
            currentDesktop?.resolvedName ?? NSLocalizedString("Unknown", comment: "Unknown Desktop"))
        desktopLabelsItem.submenu = makeDesktopMenu()
    }

    static func captureCurrentWindow() -> CurrentWindow {
        CurrentWindow(ProjectMenuResolver.currentWindow(in: Windows.list, isEligible: isCurrentWindowCandidate,
            isFocused: { $0.application.pid == Applications.frontmostPid && $0.application.focusedWindow === $0 },
            focusOrder: { $0.lastFocusOrder }))
    }

    private static func isCurrentWindowCandidate(_ window: Window) -> Bool {
        window.application.pid != AXUIElement.currentProcessPid && ProjectAssignmentPrompt.canAssign(window)
    }

    private static func menu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    private static func submenu(_ title: String, _ contents: NSMenu, enabled: Bool = true) -> NSMenuItem {
        let parent = item(title, nil)
        parent.submenu = contents
        parent.isEnabled = enabled
        return parent
    }

    private static func makeCurrentWindowMenu(_ target: Window?, project: Project?) -> NSMenu {
        let menu = makeWindowOperationsMenu(target, destination: moveDestination)
        menu.addItem(.separator())
        let title = project.map { String(format: NSLocalizedString("Add All Visible Windows to %@", comment: "Project assignment action with destination"), $0.resolvedName) }
            ?? NSLocalizedString("Add All Visible Windows", comment: "Project assignment action")
        let visible = addProjectAction(title, #selector(addVisibleWindows), project, to: menu)
        visible.isEnabled = project != nil && !visibleWindows.isEmpty
        return menu
    }

    private static func makeWindowOperationsMenu(_ target: Window?, destination: WindowDesktopMove.Destination?, selection: WindowSelection? = nil) -> NSMenu {
        let menu = menu()
        guard let window = ProjectMenuResolver.liveTarget(target, in: Windows.list, isEligible: ProjectAssignmentPrompt.canAssign) else {
            addHeading(NSLocalizedString("No current window", comment: "No eligible app window"), to: menu)
            return menu
        }
        let title = ProjectNameResolver.normalized(window.title) ?? window.application.localizedName ?? ""
        let heading = addHeading(title, to: menu)
        heading.toolTip = title
        if let icon = window.icon { heading.image = NSImage(cgImage: icon, size: NSSize(width: 16, height: 16)) }
        let owners = Projects.list.filter { $0.isCustom && $0.members.contains(window.tracked.id) }
        if owners.isEmpty {
            addHeading(NSLocalizedString("Unassigned", comment: "Window without a Project"), to: menu)
        } else {
            for owner in owners {
                addHeading(String(format: NSLocalizedString("Project: %@", comment: "Window Project membership"), owner.resolvedName), to: menu)
            }
        }
        menu.addItem(.separator())
        if let selection {
            let show = item(NSLocalizedString("Show Window", comment: "Focus a Project window"), #selector(selectWindow))
            show.representedObject = selection
            menu.addItem(show)
        }
        let bring = item(NSLocalizedString("Bring to This Desktop", comment: "Move a window to the current Desktop"), #selector(bringWindow))
        bring.representedObject = BringSelection(window, destination)
        bring.isEnabled = WindowDesktopMove.canBring(window, to: destination)
        bring.toolTip = NSLocalizedString("Move this window here and keep its Project membership. Available for individual windows on another regular Desktop.", comment: "Bring window help")
        menu.addItem(bring)
        let destinations = self.menu()
        let memberships = Set(owners.map { $0.id })
        for project in Projects.list where project.isCustom {
            let entry = item(project.resolvedName, #selector(moveCurrentWindow))
            entry.representedObject = WindowSelection(project, window)
            entry.state = memberships.contains(project.id) ? .on : .off
            entry.isEnabled = ProjectMenuResolver.canMove(to: project.id, memberships: memberships)
            destinations.addItem(entry)
        }
        menu.addItem(submenu(NSLocalizedString("Move to Project", comment: "Move current window membership"), destinations, enabled: !destinations.items.isEmpty))
        return menu
    }

    @discardableResult
    private static func addHeading(_ title: String, to menu: NSMenu) -> NSMenuItem {
        let entry = item(title, nil)
        entry.isEnabled = false
        menu.addItem(entry)
        return entry
    }

    private static func makeOtherProjectsMenu(excluding current: Project?) -> NSMenu {
        let menu = menu()
        let destination = moveDestination
        for project in Projects.list where project.isCustom && project !== current {
            let id = project.id
            menu.addItem(submenu(project.resolvedName, DeferredMenu {
                guard Projects.isEnabled, let project = Projects.byId[id], project.isCustom else { return self.menu() }
                return makeWindowsMenu(project, destination: destination)
            }))
        }
        if menu.items.isEmpty { addHeading(NSLocalizedString("No other projects", comment: "Empty Other Projects menu"), to: menu) }
        return menu
    }

    private static func makeCurrentProjectMenu(_ project: Project?, context: ProjectMenuResolver.Context) -> NSMenu {
        let menu = menu()
        let destination = moveDestination
        if let project {
            addWindows(of: project, to: menu, destination: destination)
        } else {
            addHeading(NSLocalizedString("No Active Project", comment: "Projects menu"), to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(submenu(NSLocalizedString("Unassigned", comment: "Window without a Project"), DeferredMenu { makeWindowsMenu(nil, destination: destination) }))
        menu.addItem(.separator())
        menu.addItem(submenu(NSLocalizedString("Manage…", comment: "Less-used Project commands"), makeProjectsMenu(project, context: context)))
        return menu
    }

    private static func makeProjectsMenu(_ project: Project?, context: ProjectMenuResolver.Context) -> NSMenu {
        let menu = menu()
        menu.addItem(submenu(NSLocalizedString("Switch Project", comment: "Projects menu"), makeSwitchMenu(project)))
        if let project {
            let id = project.id
            menu.addItem(submenu(NSLocalizedString("History", comment: "Project window history"), DeferredMenu {
                guard Projects.isEnabled, let project = Projects.byId[id], project.isCustom else { return self.menu() }
                return makeHistoryMenu(project)
            }))
        }
        menu.addItem(.separator())
        menu.addItem(submenu(NSLocalizedString("New Project", comment: "Projects menu"), makeNewProjectMenu(context)))
        if !context.fromLabel {
            addProjects(to: menu, title: NSLocalizedString("Rename Project", comment: "Projects submenu"), action: #selector(renameProject))
            addProjects(to: menu, title: NSLocalizedString("Delete Project", comment: "Projects submenu"), action: #selector(deleteProject))
        }
        menu.addItem(.separator())
        let heading = item(project?.resolvedName ?? NSLocalizedString("No Active Project", comment: "Projects menu"), nil)
        heading.isEnabled = false
        menu.addItem(heading)
        if context.fromLabel {
            addProjectAction(NSLocalizedString("Rename Project…", comment: "Projects menu"), #selector(renameProject), project, to: menu)
            addProjectAction(NSLocalizedString("Delete Project", comment: "Projects menu"), #selector(deleteProject), project, to: menu)
        }
        addProjectAction(NSLocalizedString("Add Windows…", comment: "Project window picker action"), #selector(chooseWindows), project, to: menu)
        menu.addItem(.separator())
        addProjects(to: menu, title: NSLocalizedString("Add Windows to", comment: "Choose a Project for manual assignment"), action: #selector(chooseWindows))
        return menu
    }

    @discardableResult
    private static func addProjectAction(_ title: String, _ action: Selector, _ project: Project?, to menu: NSMenu) -> NSMenuItem {
        let entry = item(title, action)
        entry.representedObject = project?.id
        entry.isEnabled = project != nil
        menu.addItem(entry)
        return entry
    }

    private static func makeSwitchMenu(_ active: Project?) -> NSMenu {
        let menu = menu()
        let desktop = item(NSLocalizedString("Use Desktop (No Project)", comment: ""), #selector(selectDesktop))
        desktop.state = active == nil ? .on : .off
        desktop.isEnabled = currentDesktop != nil
        menu.addItem(desktop)
        let projects = Projects.list.filter { $0.isCustom }
        if !projects.isEmpty { menu.addItem(.separator()) }
        for project in projects {
            let entry = addProjectAction(project.resolvedName, #selector(selectProject), project, to: menu)
            entry.state = project === active ? .on : .off
        }
        return menu
    }

    private static func makeNewProjectMenu(_ context: ProjectMenuResolver.Context) -> NSMenu {
        let menu = menu()
        let empty = item(NSLocalizedString("Empty Project…", comment: "New Project menu"), #selector(createEmptyProject))
        empty.isEnabled = currentDesktop != nil
        menu.addItem(empty)
        let all = item(NSLocalizedString("From All Visible Windows…", comment: "New Project menu"), #selector(createVisibleProject))
        all.isEnabled = currentDesktop != nil && !visibleWindows.isEmpty
        menu.addItem(all)
        guard !context.fromLabel else { return menu }
        let window = item(NSLocalizedString("From Active Window…", comment: "New Project menu"), #selector(createProject))
        window.isEnabled = currentDesktop != nil && focusedWindow != nil
        menu.addItem(window)
        return menu
    }

    private static func makeDesktopMenu() -> NSMenu {
        let menu = menu()
        let name = item(NSLocalizedString("Name This Desktop…", comment: "Desktop menu action"), #selector(nameDesktop))
        name.isEnabled = currentDesktop != nil
        menu.addItem(name)
        guard Projects.isEnabled else { return menu }
        menu.addItem(.separator())
        let heading = item(NSLocalizedString("Project Labels", comment: "Project label menu section"), nil)
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(item(NSLocalizedString("Show All", comment: "Show all Project labels button"), #selector(showSpaceLabels)))
        menu.addItem(item(NSLocalizedString("Bring All to Front", comment: "Raise all Project labels button"), #selector(raiseSpaceLabels)))
        for (title, action) in [(NSLocalizedString("Minimize All", comment: "Minimize all Project labels button"), #selector(minimizeSpaceLabels)),
                                (NSLocalizedString("Close All", comment: "Close all Project labels button"), #selector(closeSpaceLabels))] {
            let entry = item(title, action)
            entry.isEnabled = SpaceLabelWindows.hasLabels
            menu.addItem(entry)
        }
        return menu
    }

    static func showWindows(for projectId: String, from view: NSView) {
        guard Projects.isEnabled, let project = Projects.byId[projectId], project.isCustom else { return }
        popUp(makeWindowsMenu(project, destination: WindowDesktopMove.currentDestination), from: view)
    }

    static func showHistory(for projectId: String, from view: NSView) {
        guard Projects.isEnabled, let project = Projects.byId[projectId], project.isCustom else { return }
        popUp(makeHistoryMenu(project), from: view)
    }

    private static func popUp(_ menu: NSMenu, from view: NSView) {
        guard view.window?.isVisible == true else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: view.bounds.maxY), in: view)
    }

    static func rename(_ context: ProjectMenuResolver.Context, from window: NSWindow) {
        if let id = context.projectId {
            guard Projects.isEnabled, let project = Projects.byId[id], project.isCustom else { return }
            ProjectNamePrompt.rename(project, from: window)
            return
        }
        guard let uuid = context.desktopUuid, Projects.spaces.contains(where: { $0.uuid == uuid }) else { return }
        DesktopNamePrompt.present(Projects.forSpace(uuid: uuid))
    }

    private static func logMenu(_ action: String, _ phase: String, _ sender: NSMenuItem? = nil) {
        Logger.debug {
            let target = sender?.representedObject as? String ?? (sender?.representedObject as? WindowSelection)?.projectId ?? "none"
            let window = (sender?.representedObject as? WindowSelection)?.window?.tracked.id ?? focusedWindow?.tracked.id ?? "none"
            let counts = Projects.list.filter { $0.isCustom }.map { "\($0.id):\($0.members.count)" }.joined(separator: ",")
            return "projects menu action=\(action) phase=\(phase) enabled=\(Projects.isEnabled) target=\(target) active=\(Projects.active?.id ?? "none") window=\(window) visible=\(visibleWindows.map { $0.tracked.id }) counts=[\(counts)]"
        }
    }

    private static var currentDesktop: Project? {
        guard let uuid = desktopUuid, Projects.spaces.contains(where: { $0.uuid == uuid }) else { return nil }
        return Projects.forSpace(uuid: uuid)
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

    @objc private static func showSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.showAll() }
    }

    @objc private static func closeSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.closeAll() }
    }

    @objc private static func raiseSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.bringAllToFront() }
    }

    @objc private static func minimizeSpaceLabels() {
        DispatchQueue.main.async { SpaceLabelWindows.minimizeAll() }
    }

    private static func makeWindowsMenu(_ project: Project?, destination: WindowDesktopMove.Destination?) -> NSMenu {
        let menu = menu()
        addWindows(of: project, to: menu, destination: destination)
        return menu
    }

    private static func addWindows(of project: Project?, to menu: NSMenu, destination: WindowDesktopMove.Destination?) {
        let assigned = project == nil ? Set(Projects.list.filter { $0.isCustom }.flatMap { $0.members }) : []
        let windows = Windows.list.filter { window in
            ProjectAssignmentPrompt.canAssign(window)
                && (project.map { $0.members.contains(window.tracked.id) } ?? !assigned.contains(window.tracked.id))
        }
            .sorted { $0.lastFocusOrder < $1.lastFocusOrder }
        for window in windows {
            ProjectBrowserURLs.refresh(window)
            let title = ProjectNameResolver.normalized(window.title) ?? window.application.localizedName ?? ""
            let entry = item(title, nil)
            entry.submenu = makeWindowOperationsMenu(window, destination: destination, selection: WindowSelection(project, window))
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

    private static func makeHistoryMenu(_ project: Project) -> NSMenu {
        let history = menu()
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
        return history
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

    @objc private static func moveCurrentWindow(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? WindowSelection else { return }
        DispatchQueue.main.async {
            guard Projects.isEnabled, let id = selection.projectId, let project = Projects.byId[id], project.isCustom,
                  let window = ProjectMenuResolver.liveTarget(selection.window, in: Windows.list, isEligible: ProjectAssignmentPrompt.canAssign) else { return }
            Projects.assign([window.tracked.id], to: project, move: true)
        }
    }

    @objc private static func bringWindow(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? BringSelection, let destination = selection.destination else { return }
        DispatchQueue.main.async {
            guard let window = ProjectMenuResolver.liveTarget(selection.window, in: Windows.list, isEligible: isCurrentWindowCandidate) else { return }
            WindowDesktopMove.bring(window, to: destination)
        }
    }

    @objc private static func restoreProjectDesktops() {
        DispatchQueue.main.async { WindowDesktopRestore.restoreAll() }
    }

    @objc private static func showRestoreResults() {
        DispatchQueue.main.async { WindowDesktopRestore.showLastResults() }
    }

    @objc private static func selectProject(_ sender: NSMenuItem) {
        logMenu("selectProject", "requested", sender)
        defer { logMenu("selectProject", "finished", sender) }
        cancelNavigation()
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        Projects.active = project
        ProjectVisibility.focus(project)
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
    private static func isVisibleOnDesktop(_ window: Window, on uuid: String?) -> Bool {
        guard let space = Projects.spaces.first(where: { $0.uuid == uuid }) else { return false }
        return ProjectAssignmentPrompt.canAssign(window) && !window.isMinimized && !window.isHidden
            && window.spaceIds.contains(space.spaceId)
    }

    static func captureVisibleWindows(on uuid: String?) -> [Window] {
        Windows.list.filter { isVisibleOnDesktop($0, on: uuid) }
    }

    static func addAllVisibleWindows(_ windows: [Window], projectId: String?, desktopUuid: String?, from parent: NSWindow?) {
        guard Projects.isEnabled, let id = projectId, let project = Projects.byId[id], project.isCustom,
              let uuid = desktopUuid, Projects.spaces.contains(where: { $0.uuid == uuid }) else { return }
        ProjectAssignmentPrompt.add(windows, to: project, from: parent)
    }

    @objc private static func createEmptyProject() {
        logMenu("createEmptyProject", "requested")
        defer { logMenu("createEmptyProject", "finished") }
        createNamedProject(with: [], title: NSLocalizedString("New Project…", comment: ""))
    }

    @objc private static func createVisibleProject() {
        logMenu("createVisibleProject", "requested")
        defer { logMenu("createVisibleProject", "finished") }
        createNamedProject(with: visibleWindows.filter { isVisibleOnDesktop($0, on: desktopUuid) },
            title: NSLocalizedString("New Project from All Visible Windows…", comment: ""))
    }

    @objc private static func createProject() {
        logMenu("createProject", "requested")
        defer { logMenu("createProject", "finished") }
        guard let window = focusedWindow else { return }
        createNamedProject(with: [window], title: NSLocalizedString("New Project from this Window…", comment: "Projects menu action"))
    }

    private static func createNamedProject(with windows: [Window], title: String) {
        guard let uuid = desktopUuid else { return }
        let parent = presentationWindow
        DispatchQueue.main.async { createNamedProject(with: windows, title: title, desktopUuid: uuid, from: parent) }
    }

    private static func createNamedProject(with windows: [Window], title: String, desktopUuid: String, from parent: NSWindow?) {
        guard Projects.isEnabled, Projects.spaces.contains(where: { $0.uuid == desktopUuid }),
              let project = Projects.createCustom(homeSpaceUuid: desktopUuid) else { return }
        project.autoName = windows.first.flatMap { ProjectNameResolver.claim(name: nil, autoName: nil, appName: $0.application.localizedName) }
        ProjectNamePrompt.present(project, title: title, from: parent) { saved in
            guard saved else { Projects.delete(id: project.id); return }
            guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
            for window in windows where Windows.list.contains(where: { $0 === window }) && ProjectAssignmentPrompt.canAssign(window) {
                Projects.add(windowId: window.tracked.id, to: project)
            }
            Projects.active = project
        }
    }

    @objc private static func addVisibleWindows(_ sender: NSMenuItem) {
        logMenu("addVisibleWindows", "requested", sender)
        defer { logMenu("addVisibleWindows", "finished", sender) }
        let id = sender.representedObject as? String
        let uuid = desktopUuid
        let windows = visibleWindows
        let parent = presentationWindow
        DispatchQueue.main.async { addAllVisibleWindows(windows, projectId: id, desktopUuid: uuid, from: parent) }
    }

    @objc private static func chooseWindows(_ sender: NSMenuItem) {
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        let parent = presentationWindow
        DispatchQueue.main.async { ProjectWindowPicker.present(for: project, from: parent) }
    }

    @objc private static func renameProject(_ sender: NSMenuItem) {
        logMenu("renameProject", "requested", sender)
        defer { logMenu("renameProject", "finished", sender) }
        guard Projects.isEnabled, let id = sender.representedObject as? String, let project = Projects.byId[id] else { return }
        let parent = presentationWindow
        DispatchQueue.main.async {
            guard Projects.isEnabled, Projects.byId[project.id] === project else { return }
            ProjectNamePrompt.rename(project, from: parent)
        }
    }

    @objc private static func deleteProject(_ sender: NSMenuItem) {
        logMenu("deleteProject", "requested", sender)
        defer { logMenu("deleteProject", "finished", sender) }
        guard Projects.isEnabled, let id = sender.representedObject as? String else { return }
        Projects.delete(id: id)
    }
}
