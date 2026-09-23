import Foundation

enum ProjectVisibilityResolver {
    struct Window {
        let id: String
        var spaceIds: [UInt64]
        var projectIds: Set<String>
        var isMinimized = false
        var isExplicitlyVisible = false
        var isEligible = true
    }

    struct Context {
        var enabled: Bool
        var spaceId: UInt64?
        var projectId: String?
        var projectIsLocal = true
    }

    final class Command {
        let windowId: String
        let minimize: Bool
        private let lock = NSLock()
        private var cancelled = false
        fileprivate var relinquished = false

        init(windowId: String, minimize: Bool) {
            self.windowId = windowId
            self.minimize = minimize
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

    enum Outcome {
        case changed
        case unchanged(Bool)
        case failed
        case cancelled
    }

    /// State stays on main; workers receive only a cancellable command and an immutable AX destination.
    struct Session {
        private(set) var managed = Set<String>()
        private(set) var pending = [String: Command]()
        private var compensate = Set<String>()
        private var completedState = [String: Bool]()

        mutating func recover(_ id: String) {
            managed.insert(id)
        }

        func cancelPending() {
            pending.values.forEach { $0.cancel() }
        }

        mutating func plan(_ windows: [Window], _ context: Context) -> [Command] {
            let targets = Dictionary(uniqueKeysWithValues: windows.map { window in
                (window.id, desired(window, context) ?? (compensate.contains(window.id) && window.isEligible ? false : nil))
            })
            for (id, command) in pending where (targets[id] ?? nil) != command.minimize { command.cancel() }
            var commands = [Command]()
            for window in windows {
                let minimized = completedState[window.id] ?? window.isMinimized
                if (targets[window.id] ?? nil) == true { compensate.remove(window.id) }
                guard pending[window.id] == nil, let target = targets[window.id] ?? nil,
                      target ? !managed.contains(window.id) && !minimized : managed.contains(window.id) else { continue }
                let command = Command(windowId: window.id, minimize: target)
                pending[window.id] = command
                commands.append(command)
            }
            return commands.sorted { !$0.minimize && $1.minimize }
        }

        /// AX writes already sent cannot be cancelled. Remember their effect, then undo a stale minimize.
        @discardableResult
        mutating func complete(_ command: Command, _ outcome: Outcome) -> Bool {
            guard pending[command.windowId] === command else { return false }
            pending.removeValue(forKey: command.windowId)
            guard !command.relinquished else { return false }
            switch outcome {
            case .changed:
                completedState[command.windowId] = command.minimize
                if command.minimize {
                    managed.insert(command.windowId)
                    if command.isCancelled { compensate.insert(command.windowId) }
                } else {
                    managed.remove(command.windowId)
                    compensate.remove(command.windowId)
                }
            case .unchanged(let minimized):
                completedState[command.windowId] = minimized
                if !minimized {
                    managed.remove(command.windowId)
                    compensate.remove(command.windowId)
                }
            case .failed, .cancelled: break
            }
            return command.isCancelled
        }

        mutating func release(_ id: String) {
            managed.remove(id)
            compensate.remove(id)
            completedState.removeValue(forKey: id)
            pending[id]?.relinquished = true
            pending[id]?.cancel()
        }

        mutating func observed(_ id: String, minimized: Bool) {
            completedState.removeValue(forKey: id)
            if let command = pending[id], command.minimize != minimized {
                release(id)
            } else if !minimized, pending[id] == nil {
                release(id)
            }
        }

        mutating func forget(_ id: String) {
            release(id)
            pending.removeValue(forKey: id)
        }
    }

    static func desired(_ window: Window, _ context: Context) -> Bool? {
        guard window.isEligible else { return nil }
        if window.isExplicitlyVisible { return false }
        guard context.enabled else { return false }
        guard let spaceId = context.spaceId, window.spaceIds.contains(spaceId) else { return nil }
        guard context.projectIsLocal else { return nil }
        guard let projectId = context.projectId else { return false }
        guard Set(window.spaceIds).count == 1 else { return false }
        return !window.projectIds.isEmpty && !window.projectIds.contains(projectId)
    }
}
