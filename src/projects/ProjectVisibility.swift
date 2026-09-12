import Cocoa

/// Registry, ownership and focus are main-thread-only. Foreign AX calls use the existing command pool.
enum ProjectVisibility {
    private static var session = ProjectVisibilityResolver.Session()
    private static var identities = [String: ProjectWindowIdentity]()
    private static var saved = [ProjectWindowIdentity]()
    private static var observer: NSObjectProtocol?
    private static var enabled = false
    private static var queued = false
    private static var persistenceQueued = false
    private static var focusProject: Project?
    private static weak var focusWindow: Window?

    static var isEnabled: Bool { Projects.isEnabled && Preferences.projectsMinimizeInactive }

    static func start() {
        guard observer == nil else { return }
        saved = CachedUserDefaults.json("projectsAutoMinimizedWindows", [ProjectWindowIdentity].self)
        enabled = isEnabled
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            guard enabled != isEnabled else { return }
            enabled = isEnabled
            selectionChanged()
        }
        refresh()
    }

    static func selectionChanged() {
        WindowDesktopMove.selectionChanged()
        session.cancelPending()
        focusProject = nil
        focusWindow = nil
        refresh()
    }

    static func refresh() {
        guard observer != nil, !queued, isEnabled || !session.managed.isEmpty || !session.pending.isEmpty else { return }
        queued = true
        // Let panel/menu dismissal commit before taking snapshots or issuing window commands.
        DispatchQueue.main.async {
            queued = false
            reconcile()
        }
    }

    static func register(_ window: Window, _ identity: ProjectWindowIdentity) {
        identities[identity.windowId] = identity
        if saved.contains(identity), window.isMinimized { session.recover(identity.windowId) }
        persist(identity.windowId)
        refresh()
    }

    static func forget(_ windows: [Window]) {
        for window in windows {
            let id = window.tracked.id
            session.forget(id)
            identities.removeValue(forKey: id)
            persist(id)
        }
    }

    static func minimizedChanged(_ window: Window) {
        guard identities[window.tracked.id] != nil else { return }
        session.observed(window.tracked.id, minimized: window.isMinimized)
        persist(window.tracked.id)
    }

    static func manuallyChanged(_ window: Window) {
        let id = window.tracked.id
        session.release(id)
        persist(id)
        if focusWindow === window { focusWindow = nil; focusProject = nil }
    }

    /// Return true when this mode handles focus, including an empty or entirely manually minimized Project.
    @discardableResult
    static func focus(_ project: Project) -> Bool {
        guard isEnabled, project.isCustom else { return false }
        let members = Windows.list.filter { !$0.isWindowlessApp && project.members.contains($0.tracked.id) }
        let local = members.filter { $0.spaceIds.contains(Spaces.currentSpaceId) }
        guard !local.isEmpty || members.isEmpty else { return false }
        focusProject = project
        focusWindow = local.filter {
            !$0.isPhantom && !$0.isTabbed && !$0.isHidden
                && (!$0.isMinimized || session.managed.contains($0.tracked.id))
        }.min { $0.lastFocusOrder < $1.lastFocusOrder }
        refresh()
        return true
    }

    private static func reconcile() {
        MainThreadStall.step()
        let desktop = Projects.spaces.first { $0.isCurrent && $0.desktopNumber > 0 }
        let project = Projects.active.flatMap { $0.isCustom ? $0 : nil }
        let local = project == nil || project?.homeSpaceUuid == desktop?.uuid || Windows.list.contains {
            project?.members.contains($0.tracked.id) == true && $0.spaceIds.contains(desktop?.spaceId ?? 0)
        }
        let context = ProjectVisibilityResolver.Context(enabled: isEnabled,
            spaceId: desktop?.spaceId, projectId: project?.id, projectIsLocal: local)
        var owners = [String: Set<String>]()
        for project in Projects.list where project.isCustom {
            for id in project.members { owners[id, default: []].insert(project.id) }
        }
        let windows = Windows.list
        let snapshots = windows.map { snapshot($0, owners[$0.tracked.id] ?? []) }
        let byId = Dictionary(uniqueKeysWithValues: windows.map { ($0.tracked.id, $0) })
        let commands = session.plan(snapshots, context)
        for command in commands {
            guard let window = byId[command.windowId], let element = window.axUiElement else {
                session.complete(command, .failed)
                continue
            }
            execute(command, window, element)
        }
        finishFocus()
    }

    private static func snapshot(_ window: Window, _ owners: Set<String>) -> ProjectVisibilityResolver.Window {
        ProjectVisibilityResolver.Window(id: window.tracked.id, spaceIds: window.spaceIds, projectIds: owners,
            isMinimized: window.isMinimized, isExplicitlyVisible: WindowDesktopMove.keepsVisible(window), isEligible: !window.isWindowlessApp && !window.isPhantom
                && !window.isTabbed && window.tabbedSiblingWids == nil && !window.isFullscreen && !window.isFullscreenMirrored
                && !window.spaceIsBorrowed && window.application.pid != AXUIElement.currentProcessPid
                && window.axUiElement != nil && identities[window.tracked.id] != nil)
    }

    private static func execute(_ command: ProjectVisibilityResolver.Command, _ window: Window, _ element: AXUIElement) {
        BackgroundWork.accessibilityCommandsQueue.addOperation { [weak window] in
            let outcome = apply(command, element)
            DispatchQueue.main.async {
                guard let window, Windows.list.contains(where: { $0 === window }) else { return }
                let needsCorrection = session.complete(command, outcome)
                if needsCorrection { refresh() }
                finishFocus()
                persist(command.windowId)
                Logger.debug { "projects visibility window=\(command.windowId) minimize=\(command.minimize) outcome=\(outcome) cancelled=\(command.isCancelled)" }
            }
        }
    }

    private static func apply(_ command: ProjectVisibilityResolver.Command, _ element: AXUIElement) -> ProjectVisibilityResolver.Outcome {
        guard !command.isCancelled else { return .cancelled }
        guard let attributes = try? element.attributes([kAXMinimizedAttribute, kAXFullscreenAttribute]),
              let minimized = attributes.isMinimized, attributes.isFullscreen != true else { return .failed }
        guard !command.isCancelled else { return .cancelled }
        guard minimized != command.minimize else { return .unchanged(minimized) }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable) == .success,
              settable.boolValue else { return .failed }
        guard !command.isCancelled else { return .cancelled }
        let result = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, command.minimize as CFBoolean)
        // A timed-out command may still execute in the target app; retain ownership without retrying the write.
        return result == .success || result == .cannotComplete ? .changed : .failed
    }

    private static func finishFocus() {
        guard let project = focusProject, let window = focusWindow else { return }
        guard isEnabled, Projects.active === project, Projects.byId[project.id] === project,
              Windows.list.contains(where: { $0 === window }), project.members.contains(window.tracked.id),
              window.spaceIds.contains(Spaces.currentSpaceId), !ProjectSwitcher.isActive, !SwitcherSession.isActive,
              App.shared.modalWindow == nil else {
            focusProject = nil
            focusWindow = nil
            return
        }
        guard session.pending[window.tracked.id] == nil,
              !session.pending.values.contains(where: { !$0.minimize }) else { return }
        focusProject = nil
        focusWindow = nil
        guard !session.managed.contains(window.tracked.id) else { return }
        window.focus()
    }

    private static func persist(_ id: String) {
        let identity = session.managed.contains(id) ? identities[id] : nil
        guard saved.first(where: { $0.windowId == id }) != identity else { return }
        saved.removeAll { $0.windowId == id }
        if let identity { saved.append(identity) }
        guard !persistenceQueued else { return }
        persistenceQueued = true
        DispatchQueue.main.async {
            persistenceQueued = false
            Preferences.set("projectsAutoMinimizedWindows", saved, false)
        }
    }
}
