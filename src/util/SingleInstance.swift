import Foundation
import Darwin

final class SingleInstance {
    static let restartArgument = "--wait-for-instance"
    // All build locations and bundle-ID variants control the same user's global shortcuts and Desktops.
    static let lockURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.lwouis.alt-tab-macos/instance.lock")
    enum Failure: Error {
        case alreadyRunning
        case system(Int32)
    }
    private let descriptor: Int32

    init(url: URL, wait: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.system(errno) }
        guard flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw Failure.alreadyRunning }
            throw Failure.system(code)
        }
        self.descriptor = descriptor
    }

    deinit {
        // Keep the file: unlinking it lets another launch lock a different inode while a waiter owns this one.
        close(descriptor)
    }
}
