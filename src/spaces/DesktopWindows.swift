import Cocoa

/// Ordered, transparent windows remain focus targets even when the user hides or minimizes labels.
/// AppKit ownership and focus are confined to main; Space membership uses the CGS scheduler.
enum DesktopWindows {
    private final class Anchor: NSWindow {
        var spaceId: UInt64?
        var assigning = false
        var retired = false
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2), styleMask: .borderless, backing: .buffered, defer: false)
            backgroundColor = .clear
            isOpaque = false
            hasShadow = false
            ignoresMouseEvents = true
            isReleasedWhenClosed = false
            hidesOnDeactivate = false
            isExcludedFromWindowsMenu = true
            // Managed transparent windows produce blank Exposé entries; only navigation temporarily opts in.
            collectionBehavior = [.stationary, .ignoresCycle]
            setAccessibilitySubrole(.floatingWindow)
        }
    }

    private static var anchors = [String: Anchor]()
    private static var ids = Set<CGWindowID>()
    private static var activation = DesktopNavigationResolver.AnchorActivation()
    private static var watchdog: DispatchWorkItem?
    static var activationRevision: Int { activation.revision }

    static func contains(_ id: CGWindowID?) -> Bool { id.map { ids.contains($0) } ?? false }

    static func reconcile(_ spaces: [SpaceLabelResolver.Space], visibleSpaceIds: Set<UInt64>?, observedActivationRevision: Int) {
        let desktops = spaces.filter { $0.desktopNumber > 0 }
        settle(activation.retain(availableSpaceIds: Set(desktops.map { $0.id })))
        let live = Set(desktops.map { $0.uuid })
        for uuid in Array(anchors.keys) where !live.contains(uuid) {
            guard let anchor = anchors.removeValue(forKey: uuid) else { continue }
            anchor.retired = true
            ids.remove(CGWindowID(anchor.windowNumber))
            anchor.orderOut(nil)
            if !anchor.assigning { anchor.close() }
        }
        for desktop in desktops {
            let anchor = anchors[desktop.uuid] ?? Anchor()
            anchors[desktop.uuid] = anchor
            guard !anchor.assigning, anchor.spaceId != desktop.id else { continue }
            anchor.assigning = true
            anchor.spaceId = nil
            anchor.orderBack(nil)
            let wid = CGWindowID(anchor.windowNumber)
            ids.insert(wid)
            SpaceLabelWindow.assign(wid, to: desktop.id) { success in
                anchor.assigning = false
                guard !anchor.retired else { anchor.close(); return }
                if success { anchor.spaceId = desktop.id }
            }
        }
        if let visibleSpaceIds { settle(activation.confirmed(visibleSpaceIds: visibleSpaceIds, observedRevision: observedActivationRevision)) }
    }

    static func activate(_ space: SpaceItem) -> Bool {
        guard let anchor = anchors[space.uuid], !anchor.assigning, anchor.spaceId == space.spaceId else { return false }
        FocusIntents.shared.supersede()
        watchdog?.cancel()
        let previous = activation.begin(space.spaceId)
        let revision = activation.revision
        normalize(previous)
        guard activation.revision == revision else { return true }
        anchor.collectionBehavior = [.managed, .ignoresCycle]
        guard activation.revision == revision else { return true }
        // macOS 26.5 probe: making the destination key and ordered before activation switches Spaces;
        // making it key without ordering returned success from SLPS but did not switch.
        anchor.makeKeyAndOrderFront(nil)
        guard activation.revision == revision else { return true }
        App.shared.activate(ignoringOtherApps: true)
        guard activation.revision == revision else { return true }
        let timeout = DispatchWorkItem { settle(activation.expire(revision: revision)) }
        watchdog = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        SpaceLabelWindows.refreshTopology()
        return true
    }

    private static func settle(_ spaceId: UInt64?) {
        guard let spaceId else { return }
        watchdog?.cancel()
        watchdog = nil
        normalize(spaceId)
    }

    private static func normalize(_ spaceId: UInt64?) {
        guard let spaceId else { return }
        // Ordering out the key anchor can rekey a remote app window and reverse the completed Space switch.
        for anchor in anchors.values where anchor.spaceId == spaceId && anchor.collectionBehavior.contains(.managed) {
            anchor.collectionBehavior = [.stationary, .ignoresCycle]
        }
    }
}
