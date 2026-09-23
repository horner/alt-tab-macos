import XCTest

final class ProjectAtticResolverTests: XCTestCase {
    private func entry(_ history: [ProjectWindowPattern] = []) -> ProjectEntry {
        ProjectEntry(id: "lilly", kind: "custom", spaceUuid: nil, homeSpaceUuid: "old-desktop", name: "Lilly", autoName: nil, windowHistory: history, isClosed: true)
    }

    private func page(_ url: String = "https://example.com/work", browser: String = "com.apple.Safari", at time: TimeInterval = 10) -> ProjectWindowPattern {
        ProjectWindowPattern(bundleIdentifier: browser, title: "Work", spaceUuid: "old-desktop", lastSeenAt: Date(timeIntervalSince1970: time), url: url)
    }

    func testSnapshotAndEmptySnapshotSurviveRestart() throws {
        var archived = entry()
        archived.closedWindows = [page()]
        var decoded = try JSONDecoder().decode(ProjectEntry.self, from: JSONEncoder().encode(archived))
        XCTAssertEqual(decoded.closedWindows, archived.closedWindows)
        archived.closedWindows = []
        decoded = try JSONDecoder().decode(ProjectEntry.self, from: JSONEncoder().encode(archived))
        XCTAssertEqual(decoded.closedWindows, [])
    }

    func testLegacyHistoryDoesNotPretendToBeSnapshot() throws {
        let archived = try JSONDecoder().decode(ProjectEntry.self, from: JSONEncoder().encode(entry([page()])))
        XCTAssertNil(archived.closedWindows)
        XCTAssertEqual(ProjectAtticResolver.pages(in: archived).map { $0.wasOpen }, [false])
    }

    func testSnapshotPagesPrecedeMoreRecentHistory() {
        var archived = entry([page("https://example.com/history", at: 20)])
        archived.closedWindows = [page()]
        let pages = ProjectAtticResolver.pages(in: archived)
        XCTAssertEqual(pages.map { $0.wasOpen }, [true, false])
        XCTAssertEqual(pages.first?.pattern.url, page().url)
    }

    func testDeduplicatesPageAcrossTitlesDesktopsAndCredentials() {
        let old = page("HTTPS://user:password@EXAMPLE.com:443/work?code=secret", at: 10)
        var recent = ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Updated title", lastSeenAt: Date(timeIntervalSince1970: 20), url: "https://example.com/work")
        recent.spaceUuid = "new-desktop"
        var archived = entry([old, recent])
        archived.memberPatterns = [old]
        archived.closedWindows = [old]
        let pages = ProjectAtticResolver.pages(in: archived)
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.pattern.url, "https://example.com/work")
        XCTAssertEqual(pages.first?.pattern.spaceUuid, "new-desktop")
        XCTAssertEqual(pages.first?.pattern.title, "Updated title")
        XCTAssertTrue(pages.first?.wasOpen == true)
    }

    func testSameURLInDifferentBrowsersIsSeparate() {
        let archived = entry([page(), page(browser: "com.google.Chrome")])
        XCTAssertEqual(ProjectAtticResolver.pages(in: archived).count, 2)
    }

    func testRejectsUnsupportedApplicationsUnsafeURLsAndTransientPages() {
        let archived = entry([
            page(browser: "com.example.editor"), page("file:///private/document"), page("javascript:alert(1)"),
            page("https://example.com/oauth/callback?code=secret"), page("https://example.com/login"),
            ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Title only")
        ])
        XCTAssertTrue(ProjectAtticResolver.pages(in: archived).isEmpty)
    }

    func testTitleOnlyEditorWindowsRemainSavedWithoutReopenAction() throws {
        let editor = ProjectWindowPattern(bundleIdentifier: "com.example.editor", title: "Research")
        var archived = entry([editor])
        archived.closedWindows = [editor]
        let decoded = try JSONDecoder().decode(ProjectEntry.self, from: JSONEncoder().encode(archived))
        XCTAssertEqual(decoded.closedWindows, [editor])
        XCTAssertTrue(ProjectAtticResolver.pages(in: decoded).isEmpty)
    }

    func testNoPagesOpenUntilSelectedIncludingSnapshotPages() {
        var archived = entry((0..<139).map { page("https://example.com/\($0)") })
        archived.closedWindows = [page()]
        XCTAssertTrue(ProjectAtticResolver.pagesToOpen(in: archived, selected: [], alreadyOpen: []).isEmpty)
    }

    func testOnlySelectedSavedPagesOpenAndOpenPagesAreRechecked() throws {
        let first = page()
        let second = page("https://example.com/second")
        let firstKey = try XCTUnwrap(ProjectAtticResolver.pageKey(first))
        let secondKey = try XCTUnwrap(ProjectAtticResolver.pageKey(second))
        let archived = entry([first, second])
        let result = ProjectAtticResolver.pagesToOpen(in: archived, selected: [firstKey, secondKey, "not-saved"], alreadyOpen: [firstKey])
        XCTAssertEqual(result, [second])
    }

    func testStableOrderingWhenHistoryDatesAreMissing() {
        let first = ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "B", url: "https://example.com/b")
        let second = ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "A", url: "https://example.com/a")
        let forward = ProjectAtticResolver.pages(in: entry([first, second])).map { $0.key }
        let reverse = ProjectAtticResolver.pages(in: entry([second, first])).map { $0.key }
        XCTAssertEqual(forward, reverse)
    }

    func testStillOpenWindowRequiresExactProcessIdentityAndNoOtherOwner() {
        let identity = ProjectWindowIdentity(windowId: "7", pid: 42, processLaunchedAt: Date(timeIntervalSince1970: 10))
        var archived = entry()
        archived.members = [identity]
        XCTAssertTrue(ProjectAtticResolver.canBringBack(identity, from: archived, hasOwner: false))
        XCTAssertFalse(ProjectAtticResolver.canBringBack(identity, from: archived, hasOwner: true))
        XCTAssertFalse(ProjectAtticResolver.canBringBack(nil, from: archived, hasOwner: false))
        let reused = ProjectWindowIdentity(windowId: "7", pid: 42, processLaunchedAt: Date(timeIntervalSince1970: 20))
        XCTAssertFalse(ProjectAtticResolver.canBringBack(reused, from: archived, hasOwner: false))
        archived.excludedMembers = [identity]
        XCTAssertFalse(ProjectAtticResolver.canBringBack(identity, from: archived, hasOwner: false))
    }

    func testRestoringDoesNotConsumeSavedHistoryOrSnapshot() {
        var archived = entry([page()])
        archived.closedWindows = [page()]
        let restored = ProjectLifecycleResolver.reopened(archived, on: "new-desktop")
        XCTAssertEqual(restored.closedWindows, archived.closedWindows)
        XCTAssertEqual(restored.windowHistory, archived.windowHistory)
        XCTAssertEqual(restored.id, archived.id)
        XCTAssertEqual(restored.homeSpaceUuid, "new-desktop")
        XCTAssertTrue(archived.isClosed)
    }

    func testSnapshotOnlyWindowsJoinHistoryWhenProjectReturns() {
        var archived = entry([page()])
        let snapshot = ProjectWindowPattern(bundleIdentifier: "com.example.editor", title: "Unfinished research")
        archived.closedWindows = [page(), snapshot]
        let restored = ProjectLifecycleResolver.reopened(archived, on: "new-desktop")
        XCTAssertEqual(restored.windowHistory, [page(), snapshot])
        XCTAssertEqual(archived.windowHistory, [page()])
    }
}
