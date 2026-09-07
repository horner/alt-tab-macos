import Foundation

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
    var name: String?
    var autoName: String?
    var members = Set<String>()
    var iconSource = IconSource.mostRecent

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
    static var active: Project?
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "projectsEnabled") }

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
    }

    static func add(windowId: String, to project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        project.members.insert(windowId)
    }

    static func remove(windowId: String, from project: Project) {
        guard isEnabled, project.isCustom, byId[project.id] === project else { return }
        project.members.remove(windowId)
    }

    @discardableResult
    private static func insert(_ project: Project) -> Project {
        list.append(project)
        byId[project.id] = project
        return project
    }
}
