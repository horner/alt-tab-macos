enum ProjectMenuResolver {
    struct Context: Equatable {
        let projectId: String?
        let desktopUuid: String?
        let fromLabel: Bool
    }

    static func context(labelId: String?, desktopUuid: String?, activeProjectId: String?,
                        currentDesktopUuid: String?, projectLabels: [String: String]) -> Context {
        guard let labelId else {
            return Context(projectId: activeProjectId, desktopUuid: currentDesktopUuid, fromLabel: false)
        }
        return Context(projectId: projectLabels[labelId], desktopUuid: desktopUuid, fromLabel: true)
    }

    static func canAssign(isWindowless: Bool, isPhantom: Bool, isTabbed: Bool, labelVisibility: Bool?) -> Bool {
        !isWindowless && !isPhantom && !isTabbed && labelVisibility == nil
    }
}
