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
        active = spaces.first { $0.isCurrent }.map { forSpace(uuid: $0.uuid) }
    }

    static var activeMembers: Set<String>? {
        guard isEnabled, let project = active else { return nil }
        return ProjectMembershipResolver.activeMembers(isEnabled: true, activeIsCustom: project.isCustom, members: project.members)
    }

    /// Discovery applies the real Space after appendWindow, in the same main-queue turn.
    static func windowAdded(_ window: Window) {
        DispatchQueue.main.async { [weak window] in
            guard let window, !window.isWindowlessApp, Windows.list.contains(where: { $0 === window }) else { return }
            restoreMembership(window)
            for space in spaces where window.spaceIds.contains(space.spaceId) {
                claimName(window.application.localizedName, for: forSpace(uuid: space.uuid))
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
                    if project.memberIdentities.contains(identity) { project.members.insert(identity.windowId) }
                    if project.members.contains(identity.windowId), !project.memberIdentities.contains(identity) {
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
        ids.forEach { windowIdentities.removeValue(forKey: $0) }
        var changed = false
        let spaceIds = Set(windows.filter { !$0.isWindowlessApp }.flatMap { $0.spaceIds })
        for project in list {
            if project.isCustom {
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

    static func delete(id: String) {
        guard let project = byId[id], project.isCustom else { return }
        if active === project { active = nil }
        byId.removeValue(forKey: id)
        list.removeAll { $0.id == id }
        iconFileNames.removeValue(forKey: id)
        save()
    }

    static func add(windowId: String, to project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        project.members.insert(windowId)
        if let identity = windowIdentities[windowId], !project.memberIdentities.contains(identity) { project.memberIdentities.append(identity) }
        save()
    }

    static func remove(windowId: String, from project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
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
            project.memberIdentities = entry.members
            project.name = entry.name
            project.autoName = entry.autoName
            iconFileNames[project.id] = entry.iconFileName
            insert(project)
        }
    }

    static func save() {
        guard !isLoading else { return }
        let entries = list.map { project -> ProjectEntry in
            let uuid: String?
            if case .desktop(let spaceUuid) = project.kind { uuid = spaceUuid } else { uuid = nil }
            return ProjectEntry(id: project.id, kind: project.isCustom ? "custom" : "desktop", spaceUuid: uuid,
                homeSpaceUuid: project.homeSpaceUuid, name: project.name, autoName: project.autoName,
                iconFileName: iconFileNames[project.id], members: project.memberIdentities)
        }
        Preferences.set("projects", entries + retainedEntries, false)
    }

    @discardableResult
    private static func insert(_ project: Project) -> Project {
        list.append(project)
        byId[project.id] = project
        save()
        return project
    }
}
