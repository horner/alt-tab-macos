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
    var pendingDesktopRemoval = false
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
    static private(set) var closedProjects = [ProjectEntry]()
    static var active: Project? {
        didSet {
            guard !isLoading, active?.id != oldValue?.id else { return }
            ProjectVisibility.selectionChanged()
            Logger.debug { "projects active previous=\(oldValue?.id ?? "none") next=\(active?.id ?? "none")" }
            let id = active?.id ?? ""
            DispatchQueue.main.async {
                guard (active?.id ?? "") == id else { return }
                Preferences.set("projectsActiveId", id, false)
                ProjectPersistence.scheduleSnapshot()
            }
        }
    }
    static var isEnabled: Bool { Preferences.projectsEnabled }
    static private(set) var spaces = [SpaceItem]()
    private static var spaceObserver: NSObjectProtocol?
    private static var isLoading = false
    private static var storageReady = false
    private static var storageStarted = false
    private static var windowIdentities = [String: ProjectWindowIdentity]()
    private static var retainedEntries = [ProjectEntry]()
    private static var iconFileNames = [String: String]()
    private static var pendingSpaceUpdates = Set<String>()
    private static var restoredWindows = Set<String>()
    private static var desktopAssignmentQueued = false
    private static var desktopTopology = [SpaceLabelResolver.Space]()
    private static var desktopWindowIds = [String: Set<String>]()
    private struct CreationContext {
        let isNew: Bool
        let observedAt: Date
        let spaceId: UInt64
        let project: Project?
        var onCreationDesktop = false
    }
    private static var creationContexts = [String: CreationContext]()
    private static var identityReads = Set<String>()
    private static var declinedRestorations = Set<String>()
    private static var metadataUpdates = [String: DispatchWorkItem]()
    private static var saveWork: DispatchWorkItem?

    static func startObservingSpaceChanges() {
        guard !storageStarted else { return }
        storageStarted = true
        Logger.debug { "projects startup enabled=\(isEnabled)" }
        ProjectPersistence.start(legacy: Preferences.projects) { entries, initial in
            if initial {
                load(entries)
                storageReady = true
                finishStarting()
            } else {
                applyFileChanges(entries)
            }
        }
    }

    private static func finishStarting() {
        let savedActiveId = UserDefaults.standard.string(forKey: "projectsActiveId")
        ProjectLifecyclePrompt.start()
        ProjectVisibility.start()
        refreshSpaces()
        SpaceLabelWindows.start()
        if isEnabled, !Preferences.projectsFollowDesktop, let id = savedActiveId, let project = byId[id], project.isCustom { active = project }
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

    static func applyDesktopTopology(_ snapshot: [SpaceLabelResolver.Space], labelLocations: [String: [UInt64]],
                                     windowLocations: [String: [UInt64]], movedLabels: [ProjectDesktopResolver.LabelLocation] = []) {
        let previousDesktop = spaces.first { $0.isCurrent }?.uuid
        let origin = DesktopNavigation.leaving(spaces.first { $0.isCurrent })
        let previous = desktopTopology
        desktopTopology = snapshot
        spaces = snapshot.map { SpaceItem(spaceId: $0.id, uuid: $0.uuid, desktopNumber: $0.desktopNumber, isCurrent: $0.id == Spaces.currentSpaceId) }
        let restoration = DesktopNavigation.entered(spaces.first { $0.isCurrent }, leaving: origin)
        let previousCount = list.count
        isLoading = true
        spaces.forEach { _ = forSpace(uuid: $0.uuid) }
        var merged = false
        for source in previous where !snapshot.contains(where: { $0.uuid == source.uuid }) {
            guard let destination = ProjectDesktopResolver.destination(for: source, previous: previous, current: snapshot,
                labelSpaces: labelLocations[source.uuid] ?? [], memberSpaces: windowLocations[source.uuid] ?? []) else { continue }
            merged = mergeDesktop(source.uuid, into: destination) || merged
        }
        var movedProjects = Set<String>()
        for location in movedLabels {
            guard let destination = ProjectDesktopResolver.relocation(location, in: snapshot),
                  let project = relocateLabel(location.labelId, from: location.sourceUuid, to: destination.uuid) else { continue }
            movedProjects.insert(project.id)
        }
        isLoading = false
        if merged || !movedProjects.isEmpty || list.count != previousCount { save() }
        desktopWindowIds = Dictionary(uniqueKeysWithValues: snapshot.map { space in
            (space.uuid, Set(Windows.list.filter { canBelongToProject($0) && $0.spaceIds.contains(space.id) }.map { $0.tracked.id }))
        })
        let desktop = spaces.first { $0.isCurrent }.map { forSpace(uuid: $0.uuid) }
        let activeMovedAway = active.map { movedProjects.contains($0.id) && $0.homeSpaceUuid != desktop?.homeSpaceUuid } ?? false
        let selected = ProjectDesktopResolver.selection(current: active?.id,
            customProjects: isEnabled ? Set(list.filter { $0.isCustom }.map { $0.id }) : [], desktop: desktop?.id,
            linkedProjects: desktop.map { linkedProjects(for: $0).map { $0.id } } ?? [],
            followsDesktop: isEnabled && Preferences.projectsFollowDesktop, changedDesktop: previousDesktop != desktop?.homeSpaceUuid || activeMovedAway)
        active = selected.flatMap { byId[$0] }
        if isEnabled, let id = restoration?.projectId, let project = byId[id] { active = project }
        if isEnabled {
            for desktop in list where !desktop.isCustom {
                if let project = defaultProject(for: desktop) { captureDesktopWindows(desktop, into: project) }
            }
        }
        if !movedProjects.isEmpty { DispatchQueue.main.async { App.refreshOpenUiAfterExternalEvent([]) } }
        if previousDesktop != desktop?.homeSpaceUuid { ProjectVisibility.selectionChanged() }
        ProjectVisibility.refresh()
        ProjectLifecyclePrompt.refresh()
    }

    private static func relocateLabel(_ labelId: String, from sourceUuid: String, to destinationUuid: String) -> Project? {
        guard isEnabled, let source = byId["desktop-\(sourceUuid)"],
              let project = linkedProjects(for: source).first(where: { ($0.labelUuid ?? $0.id) == labelId }) else { return nil }
        let destination = forSpace(uuid: destinationUuid)
        source.linkedProjectIds.removeAll { $0 == project.id }
        destination.linkedProjectIds = ProjectDesktopResolver.merge(resident: destination.linkedProjectIds, incoming: [project.id])
        project.homeSpaceUuid = destinationUuid
        Logger.debug { "projects label moved project=\(project.id) source=\(sourceUuid) destination=\(destinationUuid)" }
        return project
    }

    static func migrationWindowIds() -> [String: [CGWindowID]] {
        Dictionary(uniqueKeysWithValues: desktopWindowIds.map { uuid, ids in
            (uuid, Windows.list.filter { ids.contains($0.tracked.id) }.compactMap { $0.cgWindowId })
        })
    }

    private static func mergeDesktop(_ sourceUuid: String, into destinationUuid: String) -> Bool {
        guard let source = byId["desktop-\(sourceUuid)"], !source.isCustom else { return false }
        let incoming = linkedProjects(for: source)
        guard !incoming.isEmpty else { return false }
        let destination = forSpace(uuid: destinationUuid)
        for project in incoming {
            project.labelUuid = project.labelUuid ?? sourceUuid
            project.homeSpaceUuid = destinationUuid
            project.pendingDesktopRemoval = isEnabled
        }
        destination.linkedProjectIds = ProjectDesktopResolver.merge(resident: destination.linkedProjectIds, incoming: incoming.map { $0.id })
        source.linkedProjectIds.removeAll()
        Logger.debug { "projects desktop removed source=\(sourceUuid) destination=\(destinationUuid) projects=\(incoming.map { $0.id })" }
        return true
    }

    static func desktopLabels(_ spaces: [SpaceLabelResolver.Space]) -> [SpaceLabelResolver.Label] {
        spaces.flatMap { space in
            guard let desktop = byId["desktop-\(space.uuid)"] else { return [SpaceLabelResolver.Label(space: space, name: nil)] }
            let projects = linkedProjects(for: desktop)
            guard !projects.isEmpty else {
                if closedProjects.contains(where: { $0.homeSpaceUuid == space.uuid }) { return [] }
                return [SpaceLabelResolver.Label(space: space, name: ProjectNameResolver.normalized(desktop.name))]
            }
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
        let changed = active !== project
        active = project
        if changed { ProjectVisibility.focus(project) }
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
        ProjectPersistence.scheduleSnapshot()
        WindowDesktopMove.spaceChanged(window)
        ProjectVisibility.refresh()
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

    static func numberedProjectChoices() -> [ProjectNumberResolver.Choice] {
        let desktops = spaces.filter { $0.desktopNumber > 0 }
        let numbers = Dictionary(uniqueKeysWithValues: desktops.map { ($0.uuid, $0.desktopNumber) })
        var claims = [String: (number: Int, index: Int)]()
        for space in desktops {
            guard let desktop = byId["desktop-\(space.uuid)"] else { continue }
            for (index, project) in linkedProjects(for: desktop).enumerated() { claims[project.id] = (space.desktopNumber, index) }
        }
        let entries = switcherProjectIds().compactMap { id -> ProjectNumberResolver.Entry? in
            guard let project = byId[id] else { return nil }
            return .init(id: id, desktopNumber: claims[id]?.number ?? numbers[project.homeSpaceUuid], claimIndex: claims[id]?.index ?? Int.max)
        }
        return ProjectNumberResolver.choices(entries, desktopCount: desktops.count)
    }

    /// Discovery applies the real Space after appendWindow, in the same main-queue turn.
    static func windowAdded(_ window: Window) {
        ProjectPersistence.scheduleSnapshot()
        // discoveryLanded consumes the WindowServer creation marker after appendWindow returns.
        // Capture it now so startup discovery and re-admission never count as a new window.
        let isNew = window.cgWindowId.map { Windows.recentlyCreatedWindows.contains($0) } ?? false
        creationContexts[window.tracked.id] = CreationContext(isNew: isEnabled && isNew, observedAt: Date(), spaceId: Spaces.currentSpaceId, project: active)
        DispatchQueue.main.async { [weak window] in
            guard let window, !window.isWindowlessApp, Windows.list.contains(where: { $0 === window }) else { return }
            if let context = creationContexts[window.tracked.id] { creationContexts[window.tracked.id]?.onCreationDesktop = window.spaceIds.contains(context.spaceId) }
            Logger.debug { "projects discovered window=\(window.tracked.id) spaces=\(window.spaceIds) phantom=\(window.isPhantom) active=\(active?.id ?? "none")" }
            restoreMembership(window)
            ProjectBrowserURLs.refresh(window) { restoreMembership(window) }
        }
    }

    static func windowTitleChanged(_ window: Window) {
        ProjectPersistence.scheduleSnapshot()
        guard isEnabled, Windows.list.contains(where: { $0 === window }) else { return }
        let id = window.tracked.id
        ProjectBrowserURLs.invalidate(window)
        metadataUpdates[id]?.cancel()
        let work = DispatchWorkItem { [weak window] in
            metadataUpdates.removeValue(forKey: id)
            guard let window, Windows.list.contains(where: { $0 === window }) else { return }
            ProjectBrowserURLs.refresh(window) { browserURLUpdated(window, restoreIfUnassigned: true) }
        }
        metadataUpdates[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    static func browserURLUpdated(_ window: Window, restoreIfUnassigned: Bool) {
        guard isEnabled, metadataUpdates[window.tracked.id] == nil else { return }
        if list.contains(where: { $0.isCustom && $0.members.contains(window.tracked.id) }) {
            for project in list where project.isCustom && project.members.contains(window.tracked.id) { _ = rememberPattern(window.tracked.id, in: project) }
            scheduleSave()
        } else if restoreIfUnassigned {
            restoreMembership(window)
        }
    }

    private static func restoreMembership(_ window: Window) {
        guard canBelongToProject(window), !WindowDesktopMove.preservesMembership(window) else { return }
        if let identity = windowIdentities[window.tracked.id] { applyRestoration(window, identity: identity); return }
        guard identityReads.insert(window.tracked.id).inserted else { return }
        let application = window.application.runningApplication
        DispatchQueue.global(qos: .utility).async { [weak window] in
            let launchDate = application.launchDate
            DispatchQueue.main.async {
                guard let window, Windows.list.contains(where: { $0 === window }) else { return }
                identityReads.remove(window.tracked.id)
                let identity = launchDate.map { ProjectWindowIdentity(windowId: window.tracked.id, pid: window.application.pid, processLaunchedAt: $0) }
                if let identity { windowIdentities[identity.windowId] = identity; ProjectVisibility.register(window, identity) }
                applyRestoration(window, identity: identity)
            }
        }
    }

    private static func applyRestoration(_ window: Window, identity: ProjectWindowIdentity?) {
        ProjectPersistence.scheduleSnapshot()
        guard canBelongToProject(window), !WindowDesktopMove.preservesMembership(window) else { return }
        let id = window.tracked.id
        if let context = creationContexts.removeValue(forKey: id), let identity,
           ProjectReattachResolver.allowsActiveAssignment(isNew: context.isNew,
               applicationAge: context.observedAt.timeIntervalSince(identity.processLaunchedAt), onCurrentDesktop: context.onCreationDesktop),
           !declinedRestorations.contains(id),
           !list.contains(where: { $0.isCustom && $0.members.contains(id) }) {
            if let project = context.project, project.isCustom, byId[project.id] === project {
                Logger.debug { "projects assignment source=window-created project=\(project.id) window=\(id)" }
                add(windowId: id, to: project)
                claimName(window.application.localizedName, for: project)
            } else {
                declinedRestorations.insert(id)
            }
        }
        let liveOwners = Set(list.filter { $0.isCustom && $0.members.contains(id) }.map { $0.id })
        let identityOwners = Set(list.filter { project in
            project.isCustom && (identity.map { project.memberIdentities.contains($0) && !project.excludedMembers.contains($0) && !project.excludedWindowIds.contains(id) } ?? false)
        }.map { $0.id })
        let ready = metadataUpdates[id] == nil && ProjectBrowserURLs.isReady(window)
        let savedOwners = isEnabled && liveOwners.isEmpty && identityOwners.isEmpty && !declinedRestorations.contains(id) && ready ? owners(of: id) : []
        let candidates = ProjectReattachResolver.restorationCandidates(liveOwners: liveOwners, identityOwners: identityOwners,
            savedOwners: savedOwners, declined: declinedRestorations.contains(id))
        var changed = false
        for project in list where project.isCustom {
            if let identity {
                if project.excludedMembers.contains(identity) { project.excludedWindowIds.insert(id) }
                if project.excludedWindowIds.contains(id), !project.excludedMembers.contains(identity) {
                    project.excludedMembers.append(identity)
                    changed = true
                }
            }
            let identityOwner = identityOwners.contains(project.id)
            if candidates.contains(project.id), ProjectReattachResolver.shouldRestore(hasLiveIdentity: identityOwner,
                identityExcluded: project.excludedWindowIds.contains(id) || (identity.map { project.excludedMembers.contains($0) } ?? false),
                patternExcluded: isExcluded(id, from: project), isUniquePatternOwner: savedOwners == [project.id]) {
                if project.members.insert(id).inserted {
                    changed = true
                    if !identityOwner, let candidate = pattern(for: window) {
                        let origins = Set(project.memberPatterns.filter { ProjectReattachResolver.matchesObservation($0, candidate) }.compactMap { $0.spaceUuid })
                        let elsewhere = candidate.spaceUuid.map { !origins.isEmpty && !origins.contains($0) } ?? false
                        ProjectRestoreNotice.record(window: window, windowName: window.title, projectName: project.resolvedName, differentDesktop: elsewhere)
                    }
                }
            }
            if project.members.contains(id), let identity, !project.memberIdentities.contains(identity) {
                project.memberIdentities.append(identity)
                changed = true
            }
        }
        restoredWindows.insert(id)
        if savedOwners.count > 1, let candidate = pattern(for: window) {
            ProjectRestoreNotice.ask(window: window, pattern: candidate, projectIds: savedOwners)
        } else {
            ProjectRestoreNotice.forgetQuestions(for: [id])
        }
        if changed { save() }
        captureLinkedDesktopWindow(window)
        if changed || SwitcherSession.isActive { App.refreshOpenUiAfterExternalEvent([]) }
    }

    static func declineRestoration(_ window: Window) {
        guard Windows.list.contains(where: { $0 === window }) else { return }
        declinedRestorations.insert(window.tracked.id)
        ProjectRestoreNotice.forgetQuestions(for: [window.tracked.id])
    }

    static func resolveRestoration(_ window: Window, expected: ProjectWindowPattern, candidates: Set<String>, project: Project, move: Bool) {
        let id = window.tracked.id
        guard isEnabled, Windows.list.contains(where: { $0 === window }), canBelongToProject(window),
              byId[project.id] === project, project.isCustom, !WindowDesktopMove.preservesMembership(window),
              !list.contains(where: { $0.isCustom && $0.members.contains(id) }), !declinedRestorations.contains(id),
              metadataUpdates[id] == nil, ProjectBrowserURLs.isReady(window), let current = pattern(for: window),
              ProjectReattachResolver.sameEvidence(expected, current), owners(of: id) == candidates,
              var evidence = ProjectReattachResolver.evidence(current) else { restoreMembership(window); return }
        evidence.confirmedAt = Date()
        recordPattern(evidence, in: &project.memberPatterns)
        add(windowId: id, to: project)
        save()
        App.refreshOpenUiAfterExternalEvent([])
        if move { ProjectAssignmentPrompt.moveToDesktop([window], project: project) }
    }

    private static func captureLinkedDesktopWindow(_ window: Window) {
        guard canBelongToProject(window) else { return }
        for space in spaces where window.spaceIds.contains(space.spaceId) {
            let desktop = forSpace(uuid: space.uuid)
            desktopWindowIds[space.uuid, default: []].insert(window.tracked.id)
            if isEnabled, let project = defaultProject(for: desktop) { addAutomatically(windowId: window.tracked.id, to: project) }
        }
    }

    private static func claimName(_ appName: String?, for project: Project) {
        project.autoName = ProjectNameResolver.claim(name: project.name, autoName: project.autoName, appName: appName)
    }

    static func windowsRemoved(_ windows: [Window]) {
        ProjectPersistence.scheduleSnapshot()
        WindowDesktopMove.forget(windows)
        ProjectVisibility.forget(windows)
        let ids = Set(windows.map { $0.tracked.id })
        Logger.debug { "projects tracking removal windows=\(ids.sorted())" }
        ids.forEach { windowIdentities.removeValue(forKey: $0) }
        for id in ids {
            creationContexts.removeValue(forKey: id)
            metadataUpdates.removeValue(forKey: id)?.cancel()
        }
        identityReads.subtract(ids)
        declinedRestorations.subtract(ids)
        ProjectRestoreNotice.forgetQuestions(for: ids)
        restoredWindows.subtract(ids)
        var changed = false
        let spaceIds = Set(windows.filter { !$0.isWindowlessApp }.flatMap { $0.spaceIds })
        for project in list {
            project.excludedWindowIds.subtract(ids)
            if project.isCustom {
                for window in windows where project.members.contains(window.tracked.id) {
                    if let pattern = pattern(for: window), ProjectBrowserURLs.isReady(window) {
                        if let evidence = ProjectReattachResolver.evidence(pattern) { recordPattern(evidence, in: &project.memberPatterns) }
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
                changed = changed || hadMember || count != project.memberIdentities.count
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
        let project = Project(id: UUID().uuidString, kind: .custom, homeSpaceUuid: homeSpaceUuid)
        project.name = availableProjectName("Project")
        return insert(project)
    }

    static func projectNames(excluding id: String? = nil) -> [String] {
        var names = ProjectPersistence.projectNames
        for project in list where project.isCustom { names[project.id] = project.resolvedName }
        for entry in closedProjects + retainedEntries where entry.kind == "custom" { names[entry.id] = entry.name ?? entry.autoName }
        if let id { names[id] = nil }
        return Array(names.values)
    }

    static func availableProjectName(_ proposed: String, excluding id: String? = nil) -> String {
        ProjectNameResolver.available(proposed, existing: projectNames(excluding: id))
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
        desktop.linkedProjectIds = ProjectDesktopResolver.linkOrder(existing: desktop.linkedProjectIds, selected: projects.map { $0.id })
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
        declinedRestorations.remove(windowId)
        ProjectRestoreNotice.forgetQuestions(for: [windowId])
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
        guard restoredWindows.contains(windowId), !declinedRestorations.contains(windowId), metadataUpdates[windowId] == nil,
              let window = Windows.list.first(where: { $0.tracked.id == windowId }), ProjectBrowserURLs.isReady(window),
              let pattern = pattern(for: window), ProjectReattachResolver.evidence(pattern) != nil,
              !WindowDesktopMove.preservesMembership(window),
              SpaceLabelWindows.switcherVisibility(windowId: window.cgWindowId, pid: window.application.pid) == nil,
              !isExcluded(windowId, from: project) else { return false }
        let savedOwners = owners(of: windowId)
        let liveOwners = Set(list.filter { $0.isCustom && $0.members.contains(windowId) }.map { $0.id })
        return ProjectReattachResolver.allowsAutomaticAssignment(to: project.id, savedOwners: savedOwners, liveOwners: liveOwners)
    }

    private static func addAutomatically(windowId: String, to project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project, permitsAutomaticAssignment(windowId, to: project) else { return }
        if insertMember(windowId, into: project) {
            Logger.debug { "projects assignment source=desktop-capture project=\(project.id) window=\(windowId)" }
            save()
            App.refreshOpenUiAfterExternalEvent([])
        }
    }

    static func assign(_ windowIds: Set<String>, to project: Project, move: Bool) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        let windows = Windows.list.filter { !$0.isWindowlessApp && windowIds.contains($0.tracked.id) }
        let liveIds = Set(windows.map { $0.tracked.id })
        if move {
            for source in list where source.isCustom && source !== project {
                for id in source.members.intersection(liveIds) { remove(windowId: id, from: source) }
            }
        }
        for id in liveIds { add(windowId: id, to: project) }
        if move { ProjectAssignmentPrompt.moveToDesktop(windows, project: project) }
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
        guard metadataUpdates[windowId] == nil, let window = Windows.list.first(where: { $0.tracked.id == windowId }),
              ProjectBrowserURLs.isReady(window), let pattern = pattern(for: window), (!pattern.title.isEmpty || pattern.url != nil) else { return false }
        recordPattern(pattern, in: &project.windowHistory)
        guard let evidence = ProjectReattachResolver.evidence(pattern) else { return false }
        let inserted = !project.memberPatterns.contains(evidence)
        recordPattern(evidence, in: &project.memberPatterns)
        return inserted
    }

    private static func recordPattern(_ pattern: ProjectWindowPattern, in history: inout [ProjectWindowPattern]) {
        if let index = history.firstIndex(of: pattern) {
            var updated = pattern
            updated.lastSeenAt = max(pattern.lastSeenAt ?? .distantPast, history[index].lastSeenAt ?? .distantPast)
            updated.confirmedAt = pattern.confirmedAt ?? history[index].confirmedAt
            history[index] = updated
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
        declinedRestorations.insert(windowId)
        Logger.debug { "projects explicit remove project=\(project.id) window=\(windowId) wasMember=\(project.members.contains(windowId))" }
        if let pattern = pattern(for: windowId) {
            recordPattern(pattern, in: &project.windowHistory)
            project.memberPatterns.removeAll { ProjectReattachResolver.matchesObservation($0, pattern) }
            if let evidence = ProjectReattachResolver.evidence(pattern), !project.excludedPatterns.contains(evidence) { project.excludedPatterns.append(evidence) }
        }
        project.excludedWindowIds.insert(windowId)
        if let identity = windowIdentities[windowId], !project.excludedMembers.contains(identity) { project.excludedMembers.append(identity) }
        project.members.remove(windowId)
        project.memberIdentities.removeAll { $0.windowId == windowId }
        save()
    }

    static func entry(for project: Project) -> ProjectEntry {
        let uuid: String?
        if case .desktop(let spaceUuid) = project.kind { uuid = spaceUuid } else { uuid = nil }
        return ProjectEntry(id: project.id, kind: project.isCustom ? "custom" : "desktop", spaceUuid: uuid,
            homeSpaceUuid: project.homeSpaceUuid, name: project.name, autoName: project.autoName,
            iconFileName: iconFileNames[project.id], members: project.memberIdentities, linkedProjectId: project.linkedProjectId,
            excludedMembers: project.excludedMembers, memberPatterns: project.memberPatterns, excludedPatterns: project.excludedPatterns,
            windowHistory: project.windowHistory, linkedProjectIds: project.linkedProjectIds, labelUuid: project.labelUuid,
            pendingDesktopRemoval: project.pendingDesktopRemoval)
    }

    static func keepAfterDesktopRemoval(_ project: Project) {
        guard isEnabled, byId[project.id] === project else { return }
        project.pendingDesktopRemoval = false
        save()
    }

    static func close(_ project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        Logger.debug { "projects close project=\(project.id) desktop=\(project.homeSpaceUuid) label=\(project.labelUuid ?? "none") history=\(project.windowHistory.count)" }
        archive(project)
        save()
        DispatchQueue.main.async { App.refreshOpenUiAfterExternalEvent([]) }
    }

    private static func archive(_ project: Project) {
        for id in project.members { _ = rememberPattern(id, in: project) }
        var snapshot = ProjectLifecycleResolver.closed(entry(for: project))
        snapshot.closedWindows = Windows.list.filter { project.members.contains($0.tracked.id) }.compactMap { pattern(for: $0) }
        if snapshot.name == nil, snapshot.autoName == nil { snapshot.name = project.resolvedName }
        closedProjects.append(snapshot)
        for desktop in list { desktop.linkedProjectIds.removeAll { $0 == project.id } }
        if active === project { active = spaces.first { $0.isCurrent }.map { forSpace(uuid: $0.uuid) } }
        byId.removeValue(forKey: project.id)
        list.removeAll { $0 === project }
        ProjectRestoreNotice.forgetQuestions(for: project.members)
    }

    static func atticWindows(_ entry: ProjectEntry) -> [Window] {
        Windows.list.filter { window in
            ProjectAssignmentPrompt.canAssign(window) && ProjectAtticResolver.canBringBack(windowIdentities[window.tracked.id], from: entry,
                hasOwner: list.contains { $0.isCustom && $0.members.contains(window.tracked.id) })
        }
    }

    @discardableResult
    static func reopen(id: String, on desktopUuid: String, bringWindows: Bool = false) -> Project? {
        guard isEnabled, byId[id] == nil, spaces.contains(where: { $0.uuid == desktopUuid && $0.desktopNumber > 0 }),
              let index = closedProjects.firstIndex(where: { $0.id == id }) else { return nil }
        let live = atticWindows(closedProjects[index])
        Logger.debug { "projects attic restore project=\(id) destination=\(desktopUuid) bringWindows=\(bringWindows) live=\(live.count)" }
        let saved = ProjectLifecycleResolver.reopened(closedProjects.remove(at: index), on: desktopUuid)
        isLoading = true
        let project = insert(project(from: saved, kind: .custom))
        let desktop = forSpace(uuid: desktopUuid)
        desktop.linkedProjectIds = ProjectDesktopResolver.merge(resident: desktop.linkedProjectIds, incoming: [id])
        for window in live { _ = insertMember(window.tracked.id, into: project) }
        isLoading = false
        save()
        DispatchQueue.main.async {
            guard isEnabled, byId[id] === project else { return }
            if spaces.contains(where: { $0.uuid == desktopUuid && $0.isCurrent }) { active = project }
            SpaceLabelWindows.show(on: desktopUuid)
            for window in Windows.list where !list.contains(where: { $0.isCustom && $0.members.contains(window.tracked.id) }) {
                restoreMembership(window)
            }
            App.refreshOpenUiAfterExternalEvent([])
            if bringWindows { ProjectAssignmentPrompt.moveToDesktop(live, project: project, onlyUnshared: true) }
        }
        return project
    }

    static func combine(_ source: Project, into destination: Project) {
        guard isEnabled, byId[source.id] === source, byId[destination.id] === destination,
              spaces.contains(where: { $0.uuid == source.homeSpaceUuid && $0.desktopNumber > 0 }),
              let merged = ProjectLifecycleResolver.combined(entry(for: source), into: entry(for: destination)) else { return }
        let members = source.members.union(destination.members)
        let wasActive = active === source
        archive(source)
        destination.members = members
        destination.memberIdentities = merged.members
        destination.memberPatterns = merged.memberPatterns
        destination.windowHistory = merged.windowHistory
        destination.excludedMembers = merged.excludedMembers
        destination.excludedPatterns = merged.excludedPatterns
        destination.excludedWindowIds.formUnion(source.excludedWindowIds)
        destination.excludedWindowIds.subtract(members)
        if wasActive { active = destination }
        save()
        DispatchQueue.main.async { App.refreshOpenUiAfterExternalEvent([]) }
    }

    private static func load(_ saved: [ProjectEntry]) {
        isLoading = true
        list = []
        byId = [:]
        closedProjects = []
        retainedEntries = []
        iconFileNames = [:]
        let repaired = ProjectLifecycleResolver.repairingUnlinkedProjects(ProjectLifecycleResolver.repairingEmptyDesktopAliases(saved))
        defer {
            isLoading = false
            if repaired != saved {
                Logger.debug { "projects repaired saved Desktop links and aliases removed=\(saved.count - repaired.count)" }
                save()
            }
        }
        for entry in repaired {
            guard byId[entry.id] == nil, !closedProjects.contains(where: { $0.id == entry.id }) else { continue }
            let kind: Project.Kind
            if entry.kind == "desktop", let uuid = entry.spaceUuid {
                kind = .desktop(spaceUuid: uuid)
            } else if entry.kind == "custom", !entry.homeSpaceUuid.isEmpty {
                kind = .custom
            } else {
                retainedEntries.append(entry)
                continue
            }
            if entry.isClosed, entry.kind == "custom" {
                closedProjects.append(entry)
                continue
            }
            insert(project(from: entry, kind: kind))
        }
        for desktop in list where !desktop.isCustom {
            for project in linkedProjects(for: desktop) { project.labelUuid = project.labelUuid ?? desktop.homeSpaceUuid }
        }
    }

    private static func project(from entry: ProjectEntry, kind: Project.Kind) -> Project {
        let project = Project(id: entry.id, kind: kind, homeSpaceUuid: entry.homeSpaceUuid)
        project.windowHistory = entry.windowHistory
        for pattern in entry.memberPatterns { recordPattern(pattern, in: &project.windowHistory) }
        project.memberPatterns = entry.memberPatterns.compactMap { ProjectReattachResolver.evidence($0) }
        project.excludedPatterns = entry.excludedPatterns.compactMap { ProjectReattachResolver.evidence($0) }
        project.memberIdentities = entry.members
        project.excludedMembers = entry.excludedMembers
        project.linkedProjectIds = entry.linkedProjectIds
        project.labelUuid = entry.labelUuid
        project.name = entry.name
        project.autoName = entry.autoName
        iconFileNames[project.id] = entry.iconFileName
        project.pendingDesktopRemoval = entry.pendingDesktopRemoval
        return project
    }

    private static func scheduleSave() {
        guard saveWork == nil else { return }
        let work = DispatchWorkItem { save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    static func finishPendingSave(_ completion: @escaping () -> Void) {
        if saveWork != nil { save() }
        ProjectPersistence.finishPendingSave(completion)
    }

    static func save() {
        guard !isLoading, storageReady else { return }
        saveWork?.cancel()
        saveWork = nil
        ProjectVisibility.refresh()
        for project in list where project.isCustom {
            for id in project.members { _ = rememberPattern(id, in: project) }
        }
        ProjectPersistence.scheduleSnapshot()
        SpaceLabelWindows.refreshNames()
        ProjectLifecyclePrompt.refresh()
    }

    static func persistSnapshot() {
        guard storageReady, !isLoading else { return }
        let entries = list.map { entry(for: $0) } + closedProjects + retainedEntries
        let windows = Windows.list.map { window -> ProjectDiagnosticSnapshot.Window in
            let id = window.tracked.id
            let projectIds = list.filter { $0.isCustom && $0.members.contains(id) }.map(\.id).sorted()
            let candidates = owners(of: id).sorted()
            let status: String
            if !isEnabled { status = "projects-disabled" }
            else if window.isWindowlessApp || window.isPhantom { status = "ineligible-window" }
            else if declinedRestorations.contains(id) { status = "restoration-declined" }
            else if !projectIds.isEmpty { status = "assigned" }
            else if identityReads.contains(id) { status = "waiting-for-process-identity" }
            else if !ProjectBrowserURLs.isReady(window) { status = "waiting-for-browser-metadata" }
            else if candidates.count > 1 { status = "ambiguous-project-match" }
            else if candidates.isEmpty { status = "no-saved-project-match" }
            else { status = "match-not-restored-or-excluded" }
            return .init(id: id, pid: window.application.pid, bundleIdentifier: window.application.bundleIdentifier,
                title: window.title, spaceIds: window.spaceIds, isMinimized: window.isMinimized, isFullscreen: window.isFullscreen,
                position: window.position, size: window.size, projectIds: projectIds, candidateProjectIds: candidates,
                identity: windowIdentities[id], restorationStatus: status)
        }.sorted { $0.id < $1.id }
        let desktops = spaces.map { ProjectDiagnosticSnapshot.Desktop(spaceId: $0.spaceId, uuid: $0.uuid, number: $0.desktopNumber, isCurrent: $0.isCurrent) }
        ProjectPersistence.save(entries, windows: windows, desktops: desktops, activeId: active?.id)
    }

    private static func applyFileChanges(_ entries: [ProjectEntry]) {
        let activeId = active?.id
        let existing = byId
        load(entries)
        isLoading = true
        for index in list.indices {
            let loaded = list[index]
            guard let project = existing[loaded.id] else { continue }
            let previous = ProjectFileDocument.durable(entry(for: project))
            let rulesChanged = previous.memberPatterns != loaded.memberPatterns || previous.excludedPatterns != loaded.excludedPatterns
            project.kind = loaded.kind
            project.homeSpaceUuid = loaded.homeSpaceUuid
            project.name = loaded.name
            project.autoName = loaded.autoName
            project.windowHistory = loaded.windowHistory
            project.memberPatterns = loaded.memberPatterns
            project.excludedPatterns = loaded.excludedPatterns
            project.linkedProjectIds = loaded.linkedProjectIds
            project.labelUuid = loaded.labelUuid
            if rulesChanged {
                project.members = []
                project.memberIdentities = []
                project.excludedMembers = []
                project.excludedWindowIds = []
            }
            list[index] = project
            byId[project.id] = project
        }
        active = activeId.flatMap { byId[$0] }
        isLoading = false
        restoredWindows.removeAll()
        Windows.list.forEach { restoreMembership($0) }
        refreshSpaces()
        SpaceLabelWindows.refreshNames()
        ProjectLifecyclePrompt.refresh()
        ProjectVisibility.refresh()
        App.refreshOpenUiAfterExternalEvent([])
        ProjectPersistence.scheduleSnapshot()
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
