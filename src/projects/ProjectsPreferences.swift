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
         "projectsAutoMinimizedWindows": "[]", "projects": "[]", "projectWindowsInSwitcher": "true", "spaceLabelRevealDuration": String(SpaceLabelResolver.defaultRevealDuration),
         ProjectSwitcher.holdShortcutId: defaultShortcut(""),
         ProjectSwitcher.nextShortcutId: defaultShortcut("⇥"),
         ProjectSwitcher.previousShortcutId: defaultShortcut("⇧"),
         "projectsShortcutStyle": ShortcutStylePreference.focusOnRelease.indexAsString]
    }
}

/// Product policy is installed before preference registration and license initialization.
enum ProjectsStartup {
    private(set) static var isEnabled = false

    static func configure() {
        guard App.name == "AltTabProjects", !isEnabled else { return }
        isEnabled = true
        Preferences.defaultValues.merge([
            "holdShortcut": Preferences.defaultShortcut("⌘"),
            "holdShortcut2": Preferences.defaultShortcut("⌘"),
            "nextWindowShortcut": Preferences.defaultShortcut("⇥"),
            "appsToShow": AppsToShowPreference.all.indexAsString,
            "spacesToShow": SpacesToShowPreference.visible.indexAsString,
            "screensToShow": ScreensToShowPreference.showingAltTab.indexAsString,
            "showMinimizedWindows": ShowHowPreference.show.indexAsString,
            "projectsEnabled": "true",
            ProjectSwitcher.holdShortcutId: Preferences.defaultShortcut("⌥"),
        ]) { _, value in value }
        LicenseManager.shared.stateOverride = .pro
    }
}
