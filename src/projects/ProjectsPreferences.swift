import Foundation
import ShortcutRecorder

extension Preferences {
    static var projectsEnabled: Bool { UserDefaults.standard.bool(forKey: "projectsEnabled") }
    static var projects: [ProjectEntry] { CachedUserDefaults.json("projects", [ProjectEntry].self) }
    static var projectsShortcutStyle: ShortcutStylePreference { CachedUserDefaults.macroPref("projectsShortcutStyle", ShortcutStylePreference.allCases) }
    static var projectsDefaultValues: [String: Any] {
        ["projectsEnabled": "false", "projects": "[]",
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

    init(id: String, kind: String, spaceUuid: String?, homeSpaceUuid: String, name: String?, autoName: String?, iconFileName: String? = nil, members: [ProjectWindowIdentity] = []) {
        self.id = id
        self.kind = kind
        self.spaceUuid = spaceUuid
        self.homeSpaceUuid = homeSpaceUuid
        self.name = name
        self.autoName = autoName
        self.iconFileName = iconFileName
        self.members = members
    }

    /// Optional or newly added fields must not make CachedUserDefaults reset the entire collection.
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        spaceUuid = try? c?.decode(String.self, forKey: .spaceUuid)
        id = (try? c?.decode(String.self, forKey: .id)) ?? spaceUuid.map { "desktop-\($0)" } ?? UUID().uuidString
        kind = (try? c?.decode(String.self, forKey: .kind)) ?? (spaceUuid == nil ? "custom" : "desktop")
        homeSpaceUuid = (try? c?.decode(String.self, forKey: .homeSpaceUuid)) ?? spaceUuid ?? ""
        name = try? c?.decode(String.self, forKey: .name)
        autoName = try? c?.decode(String.self, forKey: .autoName)
        iconFileName = try? c?.decode(String.self, forKey: .iconFileName)
        members = (try? c?.decode([ProjectWindowIdentity].self, forKey: .members)) ?? []
    }
}
