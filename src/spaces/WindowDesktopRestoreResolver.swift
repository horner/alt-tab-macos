enum WindowDesktopRestoreResolver {
    typealias Destination = WindowDesktopMoveResolver.Destination

    enum Decision: Equatable {
        case move(Destination), alreadyHome, unassigned, conflictingProjects, missingDesktop, unsupported
    }

    struct Detail: Equatable {
        let windowName: String
        let reason: String
        var windowId: String? = nil
    }

    struct Summary {
        var moved = 0
        var alreadyHome = 0
        var unassigned = 0
        var conflictingProjects = 0
        var missingDesktop = 0
        var unsupported = 0
        var failed = 0
        var details = [Detail]()

        var skipped: Int { unassigned + conflictingProjects + missingDesktop + unsupported }

        mutating func record(_ decision: Decision, detail: Detail? = nil) {
            switch decision {
            case .move: return
            case .alreadyHome: alreadyHome += 1; return
            case .unassigned: unassigned += 1
            case .conflictingProjects: conflictingProjects += 1
            case .missingDesktop: missingDesktop += 1
            case .unsupported: unsupported += 1
            }
            if let detail { details.append(detail) }
        }

        mutating func fail(windowName: String, reason: String, windowId: String? = nil) {
            failed += 1
            details.append(Detail(windowName: windowName, reason: reason, windowId: windowId))
        }
    }

    static func decision(isEligible: Bool, spaces: [UInt64], projectHomes: [String], desktops: [UInt64: String]) -> Decision {
        guard !projectHomes.isEmpty else { return .unassigned }
        let homes = Set(projectHomes)
        guard homes.count == 1, let home = homes.first else { return .conflictingProjects }
        guard let desktop = desktops.first(where: { $0.value == home }) else { return .missingDesktop }
        guard isEligible, spaces.count == 1, let source = spaces.first, desktops[source] != nil else { return .unsupported }
        let destination = Destination(id: desktop.key, uuid: desktop.value)
        return source == destination.id ? .alreadyHome : .move(destination)
    }
}
