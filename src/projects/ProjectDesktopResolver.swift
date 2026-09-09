import Foundation

enum ProjectDesktopResolver {
    struct LabelLocation {
        let labelId: String
        let sourceUuid: String
        let spaceIds: [UInt64]
    }

    static func relocation(_ location: LabelLocation, in current: [SpaceLabelResolver.Space]) -> SpaceLabelResolver.Space? {
        guard current.contains(where: { $0.uuid == location.sourceUuid && $0.desktopNumber > 0 }),
              Set(location.spaceIds).count == 1, let id = location.spaceIds.first,
              let destination = current.first(where: { $0.id == id && $0.desktopNumber > 0 }),
              destination.uuid != location.sourceUuid else { return nil }
        return destination
    }

    static func destination(for removed: SpaceLabelResolver.Space, previous: [SpaceLabelResolver.Space],
                            current: [SpaceLabelResolver.Space], labelSpaces: [UInt64], memberSpaces: [UInt64]) -> String? {
        guard removed.desktopNumber > 0, !current.contains(where: { $0.uuid == removed.uuid }) else { return nil }
        let candidates = current.filter { $0.displayIdentifier == removed.displayIdentifier && $0.desktopNumber > 0 }
        guard !candidates.isEmpty else { return nil }
        for observations in [labelSpaces, memberSpaces] {
            let counts = candidates.map { space in (space, observations.filter { $0 == space.id }.count) }
            let maximum = counts.map { $0.1 }.max() ?? 0
            let best = counts.filter { $0.1 == maximum }
            if maximum > 0, best.count == 1 { return best[0].0.uuid }
        }
        let surviving = previous.filter { old in candidates.contains { $0.uuid == old.uuid } }
        return surviving.last { $0.ordinal < removed.ordinal }?.uuid
            ?? surviving.first { $0.ordinal > removed.ordinal }?.uuid ?? candidates.first?.uuid
    }

    static func merge(resident: [String], incoming: [String]) -> [String] {
        var seen = Set<String>()
        return (resident + incoming).filter { seen.insert($0).inserted }
    }

    static func linkOrder(existing: [String], selected: [String]) -> [String] {
        let selectedIds = Set(selected)
        return merge(resident: existing.filter { selectedIds.contains($0) }, incoming: selected)
    }

    static func selection(current: String?, customProjects: Set<String>, desktop: String?, linkedProjects: [String],
                          followsDesktop: Bool, changedDesktop: Bool) -> String? {
        if let current, customProjects.contains(current), !followsDesktop || !changedDesktop { return current }
        return followsDesktop ? linkedProjects.first ?? desktop : desktop
    }
}
