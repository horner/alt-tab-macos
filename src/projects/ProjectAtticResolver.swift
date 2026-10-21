import Foundation

enum ProjectAtticResolver {
    struct Page {
        let key: String
        let pattern: ProjectWindowPattern
        let wasOpen: Bool
    }

    static func pageKey(_ pattern: ProjectWindowPattern) -> String? {
        guard ProjectBrowserURLResolver.supports(pattern.bundleIdentifier),
              let url = ProjectBrowserURLResolver.normalized(pattern.url) else { return nil }
        var normalized = pattern
        normalized.url = url
        guard ProjectReattachResolver.evidence(normalized) != nil else { return nil }
        return pattern.bundleIdentifier + "\u{0}" + url
    }

    static func pages(in entry: ProjectEntry) -> [Page] {
        let open = Set((entry.closedWindows ?? []).compactMap { pageKey($0) })
        var latest = [String: ProjectWindowPattern]()
        for pattern in entry.windowHistory + entry.memberPatterns + (entry.closedWindows ?? []) {
            guard let key = pageKey(pattern) else { continue }
            if let previous = latest[key], (previous.lastSeenAt ?? .distantPast) > (pattern.lastSeenAt ?? .distantPast) { continue }
            var normalized = pattern
            normalized.url = ProjectBrowserURLResolver.normalized(pattern.url)
            latest[key] = normalized
        }
        return latest.map { Page(key: $0.key, pattern: $0.value, wasOpen: open.contains($0.key)) }.sorted {
            if $0.wasOpen != $1.wasOpen { return $0.wasOpen }
            let first = $0.pattern.lastSeenAt ?? .distantPast
            let second = $1.pattern.lastSeenAt ?? .distantPast
            return first != second ? first > second : $0.key < $1.key
        }
    }

    static func pagesToOpen(in entry: ProjectEntry, selected: Set<String>, alreadyOpen: Set<String>) -> [ProjectWindowPattern] {
        pages(in: entry).filter { selected.contains($0.key) && !alreadyOpen.contains($0.key) }.map { $0.pattern }
    }

    static func canBringBack(_ identity: ProjectWindowIdentity?, from entry: ProjectEntry, hasOwner: Bool) -> Bool {
        guard let identity, !hasOwner else { return false }
        return entry.members.contains(identity) && !entry.excludedMembers.contains(identity)
    }
}
