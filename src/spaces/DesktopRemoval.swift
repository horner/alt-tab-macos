import Cocoa

/// Dock owns Desktop removal. Match its numbered Desktop button and verify the UUID disappears;
/// never destroy a CGS Space directly, which would bypass Dock's Mission Control state.
enum DesktopRemoval {
    private final class Request {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private static var request: Request?
    private static var target: SpaceItem?
    private static var completion: ((Bool) -> Void)?
    private static var submitted = false
    private static var timeout: DispatchWorkItem?
    private static var token = UUID()

    static func remove(_ space: SpaceItem, then completion: @escaping (Bool) -> Void) {
        guard self.completion == nil, space.desktopNumber > 0 else { completion(false); return }
        self.completion = completion
        self.request = Request()
        target = space
        submitted = false
        token = UUID()
        let request = token
        let work = DispatchWorkItem {
            guard token == request else { return }
            verify(final: true)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        if MissionControl.state() == .showAllWindows { missionControlChanged(.showAllWindows); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let opened = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            DispatchQueue.main.async {
                guard token == request, self.completion != nil else { return }
                if !opened { finish(false) }
            }
        }
    }

    static func missionControlChanged(_ state: MissionControlState) {
        guard completion != nil else { return }
        if state == .inactive { verify(final: true); return }
        guard state == .showAllWindows, !submitted else { return }
        submitted = true
        let request = token
        // Dock publishes AXRemoveDesktop after its entry animation, not at the leading Exposé event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard request == token, completion != nil, let target else { return }
            guard DesktopArchive.canRemoveDesktop(target.uuid) else { finish(false); return }
            CGSCallScheduler.run {
                let raw = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [NSDictionary]
                let spaces = raw.flatMap { SpaceLabelResolver.spaces(from: $0) }
                let destination = spaces?.first { $0.uuid == target.uuid && $0.id == target.spaceId && $0.desktopNumber > 0 }
                let count = spaces?.filter { $0.displayIdentifier == destination?.displayIdentifier && $0.desktopNumber > 0 }.count ?? 0
                DispatchQueue.main.async {
                    guard request == token, completion != nil else { return }
                    guard let destination, count > 1, DesktopArchive.canRemoveDesktop(target.uuid) else { finish(false); return }
                    press(desktopNumber: destination.desktopNumber, request: request)
                }
            }
        }
    }

    private static func press(desktopNumber: Int, request: UUID) {
        guard let operation = self.request else { return }
        BackgroundWork.accessibilityCommandsQueue.addOperation {
            guard !operation.isCancelled else { return }
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            let dock = pid.map { AXUIElementCreateApplication($0) }
            let lists = dock.map { descendants($0, identifier: "mc.spaces.list") } ?? []
            // Dock's Localizable.strings uses DesktopNum for ordinary Space button titles.
            let format = Bundle(path: "/System/Library/CoreServices/Dock.app")?.localizedString(forKey: "DesktopNum", value: "Desktop %@", table: nil) ?? "Desktop %@"
            let title = String(format: format, String(desktopNumber))
            let candidates = lists.flatMap { children($0) }.filter { value($0, kAXTitleAttribute) as? String == title }
            let result: Bool
            if candidates.count == 1 {
                var names: CFArray?
                AXUIElementCopyActionNames(candidates[0], &names)
                result = (names as? [String])?.contains("AXRemoveDesktop") == true && !operation.isCancelled
                    && AXUIElementPerformAction(candidates[0], "AXRemoveDesktop" as CFString) == .success
            } else { result = false }
            DispatchQueue.main.async {
                guard request == token, completion != nil else { return }
                guard result else { finish(false); return }
                SpaceLabelWindows.refreshTopology()
            }
        }
    }

    static func topologyChanged(_ spaces: [SpaceLabelResolver.Space]) {
        guard let target, completion != nil, !spaces.contains(where: { $0.uuid == target.uuid }) else { return }
        finish(true)
    }

    private static func verify(final: Bool) {
        let request = token
        CGSCallScheduler.run {
            let spaces = (CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [NSDictionary]).flatMap { SpaceLabelResolver.spaces(from: $0) }
            DispatchQueue.main.async {
                guard request == token, completion != nil, let target else { return }
                if let spaces, !spaces.contains(where: { $0.uuid == target.uuid }) { finish(true) }
                else if final { finish(false) }
            }
        }
    }

    private static func finish(_ success: Bool) {
        guard let callback = completion else { return }
        request?.cancel()
        request = nil
        timeout?.cancel()
        timeout = nil
        completion = nil
        target = nil
        if success, MissionControl.state() == .showAllWindows {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
        callback(success)
    }

    private static func descendants(_ element: AXUIElement, identifier: String, depth: Int = 0) -> [AXUIElement] {
        guard depth < 6 else { return [] }
        if value(element, kAXIdentifierAttribute) as? String == identifier { return [element] }
        return children(element).flatMap { descendants($0, identifier: identifier, depth: depth + 1) }
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
}
