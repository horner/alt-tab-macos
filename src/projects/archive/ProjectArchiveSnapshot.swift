import Foundation

struct ProjectArchiveSnapshot: Codable {
    struct Window: Codable {
        let id: String
        let windowId: UInt32
        let app: String
        let bundleIdentifier: String?
        let title: String
        let position: CGPoint?
        let size: CGSize?
        let minimized: Bool
        let projectIds: [String]
        var reference: String?
        var screenshot: String?
        var screenshotIssue: String?
        var outcome = "Open at capture"
    }

    var schemaVersion = 1
    let capturedAt: Date
    let desktopUuid: String
    let desktopNumber: Int
    let name: String
    var status = "Snapshot saved; no close requests sent"
    var windows: [Window]

    var markdown: String {
        var lines = ["# \(Self.escape(name))", "", "Captured: \(ISO8601DateFormatter().string(from: capturedAt))",
            "Desktop: \(desktopNumber)", "", Self.escape(status), "",
            "This is a visual checkpoint, not a backup of unsaved documents. Reopening details are in `snapshot.json` and `projects.json`.", ""]
        for (index, window) in windows.enumerated() {
            lines += ["## \(index + 1). \(Self.escape(window.app)) — \(Self.escape(window.title))", "",
                "\(Self.escape(window.outcome))\(window.minimized ? " · Minimized at capture" : "")", ""]
            if let reference = window.reference { lines += ["File or URL: \(Self.escape(reference))", ""] }
            if let position = window.position, let size = window.size {
                lines += ["Position: \(position.x), \(position.y) · Size: \(size.width) × \(size.height)", ""]
            }
            if let screenshot = window.screenshot { lines += ["![Window \(index + 1)](\(screenshot))", ""] }
            if let issue = window.screenshotIssue { lines += ["Screenshot unavailable: \(Self.escape(issue))", ""] }
        }
        if windows.isEmpty { lines += ["No application windows were open on this desktop.", ""] }
        return lines.joined(separator: "\n")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "#", with: "\\#").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func folderName(_ date: Date, id: UUID = UUID()) -> String {
        ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-") + "-" + id.uuidString
    }
}
