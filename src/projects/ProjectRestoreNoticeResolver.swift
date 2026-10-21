enum ProjectRestoreNoticeResolver {
    struct Placement: Equatable {
        let projectId: String
        let spaces: [UInt64]
        let destination: WindowDesktopMoveResolver.Destination
    }

    static func placement(isEligible: Bool, spaces: [UInt64], projectHomes: [String: String], desktops: [UInt64: String]) -> Placement? {
        guard projectHomes.count == 1, let project = projectHomes.first,
              case .move(let destination) = WindowDesktopRestoreResolver.decision(isEligible: isEligible,
                  spaces: spaces, projectHomes: [project.value], desktops: desktops) else { return nil }
        return Placement(projectId: project.key, spaces: spaces, destination: destination)
    }
}
