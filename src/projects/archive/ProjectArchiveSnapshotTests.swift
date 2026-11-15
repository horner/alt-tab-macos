import XCTest

final class ProjectArchiveSnapshotTests: XCTestCase {
    func testMarkdownEscapesWindowContentAndEmbedsRelativeScreenshots() {
        let snapshot = example(title: "[link](file:///tmp/test) <script>\n# heading")
        XCTAssertTrue(snapshot.markdown.contains("\\[link\\]"))
        XCTAssertTrue(snapshot.markdown.contains("&lt;script&gt; \\# heading"))
        XCTAssertTrue(snapshot.markdown.contains("![Window 1](screenshots/window-1.png)"))
        XCTAssertFalse(snapshot.markdown.contains("\n# heading"))
    }

    func testUnavailableImageIsExplainedWithoutBrokenEmbed() {
        var snapshot = example()
        snapshot.windows[0].screenshot = nil
        snapshot.windows[0].screenshotIssue = "Protected window"
        XCTAssertTrue(snapshot.markdown.contains("Screenshot unavailable: Protected window"))
        XCTAssertFalse(snapshot.markdown.contains("![Window"))
    }

    func testCloseCancellationKeepsPerWindowOutcomeAndRestorationData() throws {
        var snapshot = example()
        snapshot.status = "Closing stopped; Desktop remains open"
        snapshot.windows[0].outcome = "Still open; cancelled"
        let result = try JSONDecoder().decode(ProjectArchiveSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(result.windows[0].reference, "file:///tmp/document.txt")
        XCTAssertEqual(result.windows[0].position, CGPoint(x: 12, y: 34))
        XCTAssertEqual(result.windows[0].projectIds, ["project-id"])
        XCTAssertTrue(result.markdown.contains("Still open; cancelled"))
        XCTAssertTrue(result.markdown.contains("Desktop remains open"))
    }

    func testSameSecondSnapshotsHaveDifferentSafeFolderNames() {
        let date = Date(timeIntervalSince1970: 0)
        let first = ProjectArchiveSnapshot.folderName(date)
        let second = ProjectArchiveSnapshot.folderName(date)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains(":"))
        XCTAssertFalse(first.contains("/"))
    }

    func testEmptyDesktopHasAnExplicitVisualCheckpoint() {
        var snapshot = example()
        snapshot.windows = []
        XCTAssertTrue(snapshot.markdown.contains("No application windows were open"))
    }

    private func example(title: String = "Notes") -> ProjectArchiveSnapshot {
        ProjectArchiveSnapshot(capturedAt: Date(timeIntervalSince1970: 0), desktopUuid: "space-id", desktopNumber: 7,
            name: "Research", windows: [.init(id: "window-id", windowId: 42, app: "TextEdit", bundleIdentifier: "com.apple.TextEdit",
                title: title, position: CGPoint(x: 12, y: 34), size: CGSize(width: 640, height: 480), minimized: true,
                projectIds: ["project-id"], reference: "file:///tmp/document.txt", screenshot: "screenshots/window-1.png")])
    }
}
