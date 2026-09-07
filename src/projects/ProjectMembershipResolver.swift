enum ProjectMembershipResolver {
    static func activeMembers(isEnabled: Bool, activeIsCustom: Bool, members: Set<String>) -> Set<String>? {
        guard isEnabled, activeIsCustom else { return nil }
        return members
    }
}
