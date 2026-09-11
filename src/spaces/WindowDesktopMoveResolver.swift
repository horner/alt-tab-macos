enum WindowDesktopMoveResolver {
    struct Destination: Equatable {
        let id: UInt64
        let uuid: String
    }

    static func canMove(isEligible: Bool, spaces: [UInt64], destination: Destination?, desktops: [UInt64: String]) -> Bool {
        guard isEligible, let destination, desktops[destination.id] == destination.uuid,
              spaces.count == 1, let source = spaces.first, desktops[source] != nil else { return false }
        return source != destination.id
    }

    static func confirmed(_ spaces: [UInt64], destination: Destination) -> Bool {
        spaces == [destination.id]
    }
}
