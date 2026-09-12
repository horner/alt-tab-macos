import Cocoa

/// Requests and placement exceptions belong to the main thread; workers use captured IDs and cancellation only.
enum WindowDesktopMove {
    typealias Destination = WindowDesktopMoveResolver.Destination

    private final class Request {
        weak var window: Window?
        let windowId: CGWindowID
        let pid: pid_t
        let source: [UInt64]
        let destination: Destination
        let visibilityGeneration: Int
        let focusOnArrival: Bool
        var completion: ((Bool) -> Void)?
        var timeout: DispatchWorkItem?
        private let lock = NSLock()
        private var cancelled = false

        init(_ window: Window, _ destination: Destination, focusOnArrival: Bool, completion: ((Bool) -> Void)?) {
            self.window = window
            windowId = window.cgWindowId!
            pid = window.application.pid
            source = window.spaceIds
            self.destination = destination
            visibilityGeneration = WindowDesktopMove.visibilityGeneration
            self.focusOnArrival = focusOnArrival
            self.completion = completion
        }

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

    private static var pending = [String: Request]()
    private static var placements = [String: Request]()
    private static var visibilityGeneration = 0

    static var currentDestination: Destination? {
        Projects.spaces.first { $0.spaceId == Spaces.currentSpaceId && $0.desktopNumber > 0 }
            .map { Destination(id: $0.spaceId, uuid: $0.uuid) }
    }

    static func canBring(_ window: Window, to destination: Destination?) -> Bool {
        let desktops = Dictionary(uniqueKeysWithValues: Projects.spaces.filter { $0.desktopNumber > 0 }.map { ($0.spaceId, $0.uuid) })
        return WindowDesktopMoveBridge.isAvailable && pending[window.tracked.id] == nil
            && WindowDesktopMoveResolver.canMove(isEligible: isEligible(window), spaces: window.spaceIds,
                destination: destination, desktops: desktops)
    }

    static func isEligible(_ window: Window) -> Bool {
        window.cgWindowId != nil && window.application.pid != AXUIElement.currentProcessPid
            && ProjectAssignmentPrompt.canAssign(window) && window.tabbedSiblingWids == nil
            && !window.isFullscreen && !window.isFullscreenMirrored && !window.spaceIsBorrowed
    }

    static func bring(_ window: Window, to destination: Destination) {
        move(window, to: destination, focusOnArrival: true)
    }

    static func restore(_ window: Window, to destination: Destination, completion: @escaping (Bool) -> Void) {
        move(window, to: destination, focusOnArrival: false, completion: completion)
    }

    private static func move(_ window: Window, to destination: Destination, focusOnArrival: Bool, completion: ((Bool) -> Void)? = nil) {
        guard Projects.isEnabled, Windows.list.contains(where: { $0 === window }), canBring(window, to: destination) else {
            completion?(false)
            return
        }
        let request = Request(window, destination, focusOnArrival: focusOnArrival, completion: completion)
        let id = window.tracked.id
        pending[id] = request
        ProjectVisibility.refresh()
        let timeout = DispatchWorkItem { verify(request, final: true) }
        request.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)
        CGSCallScheduler.run {
            let submitted = submit(request)
            DispatchQueue.main.async {
                guard pending[id] === request else { return }
                guard submitted else { finish(request, succeeded: false); return }
                verify(request, final: false)
            }
        }
    }

    private static func submit(_ request: Request) -> Bool {
        guard !request.isCancelled,
              let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, request.windowId) as? [[String: Any]],
              rows.first?[kCGWindowOwnerPID as String] as? pid_t == request.pid,
              let spaces = CGSCallScheduler.windowSpaces(request.windowId), spaces == request.source else { return false }
        let displays = CGSCopyManagedDisplaySpaces(CGS_CONNECTION) as? [[String: Any]] ?? []
        var desktops = [UInt64: String]()
        for space in displays.flatMap({ $0["Spaces"] as? [[String: Any]] ?? [] }) {
            guard space["type"] as? Int == 0, let id = space["id64"] as? UInt64, let uuid = space["uuid"] as? String else { continue }
            desktops[id] = uuid
        }
        guard WindowDesktopMoveResolver.canMove(isEligible: true, spaces: spaces, destination: request.destination, desktops: desktops),
              !request.isCancelled else { return false }
        return WindowDesktopMoveBridge.submit(windowId: request.windowId, spaceId: request.destination.id)
    }

    private static func verify(_ request: Request, final: Bool) {
        guard let window = request.window, pending[window.tracked.id] === request else { return }
        CGSCallScheduler.windowSpaces(request.windowId) { spaces in
            guard pending[window.tracked.id] === request else { return }
            if let spaces, WindowDesktopMoveResolver.confirmed(spaces, destination: request.destination) {
                // Feed observed membership through the reducer; never predict a Space change from submission.
                TrackedWindowStateBridge.dispatch(.spacesSynced(windowToSpaces: [request.windowId: spaces],
                    queried: [request.windowId], answered: [request.windowId], placedByWindowServer: [], topologyChanged: false))
                if pending[window.tracked.id] === request { finish(request, succeeded: true) }
            } else if final {
                finish(request, succeeded: false)
            }
        }
    }

    static func spaceChanged(_ window: Window) {
        guard let request = pending[window.tracked.id], request.window === window,
              WindowDesktopMoveResolver.confirmed(window.spaceIds, destination: request.destination) else { return }
        finish(request, succeeded: true)
    }

    private static func finish(_ request: Request, succeeded: Bool) {
        guard let window = request.window, pending[window.tracked.id] === request else { return }
        pending.removeValue(forKey: window.tracked.id)
        request.timeout?.cancel()
        request.timeout = nil
        request.cancel()
        if succeeded { placements[window.tracked.id] = request }
        ProjectVisibility.refresh()
        Logger.debug { "desktop move window=\(request.windowId) destination=\(request.destination.id) confirmed=\(succeeded)" }
        let completion = request.completion
        request.completion = nil
        DispatchQueue.main.async {
            completion?(succeeded)
            guard request.focusOnArrival else { return }
            guard Windows.list.contains(where: { $0 === window }) else { return }
            guard succeeded else { showFailure(); return }
            guard currentDestination == request.destination, request.visibilityGeneration == visibilityGeneration,
                  window.spaceIds == [request.destination.id], !SwitcherSession.isActive, !ProjectSwitcher.isActive,
                  App.shared.modalWindow == nil else { return }
            window.focus()
        }
    }

    static func preservesMembership(_ window: Window) -> Bool {
        pending[window.tracked.id]?.window === window || placements[window.tracked.id]?.window === window
    }

    static func keepsVisible(_ window: Window) -> Bool {
        guard let request = pending[window.tracked.id] ?? placements[window.tracked.id], request.window === window else { return false }
        return request.focusOnArrival && request.visibilityGeneration == visibilityGeneration && window.spaceIds.contains(request.destination.id)
    }

    static func selectionChanged() { visibilityGeneration += 1 }

    static func forget(_ windows: [Window]) {
        for window in windows {
            let request = pending.removeValue(forKey: window.tracked.id)
            request?.cancel()
            request?.timeout?.cancel()
            request?.timeout = nil
            let completion = request?.completion
            request?.completion = nil
            if let completion { DispatchQueue.main.async { completion(false) } }
            placements.removeValue(forKey: window.tracked.id)
        }
    }

    private static func showFailure() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Could not bring window to this Desktop", comment: "Desktop move error")
        alert.informativeText = NSLocalizedString("macOS did not confirm the move. The window may have closed or its Desktop may no longer be available.", comment: "Desktop move error")
        alert.runModal()
    }
}
