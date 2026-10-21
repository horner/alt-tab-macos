import Foundation
import Darwin

struct ProjectDiagnosticSnapshot: Codable {
    struct Window: Codable {
        var id: String
        var pid: Int32
        var bundleIdentifier: String?
        var title: String
        var spaceIds: [UInt64]
        var isMinimized: Bool
        var isFullscreen: Bool
        var position: CGPoint?
        var size: CGSize?
        var projectIds: [String]
        var candidateProjectIds: [String]
        var identity: ProjectWindowIdentity?
        var restorationStatus: String
    }
    struct Desktop: Codable {
        var spaceId: UInt64
        var uuid: String
        var number: Int
        var isCurrent: Bool
    }
    var schemaVersion = 1
    var timestamp = Date()
    var bootedAt: Date
    var appVersion: String
    var bundleIdentifier: String
    var activeProjectId: String?
    var autoMinimizedWindows: [ProjectWindowIdentity]
    var projects: [ProjectRuntimeEntry]
    var windows: [Window]
    var desktops: [Desktop] = []
    var errors = [String]()

    static func bootDate() -> Date {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            return Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
        }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }

    static func bootFolder(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
