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
    let kind: Kind
    let homeSpaceUuid: String
    var name: String? { didSet { if name != oldValue { Projects.save() } } }
    var autoName: String? { didSet { if autoName != oldValue { Projects.save() } } }
    var members = Set<String>()
    var memberIdentities = [ProjectWindowIdentity]()
    var memberPatterns = [ProjectWindowPattern]()
    var excludedPatterns = [ProjectWindowPattern]()
    var excludedMembers = [ProjectWindowIdentity]()
    var excludedWindowIds = Set<String>()
    var linkedProjectId: String?
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

    static func startObservingSpaceChanges() {
        guard spaceObserver == nil else { return }
        Logger.debug { "projects startup enabled=\(isEnabled)" }
        let savedActiveId = UserDefaults.standard.string(forKey: "projectsActiveId")
        load()
        refreshSpaces()
        if isEnabled, let id = savedActiveId, let project = byId[id], project.isCustom { active = project }
        Windows.list.forEach { restoreMembership($0) }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Spaces.refresh()
            refreshSpaces()
        }
    }

    private static func refreshSpaces() {
        spaces = SpacesList.enumerate(includeFullscreen: true).map { $0.0 }
        let previousCount = list.count
        isLoading = true
        spaces.forEach { _ = forSpace(uuid: $0.uuid) }
        isLoading = false
        if list.count != previousCount { save() }
        if isEnabled {
            for desktop in list where !desktop.isCustom {
                if let project = linkedProject(for: desktop) { captureDesktopWindows(desktop, into: project) }
            }
        }
        if isEnabled, !Preferences.projectsFollowDesktop, let active, active.isCustom, byId[active.id] === active { return }
        active = spaces.first { $0.isCurrent }.map { space in
            let desktop = forSpace(uuid: space.uuid)
            return isEnabled && Preferences.projectsFollowDesktop ? linkedProject(for: desktop) ?? desktop : desktop
        }
    }

    static var activeMembers: Set<String>? {
        guard isEnabled, let project = active else { return nil }
        return ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: project.isCustom, members: project.members)
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
            restoreMembership(window)
            if !window.isPhantom, let project = creationProject, project.isCustom {
                Logger.debug { "projects auto-add source=window-created project=\(project.id) window=\(window.tracked.id)" }
                addAutomatically(windowId: window.tracked.id, to: project)
            } else {
                Logger.debug { "projects auto-add skipped window=\(window.tracked.id) new=\(isNew) target=\(creationProject?.id ?? "none") phantom=\(window.isPhantom)" }
            }
            for space in spaces where window.spaceIds.contains(space.spaceId) {
                let desktop = forSpace(uuid: space.uuid)
                claimName(window.application.localizedName, for: desktop)
                if isEnabled, !window.isPhantom, let project = linkedProject(for: desktop) { addAutomatically(windowId: window.tracked.id, to: project) }
            }
            if isEnabled, let project = active, project.isCustom {
                claimName(window.application.localizedName, for: project)
            }
        }
    }

    private static func restoreMembership(_ window: Window) {
        guard !window.isWindowlessApp else { return }
        let application = window.application.runningApplication
        DispatchQueue.global(qos: .utility).async { [weak window] in
            let launchDate = application.launchDate
            DispatchQueue.main.async {
                guard let window, let launchDate, Windows.list.contains(where: { $0 === window }) else { return }
                let identity = ProjectWindowIdentity(windowId: window.tracked.id, pid: window.application.pid, processLaunchedAt: launchDate)
                windowIdentities[identity.windowId] = identity
                var changed = false
                for project in list where project.isCustom {
                    if project.excludedMembers.contains(identity) { project.excludedWindowIds.insert(identity.windowId) }
                    if project.excludedWindowIds.contains(identity.windowId), !project.excludedMembers.contains(identity) {
                        project.excludedMembers.append(identity)
                        changed = true
                    }
                    if project.memberIdentities.contains(identity) {
                        project.members.insert(identity.windowId)
                        Logger.debug { "projects restored project=\(project.id) window=\(identity.windowId) pid=\(identity.pid)" }
                    }
                    if project.members.contains(identity.windowId), !project.memberIdentities.contains(identity) {
                        Logger.debug { "projects identity saved project=\(project.id) window=\(identity.windowId)" }
                        project.memberIdentities.append(identity)
                        changed = true
                    }
                }
                if changed { save() }
            }
        }
    }

    private static func claimName(_ appName: String?, for project: Project) {
        project.autoName = ProjectNameResolver.claim(name: project.name, autoName: project.autoName, appName: appName)
    }

    static func windowsRemoved(_ windows: [Window]) {
        let ids = Set(windows.map { $0.tracked.id })
        Logger.debug { "projects tracking removal windows=\(ids.sorted())" }
        ids.forEach { windowIdentities.removeValue(forKey: $0) }
        var changed = false
        let spaceIds = Set(windows.filter { !$0.isWindowlessApp }.flatMap { $0.spaceIds })
        for project in list {
            project.excludedWindowIds.subtract(ids)
            if project.isCustom {
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
        guard !desktop.isCustom, let id = desktop.linkedProjectId, let project = byId[id], project.isCustom else { return nil }
        return project
    }

    @discardableResult
    static func link(_ desktop: Project, to project: Project?) -> Bool {
        guard !desktop.isCustom, byId[desktop.id] === desktop else { return false }
        if let project {
            guard isEnabled, project.isCustom, byId[project.id] === project,
                  !list.contains(where: { $0 !== desktop && $0.linkedProjectId == project.id }) else { return false }
        }
        if project == nil, desktop.linkedProjectId == nil { return true }
        Logger.debug { "projects link desktop=\(desktop.id) previous=\(desktop.linkedProjectId ?? "none") next=\(project?.id ?? "none")" }
        desktop.linkedProjectId = project?.id
        if let project { captureDesktopWindows(desktop, into: project) }
        if spaces.contains(where: { $0.isCurrent && $0.uuid == desktop.homeSpaceUuid }) { active = project ?? desktop }
        save()
        return true
    }

    private static func captureDesktopWindows(_ desktop: Project, into project: Project) {
        guard let space = spaces.first(where: { $0.uuid == desktop.homeSpaceUuid }) else { return }
        var changed = false
        for window in Windows.list where !window.isWindowlessApp && !window.isPhantom && window.spaceIds.contains(space.spaceId) {
            if !isExcluded(window.tracked.id, from: project), insertMember(window.tracked.id, into: project) { changed = true }
        }
        if changed { save() }
    }

    static func delete(id: String) {
        guard let project = byId[id], project.isCustom else { return }
        for desktop in list where desktop.linkedProjectId == id { desktop.linkedProjectId = nil }
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
        if let pattern = pattern(for: windowId) { project.excludedPatterns.removeAll { $0 == pattern } }
        let inserted = insertMember(windowId, into: project)
        if inserted || wasExcluded { save() }
    }

    private static func isExcluded(_ windowId: String, from project: Project) -> Bool {
        if project.excludedWindowIds.contains(windowId) { return true }
        if let identity = windowIdentities[windowId] { return project.excludedMembers.contains(identity) }
        // Defer auto-capture until launch-time identity validation can distinguish a reused window ID.
        return project.excludedMembers.contains { $0.windowId == windowId }
    }

    private static func addAutomatically(windowId: String, to project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project, !isExcluded(windowId, from: project) else { return }
        if insertMember(windowId, into: project) { save() }
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
        guard let window = Windows.list.first(where: { $0.tracked.id == windowId }),
              let bundle = window.application.bundleIdentifier, !bundle.isEmpty,
              !window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ProjectWindowPattern(bundleIdentifier: bundle, title: window.title)
    }

    @discardableResult
    private static func rememberPattern(_ windowId: String, in project: Project) -> Bool {
        guard let pattern = pattern(for: windowId), !project.memberPatterns.contains(pattern) else { return false }
        project.memberPatterns.append(pattern)
        return true
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
            project.memberPatterns.removeAll { $0 == pattern }
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
            project.memberPatterns = entry.memberPatterns
            project.excludedPatterns = entry.excludedPatterns
            project.memberIdentities = entry.members
            project.excludedMembers = entry.excludedMembers
            project.linkedProjectId = entry.linkedProjectId
            project.name = entry.name
            project.autoName = entry.autoName
            iconFileNames[project.id] = entry.iconFileName
            insert(project)
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
                memberPatterns: project.memberPatterns, excludedPatterns: project.excludedPatterns)
        }
        Preferences.set("projects", entries + retainedEntries, false)
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
