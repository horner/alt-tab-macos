import Foundation

enum ProjectDesktopResolver {
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
}
