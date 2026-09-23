import Foundation

/// Window IDs identify WindowServer destinations; process launch time prevents PID reuse from matching.
struct ProjectWindowIdentity: Codable, Equatable {
    let windowId: String
    let pid: Int32
    let processLaunchedAt: Date
}
