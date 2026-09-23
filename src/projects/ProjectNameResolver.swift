import Foundation

enum ProjectNameResolver {
    static func resolved(name: String?, autoName: String?, desktopNumber: Int?, projectNumber: Int) -> String {
        if let name = normalized(name) { return name }
        if let desktopNumber {
            return String(format: NSLocalizedString("Desktop %d", comment: "Spaces switcher tile label"), desktopNumber)
        }
        if let name = normalized(autoName) { return name }
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

    static func folderName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let slug = String(parts.joined(separator: "-").prefix(60))
        return slug.isEmpty ? "project" : slug
    }

    static func validationError(_ name: String?, existing: [String]) -> String? {
        guard let name = normalized(name) else { return NSLocalizedString("Enter a project name.", comment: "Project name validation") }
        guard !existing.contains(where: { folderName($0) == folderName(name) }) else {
            return NSLocalizedString("Another project already uses this name or folder name. Choose a different name.", comment: "Duplicate project name validation")
        }
        return nil
    }

    static func available(_ proposed: String, existing: [String]) -> String {
        let name = normalized(proposed) ?? "Project"
        let occupied = Set(existing.map(folderName))
        guard occupied.contains(folderName(name)) else { return name }
        let stem = String(name.prefix(50))
        var number = 2
        while occupied.contains(folderName("\(stem) \(number)")) { number += 1 }
        return "\(stem) \(number)"
    }
}
