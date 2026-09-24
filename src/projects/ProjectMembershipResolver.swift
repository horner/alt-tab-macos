enum ProjectMembershipResolver {
    static func activeMembers(isEnabled: Bool, activeIsCustom: Bool, members: Set<String>, unassignedOnDesktop: Set<String> = [], ownsCurrentDesktop: Bool = false) -> Set<String>? {
        guard isEnabled, activeIsCustom else { return nil }
        return ownsCurrentDesktop ? members.union(unassignedOnDesktop) : members
    }

    static func unassignedOnDesktop(spaceId: UInt64, windowSpaces: [String: [UInt64]], assigned: Set<String>) -> Set<String> {
        Set(windowSpaces.compactMap { id, spaces in
            !assigned.contains(id) && spaces.contains(spaceId) ? id : nil
        })
    }
}
