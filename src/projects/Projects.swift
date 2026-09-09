import Cocoa

final class Project {
    enum Kind: Equatable {
        case desktop(spaceUuid: String)
        case custom
    }

    enum IconSource {
        case mostRecent
    }

    let id: String
    var kind: Kind
    var homeSpaceUuid: String
    var name: String? { didSet { if name != oldValue { Projects.save() } } }
    var autoName: String? { didSet { if autoName != oldValue { Projects.save() } } }
    var members = Set<String>()
    var memberIdentities = [ProjectWindowIdentity]()
    var windowHistory = [ProjectWindowPattern]()
    var memberPatterns = [ProjectWindowPattern]()
    var excludedPatterns = [ProjectWindowPattern]()
    var excludedMembers = [ProjectWindowIdentity]()
    var excludedWindowIds = Set<String>()
    var linkedProjectIds = [String]()
    var linkedProjectId: String? { linkedProjectIds.first }
    var labelUuid: String?
    var iconSource = IconSource.mostRecent { didSet { Projects.save() } }

    init(id: String, kind: Kind, homeSpaceUuid: String) {
        self.id = id
        self.kind = kind
        self.homeSpaceUuid = homeSpaceUuid
    }

    var isCustom: Bool { kind == .custom }
}

/// The registry and its Project objects are confined to the main thread.
enum Projects {
    static private(set) var list = [Project]()
    static private(set) var byId = [String: Project]()
    static var active: Project? {
        didSet {
            guard !isLoading, active?.id != oldValue?.id else { return }
            Logger.debug { "projects active previous=\(oldValue?.id ?? "none") next=\(active?.id ?? "none")" }
            let id = active?.id ?? ""
            DispatchQueue.main.async {
                guard (active?.id ?? "") == id else { return }
                Preferences.set("projectsActiveId", id, false)
            }
        }
    }
    static var isEnabled: Bool { Preferences.projectsEnabled }
    static private(set) var spaces = [SpaceItem]()
    private static var spaceObserver: NSObjectProtocol?
    private static var isLoading = false
    private static var windowIdentities = [String: ProjectWindowIdentity]()
    private static var retainedEntries = [ProjectEntry]()
    private static var iconFileNames = [String: String]()
    private static var pendingSpaceUpdates = Set<String>()
    private static var restoredWindows = Set<String>()
    private static var desktopAssignmentQueued = false
    private static var desktopTopology = [SpaceLabelResolver.Space]()
    private static var desktopWindowIds = [String: Set<String>]()

    static func startObservingSpaceChanges() {
        guard spaceObserver == nil else { return }
        Logger.debug { "projects startup enabled=\(isEnabled)" }
        let savedActiveId = UserDefaults.standard.string(forKey: "projectsActiveId")
        load()
        refreshSpaces()
        SpaceLabelWindows.start()
        if isEnabled, let id = savedActiveId, let project = byId[id], project.isCustom { active = project }
        Windows.list.forEach { window in ProjectBrowserURLs.refresh(window) { restoreMembership(window) } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Spaces.refresh()
            refreshSpaces()
        }
    }

    private static func refreshSpaces() {
        SpaceLabelWindows.refreshTopology()
    }

