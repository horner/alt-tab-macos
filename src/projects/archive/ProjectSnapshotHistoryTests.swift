import XCTest

final class ProjectSnapshotHistoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testHistoryUsesCaptureDatesAndWindowCountsWithoutRequiringWindowDetails() throws {
        let older = try snapshot("sort-first", date: "2026-09-12T11:12:13Z", windows: 2, status: "Closing stopped")
        let newer = try snapshot("sort-last", date: "2026-09-13T11:12:13Z", windows: 0, status: "Snapshot saved; windows kept open")
        let entries = ProjectSnapshotHistory.load(in: root)
        XCTAssertEqual(entries.map { $0.readme.resolvingSymlinksInPath() }, [newer, older].map { $0.appendingPathComponent("README.md").resolvingSymlinksInPath() })
        XCTAssertEqual(entries.map(\.windowCount), [0, 2])
        XCTAssertEqual(entries.map(\.status), ["Snapshot saved; windows kept open", "Closing stopped"])
    }

    func testStagingAndIncompleteArchivesNeverProduceBrokenLinks() throws {
        _ = try snapshot(".in-progress")
        let missing = try snapshot("missing-readme")
        try FileManager.default.removeItem(at: missing.appendingPathComponent("README.md"))
        let directory = try snapshot("readme-is-directory")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("README.md"), withIntermediateDirectories: false)
        XCTAssertTrue(ProjectSnapshotHistory.load(in: root).isEmpty)
    }

    func testDamagedMetadataKeepsReadableMarkdownAndFallsBackToFolderDate() throws {
        let folder = try snapshot("2026-09-13T11-12-13Z-unique")
        try Data("invalid json".utf8).write(to: folder.appendingPathComponent("snapshot.json"))
        let entry = try XCTUnwrap(ProjectSnapshotHistory.load(in: root).first)
        XCTAssertEqual(entry.readme.resolvingSymlinksInPath(), folder.appendingPathComponent("README.md").resolvingSymlinksInPath())
        XCTAssertEqual(entry.capturedAt, ISO8601DateFormatter().date(from: "2026-09-13T11:12:13Z"))
        XCTAssertNil(entry.windowCount)
        XCTAssertTrue(entry.status.contains("unavailable"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("snapshot.json"))
        XCTAssertEqual(ProjectSnapshotHistory.load(in: root), [entry])
    }

    func testMetadataRefreshReflectsFinalCloseStatusAndDeletedSnapshotsDisappear() throws {
        let folder = try snapshot("checkpoint", status: "Waiting for a save prompt")
        XCTAssertEqual(ProjectSnapshotHistory.load(in: root).first?.status, "Waiting for a save prompt")
        _ = try snapshot("checkpoint", status: "Closing stopped; Desktop kept open")
        XCTAssertEqual(ProjectSnapshotHistory.load(in: root).first?.status, "Closing stopped; Desktop kept open")
        try FileManager.default.removeItem(at: folder)
        XCTAssertTrue(ProjectSnapshotHistory.load(in: root).isEmpty)
    }

    func testMissingArchivesAreEmptyAndMovedProjectUsesItsNewLocation() throws {
        XCTAssertTrue(ProjectSnapshotHistory.load(in: root).isEmpty)
        _ = try snapshot("checkpoint")
        let moved = root.appendingPathComponent("renamed-project", isDirectory: true)
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: false)
        try FileManager.default.moveItem(at: root.appendingPathComponent("archives"), to: moved.appendingPathComponent("archives"))
        XCTAssertTrue(ProjectSnapshotHistory.load(in: root).isEmpty)
        XCTAssertEqual(ProjectSnapshotHistory.load(in: moved).first?.readme.resolvingSymlinksInPath(),
            moved.appendingPathComponent("archives/checkpoint/README.md").resolvingSymlinksInPath())
    }

    func testSymbolicLinksDoNotEscapeTheSnapshotFolder() throws {
        let original = try snapshot("original")
        let linked = root.appendingPathComponent("archives/linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: original)
        let linkedReadme = try snapshot("linked-readme")
        try FileManager.default.removeItem(at: linkedReadme.appendingPathComponent("README.md"))
        try FileManager.default.createSymbolicLink(at: linkedReadme.appendingPathComponent("README.md"), withDestinationURL: original.appendingPathComponent("README.md"))
        XCTAssertEqual(ProjectSnapshotHistory.load(in: root).map { $0.readme.resolvingSymlinksInPath() }, [original.appendingPathComponent("README.md").resolvingSymlinksInPath()])
    }

    func testFilesystemObserverRefreshesAtomicSnapshotMetadataChanges() throws {
        let watched = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".alt-tab-snapshot-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: watched) }
        let directory = watched.appendingPathComponent("projects/example/archives/checkpoint", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metadata = directory.appendingPathComponent("snapshot.json")
        try Data("{}".utf8).write(to: metadata)
        let changed = expectation(description: "Snapshot history changed")
        changed.assertForOverFulfill = false
        let observer = try ProjectDirectoryObserver(root: watched, queue: DispatchQueue(label: "snapshot-history-test"),
            snapshotsChanged: { changed.fulfill() }, changed: {})
        try Data("{\"status\":\"complete\"}".utf8).write(to: metadata, options: .atomic)
        withExtendedLifetime(observer) { wait(for: [changed], timeout: 5) }
    }

    private func snapshot(_ name: String, date: String = "2026-09-13T11:12:13Z", windows: Int = 1, status: String = "Snapshot saved") throws -> URL {
        let directory = root.appendingPathComponent("archives/" + name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("# Visual checkpoint\n".utf8).write(to: directory.appendingPathComponent("README.md"))
        let metadata: [String: Any] = ["capturedAt": date, "windows": Array(repeating: [String: String](), count: windows), "status": status]
        try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("snapshot.json"), options: .atomic)
        return directory
    }
}
