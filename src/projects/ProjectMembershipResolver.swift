enum ProjectMembershipResolver {
    static func activeMembers(isEnabled: Bool, activeIsCustom: Bool, members: Set<String>, unassignedOnDesktop: Set<String> = []) -> Set<String>? {
        guard isEnabled, activeIsCustom else { return nil }
        return members.union(unassignedOnDesktop)
    }

    static func unassignedOnDesktop(spaceId: UInt64, windowSpaces: [String: [UInt64]], assigned: Set<String>) -> Set<String> {
        Set(windowSpaces.compactMap { id, spaces in
            !assigned.contains(id) && spaces.contains(spaceId) ? id : nil
        })
    }
}