    static func applyDesktopTopology(_ snapshot: [SpaceLabelResolver.Space], labelLocations: [String: [UInt64]], windowLocations: [String: [UInt64]]) {
        let previous = desktopTopology
        desktopTopology = snapshot
        spaces = snapshot.map { SpaceItem(spaceId: $0.id, uuid: $0.uuid, desktopNumber: $0.desktopNumber, isCurrent: $0.id == Spaces.currentSpaceId) }
        let previousCount = list.count
        isLoading = true
        spaces.forEach { _ = forSpace(uuid: $0.uuid) }
        var merged = false
        for source in previous where !snapshot.contains(where: { $0.uuid == source.uuid }) {
            guard let destination = ProjectDesktopResolver.destination(for: source, previous: previous, current: snapshot,
                labelSpaces: labelLocations[source.uuid] ?? [], memberSpaces: windowLocations[source.uuid] ?? []) else { continue }
            merged = mergeDesktop(source.uuid, into: destination) || merged
        }
        isLoading = false
        if merged || list.count != previousCount { save() }
        desktopWindowIds = Dictionary(uniqueKeysWithValues: snapshot.map { space in
            (space.uuid, Set(Windows.list.filter { canBelongToProject($0) && $0.spaceIds.contains(space.id) }.map { $0.tracked.id }))
        })
        if isEnabled {
            for desktop in list where !desktop.isCustom {
                if let project = defaultProject(for: desktop) { captureDesktopWindows(desktop, into: project) }
            }
        }
        if isEnabled, !Preferences.projectsFollowDesktop, let active, active.isCustom, byId[active.id] === active { return }
        active = spaces.first { $0.isCurrent }.map { space in
            let desktop = forSpace(uuid: space.uuid)
            return isEnabled && Preferences.projectsFollowDesktop ? defaultProject(for: desktop) ?? desktop : desktop
        }
    }

    static func migrationWindowIds() -> [String: [CGWindowID]] {
        Dictionary(uniqueKeysWithValues: desktopWindowIds.map { uuid, ids in
            (uuid, Windows.list.filter { ids.contains($0.tracked.id) }.compactMap { $0.cgWindowId })
        })
    }

    private static func mergeDesktop(_ sourceUuid: String, into destinationUuid: String) -> Bool {
        guard let source = byId["desktop-\(sourceUuid)"], !source.isCustom else { return false }
        let destination = forSpace(uuid: destinationUuid)
        if linkedProjects(for: destination).isEmpty {
            let resident = Project(id: UUID().uuidString, kind: .custom, homeSpaceUuid: destinationUuid)
            resident.name = destination.name
            resident.autoName = destination.autoName
            resident.labelUuid = destinationUuid
            insert(resident)
            destination.linkedProjectIds = [resident.id]
            for id in desktopWindowIds[destinationUuid] ?? [] where !list.contains(where: { $0.isCustom && $0 !== resident && $0.members.contains(id) }) {
                _ = insertMember(id, into: resident)
            }
        }
        var incoming = linkedProjects(for: source)
        if incoming.isEmpty {
            source.kind = .custom
            source.labelUuid = sourceUuid
            source.homeSpaceUuid = destinationUuid
            for id in desktopWindowIds[sourceUuid] ?? [] where !list.contains(where: { $0.isCustom && $0 !== source && $0.members.contains(id) }) {
                _ = insertMember(id, into: source)
            }
            incoming = [source]
        }
        for project in incoming {
            project.labelUuid = project.labelUuid ?? sourceUuid
            project.homeSpaceUuid = destinationUuid
        }
        destination.linkedProjectIds = ProjectDesktopResolver.merge(resident: destination.linkedProjectIds, incoming: incoming.map { $0.id })
        if !source.isCustom { source.linkedProjectIds.removeAll() }
        Logger.debug { "projects desktop removed source=\(sourceUuid) destination=\(destinationUuid) projects=\(incoming.map { $0.id })" }
        return true
    }

    static func desktopLabels(_ spaces: [SpaceLabelResolver.Space]) -> [SpaceLabelResolver.Label] {
        spaces.flatMap { space in
            guard let desktop = byId["desktop-\(space.uuid)"] else { return [SpaceLabelResolver.Label(space: space, name: nil)] }
            let projects = linkedProjects(for: desktop)
            guard !projects.isEmpty else { return [SpaceLabelResolver.Label(space: space, name: desktop.name ?? desktop.autoName)] }
            return projects.enumerated().map { index, project in
                SpaceLabelResolver.Label(space: space, name: project.resolvedName, identity: project.labelUuid ?? project.id, stackIndex: index)
            }
        }
    }

