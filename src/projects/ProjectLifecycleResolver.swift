import Foundation

enum ProjectLifecycleResolver {
    static func repairingUnlinkedProjects(_ entries: [ProjectEntry]) -> [ProjectEntry] {
        var result = entries
        let linkedIds = Set(entries.flatMap { $0.linkedProjectIds })
        for index in result.indices where result[index].kind == "desktop" {
            result[index].autoName = nil
            guard let uuid = result[index].spaceUuid, result[index].linkedProjectIds.isEmpty else { continue }
            let candidates = entries.indices.filter { entries[$0].kind == "custom" && !entries[$0].isClosed
                && entries[$0].homeSpaceUuid == uuid && !linkedIds.contains(entries[$0].id) }
            // A label identity survives explicit unlinking; only repair a sole Project that has never claimed a Desktop.
            guard candidates.count == 1, let projectIndex = candidates.first, entries[projectIndex].labelUuid == nil else { continue }
            let id = entries[projectIndex].id
            result[index].linkedProjectIds = [id]
            result[index].linkedProjectId = id
            result[projectIndex].labelUuid = entries.contains { $0.labelUuid == uuid } ? id : uuid
        }
        return result
    }

    static func repairingEmptyDesktopAliases(_ entries: [ProjectEntry]) -> [ProjectEntry] {
        var result = entries
        for alias in entries where isEmptyDesktopAlias(alias) {
            let candidates = result.indices.filter { result[$0].kind == "custom" && result[$0].id != alias.id
                && result[$0].labelUuid == alias.labelUuid && result[$0].name == alias.name && result[$0].autoName == alias.autoName }
            guard candidates.count == 1, let index = candidates.first else { continue }
            if alias.isClosed {
                result[index] = closed(result[index])
                result[index].closedWindows = result[index].closedWindows ?? alias.closedWindows
            }
            let canonical = result[index]
            result.removeAll { $0.id == alias.id }
            for index in result.indices {
                result[index].linkedProjectIds = union([], result[index].linkedProjectIds.compactMap { id in
                    if id == alias.id || id == canonical.id { return canonical.isClosed ? nil : canonical.id }
                    return id
                })
                result[index].linkedProjectId = result[index].linkedProjectIds.first
            }
        }
        return result
    }

    private static func isEmptyDesktopAlias(_ entry: ProjectEntry) -> Bool {
        guard let label = entry.labelUuid, entry.id == "desktop-" + label, entry.kind == "custom" else { return false }
        return entry.members.isEmpty && entry.memberPatterns.isEmpty && entry.windowHistory.isEmpty
            && entry.excludedMembers.isEmpty && entry.excludedPatterns.isEmpty && (entry.closedWindows ?? []).isEmpty
            && entry.linkedProjectIds.isEmpty && entry.iconFileName == nil
    }

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
        result.windowHistory = patterns(result.windowHistory, entry.closedWindows ?? [])
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
