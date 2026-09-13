import XCTest
import ImageIO

final class ProjectArchiveStoreTests: XCTestCase {
    func testCompleteArchiveContainsReadablePngMarkdownAndRestorationData() throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        let projects = Data("[{\"id\":\"project-1\"}]".utf8)
        let (snapshot, paths) = try ProjectArchiveStore.write(example(), projects: projects, directories: [root], image: { _ in context.makeImage() })
        let folder = try XCTUnwrap(paths.first)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("projects.json")), projects)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("README.md")), snapshot.markdown)
        let saved = try JSONDecoder().decode(ProjectArchiveSnapshot.self, from: Data(contentsOf: folder.appendingPathComponent("snapshot.json")), dateStrategy: .iso8601)
        XCTAssertEqual(saved.windows[0].screenshot, "screenshots/window-1.png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(folder.appendingPathComponent(saved.windows[0].screenshot!) as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 12)
    }

    func testCancellationDuringCapturePublishesNothing() throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let cancellation = ProjectArchiveCancellation()
        XCTAssertThrowsError(try ProjectArchiveStore.write(example(), projects: Data("[]".utf8), directories: [root], cancellation: cancellation, image: { _ in
            XCTAssertTrue(cancellation.cancel())
            return nil
        })) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.userCancelled.rawValue)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("archives").path))
    }

    func testPublishedSnapshotCannotBeReportedCancelled() throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let cancellation = ProjectArchiveCancellation()
        let (_, paths) = try ProjectArchiveStore.write(example(), projects: Data("[]".utf8), directories: [root], cancellation: cancellation, image: { _ in nil })
        XCTAssertFalse(cancellation.cancel())
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths[0].appendingPathComponent("README.md").path))
    }

    func testUnavailableCaptureRecordsReasonAndDoesNotInventAnImage() throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let (snapshot, paths) = try ProjectArchiveStore.write(example(), projects: Data("[]".utf8), directories: [root], image: { _ in nil })
        XCTAssertNil(snapshot.windows[0].screenshot)
        XCTAssertNotNil(snapshot.windows[0].screenshotIssue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths[0].appendingPathComponent("screenshots/window-1.png").path))
    }

    func testMovedProjectFolderFailsInsteadOfRecreatingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try ProjectArchiveStore.write(example(), projects: Data(), directories: [root], image: { _ in nil }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testTwoArchivesNeverOverwriteAnEarlierSnapshot() throws {
        let root = try projectFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ProjectArchiveStore.write(example(), projects: Data("[]".utf8), directories: [root], image: { _ in nil }).1[0]
        let second = try ProjectArchiveStore.write(example(), projects: Data("[]".utf8), directories: [root], image: { _ in nil }).1[0]
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.appendingPathComponent("README.md").path))
    }

    private func projectFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("id: project-1".utf8).write(to: root.appendingPathComponent("project.yaml"))
        return root
    }

    private func example() -> ProjectArchiveSnapshot {
        ProjectArchiveSnapshot(capturedAt: Date(timeIntervalSince1970: 0), desktopUuid: "desktop", desktopNumber: 8, name: "Archive test",
            windows: [.init(id: "wid-1", windowId: 1, app: "Test", bundleIdentifier: "test", title: "Draft", position: nil, size: nil,
                minimized: false, projectIds: ["project-1"], reference: "file:///tmp/draft.txt")])
    }
}

private extension JSONDecoder {
    func decode<T: Decodable>(_ type: T.Type, from data: Data, dateStrategy: DateDecodingStrategy) throws -> T {
        dateDecodingStrategy = dateStrategy
        return try decode(type, from: data)
    }
}
