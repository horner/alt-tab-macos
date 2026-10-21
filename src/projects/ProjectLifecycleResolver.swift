import Foundation

enum ProjectLifecycleResolver {
    static func normalizingDesktopOwnership(_ entries: [ProjectEntry]) -> [ProjectEntry] {
        var result = entries
        let projects = entries.indices.filter { entries[$0].kind == "custom" }.sorted { entries[$0].id < entries[$1].id }
        let desktops = entries.indices.filter { entries[$0].kind == "desktop" }.sorted {
            [entries[$0].spaceUuid ?? "", entries[$0].id].lexicographicallyPrecedes([entries[$1].spaceUuid ?? "", entries[$1].id])
        }
        var assignments = [String: String]()
        var occupied = Set<String>()
        var linked = Set<String>()
        for index in projects where entries[index].desktopOwnershipVersion == 1 && !entries[index].isClosed {
            claim(entries[index], desktop: entries[index].homeSpaceUuid, assignments: &assignments, occupied: &occupied)
        }
        for index in desktops where entries[index].desktopOwnershipVersion == nil {
            guard let uuid = entries[index].spaceUuid, !uuid.isEmpty else { continue }
            let candidates = entries[index].linkedProjectIds.compactMap { id in
                projects.first { entries[$0].id == id && entries[$0].desktopOwnershipVersion == nil && !entries[$0].isClosed }
            }
            linked.formUnion(candidates.map { entries[$0].id })
            for candidate in candidates {
                claim(entries[candidate], desktop: uuid, assignments: &assignments, occupied: &occupied)
            }
        }
        for index in projects where entries[index].desktopOwnershipVersion == nil && !entries[index].isClosed && !linked.contains(entries[index].id) {
            claim(entries[index], desktop: entries[index].homeSpaceUuid, assignments: &assignments, occupied: &occupied)
        }
        for index in projects {
            result[index].homeSpaceUuid = assignments[entries[index].id] ?? ""
            result[index].desktopOwnershipVersion = 1
            result[index].linkedProjectIds = []
            result[index].linkedProjectId = nil
            if result[index].isClosed { result[index].pendingDesktopRemoval = false }
        }
        for index in desktops {
            let desktop = entries[index]
            if desktop.desktopOwnershipVersion == nil, let uuid = desktop.spaceUuid, !occupied.contains(uuid),
               let project = preservedDesktopProject(desktop, among: result) {
                result.append(project)
                if !project.homeSpaceUuid.isEmpty { occupied.insert(project.homeSpaceUuid) }
            }
            result[index].name = nil
            result[index].autoName = nil
            result[index].linkedProjectIds = []
            result[index].linkedProjectId = nil
            result[index].desktopOwnershipVersion = 1
        }
        return result
    }

    private static func claim(_ project: ProjectEntry, desktop: String, assignments: inout [String: String], occupied: inout Set<String>) {
        guard !desktop.isEmpty, assignments[project.id] == nil, occupied.insert(desktop).inserted else { return }
        assignments[project.id] = desktop
    }

    private static func preservedDesktopProject(_ desktop: ProjectEntry, among entries: [ProjectEntry]) -> ProjectEntry? {
        guard let uuid = desktop.spaceUuid, !uuid.isEmpty,
              let name = ProjectNameResolver.normalized(desktop.name) ?? ProjectNameResolver.normalized(desktop.autoName) else { return nil }
        guard !entries.contains(where: { $0.kind == "custom" && desktop.linkedProjectIds.contains($0.id) }) else { return nil }
        let label = desktop.labelUuid ?? uuid
        guard !entries.contains(where: { $0.kind == "custom" && $0.labelUuid == label
            && $0.name == desktop.name && $0.autoName == desktop.autoName }) else { return nil }
        let baseId = "project-desktop-" + uuid
        var id = baseId
        var suffix = 2
        while entries.contains(where: { $0.id == id }) { id = baseId + "-\(suffix)"; suffix += 1 }
        var project = desktop
        project.id = id
        project.kind = "custom"
        project.spaceUuid = nil
        project.homeSpaceUuid = desktop.isClosed ? "" : uuid
        project.name = ProjectNameResolver.available(name, existing: entries.filter { $0.kind == "custom" }.compactMap(\.name))
        project.labelUuid = label
        project.linkedProjectIds = []
        project.linkedProjectId = nil
        project.pendingDesktopRemoval = false
        project.desktopOwnershipVersion = 1
        return project
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
        result.homeSpaceUuid = ""
        result.desktopOwnershipVersion = 1
        result.pendingDesktopRemoval = false
        return result
    }

    static func reopened(_ entry: ProjectEntry, on desktop: String) -> ProjectEntry {
        var result = entry
        result.isClosed = false
        result.pendingDesktopRemoval = false
        result.homeSpaceUuid = desktop
        result.desktopOwnershipVersion = 1
        result.windowHistory = patterns(result.windowHistory, entry.closedWindows ?? [])
        return result
    }

    static func canCombine(_ source: ProjectEntry, into destination: ProjectEntry) -> Bool {
        source.id != destination.id && source.kind == "custom" && destination.kind == "custom"
            && !source.isClosed && !destination.isClosed && !source.homeSpaceUuid.isEmpty && source.homeSpaceUuid == destination.homeSpaceUuid
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
