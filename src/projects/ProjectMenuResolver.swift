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

    static func currentWindow<T>(in windows: [T], isEligible: (T) -> Bool, isFocused: (T) -> Bool, focusOrder: (T) -> Int) -> T? {
        var recent: T?
        for window in windows where isEligible(window) {
            if isFocused(window) { return window }
            if recent.map({ focusOrder(window) < focusOrder($0) }) ?? true { recent = window }
        }
        return recent
    }

    static func liveTarget<T: AnyObject>(_ target: T?, in windows: [T], isEligible: (T) -> Bool) -> T? {
        guard let target, windows.contains(where: { $0 === target }), isEligible(target) else { return nil }
        return target
    }

    static func canMove(to projectId: String, memberships: Set<String>) -> Bool {
        memberships != [projectId]
    }
}
