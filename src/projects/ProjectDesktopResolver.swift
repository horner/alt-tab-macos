import Foundation

enum ProjectDesktopResolver {
    struct Assignment: Equatable {
        let id: String
        var desktopUuid: String
    }

    static func assigning(_ projectId: String?, to desktopUuid: String, among assignments: [Assignment]) -> [Assignment] {
        guard !desktopUuid.isEmpty, projectId == nil || assignments.contains(where: { $0.id == projectId }) else { return assignments }
        return assignments.map { assignment in
            if assignment.id == projectId { return Assignment(id: assignment.id, desktopUuid: desktopUuid) }
            if assignment.desktopUuid == desktopUuid { return Assignment(id: assignment.id, desktopUuid: "") }
            return assignment
        }
    }

    static func selection(current: String?, customProjects: Set<String>, desktop: String?, linkedProjects: [String],
                          followsDesktop: Bool, changedDesktop: Bool) -> String? {
        if let current, customProjects.contains(current), !followsDesktop || !changedDesktop { return current }
        return followsDesktop ? linkedProjects.first ?? desktop : desktop
    }
}
