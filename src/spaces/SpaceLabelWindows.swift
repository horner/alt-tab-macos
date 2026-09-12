import Cocoa

/// AppKit state is main-thread-only. Topology reads and window assignment run on the CGS scheduler.
enum SpaceLabelWindows {
    private final class Entry {
        let uuid: String
        let window: SpaceLabelWindow
        var spaceId: CGSSpaceID?
        var spaceUuid: String?
        var windowId: CGWindowID?
        var assigning = false
        var assignmentRevision = 0
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

    private struct PlacementRead {
        let windowId: CGWindowID
        let spaceId: CGSSpaceID
        let spaceUuid: String
        let assignmentRevision: Int
    }

    private static var windows = [String: Entry]()
    private static var windowIds = Set<CGWindowID>()
    private static var showInSwitcher: Bool?
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
    private static var requestedSpaceShows = Set<String>()
    private static var requestedLabelShows = Set<String>()

    static var hasLabels: Bool { visibility.isRequested }

    static func switcherVisibility(windowId: CGWindowID?, pid: pid_t) -> Bool? {
        SpaceLabelResolver.switcherVisibility(windowId: windowId, pid: pid, ownerPid: AXUIElement.currentProcessPid,
            labelWindowIds: windowIds, showInSwitcher: Preferences.projectWindowsInSwitcher)
    }

    private static func synchronizeSwitcherVisibility() {
        guard showInSwitcher != Preferences.projectWindowsInSwitcher else { return }
        showInSwitcher = Preferences.projectWindowsInSwitcher
        for entry in windows.values {
            entry.window.synchronizeSwitcherVisibility()
            guard let wid = entry.windowId else { continue }
            if let window = Windows.byWindowId[wid], let semantic = window.semanticSurface {
                Windows.reevaluateAdmission(window, semantic)
            }
            if showInSwitcher == true, !entry.assigning { Applications.discoverWindow(wid) }
        }
        App.refreshOpenUiAfterExternalEvent([])
    }

    static func showAll() {
        guard Projects.isEnabled else { return }
        synchronizeEnabled()
        visibility.showAll()
        updatePresentation()
        refresh()
    }

    static func show(on spaceUuid: String) {
        guard Projects.isEnabled else { return }
        synchronizeEnabled()
        requestedSpaceShows.insert(spaceUuid)
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

    static func closeAll() {
        visibility.hideAll()
        requestedSpaceShows.removeAll()
        requestedLabelShows.removeAll()
        revealRequested = false
        reveal.cancel()
        arrival = SpaceLabelResolver.Arrival()
        removeClickMonitors()
        revision += 1
        windows.values.forEach { retire($0) }
        windows.removeAll()
    }

    private static func close(_ uuid: String) {
        visibility.close(uuid)
        requestedLabelShows.remove(uuid)
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
                synchronizeSwitcherVisibility()
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
        if !enabled { closeAll() }
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

    static func refreshTopology() { refresh() }

    static func spaceMembershipChanged(windowId: CGWindowID) {
        guard windowIds.contains(windowId), windows.values.contains(where: { $0.windowId == windowId && !$0.assigning }) else { return }
        refresh()
    }

    private static func refresh(revealOnArrival: Bool = false) {
        if revealOnArrival { revealRequested = true }
        revision += 1
        guard !refreshQueued, !refreshInFlight else { return }
        refreshQueued = true
        DispatchQueue.main.async {
            refreshQueued = false
            readSpaces()
        }
    }

    private static func readSpaces() {
        let requestedRevision = revision
        refreshInFlight = true
        let previous = spaces
        let memberIds = Projects.migrationWindowIds()
        let placements = windows.compactMapValues { entry -> PlacementRead? in
            guard !entry.assigning, !entry.retired, let windowId = entry.windowId,
                  let spaceId = entry.spaceId, let spaceUuid = entry.spaceUuid else { return nil }
            return PlacementRead(windowId: windowId, spaceId: spaceId, spaceUuid: spaceUuid, assignmentRevision: entry.assignmentRevision)
        }
        let labelIds = Dictionary(grouping: windows.values.filter { $0.spaceUuid != nil }, by: { $0.spaceUuid! })
            .mapValues { $0.compactMap { $0.windowId } }
        CGSCallScheduler.run {
            let raw = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [NSDictionary]
            let snapshot = raw.flatMap { SpaceLabelResolver.spaces(from: $0) }
            let visible = raw.flatMap { SpaceLabelResolver.visibleSpaces(from: $0) }
            let removed = previous.filter { old in snapshot.map { !$0.contains(where: { $0.uuid == old.uuid }) } ?? false }
            let ids = Set(removed.flatMap { (memberIds[$0.uuid] ?? []) + (labelIds[$0.uuid] ?? []) } + placements.values.map { $0.windowId })
            let locations = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGSCallScheduler.windowSpaces($0) ?? []) })
            let memberLocations = memberIds.mapValues { $0.flatMap { locations[$0] ?? [] } }
            let labelLocations = labelIds.mapValues { $0.flatMap { locations[$0] ?? [] } }
            DispatchQueue.main.async {
                refreshInFlight = false
                guard requestedRevision == revision else { refresh(); return }
                guard let snapshot else {
                    Logger.warning { "Project labels: unavailable Space topology; retaining current windows" }
                    return
                }
                let didSwitch = revealRequested
                revealRequested = false
                let destinations = visible.map { arrival.update($0, didSwitch: didSwitch) } ?? []
                let movedLabels = observedLabelMoves(placements, locations: locations, snapshot: snapshot)
                spaces = snapshot
                Projects.applyDesktopTopology(snapshot, labelLocations: labelLocations, windowLocations: memberLocations, movedLabels: movedLabels)
                for location in movedLabels { windows[location.labelId]?.spaceId = location.spaceIds.first }
                guard enabled else { return }
                prepareRequestedLabels()
                guard visibility.isRequested else { return }
                reconcile()
                if didSwitch, !destinations.isEmpty {
                    cancelReveals()
                    revealArrivals(destinations)
                }
            }
        }
    }

