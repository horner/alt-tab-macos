import Foundation

enum DesktopNavigationResolver {
    struct Destination: Equatable {
        let spaceUuid: String
        let projectId: String?
        let windowId: String?
    }

    struct History {
        private(set) var previous: Destination?
        private var pending: (destination: Destination, expiresAt: TimeInterval)?

        mutating func beginReturn(_ destination: Destination, now: TimeInterval) {
            pending = (destination, now + 3)
        }

        mutating func entered(_ spaceUuid: String, leaving origin: Destination?, now: TimeInterval) -> Destination? {
            guard let origin, origin.spaceUuid != spaceUuid else { return nil }
            previous = origin
            let restoration = pending
            pending = nil
            guard let restoration, restoration.destination.spaceUuid == spaceUuid, now <= restoration.expiresAt else { return nil }
            return restoration.destination
        }

        func target(currentSpaceUuid: String?, availableSpaceUuids: Set<String>) -> Destination? {
            guard let previous, let currentSpaceUuid, previous.spaceUuid != currentSpaceUuid,
                  availableSpaceUuids.contains(previous.spaceUuid) else { return nil }
            return previous
        }
    }

    static func destinationSpace(windowSpaces: [UInt64], currentSpace: UInt64, visibleSpaces: [UInt64],
                                 availableSpaces: [UInt64], isWindowlessApp: Bool) -> UInt64? {
        guard !isWindowlessApp, !windowSpaces.contains(currentSpace),
              !windowSpaces.contains(where: { visibleSpaces.contains($0) }) else { return nil }
        return availableSpaces.first { windowSpaces.contains($0) }
    }

    enum CycleDecision: Equatable {
        case windows
        case stay
        case back
        case window(Int)
    }

    static func cycle(step: Int, visibleIndices: [Int], selectedIndex: Int, returnSelected: Bool,
                      hasDestination: Bool, isSearching: Bool, allowWrap: Bool, isRepeating: Bool) -> CycleDecision {
        guard hasDestination, !isSearching, step == 1 || step == -1 else { return .windows }
        guard allowWrap else { return returnSelected ? .stay : .windows }
        guard let first = visibleIndices.first, let last = visibleIndices.last else { return .back }
        if returnSelected {
            return step < 0 ? .window(last) : (isRepeating ? .stay : .window(first))
        }
        if selectedIndex == last && step > 0 { return .back }
        if selectedIndex == first && step < 0 { return isRepeating ? .stay : .back }
        return .windows
    }

    static func isUndoShortcut(characters: String?, hasCommand: Bool, hasOtherModifiers: Bool, isSearchEditing: Bool) -> Bool {
        characters?.lowercased() == "z" && hasCommand && !hasOtherModifiers && !isSearchEditing
    }

    struct SystemShortcut: Equatable {
        let keyCode: UInt16
        let modifiers: UInt64
    }

    static func systemShortcut(desktopNumber: Int, hotKeys: [String: Any]) -> SystemShortcut? {
        guard desktopNumber > 0 else { return nil }
        // Observed in com.apple.symbolichotkeys: Desktop 1/2 use IDs 118/119, with key code and NSEvent flags in parameters 1/2.
        if let record = hotKeys[String(117 + desktopNumber)] as? [String: Any] {
            guard record["enabled"] as? Bool == true, let value = record["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count == 3,
                  let keyCode = UInt16(exactly: parameters[1]), keyCode != UInt16.max, parameters[2] >= 0 else { return nil }
            return SystemShortcut(keyCode: keyCode, modifiers: UInt64(parameters[2]))
        }
        let digitKeys: [Int: UInt16] = [1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19]
        return digitKeys[desktopNumber].map { SystemShortcut(keyCode: $0, modifiers: 1 << 18) }
    }
}
