import Foundation

struct ProjectWindowPattern: Codable, Equatable {
    let bundleIdentifier: String
    let title: String
}

enum ProjectReattachResolver {
    static func owners(of pattern: ProjectWindowPattern, assignments: [String: [ProjectWindowPattern]]) -> Set<String> {
        guard !pattern.bundleIdentifier.isEmpty, !pattern.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return Set(assignments.compactMap { $0.value.contains(pattern) ? $0.key : nil })
    }

    static func shouldRestore(hasLiveIdentity: Bool, identityExcluded: Bool, patternExcluded: Bool, isUniquePatternOwner: Bool) -> Bool {
        guard !identityExcluded else { return false }
        return hasLiveIdentity || (!patternExcluded && isUniquePatternOwner)
    }

    static func allowsActiveAssignment(isNew: Bool, applicationAge: TimeInterval, onCurrentDesktop: Bool, hasSavedOwner: Bool) -> Bool {
        isNew && applicationAge >= 30 && onCurrentDesktop && !hasSavedOwner
    }
}
