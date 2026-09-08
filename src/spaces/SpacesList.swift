import Cocoa

/// One row of the Spaces switcher. `spaceId` identifies a Space in this session; `uuid` identifies
/// its persistent Desktop record. The remaining fields are re-derived on each summon.
class SpaceItem {
    let spaceId: CGSSpaceID
    let uuid: String
    /// 1-based "Desktop N" as macOS numbers user Spaces, or 0 for a fullscreen Space. This is also the
    /// number the system's own "Switch to Desktop N" shortcut takes, which the Ctrl+N fallback relies on.
    let desktopNumber: Int
    let isCurrent: Bool
    private let fallbackLabel: String
    private(set) weak var previewWindow: Window?
    private(set) var previewIcon: NSImage?
    var label: String {
        guard let window = previewWindow else {
            let project = Projects.byId["desktop-\(uuid)"]
            return ProjectNameResolver.normalized(project?.name) ?? ProjectNameResolver.normalized(project?.autoName) ?? fallbackLabel
        }
        return ProjectNameResolver.normalized(window.title) ?? ProjectNameResolver.normalized(window.application.localizedName) ?? fallbackLabel
    }
    var subtitle: String? {
        let desktop = desktopNumber == 0 ? NSLocalizedString("Fullscreen", comment: "Spaces switcher tile label")
            : String(format: NSLocalizedString("Desktop %d", comment: "Spaces switcher tile label"), desktopNumber)
        let app = ProjectNameResolver.normalized(previewWindow?.application.localizedName)
        let name = ProjectNameResolver.normalized(Projects.byId["desktop-\(uuid)"]?.name)
        return [desktop, app, name == label || name == app ? nil : name].compactMap { $0 }.joined(separator: " · ")
    }

    init(spaceId: CGSSpaceID, uuid: String, desktopNumber: Int, isCurrent: Bool, label: String) {
        self.spaceId = spaceId
        self.uuid = uuid
        self.desktopNumber = desktopNumber
        self.isCurrent = isCurrent
        fallbackLabel = label
        previewWindow = mostRecentlyFocusedWindow()
        previewIcon = previewWindow?.icon.map { NSImage(cgImage: $0, size: .zero) }
    }

    var isFullscreen: Bool { desktopNumber == 0 }

    /// Focusing a window on the target Space is what actually moves the user there: macOS animates the
    /// Space switch as a side effect, and it is the only route that works for fullscreen Spaces.
    /// `CGSManagedDisplaySetCurrentSpace` would switch without a window, but it leaves the Dock and
    /// Mission Control's own idea of the current Space stale, so it is deliberately not used.
    func activate() {
        SpacesList.noteVisited(spaceId)
        if let window = mostRecentlyFocusedWindow() {
            window.focus()
            return
        }
        activateViaSystemShortcut()
    }

    /// An empty Desktop has no window to focus. The system's "Switch to Desktop N" shortcut is the only
    /// public way there; it is off by default past Desktop 2 in System Settings, so this can silently do
    /// nothing — hence it is the fallback, not the primary route.
    private func activateViaSystemShortcut() {
        guard let keyCode = Self.digitKeyCodes[desktopNumber] else { return }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func mostRecentlyFocusedWindow() -> Window? {
        Windows.list
            .filter { $0.spaceIds.contains(spaceId) && !$0.isWindowlessApp && !$0.isMinimized && !$0.isHidden && !$0.isPhantom && !$0.isTabbed }
            .min { $0.lastFocusOrder < $1.lastFocusOrder }
    }

    /// ANSI digit key codes, which are not contiguous (6 and 7 are swapped relative to their digits).
    private static let digitKeyCodes: [Int: CGKeyCode] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19,
    ]
}

