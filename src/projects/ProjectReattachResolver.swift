import Foundation

struct ProjectWindowPattern: Codable, Equatable {
    let bundleIdentifier: String
    let title: String
    var spaceUuid: String? = nil
    var lastSeenAt: Date? = nil
    var url: String? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.title == rhs.title && lhs.spaceUuid == rhs.spaceUuid && lhs.url == rhs.url
    }
}

enum ProjectReattachResolver {
    static func owners(of pattern: ProjectWindowPattern, assignments: [String: [ProjectWindowPattern]]) -> Set<String> {
        guard !pattern.bundleIdentifier.isEmpty else { return [] }
        let urlMatches = assignments.mapValues { $0.filter { $0.bundleIdentifier == pattern.bundleIdentifier && pattern.url != nil && $0.url == pattern.url } }
        if urlMatches.values.contains(where: { !$0.isEmpty }) { return disambiguate(urlMatches, on: pattern.spaceUuid) }
        let exact = assignments.mapValues { $0.filter { $0.bundleIdentifier == pattern.bundleIdentifier && $0.title == pattern.title && (pattern.url == nil || $0.url == nil || $0.url == pattern.url) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        let exactOwners = Set(exact.compactMap { $0.value.isEmpty ? nil : $0.key })
        if exactOwners.count == 1 { return exactOwners }
        guard let space = pattern.spaceUuid else { return exactOwners }
        let candidates = exactOwners.isEmpty ? assignments : exact
        let spaceOwners = Set(candidates.compactMap { entry in
            entry.value.contains { $0.bundleIdentifier == pattern.bundleIdentifier && $0.spaceUuid == space } ? entry.key : nil
        })
        return spaceOwners.isEmpty ? exactOwners : spaceOwners
    }

    private static func disambiguate(_ candidates: [String: [ProjectWindowPattern]], on space: String?) -> Set<String> {
        let owners = Set(candidates.compactMap { $0.value.isEmpty ? nil : $0.key })
        guard owners.count > 1, let space else { return owners }
        let local = Set(candidates.compactMap { entry in entry.value.contains { $0.spaceUuid == space } ? entry.key : nil })
        return local.isEmpty ? owners : local
    }

    static func matchesObservation(_ saved: ProjectWindowPattern, _ current: ProjectWindowPattern) -> Bool {
        guard saved.bundleIdentifier == current.bundleIdentifier else { return false }
        if let url = saved.url, let currentURL = current.url { return url == currentURL }
        return saved.title == current.title
    }

    static func shouldRestore(hasLiveIdentity: Bool, identityExcluded: Bool, patternExcluded: Bool, isUniquePatternOwner: Bool) -> Bool {
        guard !identityExcluded else { return false }
        return hasLiveIdentity || (!patternExcluded && isUniquePatternOwner)
    }

    static func allowsActiveAssignment(isNew: Bool, applicationAge: TimeInterval, onCurrentDesktop: Bool, hasSavedOwner: Bool) -> Bool {
        isNew && applicationAge >= 30 && onCurrentDesktop && !hasSavedOwner
    }

    static func allowsAutomaticAssignment(to projectId: String, savedOwners: Set<String>, liveOwners: Set<String>) -> Bool {
        guard liveOwners.isEmpty || liveOwners == [projectId] else { return false }
        return savedOwners.isEmpty || savedOwners.contains(projectId)
    }
}
