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
            collectionBehavior = [.managed, .ignoresCycle]
            setAccessibilitySubrole(.floatingWindow)
        }
    }

    private static var anchors = [String: Anchor]()
    private static var ids = Set<CGWindowID>()

    static func contains(_ id: CGWindowID?) -> Bool { id.map { ids.contains($0) } ?? false }

    static func reconcile(_ spaces: [SpaceLabelResolver.Space]) {
        let desktops = spaces.filter { $0.desktopNumber > 0 }
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
    }

    static func activate(_ space: SpaceItem) -> Bool {
        guard let anchor = anchors[space.uuid], !anchor.assigning, anchor.spaceId == space.spaceId else { return false }
        FocusIntents.shared.supersede()
        // macOS 26.5 probe: making the destination key and ordered before activation switches Spaces;
        // making it key without ordering returned success from SLPS but did not switch.
        anchor.makeKeyAndOrderFront(nil)
        App.shared.activate(ignoringOtherApps: true)
        return true
    }
}
