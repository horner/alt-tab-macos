import Foundation

enum SpaceLabelResolver {
    static let defaultRevealDuration = 1500

    static func switcherVisibility(windowId: UInt32?, pid: Int32, ownerPid: Int32,
                                   labelWindowIds: Set<UInt32>, showInSwitcher: Bool) -> Bool? {
        guard pid == ownerPid, let windowId, windowId != 0, labelWindowIds.contains(windowId) else { return nil }
        return showInSwitcher
    }

    enum Presentation {
        case front, back, minimized
    }

    struct Visibility {
        var isRequested: Bool { allRequested || !requestedLabels.isEmpty }
        private(set) var presentation = Presentation.back
        private(set) var presentationRevision = 0
        private var allRequested = false
        private var requestedLabels = Set<String>()
        private var closedSpaces = Set<String>()

        mutating func showAll() {
            allRequested = true
            requestedLabels.removeAll()
            closedSpaces.removeAll()
            bringToFront()
        }

        mutating func show(_ labels: Set<String>) {
            requestedLabels.formUnion(labels)
            closedSpaces.subtract(labels)
        }

        mutating func bringToFront() {
            guard isRequested else { return }
            presentation = .front
            presentationRevision += 1
        }

        mutating func minimizeAll() {
            guard isRequested else { return }
            presentation = .minimized
            presentationRevision += 1
        }

        mutating func sendToBack(after revision: Int) -> Bool {
            guard isRequested, presentation == .front, presentationRevision == revision else { return false }
            presentation = .back
            presentationRevision += 1
            return true
        }

        mutating func close(_ uuid: String) {
            requestedLabels.remove(uuid)
            closedSpaces.insert(uuid)
        }

        mutating func hideAll() {
            allRequested = false
            requestedLabels.removeAll()
            closedSpaces.removeAll()
            presentation = .back
            presentationRevision += 1
        }

        func includes(_ uuid: String) -> Bool {
            (allRequested || requestedLabels.contains(uuid)) && !closedSpaces.contains(uuid)
        }
    }

    struct Space: Equatable {
        let id: UInt64
        let uuid: String
        let displayIdentifier: String
        let desktopNumber: Int
        let ordinal: Int
    }

    struct Name {
        let explicit: String?
        let automatic: String?
    }

    struct Position: Codable, Equatable {
        let displayIdentifier: String
        let x: CGFloat
        let y: CGFloat
    }

    struct Arrival {
        private var visible = [String: UInt64]()

        mutating func update(_ current: [String: UInt64], didSwitch: Bool) -> Set<UInt64> {
            let destinations = current.filter { display, space in
                visible[display].map { $0 != space } ?? false
            }
            // Dock topology updates can precede the workspace arrival notification.
            visible = didSwitch ? current : Dictionary(uniqueKeysWithValues: current.map { ($0.key, visible[$0.key] ?? $0.value) })
            return didSwitch ? Set(destinations.values) : []
        }
    }

    struct Reveal {
        private(set) var revision = 0
        private(set) var targets = Set<String>()

        mutating func start(_ spaces: Set<String>, duration: Int) {
            cancel()
            if revealDuration(duration) > 0 { targets = spaces }
        }

        mutating func cancel() {
            revision += 1
            targets.removeAll()
        }

        @discardableResult
        mutating func finish(_ uuid: String, after requestedRevision: Int) -> Bool {
            guard revision == requestedRevision else { return false }
            return targets.remove(uuid) != nil
        }
    }

    static func revealDuration(_ milliseconds: Int) -> Int {
        min(3000, max(0, milliseconds))
    }

    static func visibleSpaces(from displays: [NSDictionary]) -> [String: UInt64]? {
        var result = [String: UInt64]()
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  result[identifier] == nil,
                  let current = display["Current Space"] as? NSDictionary,
                  let id = current["id64"] as? UInt64, id > 0 else { return nil }
            result[identifier] = id
        }
        return result
    }

    struct Label: Equatable {
        let space: Space
        let name: String?
        var identity: String? = nil
        var stackIndex = 0
        var id: String { identity ?? space.uuid }
        var number: Int { space.desktopNumber > 0 ? space.desktopNumber : space.ordinal }
        var isFullscreen: Bool { space.desktopNumber == 0 }
    }

    /// A partial topology is not evidence that the missing Spaces were deleted.
    static func spaces(from displays: [NSDictionary]) -> [Space]? {
        var result = [Space]()
        var seen = Set<String>()
        var desktopNumber = 0
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let spaces = display["Spaces"] as? [NSDictionary] else { return nil }
            for space in spaces {
                guard let id = space["id64"] as? UInt64, id > 0,
                      let uuid = space["uuid"] as? String, !uuid.isEmpty,
                      let type = space["type"] as? Int, seen.insert(uuid).inserted else { return nil }
                if type == 0 { desktopNumber += 1 }
                result.append(Space(id: id, uuid: uuid, displayIdentifier: identifier,
                    desktopNumber: type == 0 ? desktopNumber : 0, ordinal: result.count + 1))
            }
        }
        return result
    }

    static func labels(spaces: [Space], names: [String: Name], enabled: Bool) -> [Label] {
        guard enabled else { return [] }
        return spaces.map { space in
            let name = names[space.uuid]
            return Label(space: space, name: normalized(name?.explicit) ?? normalized(name?.automatic))
        }
    }

    static func frame(visibleFrame: CGRect, height: CGFloat, position: Position? = nil, stackIndex: Int = 0) -> CGRect {
        // Match AppKit's whole-point frame rounding so unchanged labels do not resize on every refresh.
        let size = CGSize(width: (visibleFrame.width / 2).rounded(), height: min(visibleFrame.height, height.rounded(.up)))
        let saved = position.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        let x = saved.map { visibleFrame.minX + $0.x } ?? (visibleFrame.maxX - size.width - 24)
        let y = saved.map { visibleFrame.minY + $0.y } ?? (visibleFrame.minY + 24 + CGFloat(stackIndex) * (size.height + 12))
        return CGRect(x: min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width).rounded(.down),
            y: min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height).rounded(.down), width: size.width, height: size.height)
    }

    static func avoidingOverlap(_ frame: CGRect, in visibleFrame: CGRect, occupied: [CGRect]) -> CGRect {
        guard occupied.contains(where: { $0.intersects(frame) }) else { return frame }
        let ys = ([visibleFrame.minY + 24] + occupied.map { $0.maxY + 12 }).sorted()
        for x in [frame.minX, visibleFrame.minX] {
            for y in ys {
                let candidate = CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
                if visibleFrame.contains(candidate), !occupied.contains(where: { $0.intersects(candidate) }) { return candidate }
            }
        }
        return CGRect(x: max(visibleFrame.minX, frame.minX - CGFloat(occupied.count) * 24),
            y: min(visibleFrame.maxY - frame.height, visibleFrame.minY + CGFloat(occupied.count) * 32), width: frame.width, height: frame.height)
    }

    private static func normalized(_ name: String?) -> String? {
        guard let value = name?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