    static func desktopDisplayName(_ uuid: String) -> String? {
        guard let desktop = byId["desktop-\(uuid)"] else { return nil }
        let projects = linkedProjects(for: desktop)
        return projects.count > 1 ? projects.map { $0.resolvedName }.joined(separator: " · ") : ProjectNameResolver.normalized(desktop.name)
    }

    static func activateLabel(_ uuid: String) {
        guard isEnabled, let project = list.first(where: { $0.isCustom && ($0.labelUuid ?? $0.id) == uuid }) else { return }
        active = project
    }

    static var activeMembers: Set<String>? {
        guard isEnabled, let project = active, project.isCustom else { return nil }
        return ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: project.isCustom,
            members: project.members, unassignedOnDesktop: unassignedOnCurrentDesktop)
    }

    private static var unassignedOnCurrentDesktop: Set<String> {
        let assigned = Set(list.filter { $0.isCustom }.flatMap { $0.members })
        let windowSpaces = Dictionary(uniqueKeysWithValues: Windows.list.filter { canBelongToProject($0) }.map { ($0.tracked.id, $0.spaceIds) })
        return ProjectMembershipResolver.unassignedOnDesktop(spaceId: Spaces.currentSpaceId, windowSpaces: windowSpaces, assigned: assigned)
    }

    private static func canBelongToProject(_ window: Window) -> Bool {
        !window.isWindowlessApp && !window.isPhantom
            && SpaceLabelWindows.switcherVisibility(windowId: window.cgWindowId, pid: window.application.pid) == nil
    }

    /// Membership repair runs after the switcher's first frame; visibility uses the cached union immediately.
    static func assignUnassignedWindowsOnCurrentDesktop(_ candidates: Set<String>?) {
        guard isEnabled, let project = active, project.isCustom, let candidates,
              !candidates.isSubset(of: project.members), !desktopAssignmentQueued else { return }
        desktopAssignmentQueued = true
        let spaceId = Spaces.currentSpaceId
        DispatchQueue.main.async {
            desktopAssignmentQueued = false
            guard isEnabled, active === project, byId[project.id] === project, Spaces.currentSpaceId == spaceId else { return }
            var changed = false
            for id in unassignedOnCurrentDesktop where permitsAutomaticAssignment(id, to: project) {
                if insertMember(id, into: project) { changed = true }
            }
            if changed { save(); App.refreshOpenUiAfterExternalEvent([]) }
        }
    }

    static func windowSpaceChanged(_ window: Window) {
        guard isEnabled, !window.isWindowlessApp, pendingSpaceUpdates.insert(window.tracked.id).inserted else { return }
        let id = window.tracked.id
        DispatchQueue.main.async { [weak window] in
            pendingSpaceUpdates.remove(id)
            guard let window, Windows.list.contains(where: { $0 === window }) else { return }
            ProjectBrowserURLs.refresh(window) { restoreMembership(window) }
        }
    }

    static func switcherProjectIds(mru: [String] = []) -> [String] {
        let desktop = spaces.first { $0.isCurrent }.map { forSpace(uuid: $0.uuid) }
        return ProjectsOrderResolver.sorted(currentDesktopId: desktop?.id, linkedProjectId: desktop?.linkedProjectId,
            customProjectIds: list.filter { $0.isCustom }.map { $0.id }, mru: mru)
    }

    /// Discovery applies the real Space after appendWindow, in the same main-queue turn.
    static func windowAdded(_ window: Window) {
        // discoveryLanded consumes the WindowServer creation marker after appendWindow returns.
        // Capture it now so startup discovery and re-admission never count as a new window.
        let isNew = window.cgWindowId.map { Windows.recentlyCreatedWindows.contains($0) } ?? false
        let creationProject = isEnabled && isNew ? active : nil
        DispatchQueue.main.async { [weak window] in
            guard let window, !window.isWindowlessApp, Windows.list.contains(where: { $0 === window }) else { return }
            Logger.debug { "projects discovered window=\(window.tracked.id) spaces=\(window.spaceIds) phantom=\(window.isPhantom) active=\(active?.id ?? "none")" }
            ProjectBrowserURLs.refresh(window) {
                restoreMembership(window) { applicationAge in
                    let savedOwners = owners(of: window.tracked.id)
                    let onCurrentDesktop = window.spaceIds.contains(Spaces.currentSpaceId)
                    if !window.isPhantom, pattern(for: window.tracked.id) != nil, let project = creationProject, project.isCustom,
                       ProjectReattachResolver.allowsActiveAssignment(isNew: isNew, applicationAge: applicationAge,
                           onCurrentDesktop: onCurrentDesktop, hasSavedOwner: !savedOwners.isEmpty || list.contains { $0.members.contains(window.tracked.id) }) {
                        Logger.debug { "projects auto-add source=window-created project=\(project.id) window=\(window.tracked.id)" }
                        addAutomatically(windowId: window.tracked.id, to: project)
                    } else {
                        Logger.debug { "projects auto-add skipped window=\(window.tracked.id) new=\(isNew) target=\(creationProject?.id ?? "none") phantom=\(window.isPhantom)" }
                    }
                    if isEnabled, let project = active, project.isCustom {
                        claimName(window.application.localizedName, for: project)
                    }
                }
            }
        }
    }

    static func browserURLUpdated(_ window: Window, restoreIfUnassigned: Bool) {
        guard isEnabled else { return }
        if list.contains(where: { $0.isCustom && $0.members.contains(window.tracked.id) }) {
            save()
        } else if restoreIfUnassigned {
            restoreMembership(window)
        }
    }

    private static func restoreMembership(_ window: Window, completion: ((TimeInterval) -> Void)? = nil) {
        guard !window.isWindowlessApp,
              SpaceLabelWindows.switcherVisibility(windowId: window.cgWindowId, pid: window.application.pid) == nil else { return }
        let application = window.application.runningApplication
        DispatchQueue.global(qos: .utility).async { [weak window] in
            let launchDate = application.launchDate
            DispatchQueue.main.async {
                guard let window, Windows.list.contains(where: { $0 === window }) else { return }
                guard let launchDate else {
                    restoredWindows.insert(window.tracked.id)
                    captureLinkedDesktopWindow(window)
                    completion?(0)
                    if SwitcherSession.isActive { App.refreshOpenUiAfterExternalEvent([]) }
                    return
                }
                let identity = ProjectWindowIdentity(windowId: window.tracked.id, pid: window.application.pid, processLaunchedAt: launchDate)
                windowIdentities[identity.windowId] = identity
                let savedOwners = owners(of: identity.windowId)
                if savedOwners.count > 1 { Logger.debug { "projects restoration ambiguous window=\(identity.windowId) projects=\(savedOwners.sorted())" } }
                var changed = false
                for project in list where project.isCustom {
                    if project.excludedMembers.contains(identity) { project.excludedWindowIds.insert(identity.windowId) }
                    if project.excludedWindowIds.contains(identity.windowId), !project.excludedMembers.contains(identity) {
                        project.excludedMembers.append(identity)
                        changed = true
                    }
                    let candidate = pattern(for: identity.windowId)
                    let patternExcluded = candidate.map { pattern in project.excludedPatterns.contains { ProjectReattachResolver.matchesObservation($0, pattern) && ($0.spaceUuid == nil || pattern.spaceUuid == nil || $0.spaceUuid == pattern.spaceUuid) } } ?? false
                    if ProjectReattachResolver.shouldRestore(hasLiveIdentity: project.memberIdentities.contains(identity),
                        identityExcluded: project.excludedMembers.contains(identity) || project.excludedWindowIds.contains(identity.windowId),
                        patternExcluded: patternExcluded, isUniquePatternOwner: savedOwners.count == 1 && savedOwners.contains(project.id)) {
                        let inserted = project.members.insert(identity.windowId).inserted
                        changed = changed || inserted
                        if isEnabled, inserted, !project.memberIdentities.contains(identity), let candidate {
                            let origins = Set(project.memberPatterns.filter { ProjectReattachResolver.matchesObservation($0, candidate) }.compactMap { $0.spaceUuid })
                            let elsewhere = candidate.spaceUuid.map { !origins.isEmpty && !origins.contains($0) } ?? false
                            ProjectRestoreNotice.record(windowId: identity.windowId, windowName: ProjectNameResolver.normalized(window.title) ?? window.application.localizedName ?? candidate.bundleIdentifier, projectName: project.resolvedName, differentDesktop: elsewhere)
                        }
                        Logger.debug { "projects restored project=\(project.id) window=\(identity.windowId) pid=\(identity.pid)" }
                    }
                    if project.members.contains(identity.windowId), !project.memberIdentities.contains(identity) {
                        Logger.debug { "projects identity saved project=\(project.id) window=\(identity.windowId)" }
                        project.memberIdentities.append(identity)
                        changed = true
                    }
                }
                restoredWindows.insert(window.tracked.id)
                if changed { save() }
                captureLinkedDesktopWindow(window)
                completion?(Date().timeIntervalSince(launchDate))
                if changed || SwitcherSession.isActive { App.refreshOpenUiAfterExternalEvent([]) }
            }
        }
    }

    private static func captureLinkedDesktopWindow(_ window: Window) {
        guard canBelongToProject(window) else { return }
        for space in spaces where window.spaceIds.contains(space.spaceId) {
            let desktop = forSpace(uuid: space.uuid)
            claimName(window.application.localizedName, for: desktop)
            desktopWindowIds[space.uuid, default: []].insert(window.tracked.id)
            if isEnabled, let project = defaultProject(for: desktop) { addAutomatically(windowId: window.tracked.id, to: project) }
        }
    }

    private static func claimName(_ appName: String?, for project: Project) {
        project.autoName = ProjectNameResolver.claim(name: project.name, autoName: project.autoName, appName: appName)
    }

    static func windowsRemoved(_ windows: [Window]) {
        let ids = Set(windows.map { $0.tracked.id })
        Logger.debug { "projects tracking removal windows=\(ids.sorted())" }
        ids.forEach { windowIdentities.removeValue(forKey: $0) }
        restoredWindows.subtract(ids)
        var changed = false
        let spaceIds = Set(windows.filter { !$0.isWindowlessApp }.flatMap { $0.spaceIds })
        for project in list {
            project.excludedWindowIds.subtract(ids)
            if project.isCustom {
                for window in windows where project.members.contains(window.tracked.id) {
                    if let pattern = pattern(for: window), !pattern.title.isEmpty {
                        recordPattern(pattern, in: &project.memberPatterns)
                        recordPattern(pattern, in: &project.windowHistory)
                        changed = true
                    }
                }
                let removed = project.members.intersection(ids)
                Logger.debug { "projects tracking removal project=\(project.id) removed=\(removed.sorted()) before=\(project.members.count)" }
                let hadMember = !project.members.isDisjoint(with: ids)
                project.members.subtract(ids)
                let count = project.memberIdentities.count
                project.memberIdentities.removeAll { ids.contains($0.windowId) }
                changed = changed || count != project.memberIdentities.count
                if hadMember { project.autoName = ProjectNameResolver.forget(autoName: project.autoName, hasLiveWindows: !project.members.isEmpty) }
            } else if let space = spaces.first(where: { "desktop-\($0.uuid)" == project.id }), spaceIds.contains(space.spaceId) {
                let hasLiveWindows = Windows.list.contains { !$0.isWindowlessApp && $0.spaceIds.contains(space.spaceId) }
                project.autoName = ProjectNameResolver.forget(autoName: project.autoName, hasLiveWindows: hasLiveWindows)
            }
        }
        ProjectBrowserURLs.forget(windows)
        if changed { save() }
    }

    static func forSpace(uuid: String) -> Project {
        let id = "desktop-\(uuid)"
        if let existing = byId[id] { return existing }
        return insert(Project(id: id, kind: .desktop(spaceUuid: uuid), homeSpaceUuid: uuid))
    }

    static func createCustom(homeSpaceUuid: String) -> Project? {
        guard isEnabled else { return nil }
        return insert(Project(id: UUID().uuidString, kind: .custom, homeSpaceUuid: homeSpaceUuid))
    }

    static func linkedProject(for desktop: Project) -> Project? {
        linkedProjects(for: desktop).first
    }

    static func linkedProjects(for desktop: Project) -> [Project] {
        guard !desktop.isCustom else { return [] }
        return desktop.linkedProjectIds.compactMap { byId[$0] }.filter { $0.isCustom }
    }

    private static func defaultProject(for desktop: Project) -> Project? {
        let projects = linkedProjects(for: desktop)
        return projects.first { $0 === active } ?? projects.first
    }

    @discardableResult
    static func link(_ desktop: Project, to project: Project?) -> Bool {
        link(desktop, toProjects: project.map { [$0] } ?? [])
    }

    @discardableResult
    static func link(_ desktop: Project, toProjects projects: [Project]) -> Bool {
        guard !desktop.isCustom, byId[desktop.id] === desktop else { return false }
        for project in projects {
            guard isEnabled, project.isCustom, byId[project.id] === project,
                  !list.contains(where: { $0 !== desktop && $0.linkedProjectIds.contains(project.id) }) else { return false }
        }
        desktop.linkedProjectIds = ProjectDesktopResolver.merge(resident: [], incoming: projects.map { $0.id })
        for project in projects {
            project.homeSpaceUuid = desktop.homeSpaceUuid
            if project.labelUuid == nil {
                project.labelUuid = list.contains { $0 !== project && $0.labelUuid == desktop.homeSpaceUuid } ? project.id : desktop.homeSpaceUuid
            }
        }
        if let project = defaultProject(for: desktop) { captureDesktopWindows(desktop, into: project) }
        if spaces.contains(where: { $0.isCurrent && $0.uuid == desktop.homeSpaceUuid }) { active = defaultProject(for: desktop) ?? desktop }
        save()
        return true
    }

    private static func captureDesktopWindows(_ desktop: Project, into project: Project) {
        guard let space = spaces.first(where: { $0.uuid == desktop.homeSpaceUuid }) else { return }
        var changed = false
        for window in Windows.list where !window.isWindowlessApp && !window.isPhantom && window.spaceIds.contains(space.spaceId) {
            if permitsAutomaticAssignment(window.tracked.id, to: project), insertMember(window.tracked.id, into: project) { changed = true }
        }
        if changed { save() }
    }

    static func delete(id: String) {
        guard let project = byId[id], project.isCustom else { return }
        for desktop in list { desktop.linkedProjectIds.removeAll { $0 == id } }
        if active === project { active = spaces.first { $0.isCurrent }.map { forSpace(uuid: $0.uuid) } }
        Logger.debug { "projects delete project=\(id) members=\(project.members.sorted())" }
        byId.removeValue(forKey: id)
        list.removeAll { $0.id == id }
        iconFileNames.removeValue(forKey: id)
        save()
    }

    static func add(windowId: String, to project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        let wasExcluded = project.excludedWindowIds.remove(windowId) != nil || project.excludedMembers.contains { $0.windowId == windowId }
        project.excludedMembers.removeAll { $0.windowId == windowId }
        if let pattern = pattern(for: windowId) { project.excludedPatterns.removeAll { ProjectReattachResolver.matchesObservation($0, pattern) } }
        let inserted = insertMember(windowId, into: project)
        if inserted || wasExcluded { save() }
    }

    private static func isExcluded(_ windowId: String, from project: Project) -> Bool {
        if let pattern = pattern(for: windowId), project.excludedPatterns.contains(where: { ProjectReattachResolver.matchesObservation($0, pattern) && ($0.spaceUuid == nil || pattern.spaceUuid == nil || $0.spaceUuid == pattern.spaceUuid) }) { return true }
        if project.excludedWindowIds.contains(windowId) { return true }
        if let identity = windowIdentities[windowId] { return project.excludedMembers.contains(identity) }
        // Defer auto-capture until launch-time identity validation can distinguish a reused window ID.
        return project.excludedMembers.contains { $0.windowId == windowId }
    }

    private static func owners(of windowId: String) -> Set<String> {
        guard let pattern = pattern(for: windowId) else { return [] }
        return ProjectReattachResolver.owners(of: pattern, assignments: Dictionary(uniqueKeysWithValues:
            list.filter { $0.isCustom }.map { ($0.id, $0.memberPatterns) }))
    }

    private static func permitsAutomaticAssignment(_ windowId: String, to project: Project) -> Bool {
        guard restoredWindows.contains(windowId),
              let window = Windows.list.first(where: { $0.tracked.id == windowId }), ProjectBrowserURLs.isReady(window),
              SpaceLabelWindows.switcherVisibility(windowId: window.cgWindowId, pid: window.application.pid) == nil,
              !isExcluded(windowId, from: project) else { return false }
        let savedOwners = owners(of: windowId)
        let liveOwners = Set(list.filter { $0.isCustom && $0.members.contains(windowId) }.map { $0.id })
        return ProjectReattachResolver.allowsAutomaticAssignment(to: project.id, savedOwners: savedOwners, liveOwners: liveOwners)
    }

    private static func addAutomatically(windowId: String, to project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project, permitsAutomaticAssignment(windowId, to: project) else { return }
        if insertMember(windowId, into: project) { save(); App.refreshOpenUiAfterExternalEvent([]) }
    }

    static func assign(_ windowIds: Set<String>, to project: Project, move: Bool) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        let liveIds = Set(Windows.list.filter { !$0.isWindowlessApp }.map { $0.tracked.id }).intersection(windowIds)
        if move {
            for source in list where source.isCustom && source !== project {
                for id in source.members.intersection(liveIds) { remove(windowId: id, from: source) }
            }
        }
        for id in liveIds { add(windowId: id, to: project) }
        Logger.debug { "projects assignment target=\(project.id) move=\(move) windows=\(liveIds.sorted())" }
    }

    private static func pattern(for windowId: String) -> ProjectWindowPattern? {
        guard let window = Windows.list.first(where: { $0.tracked.id == windowId }) else { return nil }
        return pattern(for: window)
    }

    private static func pattern(for window: Window) -> ProjectWindowPattern? {
        guard let bundle = window.application.bundleIdentifier, !bundle.isEmpty else { return nil }
        let space = spaces.first { window.spaceIds.contains($0.spaceId) }
        let title = window.title == window.application.localizedName ? "" : window.title
        return ProjectWindowPattern(bundleIdentifier: bundle, title: title, spaceUuid: space?.uuid, lastSeenAt: Date(), url: ProjectBrowserURLs.url(for: window))
    }

    @discardableResult
    private static func rememberPattern(_ windowId: String, in project: Project) -> Bool {
        guard let pattern = pattern(for: windowId), (!pattern.title.isEmpty || pattern.url != nil) else { return false }
        let inserted = !project.memberPatterns.contains(pattern)
        recordPattern(pattern, in: &project.memberPatterns)
        recordPattern(pattern, in: &project.windowHistory)
        return inserted
    }

    private static func recordPattern(_ pattern: ProjectWindowPattern, in history: inout [ProjectWindowPattern]) {
        if let index = history.firstIndex(of: pattern) {
            if (pattern.lastSeenAt ?? .distantPast) > (history[index].lastSeenAt ?? .distantPast) { history[index] = pattern }
        } else {
            history.append(pattern)
        }
    }

    private static func insertMember(_ windowId: String, into project: Project) -> Bool {
        let remembered = rememberPattern(windowId, in: project)
        guard project.members.insert(windowId).inserted else { return remembered }
        Logger.debug { "projects member added project=\(project.id) window=\(windowId) count=\(project.members.count) identityReady=\(windowIdentities[windowId] != nil)" }
        if let identity = windowIdentities[windowId], !project.memberIdentities.contains(identity) { project.memberIdentities.append(identity) }
        return true
    }

    static func remove(windowId: String, from project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        Logger.debug { "projects explicit remove project=\(project.id) window=\(windowId) wasMember=\(project.members.contains(windowId))" }
        if let pattern = pattern(for: windowId) {
            recordPattern(pattern, in: &project.windowHistory)
            project.memberPatterns.removeAll { ProjectReattachResolver.matchesObservation($0, pattern) }
            if !project.excludedPatterns.contains(pattern) { project.excludedPatterns.append(pattern) }
        }
        project.excludedWindowIds.insert(windowId)
        if let identity = windowIdentities[windowId], !project.excludedMembers.contains(identity) { project.excludedMembers.append(identity) }
        project.members.remove(windowId)
        project.memberIdentities.removeAll { $0.windowId == windowId }
        save()
    }

    private static func load() {
        isLoading = true
        defer { isLoading = false }
        for entry in Preferences.projects {
            guard byId[entry.id] == nil else { continue }
            let kind: Project.Kind
            if entry.kind == "desktop", let uuid = entry.spaceUuid {
                kind = .desktop(spaceUuid: uuid)
            } else if entry.kind == "custom", !entry.homeSpaceUuid.isEmpty {
                kind = .custom
            } else {
                retainedEntries.append(entry)
                continue
            }
            let project = Project(id: entry.id, kind: kind, homeSpaceUuid: entry.homeSpaceUuid)
            project.windowHistory = entry.windowHistory
            for pattern in entry.memberPatterns { recordPattern(pattern, in: &project.windowHistory) }
            project.memberPatterns = entry.memberPatterns
            project.excludedPatterns = entry.excludedPatterns
            project.memberIdentities = entry.members
            project.excludedMembers = entry.excludedMembers
            project.linkedProjectIds = entry.linkedProjectIds
            project.labelUuid = entry.labelUuid
            project.name = entry.name
            project.autoName = entry.autoName
            iconFileNames[project.id] = entry.iconFileName
            insert(project)
        }
        for desktop in list where !desktop.isCustom {
            for project in linkedProjects(for: desktop) { project.labelUuid = project.labelUuid ?? desktop.homeSpaceUuid }
        }
    }

    static func save() {
        guard !isLoading else { return }
        for project in list where project.isCustom {
            for id in project.members { _ = rememberPattern(id, in: project) }
        }
        let entries = list.map { project -> ProjectEntry in
            let uuid: String?
            if case .desktop(let spaceUuid) = project.kind { uuid = spaceUuid } else { uuid = nil }
            return ProjectEntry(id: project.id, kind: project.isCustom ? "custom" : "desktop", spaceUuid: uuid,
                homeSpaceUuid: project.homeSpaceUuid, name: project.name, autoName: project.autoName,
                iconFileName: iconFileNames[project.id], members: project.memberIdentities, linkedProjectId: project.linkedProjectId, excludedMembers: project.excludedMembers,
                memberPatterns: project.memberPatterns, excludedPatterns: project.excludedPatterns, windowHistory: project.windowHistory,
                linkedProjectIds: project.linkedProjectIds, labelUuid: project.labelUuid)
        }
        Preferences.set("projects", entries + retainedEntries, false)
        SpaceLabelWindows.refreshNames()
    }

    @discardableResult
    private static func insert(_ project: Project) -> Project {
        Logger.debug { "projects register project=\(project.id) name=\(project.name ?? "unnamed") custom=\(project.isCustom) savedMembers=\(project.memberIdentities.count)" }
        list.append(project)
        byId[project.id] = project
        save()
        return project
    }
}
