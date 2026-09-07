import Foundation

enum ProjectNameResolver {
    static func resolved(name: String?, autoName: String?, desktopNumber: Int?, projectNumber: Int) -> String {
        if let name = normalized(name) { return name }
        if let autoName = normalized(autoName) { return autoName }
        if let desktopNumber {
            return String(format: NSLocalizedString("Desktop %d", comment: "Spaces switcher tile label"), desktopNumber)
        }
        return String(format: NSLocalizedString("Project %d", comment: "Unnamed custom Project"), projectNumber)
    }

    static func claim(name: String?, autoName: String?, appName: String?) -> String? {
        guard normalized(name) == nil, normalized(autoName) == nil else { return autoName }
        return normalized(appName)
    }

    static func forget(autoName: String?, hasLiveWindows: Bool) -> String? {
        hasLiveWindows ? autoName : nil
    }

    static func normalized(_ name: String?) -> String? {
        guard let value = name?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
