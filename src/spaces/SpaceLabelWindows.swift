import Cocoa

/// AppKit state is main-thread-only. Topology reads and window assignment run on the CGS scheduler.
enum SpaceLabelWindows {
    private final class Entry {
        let uuid: String
        let window: SpaceLabelWindow
        var spaceId: CGSSpaceID?
        var assigning = false
        var retired = false
        var presentationRevision: Int?
        var revealLevel: NSWindow.Level?
        var revealTimer: DispatchWorkItem?
        var keptInFront = false

        init(uuid: String) {
            self.uuid = uuid
            window = SpaceLabelWindow(uuid: uuid)
        }
    }

    private static var windows = [String: Entry]()
    private static var spaces = [SpaceLabelResolver.Space]()
    private static var observers = [NSObjectProtocol]()
    private static var dockObserver: AXObserver?
    private static var dockRevision = 0
    private static var enabled = false
    private static var visibility = SpaceLabelResolver.Visibility()
    private static var revision = 0
    private static var refreshQueued = false
    private static var refreshInFlight = false
    private static var namesQueued = false
    private static var clickMonitors = [Any]()
    private static var arrival = SpaceLabelResolver.Arrival()
    private static var reveal = SpaceLabelResolver.Reveal()
    private static var revealRequested = false

    static var hasLabels: Bool { visibility.isRequested }

    static func showAll() {
        guard Projects.isEnabled else { return }
        Preferences.set("spaceLabelsOnLaunch", "true", false)
        synchronizeEnabled()
        visibility.showAll()
        updatePresentation()
        refresh()
    }

    static func bringAllToFront() {
        guard Projects.isEnabled else { return }
        guard visibility.isRequested else { showAll(); return }
        visibility.bringToFront()
        updatePresentation()
    }

    static func minimizeAll() {
        visibility.minimizeAll()
        updatePresentation()
    }

    static func closeAll(remember: Bool = true) {
        if remember { Preferences.set("spaceLabelsOnLaunch", "false", false) }
        visibility.hideAll()
        revealRequested = false
        reveal.cancel()
        arrival = SpaceLabelResolver.Arrival()
        removeClickMonitors()
        revision += 1
        windows.values.forEach { retire($0) }
        windows.removeAll()
        spaces.removeAll()
    }