    private static func observedLabelMoves(_ placements: [String: PlacementRead], locations: [CGWindowID: [UInt64]],
                                           snapshot: [SpaceLabelResolver.Space]) -> [ProjectDesktopResolver.LabelLocation] {
        Projects.desktopLabels(spaces).compactMap { label in
            guard let read = placements[label.id], let entry = windows[label.id], !entry.assigning, !entry.retired,
                  entry.windowId == read.windowId, entry.spaceId == read.spaceId, entry.spaceUuid == read.spaceUuid,
                  entry.assignmentRevision == read.assignmentRevision, label.space.uuid == read.spaceUuid,
                  let ids = locations[read.windowId] else { return nil }
            let location = ProjectDesktopResolver.LabelLocation(labelId: label.id, sourceUuid: read.spaceUuid, spaceIds: ids)
            return ProjectDesktopResolver.relocation(location, in: snapshot) == nil ? nil : location
        }
    }

    private static func prepareRequestedLabels() {
        guard !requestedSpaceShows.isEmpty else { return }
        let labels = Projects.desktopLabels(spaces).filter { requestedSpaceShows.contains($0.space.uuid) }
        let ids = Set(labels.map { $0.id })
        visibility.show(ids)
        requestedLabelShows.formUnion(ids)
        requestedSpaceShows.removeAll()
    }

    private static func reconcile() {
        MainThreadStall.step()
        let labels = Projects.desktopLabels(spaces).filter { visibility.includes($0.id) }
        let screens = screensByIdentifier()
        let live = Set(labels.map { $0.id })
        for uuid in Array(windows.keys) where !live.contains(uuid) {
            if let entry = windows.removeValue(forKey: uuid) { retire(entry) }
        }
        var occupied = [String: [CGRect]]()
        for label in labels {
            let entry = windows[label.id] ?? Entry(uuid: label.id)
            let migrated = entry.spaceUuid != nil && entry.spaceUuid != label.space.uuid
            let display = migrated ? label.space.displayIdentifier : entry.window.savedDisplayIdentifier ?? label.space.displayIdentifier
            guard let screen = screens[display] ?? screens[label.space.displayIdentifier] else {
                if let entry = windows.removeValue(forKey: label.id) { retire(entry) }
                continue
            }
            windows[label.id] = entry
            entry.spaceUuid = label.space.uuid
            entry.window.onClose = { close(label.id) }
            entry.window.onInteraction = { interact(with: label.id) }
            entry.window.update(label, on: screen)
            entry.window.avoidOverlap(occupied[label.space.uuid] ?? [], on: screen, migrated: migrated)
            occupied[label.space.uuid, default: []].append(entry.window.frame)
            guard !entry.assigning else { continue }
            if entry.spaceId != label.space.id { assign(entry, to: label.space) }
            if requestedLabelShows.contains(label.id) { present(entry) }
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
        entry.assignmentRevision += 1
        entry.spaceId = nil
        entry.window.alphaValue = 0
        if !entry.window.isVisible && !entry.window.isMiniaturized {
            entry.presentationRevision = nil
            entry.window.orderFrontRegardless()
        }
        let windowId = CGWindowID(entry.window.windowNumber)
        entry.windowId = windowId
        windowIds.insert(windowId)
        SpaceLabelWindow.assign(windowId, to: space.id) { success in
            entry.assigning = false
            guard !entry.retired else { entry.window.close(); return }
            guard enabled, visibility.includes(entry.uuid), spaces.contains(space) else {
                entry.window.orderOut(nil)
                refreshNames()
                return
            }
            guard success else {
                entry.window.orderOut(nil)
                reveal.finish(entry.uuid, after: reveal.revision)
                synchronizeClickMonitors()
                Logger.warning { "Project label assignment failed window=\(windowId) space=\(space.id)" }
                return
            }
            entry.spaceId = space.id
            entry.window.alphaValue = 1
            present(entry)
            revealIfRequested(entry, uuid: entry.uuid)
            Logger.debug { "Project label assigned window=\(windowId) space=\(space.id) uuid=\(space.uuid)" }
        }
    }

    private static func updatePresentation() {
        MainThreadStall.step()
        requestedSpaceShows.removeAll()
        requestedLabelShows.removeAll()
        revealRequested = false
        windows.values.forEach { $0.keptInFront = false }
        cancelReveals()
        presentNext(Array(windows.values)[...], revision: visibility.presentationRevision)
    }

    private static func revealArrivals(_ destinations: Set<UInt64>) {
        let destinationUuids = Set(spaces.filter { destinations.contains($0.id) }.map { $0.uuid })
        let targets = Set(windows.values.filter { entry in
            entry.spaceUuid.map { destinationUuids.contains($0) } == true && visibility.includes(entry.uuid)
        }.map { $0.uuid })
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
        Projects.activateLabel(uuid)
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
        guard !entry.retired, !entry.assigning, entry.spaceId != nil else { return }
        if requestedLabelShows.remove(entry.uuid) != nil {
            entry.presentationRevision = visibility.presentationRevision
            entry.keptInFront = true
            if entry.window.isMiniaturized { entry.window.deminiaturize(nil) }
            entry.window.orderFrontRegardless()
            synchronizeClickMonitors()
            return
        }
        guard entry.presentationRevision != visibility.presentationRevision else { return }
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
        if let wid = entry.windowId { windowIds.remove(wid) }
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
