import Foundation

enum ProjectLifecycleResolver {
    static func closed(_ entry: ProjectEntry) -> ProjectEntry {
        var result = entry
        result.isClosed = true
        result.pendingDesktopRemoval = false
        return result
    }

    static func reopened(_ entry: ProjectEntry, on desktop: String) -> ProjectEntry {
        var result = entry
        result.isClosed = false
        result.pendingDesktopRemoval = false
        result.homeSpaceUuid = desktop
        return result
    }

    static func canCombine(_ source: ProjectEntry, into destination: ProjectEntry) -> Bool {
        source.id != destination.id && source.kind == "custom" && destination.kind == "custom"
            && !source.isClosed && !destination.isClosed && source.homeSpaceUuid == destination.homeSpaceUuid
    }

    static func combined(_ source: ProjectEntry, into destination: ProjectEntry) -> ProjectEntry? {
        guard canCombine(source, into: destination) else { return nil }
        var result = destination
        result.members = union(destination.members, source.members)
        result.memberPatterns = patterns(destination.memberPatterns, source.memberPatterns)
        result.windowHistory = patterns(destination.windowHistory, source.windowHistory)
        result.excludedMembers = union(destination.excludedMembers, source.excludedMembers).filter { !result.members.contains($0) }
        result.excludedPatterns = patterns(destination.excludedPatterns, source.excludedPatterns).filter { excluded in
            !result.memberPatterns.contains {
                ProjectReattachResolver.matchesObservation(excluded, $0)
                    && (excluded.spaceUuid == nil || $0.spaceUuid == nil || excluded.spaceUuid == $0.spaceUuid)
            }
        }
        return result
    }

    private static func union<T: Equatable>(_ first: [T], _ second: [T]) -> [T] {
        second.reduce(into: first) { result, item in if !result.contains(item) { result.append(item) } }
    }

    private static func patterns(_ first: [ProjectWindowPattern], _ second: [ProjectWindowPattern]) -> [ProjectWindowPattern] {
        second.reduce(into: first) { result, item in
            guard let index = result.firstIndex(of: item) else { result.append(item); return }
            result[index].lastSeenAt = [result[index].lastSeenAt, item.lastSeenAt].compactMap { $0 }.max()
            result[index].confirmedAt = [result[index].confirmedAt, item.confirmedAt].compactMap { $0 }.max()
        }
    }
}
