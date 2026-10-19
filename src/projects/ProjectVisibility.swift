import Cocoa

/// Recovery ownership stays on main. Foreign AX calls use the existing command pool.
enum ProjectVisibility {
    private static var session = ProjectVisibilityResolver.Session()
    private static var identities = [String: ProjectWindowIdentity]()
    private static var saved = [ProjectWindowIdentity]()
    private static var recoveryLoaded = false
    private static var started = false
    private static var queued = false
    private static var persistenceQueued = false

    static func start() {
        guard !started else { return }
        started = true
        loadRecovery()
        refresh()
    }

    static func selectionChanged() {
        WindowDesktopMove.selectionChanged()
        refresh()
    }

    static func refresh() {
        guard started, !queued, !session.managed.isEmpty || !session.pending.isEmpty else { return }
        queued = true
        // Let panel/menu dismissal commit before taking snapshots or issuing window commands.
        DispatchQueue.main.async {
            queued = false
            reconcile()
        }
    }

    static func register(_ window: Window, _ identity: ProjectWindowIdentity) {
        loadRecovery()
        identities[identity.windowId] = identity
        session.recover(identity, saved: saved, minimized: window.isMinimized)
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
        ProjectPersistence.scheduleSnapshot()
        guard identities[window.tracked.id] != nil else { return }
        session.observed(window.tracked.id, minimized: window.isMinimized)
        persist(window.tracked.id)
    }

    static func manuallyChanged(_ window: Window) {
        let id = window.tracked.id
        session.release(id)
        persist(id)
    }

    private static func reconcile() {
        MainThreadStall.step()
        let windows = Windows.list
        let snapshots = windows.map { snapshot($0) }
        let byId = Dictionary(uniqueKeysWithValues: windows.map { ($0.tracked.id, $0) })
        let commands = session.restorationPlan(snapshots)
        for command in commands {
            guard let window = byId[command.windowId], let element = window.axUiElement else {
                session.complete(command, .failed)
                continue
            }
            execute(command, window, element)
        }
    }

    private static func snapshot(_ window: Window) -> ProjectVisibilityResolver.Window {
        ProjectVisibilityResolver.Window(id: window.tracked.id, spaceIds: window.spaceIds, projectIds: [],
            isMinimized: window.isMinimized, isEligible: !window.isWindowlessApp && !window.isPhantom
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
        // A timed-out AX write may still execute in the target app; do not retry it.
        return result == .success || result == .cannotComplete ? .changed : .failed
    }

    private static func loadRecovery() {
        guard !recoveryLoaded else { return }
        recoveryLoaded = true
        // Window discovery and manual actions can precede Project persistence startup.
        saved = CachedUserDefaults.json("projectsAutoMinimizedWindows", [ProjectWindowIdentity].self)
    }

    private static func persist(_ id: String) {
        loadRecovery()
        let identity = session.managed.contains(id) ? identities[id] : nil
        guard saved.first(where: { $0.windowId == id }) != identity else { return }
        saved.removeAll { $0.windowId == id }
        if let identity { saved.append(identity) }
        guard !persistenceQueued else { return }
        persistenceQueued = true
        DispatchQueue.main.async {
            persistenceQueued = false
            Preferences.set("projectsAutoMinimizedWindows", saved, false)
            ProjectPersistence.scheduleSnapshot()
        }
    }
}
