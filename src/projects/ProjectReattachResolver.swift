import Foundation

struct ProjectWindowPattern: Codable, Equatable {
    let bundleIdentifier: String
    let title: String
    var spaceUuid: String? = nil
    var lastSeenAt: Date? = nil
    var url: String? = nil
    var confirmedAt: Date? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.title == rhs.title && lhs.spaceUuid == rhs.spaceUuid && lhs.url == rhs.url
    }
}

enum ProjectReattachResolver {
    private static let titleTrimming = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
    private static let browserSuffixes = [" — safari", " - safari", " — google chrome", " - google chrome"]
    private static let placeholderTitles: Set<String> = ["", "start page", "new tab", "new window", "untitled", "loading", "safari", "google chrome", "chrome", "visual studio code", "visual studio code - insiders", "sign in", "signin", "log in", "login", "error", "about:blank"]
    private static let transientURLSegments: Set<String> = ["login", "signin", "sign-in", "sign_in", "oauth", "oauth2", "authorize", "sso", "error"]

    static func hasUsefulTitle(_ raw: String) -> Bool {
        var title = raw.lowercased().trimmingCharacters(in: titleTrimming)
        for suffix in browserSuffixes where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count)).trimmingCharacters(in: titleTrimming)
        }
        return !placeholderTitles.contains(title) && !title.hasPrefix("untitled ") && !title.hasPrefix("loading ")
    }

    static func evidence(_ pattern: ProjectWindowPattern) -> ProjectWindowPattern? {
        guard !pattern.bundleIdentifier.isEmpty else { return nil }
        var result = pattern
        if let raw = pattern.url {
            guard let url = URLComponents(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            guard !url.path.lowercased().split(separator: "/").contains(where: { transientURLSegments.contains(String($0)) }) else { return nil }
        }
        if !hasUsefulTitle(result.title) { result = ProjectWindowPattern(bundleIdentifier: result.bundleIdentifier, title: "", spaceUuid: result.spaceUuid, lastSeenAt: result.lastSeenAt, url: result.url, confirmedAt: result.confirmedAt) }
        return result.url != nil || !result.title.isEmpty ? result : nil
    }

    static func owners(of pattern: ProjectWindowPattern, assignments: [String: [ProjectWindowPattern]]) -> Set<String> {
        guard let pattern = evidence(pattern) else { return [] }
        let assignments = assignments.mapValues { $0.filter { $0.bundleIdentifier == pattern.bundleIdentifier }.compactMap { evidence($0) } }
        let urlMatches = assignments.mapValues { $0.filter { $0.bundleIdentifier == pattern.bundleIdentifier && pattern.url != nil && $0.url == pattern.url } }
        if urlMatches.values.contains(where: { !$0.isEmpty }) { return disambiguate(urlMatches, on: pattern.spaceUuid) }
        let exact = assignments.mapValues { $0.filter { $0.bundleIdentifier == pattern.bundleIdentifier && $0.title == pattern.title && (pattern.url == nil || $0.url == nil || $0.url == pattern.url) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        return disambiguate(exact, on: pattern.spaceUuid)
    }

    private static func disambiguate(_ candidates: [String: [ProjectWindowPattern]], on space: String?) -> Set<String> {
        let owners = Set(candidates.compactMap { $0.value.isEmpty ? nil : $0.key })
        guard owners.count > 1 else { return owners }
        let local = space.map { space in Set(candidates.compactMap { entry in entry.value.contains { $0.spaceUuid == space } ? entry.key : nil }) } ?? []
        let remaining = local.isEmpty ? owners : local
        let confirmed = Set(candidates.compactMap { entry in
            remaining.contains(entry.key) && entry.value.contains { $0.confirmedAt != nil && (local.isEmpty || $0.spaceUuid == space) } ? entry.key : nil
        })
        return confirmed.count == 1 ? confirmed : remaining
    }

    static func matchesObservation(_ saved: ProjectWindowPattern, _ current: ProjectWindowPattern) -> Bool {
        guard saved.bundleIdentifier == current.bundleIdentifier else { return false }
        if let url = saved.url, let currentURL = current.url { return url == currentURL }
        return saved.title == current.title
    }

    static func sameEvidence(_ saved: ProjectWindowPattern, _ current: ProjectWindowPattern) -> Bool {
        guard let saved = evidence(saved), let current = evidence(current), saved.spaceUuid == current.spaceUuid else { return false }
        return matchesObservation(saved, current) && (saved.url == nil) == (current.url == nil)
    }

    static func shouldRestore(hasLiveIdentity: Bool, identityExcluded: Bool, patternExcluded: Bool, isUniquePatternOwner: Bool) -> Bool {
        guard !identityExcluded else { return false }
        return hasLiveIdentity || (!patternExcluded && isUniquePatternOwner)
    }

    static func restorationCandidates(liveOwners: Set<String>, identityOwners: Set<String>, savedOwners: Set<String>, declined: Bool) -> Set<String> {
        guard liveOwners.isEmpty else { return [] }
        if !identityOwners.isEmpty { return identityOwners }
        return !declined && savedOwners.count == 1 ? savedOwners : []
    }

    static func allowsActiveAssignment(isNew: Bool, applicationAge: TimeInterval, onCurrentDesktop: Bool) -> Bool {
        isNew && applicationAge >= 30 && onCurrentDesktop
    }

    static func allowsAutomaticAssignment(to projectId: String, savedOwners: Set<String>, liveOwners: Set<String>) -> Bool {
        guard liveOwners.isEmpty || liveOwners == [projectId] else { return false }
        return savedOwners.isEmpty || savedOwners == [projectId]
    }
}
