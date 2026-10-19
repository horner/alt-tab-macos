enum ProjectMembershipResolver {
    static func activeMembers(isEnabled: Bool, activeIsCustom: Bool, members: Set<String>, currentDesktopWindows: Set<String> = []) -> Set<String>? {
        guard isEnabled, activeIsCustom else { return nil }
        return members.union(currentDesktopWindows)
    }

    static func onDesktop(spaceId: UInt64, windowSpaces: [String: [UInt64]]) -> Set<String> {
        Set(windowSpaces.compactMap { id, spaces in spaces.contains(spaceId) ? id : nil })
    }

    static func unassignedOnDesktop(spaceId: UInt64, windowSpaces: [String: [UInt64]], assigned: Set<String>) -> Set<String> {
        onDesktop(spaceId: spaceId, windowSpaces: windowSpaces).subtracting(assigned)
    }
}
