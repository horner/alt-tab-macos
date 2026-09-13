import Foundation
import ShortcutRecorder

extension Preferences {
    static var projectsEnabled: Bool { UserDefaults.standard.bool(forKey: "projectsEnabled") }
    static var projectsCurrentSpaceOnly: Bool { UserDefaults.standard.bool(forKey: "projectsCurrentSpaceOnly") }
    static var projectsFollowDesktop: Bool { UserDefaults.standard.bool(forKey: "projectsFollowDesktop") }
    static var projectsMinimizeInactive: Bool { UserDefaults.standard.bool(forKey: "projectsMinimizeInactive") }
    static var projectWindowsInSwitcher: Bool { UserDefaults.standard.bool(forKey: "projectWindowsInSwitcher") }
    static var spaceLabelRevealDuration: Int { SpaceLabelResolver.revealDuration(UserDefaults.standard.integer(forKey: "spaceLabelRevealDuration")) }
    static var projects: [ProjectEntry] { CachedUserDefaults.json("projects", [ProjectEntry].self) }
    static var projectsShortcutStyle: ShortcutStylePreference { CachedUserDefaults.macroPref("projectsShortcutStyle", ShortcutStylePreference.allCases) }
    static var projectsDefaultValues: [String: Any] {
        ["projectsCurrentSpaceOnly": "false", "projectsEnabled": "false", "projectsFollowDesktop": "true", "projectsMinimizeInactive": "false",
         "projectsAutoMinimizedWindows": "[]", "projects": "[]", "projectWindowsInSwitcher": "false", "spaceLabelRevealDuration": String(SpaceLabelResolver.defaultRevealDuration),
         ProjectSwitcher.holdShortcutId: defaultShortcut(""),
         ProjectSwitcher.nextShortcutId: defaultShortcut("⇥"),
         ProjectSwitcher.previousShortcutId: defaultShortcut("⇧"),
         "projectsShortcutStyle": ShortcutStylePreference.focusOnRelease.indexAsString]
    }
}
