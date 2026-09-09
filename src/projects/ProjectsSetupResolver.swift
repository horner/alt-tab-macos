import Foundation

enum ProjectsSetupResolver {
    struct Desktop {
        let uuid: String
        let hasLinkedProject: Bool
    }

    static var defaults: [String: String] {
        #if PROJECTS_DISTRIBUTION
        return defaults(distribution: true)
        #else
        return defaults(distribution: false)
        #endif
    }

    static func defaults(distribution: Bool) -> [String: String] {
        ["projectsEnabled": distribution ? "true" : "false",
         "spaceLabelRevealDuration": distribution ? "1500" : "0",
         "spaceLabelsOnLaunch": distribution ? "true" : "false",
         "projectsInitialSetupCompleted": "false"]
    }

    /// Nil defers setup; an empty plan completes it without replacing existing links.
    static func desktopsToLink(enabled: Bool, completed: Bool, desktops: [Desktop]) -> [String]? {
        guard enabled, !completed, !desktops.isEmpty else { return nil }
        return desktops.filter { !$0.hasLinkedProject }.map { $0.uuid }
    }
}
