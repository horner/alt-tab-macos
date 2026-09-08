import Foundation
import ShortcutRecorder

extension Preferences {
    static var projectsEnabled: Bool { UserDefaults.standard.bool(forKey: "projectsEnabled") }
    static var projectsCurrentSpaceOnly: Bool { UserDefaults.standard.bool(forKey: "projectsCurrentSpaceOnly") }
    static var projectsFollowDesktop: Bool { UserDefaults.standard.bool(forKey: "projectsFollowDesktop") }
    static var projects: [ProjectEntry] { CachedUserDefaults.json("projects", [ProjectEntry].self) }
    static var projectsShortcutStyle: ShortcutStylePreference { CachedUserDefaults.macroPref("projectsShortcutStyle", ShortcutStylePreference.allCases) }
    static var projectsDefaultValues: [String: Any] {
        ["projectsCurrentSpaceOnly": "false", "projectsEnabled": "false", "projectsFollowDesktop": "false", "projects": "[]",
         ProjectSwitcher.holdShortcutId: defaultShortcut(""),
         ProjectSwitcher.nextShortcutId: defaultShortcut("⇥"),
         ProjectSwitcher.previousShortcutId: defaultShortcut("⇧"),
         "projectsShortcutStyle": ShortcutStylePreference.focusOnRelease.indexAsString]
    }
}

struct ProjectEntry: Codable {
    var id: String
    var kind: String
    var spaceUuid: String?
    var homeSpaceUuid: String
    var name: String?
    var autoName: String?
    var iconFileName: String?
    var members: [ProjectWindowIdentity]
    var excludedMembers: [ProjectWindowIdentity]
    var memberPatterns = [ProjectWindowPattern]()
    var excludedPatterns = [ProjectWindowPattern]()
    var linkedProjectId: String?

    init(id: String, kind: String, spaceUuid: String?, homeSpaceUuid: String, name: String?, autoName: String?, iconFileName: String? = nil, members: [ProjectWindowIdentity] = [], linkedProjectId: String? = nil, excludedMembers: [ProjectWindowIdentity] = [], memberPatterns: [ProjectWindowPattern] = [], excludedPatterns: [ProjectWindowPattern] = []) {
        self.memberPatterns = memberPatterns
        self.excludedPatterns = excludedPatterns
        self.id = id
        self.kind = kind
        self.spaceUuid = spaceUuid
        self.homeSpaceUuid = homeSpaceUuid
        self.name = name
        self.autoName = autoName
        self.iconFileName = iconFileName
        self.members = members
        self.linkedProjectId = linkedProjectId
        self.excludedMembers = excludedMembers
    }

    /// Optional or newly added fields must not make CachedUserDefaults reset the entire collection.
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        memberPatterns = (try? c?.decode([ProjectWindowPattern].self, forKey: .memberPatterns)) ?? []
        excludedPatterns = (try? c?.decode([ProjectWindowPattern].self, forKey: .excludedPatterns)) ?? []
        spaceUuid = try? c?.decode(String.self, forKey: .spaceUuid)
        id = (try? c?.decode(String.self, forKey: .id)) ?? spaceUuid.map { "desktop-\($0)" } ?? UUID().uuidString
        kind = (try? c?.decode(String.self, forKey: .kind)) ?? (spaceUuid == nil ? "custom" : "desktop")
        homeSpaceUuid = (try? c?.decode(String.self, forKey: .homeSpaceUuid)) ?? spaceUuid ?? ""
        name = try? c?.decode(String.self, forKey: .name)
        autoName = try? c?.decode(String.self, forKey: .autoName)
        iconFileName = try? c?.decode(String.self, forKey: .iconFileName)
        members = (try? c?.decode([ProjectWindowIdentity].self, forKey: .members)) ?? []
        excludedMembers = (try? c?.decode([ProjectWindowIdentity].self, forKey: .excludedMembers)) ?? []
        linkedProjectId = try? c?.decode(String.self, forKey: .linkedProjectId)
    }
}
