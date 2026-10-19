enum ProjectScopeResolver {
    struct Scope {
        let visibleOnly: Bool
        let nonVisibleOnly: Bool
        let screenOnly: Bool
        let spaceIds: [UInt64]
    }

    static func resolve(hasActiveProject: Bool, visibleOnly: Bool,
                        nonVisibleOnly: Bool, screenOnly: Bool, visibleSpaceIds: [UInt64]) -> Scope {
        guard hasActiveProject else {
            return Scope(visibleOnly: visibleOnly, nonVisibleOnly: nonVisibleOnly, screenOnly: screenOnly, spaceIds: visibleSpaceIds)
        }
        return Scope(visibleOnly: false, nonVisibleOnly: false, screenOnly: false, spaceIds: visibleSpaceIds)
    }
}
