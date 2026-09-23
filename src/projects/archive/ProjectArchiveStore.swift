import Foundation
import CoreGraphics
import ImageIO

/// Publish complete snapshots from private staging directories. A failed write never authorizes closing.
enum ProjectArchiveStore {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static func write(_ source: ProjectArchiveSnapshot, projects: Data, directories: [URL], cancellation: ProjectArchiveCancellation? = nil, image: (UInt32) -> CGImage?) throws -> (ProjectArchiveSnapshot, [URL]) {
        try cancellation?.check()
        let manager = FileManager.default
        let folder = ProjectArchiveSnapshot.folderName(source.capturedAt)
        let temporary = manager.temporaryDirectory.appendingPathComponent("alt-tab-archive-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        let screenshots = temporary.appendingPathComponent("screenshots", isDirectory: true)
        try manager.createDirectory(at: screenshots, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var snapshot = source
        for index in snapshot.windows.indices {
            try cancellation?.check()
            guard let image = image(snapshot.windows[index].windowId) else {
                snapshot.windows[index].screenshotIssue = "The app or macOS did not provide an image."
                continue
            }
            let path = "screenshots/window-\(index + 1).png"
            guard let destination = CGImageDestinationCreateWithURL(temporary.appendingPathComponent(path) as CFURL, "public.png" as CFString, 1, nil) else {
                throw Failure("Could not create a window screenshot.")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure("Could not save a window screenshot.") }
            snapshot.windows[index].screenshot = path
        }
        try cancellation?.check()
        try save(snapshot, in: temporary)
        try projects.write(to: temporary.appendingPathComponent("projects.json"), options: .atomic)
        try cancellation?.beginPublication()
        var published = [URL]()
        for directory in directories {
            guard manager.fileExists(atPath: directory.appendingPathComponent("project.yaml").path) else {
                throw Failure("The project folder moved during capture. No windows were closed.")
            }
            let archives = directory.appendingPathComponent("archives", isDirectory: true)
            try manager.createDirectory(at: archives, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let staging = archives.appendingPathComponent("." + folder, isDirectory: true)
            let target = archives.appendingPathComponent(folder, isDirectory: true)
            do {
                try manager.copyItem(at: temporary, to: staging)
                try manager.moveItem(at: staging, to: target)
                published.append(target)
            } catch {
                try? manager.removeItem(at: staging)
                throw error
            }
        }
        return (snapshot, published)
    }

    static func save(_ snapshot: ProjectArchiveSnapshot, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
        try Data(snapshot.markdown.utf8).write(to: directory.appendingPathComponent("README.md"), options: .atomic)
    }
}
