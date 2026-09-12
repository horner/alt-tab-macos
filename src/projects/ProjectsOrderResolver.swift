enum ProjectsOrderResolver {
    static func sorted(currentDesktopId: String?, linkedProjectId: String? = nil, customProjectIds: [String], mru: [String]) -> [String] {
        let rank = Dictionary(uniqueKeysWithValues: mru.enumerated().map { ($0.element, $0.offset) })
        let custom = customProjectIds.enumerated().sorted { lhs, rhs in
            let leftRank = rank[lhs.element] ?? Int.max
            let rightRank = rank[rhs.element] ?? Int.max
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map { $0.element }
        let hasLinkedProject = linkedProjectId.map { customProjectIds.contains($0) } ?? false
        let desktop = hasLinkedProject ? nil : currentDesktopId
        return (desktop.map { [$0] } ?? []) + custom
    }
}
