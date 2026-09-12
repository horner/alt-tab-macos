import Cocoa

struct ProjectTileItem: GridTileItem {
    let project: Project
    let desktopNumber: Int
    var label: String { project.isCustom ? project.resolvedName : String(format: NSLocalizedString("Desktop %d", comment: ""), desktopNumber) }
    var icon: NSImage? { NSImage(named: project.isCustom ? NSImage.folderName : NSImage.computerName) }
    var isCurrent: Bool { project === Projects.active }
}

final class ProjectsPanel: GridPanel {
    static let shared = ProjectsPanel()
}
