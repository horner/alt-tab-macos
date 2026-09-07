import Foundation

extension Preferences {
    static var projectsEnabled: Bool { UserDefaults.standard.bool(forKey: "projectsEnabled") }
    static var projectsDefaultValues: [String: Any] { ["projectsEnabled": "false"] }
}