    private static func close(_ uuid: String) {
        visibility.close(uuid)
        reveal.finish(uuid, after: reveal.revision)
        if let entry = windows.removeValue(forKey: uuid) { retire(entry) }
        synchronizeClickMonitors()
    }

    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                synchronizeEnabled()
                if Preferences.spaceLabelRevealDuration == 0 { cancelReveals() }
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in refresh() })
        observers.append(center.addObserver(forName: NSNotification.Name("NSApplicationDockDidRestartNotification"), object: nil, queue: .main) { _ in
            observeDock()
            refresh()
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async { refresh(revealOnArrival: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            arrival = SpaceLabelResolver.Arrival()
            refresh()
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            sendToBackAfterClick(cancelReveal: false)
        })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.dock.prefchanged"), object: nil, queue: .main) { _ in refresh() })
        observeDock()
        synchronizeEnabled()
    }

    static func synchronizeEnabled() {
        guard enabled != Projects.isEnabled else { return }
        enabled = Projects.isEnabled
        revision += 1
        guard enabled else { closeAll(remember: false); return }
        guard Preferences.spaceLabelsOnLaunch else { return }
        visibility.restoreOnLaunch()
        refresh()
    }

    static func refreshNames() {
        guard enabled, visibility.isRequested, !namesQueued else { return }
        namesQueued = true
        DispatchQueue.main.async {
            namesQueued = false
            guard enabled, visibility.isRequested else { return }
            reconcile()
        }
    }

    private static func refresh(revealOnArrival: Bool = false) {
        guard enabled, visibility.isRequested else { return }
        if revealOnArrival { revealRequested = true }
        revision += 1
        guard !refreshQueued, !refreshInFlight else { return }
        refreshQueued = true
        DispatchQueue.main.async {
            refreshQueued = false
            guard enabled, visibility.isRequested else { return }
            readSpaces()
        }
    }

    private static func readSpaces() {
        let requestedRevision = revision
        refreshInFlight = true
        CGSCallScheduler.run {
            let raw = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [NSDictionary]
            let snapshot = raw.flatMap { SpaceLabelResolver.spaces(from: $0) }
            let visible = raw.flatMap { SpaceLabelResolver.visibleSpaces(from: $0) }
            DispatchQueue.main.async {
                refreshInFlight = false
                guard enabled, visibility.isRequested else { return }
                guard requestedRevision == revision else { refresh(); return }
                guard let snapshot else {
                    Logger.warning { "Space labels: unavailable Space topology; retaining current windows" }
                    return
                }
                let didSwitch = revealRequested
                revealRequested = false
                let destinations = visible.map { arrival.update($0, didSwitch: didSwitch) } ?? []
                spaces = snapshot
                reconcile()
                if didSwitch, !destinations.isEmpty {
                    cancelReveals()
                    revealArrivals(destinations)
                }
            }
        }
    }

    private static func reconcile() {
        MainThreadStall.step()
        let names = Dictionary(uniqueKeysWithValues: Projects.list.filter { !$0.isCustom }.map {
            ($0.homeSpaceUuid, SpaceLabelResolver.Name(explicit: $0.name, automatic: $0.autoName ?? $0.resolvedName))
        })
        let labels = SpaceLabelResolver.labels(spaces: spaces, names: names, enabled: enabled)
            .filter { visibility.includes($0.space.uuid) }
        let screens = screensByIdentifier()
        let live = Set(labels.map { $0.space.uuid })
        for uuid in Array(windows.keys) where !live.contains(uuid) {
            if let entry = windows.removeValue(forKey: uuid) { retire(entry) }
        }
        for label in labels {
            let entry = windows[label.space.uuid] ?? Entry(uuid: label.space.uuid)
            guard let screen = screens[entry.window.savedDisplayIdentifier ?? label.space.displayIdentifier] ?? screens[label.space.displayIdentifier] else {
                if let entry = windows.removeValue(forKey: label.space.uuid) { retire(entry) }
                continue
            }
            windows[label.space.uuid] = entry
            entry.window.onClose = { close(label.space.uuid) }
            entry.window.onInteraction = { interact(with: label.space.uuid) }
            entry.window.update(label, on: screen)
            guard !entry.assigning else { continue }
            if entry.spaceId != label.space.id { assign(entry, to: label.space) }
        }
        synchronizeClickMonitors()
    }

    private static func screensByIdentifier() -> [String: NSScreen] {
        let screens = NSScreen.screens
        var result = [String: NSScreen]()
        for screen in screens {
            if let uuid = screen.uuid() { result[uuid as String] = screen }
        }
        result["Main"] = screens.first
        return result
    }

    private static func assign(_ entry: Entry, to space: SpaceLabelResolver.Space) {
        entry.assigning = true
        entry.spaceId = nil
        entry.window.alphaValue = 0
        if !entry.window.isVisible && !entry.window.isMiniaturized {
            entry.presentationRevision = nil
            entry.window.orderFrontRegardless()
        }
        let windowId = CGWindowID(entry.window.windowNumber)
        SpaceLabelWindow.assign(windowId, to: space.id) { success in
            entry.assigning = false
            guard !entry.retired else { entry.window.close(); return }
            guard enabled, visibility.includes(space.uuid), spaces.contains(space) else {
                entry.window.orderOut(nil)
                refreshNames()
                return
            }
            guard success else {
                entry.window.orderOut(nil)
                reveal.finish(space.uuid, after: reveal.revision)
                synchronizeClickMonitors()
                Logger.warning { "Space label assignment failed window=\(windowId) space=\(space.id)" }
                return
            }
            entry.spaceId = space.id
            entry.window.alphaValue = 1
            present(entry)
            revealIfRequested(entry, uuid: space.uuid)
            Logger.debug { "Space label assigned window=\(windowId) space=\(space.id) uuid=\(space.uuid)" }
        }
    }

    private static func updatePresentation() {
        MainThreadStall.step()
        revealRequested = false
        windows.values.forEach { $0.keptInFront = false }
        cancelReveals()
        presentNext(Array(windows.values)[...], revision: visibility.presentationRevision)
    }

    private static func revealArrivals(_ destinations: Set<UInt64>) {
        let targets = Set(spaces.filter { destinations.contains($0.id) && visibility.includes($0.uuid) && windows[$0.uuid] != nil }.map { $0.uuid })
        reveal.start(targets, duration: Preferences.spaceLabelRevealDuration)
        for uuid in reveal.targets {
            if let entry = windows[uuid] { revealIfRequested(entry, uuid: uuid) }
        }
        synchronizeClickMonitors()
    }

    private static func revealIfRequested(_ entry: Entry, uuid: String) {
        guard reveal.targets.contains(uuid), !entry.retired, !entry.assigning, entry.spaceId != nil,
              entry.revealLevel == nil else { return }
        guard visibility.presentation != .minimized, !entry.window.isMiniaturized,
              Preferences.spaceLabelRevealDuration > 0 else {
            reveal.finish(uuid, after: reveal.revision)
            return
        }
        MainThreadStall.step()
        let requestedRevision = reveal.revision
        entry.revealLevel = entry.window.level
        entry.window.level = .floating
        entry.window.orderFrontRegardless()
        // Start the reading interval after AppKit has had a runloop turn to present the raised window.
        DispatchQueue.main.async {
            guard reveal.revision == requestedRevision, reveal.targets.contains(uuid), !entry.retired else { return }
            let timer = DispatchWorkItem {
                guard reveal.finish(uuid, after: requestedRevision) else { return }
                restoreReveal(entry)
                synchronizeClickMonitors()
            }
            entry.revealTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Preferences.spaceLabelRevealDuration), execute: timer)
        }
    }

    private static func restoreReveal(_ entry: Entry) {
        entry.revealTimer?.cancel()
        entry.revealTimer = nil
        guard let level = entry.revealLevel else { return }
        entry.revealLevel = nil
        entry.window.level = level
        if !entry.retired, !entry.window.isMiniaturized, visibility.presentation == .back, !entry.keptInFront {
            entry.window.orderBack(nil)
        }
    }

    private static func cancelReveals() {
        reveal.cancel()
        windows.values.forEach { restoreReveal($0) }
        synchronizeClickMonitors()
    }

    private static func interact(with uuid: String) {
        guard let entry = windows[uuid], !entry.retired, !entry.assigning else { return }
        reveal.finish(uuid, after: reveal.revision)
        entry.keptInFront = true
        restoreReveal(entry)
        synchronizeClickMonitors()
    }

    private static func synchronizeClickMonitors() {
        if (visibility.presentation == .front && !windows.isEmpty) || !reveal.targets.isEmpty || windows.values.contains(where: { $0.keptInFront }) {
            observeClicks()
        } else {
            removeClickMonitors()
        }
    }

    private static func presentNext(_ entries: ArraySlice<Entry>, revision: Int) {
        guard let entry = entries.first else { return }
        // Native minimize/restore can wait on Dock; yield between windows so a newer request can cancel the batch.
        DispatchQueue.main.async {
            guard visibility.presentationRevision == revision else { return }
            present(entry)
            presentNext(entries.dropFirst(), revision: revision)
        }
    }

    private static func present(_ entry: Entry) {
        MainThreadStall.step()
        guard !entry.retired, !entry.assigning, entry.spaceId != nil,
              entry.presentationRevision != visibility.presentationRevision else { return }
        entry.presentationRevision = visibility.presentationRevision
        switch visibility.presentation {
        case .front:
            if entry.window.isMiniaturized { entry.window.deminiaturize(nil) }
            entry.window.orderFrontRegardless()
        case .back:
            if !entry.window.isMiniaturized { entry.window.orderBack(nil) }
        case .minimized:
            if !entry.window.isMiniaturized { entry.window.miniaturize(nil) }
        }
    }

    private static func observeClicks() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Global monitors exclude our own windows, so local clicks need a separate monitor.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in sendToBackAfterClick() }) {
            clickMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            if let uuid = windows.first(where: { $0.value.window === event.window })?.key {
                interact(with: uuid)
            } else {
                sendToBackAfterClick()
            }
            return event
        }) {
            clickMonitors.append(monitor)
        }
    }

    private static func sendToBackAfterClick(cancelReveal: Bool = true) {
        let requestedRevision = visibility.presentationRevision
        let revealRevision = reveal.revision
        DispatchQueue.main.async {
            guard visibility.presentationRevision == requestedRevision, reveal.revision == revealRevision else { return }
            // Space transitions can activate the destination app; that activation must not end its reveal.
            guard cancelReveal || (!revealRequested && reveal.targets.isEmpty) else { return }
            revealRequested = false
            let changed = visibility.sendToBack(after: requestedRevision)
            let kept = windows.values.filter { $0.keptInFront }
            kept.forEach { $0.keptInFront = false }
            cancelReveals()
            kept.forEach { if !$0.window.isMiniaturized { $0.window.orderBack(nil) } }
            if changed { updatePresentation() }
        }
    }

    private static func removeClickMonitors() {
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors.removeAll()
    }

    private static func retire(_ entry: Entry) {
        entry.retired = true
        reveal.finish(entry.uuid, after: reveal.revision)
        entry.revealTimer?.cancel()
        entry.revealTimer = nil
        entry.window.orderOut(nil)
        // Keep the WindowServer ID alive until its pending assignment has finished.
        if !entry.assigning { entry.window.close() }
    }

    private static func observeDock() {
        guard #available(macOS 12.0, *) else { return }
        dockRevision += 1
        let requestedRevision = dockRevision
        if let dockObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dockObserver), .commonModes) }
        dockObserver = nil
        DispatchQueue.global(qos: .utility).async {
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else { return }
            AXCallScheduler.shared.schedule(key: "space-label-dock-observer", context: "dock", pid: pid) {
                var observer: AXObserver?
                guard AXObserverCreate(pid, handleDockEvent, &observer) == .success,
                      let observer else { return }
                let dock = AXUIElementCreateApplication(pid)
                // Reconcile after Mission Control changes the Space layout without switching Desktops.
                let result = AXObserverAddNotification(observer, dock, MissionControlState.inactive.rawValue as CFString, nil)
                DispatchQueue.main.async {
                    guard result == .success, requestedRevision == dockRevision else { return }
                    dockObserver = observer
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
            }
        }
    }

    private static let handleDockEvent: AXObserverCallback = { _, _, _, _ in
        DispatchQueue.main.async { SpaceLabelWindows.refresh() }
    }
}