/// The Spaces switcher's model: enumerate the Spaces the WindowServer reports, order them, and hold the
/// highlight. Ordering and selection arithmetic live in `SpacesOrderResolver`; this is the adapter that
/// reads SkyLight and keeps the visit history.
class SpacesList {
    static private(set) var list = [SpaceItem]()
    static var selectedIndex = 0
    /// Most-recently-visited first. Seeded by `startObservingSpaceChanges` and by every activation we
    /// perform ourselves, so `.recentlyFocused` still orders correctly when the user changes Space by
    /// other means (Mission Control, Ctrl+arrow, clicking a Dock item).
    private static var mru = [CGSSpaceID]()

    static var selected: SpaceItem? {
        selectedIndex >= 0 && selectedIndex < list.count ? list[selectedIndex] : nil
    }

    static func noteVisited(_ spaceId: CGSSpaceID) {
        mru.removeAll { $0 == spaceId }
        mru.insert(spaceId, at: 0)
    }

    /// `NSWorkspace` posts this after the transition completes, at which point `Spaces.currentSpaceId` has
    /// been refreshed by the WindowServer event path. Observing beats polling and costs nothing while idle.
    static func startObservingSpaceChanges() {
        noteVisited(Spaces.currentSpaceId)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Spaces.refresh()
            noteVisited(Spaces.currentSpaceId)
        }
    }

    static func refresh() {
        Spaces.refresh()
        noteVisited(Spaces.currentSpaceId)
        let items = enumerate()
        let ordered = SpacesOrderResolver.sorted(
            items.map { SpacesOrderResolver.Space(id: $0.0.spaceId, desktopNumber: $0.0.desktopNumber, enumerationRank: $0.1) },
            mru: mru, by: Preferences.spacesOrder)
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.0.spaceId, $0.0) })
        list = ordered.compactMap { byId[$0.id] }
        selectedIndex = SpacesOrderResolver.initialSelection(
            count: list.count, currentIndex: list.firstIndex { $0.isCurrent })
    }

    static func cycle(_ step: Int) {
        selectedIndex = SpacesOrderResolver.cycle(selected: selectedIndex, step: step, count: list.count)
    }

    /// Returns each Space paired with its rank in the WindowServer's display-then-Space walk.
    /// `CGSCopyManagedDisplaySpaces`' per-Space `"type"` is 0 for a user Desktop and 4 for a fullscreen
    /// Space; reading it here avoids declaring a `CGSSpaceGetType` private symbol for one call site.
    static func enumerate(includeFullscreen: Bool = false) -> [(SpaceItem, Int)] {
        let raw = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as! [NSDictionary]
        let currentSpaceId = Spaces.currentSpaceId
        var result = [(SpaceItem, Int)]()
        var rank = 0
        var desktopNumber = 0
        for display in raw {
            for space in display["Spaces"] as! [NSDictionary] {
                defer { rank += 1 }
                let spaceId = space["id64"] as! CGSSpaceID
                let uuid = space["uuid"] as! String
                Logger.debug { "Space UUID: id64=\(spaceId) uuid=\(uuid)" }
                let isFullscreen = (space["type"] as? Int ?? 0) != 0
                if !isFullscreen { desktopNumber += 1 }
                guard includeFullscreen || !isFullscreen || Preferences.showFullscreenSpaces else { continue }
                let item = SpaceItem(
                    spaceId: spaceId,
                    uuid: uuid,
                    desktopNumber: isFullscreen ? 0 : desktopNumber,
                    isCurrent: spaceId == currentSpaceId,
                    label: label(spaceId, isFullscreen ? 0 : desktopNumber))
                result.append((item, rank))
            }
        }
        return result
    }

    private static func label(_ spaceId: CGSSpaceID, _ desktopNumber: Int) -> String {
        guard desktopNumber == 0 else {
            return String(format: NSLocalizedString("Desktop %d", comment: "Spaces switcher tile label"), desktopNumber)
        }
        let appName = Windows.list.first { $0.spaceIds.contains(spaceId) }?.application.localizedName
        return appName ?? NSLocalizedString("Fullscreen", comment: "Spaces switcher tile label")
    }
}
