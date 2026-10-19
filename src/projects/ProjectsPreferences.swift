import Foundation
import ShortcutRecorder

extension Preferences {
    static var projectsInitialSetupCompleted: Bool { UserDefaults.standard.bool(forKey: "projectsInitialSetupCompleted") }
    static var projectsEnabled: Bool { UserDefaults.standard.bool(forKey: "projectsEnabled") }
    static var projectsFollowDesktop: Bool { UserDefaults.standard.bool(forKey: "projectsFollowDesktop") }
    static var projectWindowsInSwitcher: Bool { UserDefaults.standard.bool(forKey: "projectWindowsInSwitcher") }
    static var spaceLabelRevealDuration: Int { SpaceLabelResolver.revealDuration(UserDefaults.standard.integer(forKey: "spaceLabelRevealDuration")) }
    static var projects: [ProjectEntry] { CachedUserDefaults.json("projects", [ProjectEntry].self) }
    static var projectsShortcutStyle: ShortcutStylePreference { CachedUserDefaults.macroPref("projectsShortcutStyle", ShortcutStylePreference.allCases) }
    static var projectsDefaultValues: [String: Any] {
        ["projectsFollowDesktop": "true",
         "projectsAutoMinimizedWindows": "[]", "projects": "[]", "projectWindowsInSwitcher": "true",
         ProjectSwitcher.holdShortcutId: defaultShortcut(""),
         ProjectSwitcher.nextShortcutId: defaultShortcut("⇥"),
         ProjectSwitcher.previousShortcutId: defaultShortcut("⇧"),
         "projectsShortcutStyle": ShortcutStylePreference.focusOnRelease.indexAsString]
            .merging(ProjectsSetupResolver.defaults) { _, value in value }
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
