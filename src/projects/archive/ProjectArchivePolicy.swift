import Foundation

enum ProjectArchivePolicy {
    enum Mode {
        case snapshotOnly
        case archiveAndClose
    }

    enum Decision: Equatable {
        case wait
        case close(String)
        case removeDesktop
        case stop
    }

    static func next(mode: Mode = .archiveAndClose, saved: Bool, contextValid: Bool, pending: String?, remaining: [String], live: Set<String>, local: Set<String>) -> Decision {
        guard mode == .archiveAndClose, saved, contextValid else { return .stop }
        if let pending, live.contains(pending) { return .wait }
        guard let next = remaining.first(where: { live.contains($0) }) else { return local.isEmpty ? .removeDesktop : .stop }
        guard local.contains(next) else { return .stop }
        return .close(next)
    }
}

/// Cancellation wins until publication starts; afterwards completion must report the saved snapshot.
final class ProjectArchiveCancellation {
    private let lock = NSLock()
    private var cancelled = false
    private var publishing = false

    func cancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !publishing else { return false }
        cancelled = true
        return true
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CocoaError(.userCancelled) }
    }

    func beginPublication() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CocoaError(.userCancelled) }
        publishing = true
    }
}
