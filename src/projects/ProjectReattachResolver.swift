import Foundation

struct ProjectWindowPattern: Codable, Equatable {
    let bundleIdentifier: String
    let title: String
    var spaceUuid: String? = nil
    var lastSeenAt: Date? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.title == rhs.title && lhs.spaceUuid == rhs.spaceUuid
    }
}

enum ProjectReattachResolver {
    static func owners(of pattern: ProjectWindowPattern, assignments: [String: [ProjectWindowPattern]]) -> Set<String> {
        guard !pattern.bundleIdentifier.isEmpty else { return [] }
        let exact = assignments.mapValues { $0.filter { $0.bundleIdentifier == pattern.bundleIdentifier && $0.title == pattern.title && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        let exactOwners = Set(exact.compactMap { $0.value.isEmpty ? nil : $0.key })
        if exactOwners.count == 1 { return exactOwners }
        guard let space = pattern.spaceUuid else { return exactOwners }
        let candidates = exactOwners.isEmpty ? assignments : exact
        let spaceOwners = Set(candidates.compactMap { entry in
            entry.value.contains { $0.bundleIdentifier == pattern.bundleIdentifier && $0.spaceUuid == space } ? entry.key : nil
        })
        return spaceOwners.isEmpty ? exactOwners : spaceOwners
    }

    static func shouldRestore(hasLiveIdentity: Bool, identityExcluded: Bool, patternExcluded: Bool, isUniquePatternOwner: Bool) -> Bool {
        guard !identityExcluded else { return false }
        return hasLiveIdentity || (!patternExcluded && isUniquePatternOwner)
    }

    static func allowsActiveAssignment(isNew: Bool, applicationAge: TimeInterval, onCurrentDesktop: Bool, hasSavedOwner: Bool) -> Bool {
        isNew && applicationAge >= 30 && onCurrentDesktop && !hasSavedOwner
    }
}
