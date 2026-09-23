import XCTest

final class ProjectLifecycleResolverTests: XCTestCase {
    private let identity = ProjectWindowIdentity(windowId: "7", pid: 42, processLaunchedAt: Date(timeIntervalSince1970: 10))
    private let pattern = ProjectWindowPattern(bundleIdentifier: "com.example.editor", title: "Research", spaceUuid: "desktop")

    private func entry(_ id: String = "source") -> ProjectEntry {
        ProjectEntry(id: id, kind: "custom", spaceUuid: nil, homeSpaceUuid: "desktop", name: id, autoName: nil,
            members: [identity], memberPatterns: [pattern], windowHistory: [pattern], labelUuid: "label-" + id)
    }

    func testClosePreservesAllRecordsAndClearsPendingRemoval() throws {
        var source = entry()
        source.pendingDesktopRemoval = true
        source.excludedMembers = [identity]
        source.excludedPatterns = [pattern]
        let closed = ProjectLifecycleResolver.closed(source)
        XCTAssertTrue(closed.isClosed)
        XCTAssertFalse(closed.pendingDesktopRemoval)
        source.isClosed = true
        source.pendingDesktopRemoval = false
        XCTAssertEqual(closed, source)
        XCTAssertEqual(try JSONDecoder().decode(ProjectEntry.self, from: JSONEncoder().encode(closed)), closed)
    }

    func testReopenKeepsIdentityAndHistoryOnChosenDesktop() {
        let closed = ProjectLifecycleResolver.closed(entry())
        let reopened = ProjectLifecycleResolver.reopened(closed, on: "other")
        XCTAssertFalse(reopened.isClosed)
        XCTAssertFalse(reopened.pendingDesktopRemoval)
        XCTAssertEqual(reopened.homeSpaceUuid, "other")
        XCTAssertEqual(reopened.id, closed.id)
        XCTAssertEqual(reopened.labelUuid, closed.labelUuid)
        XCTAssertEqual(reopened.members, closed.members)
        XCTAssertEqual(reopened.windowHistory, closed.windowHistory)
    }

    func testLegacyEntriesRemainOpenWithoutPendingQuestion() throws {
        let json = """
        {"id":"legacy","kind":"custom","homeSpaceUuid":"desktop","linkedProjectId":"linked"}
        """
        let value = try JSONDecoder().decode(ProjectEntry.self, from: Data(json.utf8))
        XCTAssertFalse(value.isClosed)
        XCTAssertFalse(value.pendingDesktopRemoval)
        XCTAssertEqual(value.linkedProjectIds, ["linked"])
    }

    func testPendingQuestionSurvivesRestart() throws {
        var value = entry()
        value.pendingDesktopRemoval = true
        let restored = try JSONDecoder().decode(ProjectEntry.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(restored.pendingDesktopRemoval)
        XCTAssertFalse(restored.isClosed)
    }

    func testCombinePreservesDestinationIdentityAndDeduplicatesMembersAndHistory() throws {
        let source = entry()
        var destination = entry("target")
        let second = ProjectWindowIdentity(windowId: "8", pid: 42, processLaunchedAt: identity.processLaunchedAt)
        destination.members.append(second)
        let result = try XCTUnwrap(ProjectLifecycleResolver.combined(source, into: destination))
        XCTAssertEqual(result.id, destination.id)
        XCTAssertEqual(result.name, destination.name)
        XCTAssertEqual(result.labelUuid, destination.labelUuid)
        XCTAssertEqual(result.members, [identity, second])
        XCTAssertEqual(result.windowHistory, [pattern])
        XCTAssertEqual(result.memberPatterns, [pattern])
        XCTAssertEqual(source, entry())
    }

    func testCombineRetainsNewestHistoryAndConfirmationTimes() throws {
        var source = entry()
        var destination = entry("target")
        source.windowHistory[0].lastSeenAt = Date(timeIntervalSince1970: 20)
        destination.windowHistory[0].lastSeenAt = Date(timeIntervalSince1970: 10)
        destination.memberPatterns[0].confirmedAt = Date(timeIntervalSince1970: 30)
        source.memberPatterns[0].confirmedAt = Date(timeIntervalSince1970: 40)
        let result = try XCTUnwrap(ProjectLifecycleResolver.combined(source, into: destination))
        XCTAssertEqual(result.windowHistory[0].lastSeenAt, source.windowHistory[0].lastSeenAt)
        XCTAssertEqual(result.memberPatterns[0].confirmedAt, source.memberPatterns[0].confirmedAt)
    }

    func testIncludedMembersWinOverExclusionsFromEitherProject() throws {
        var source = entry()
        source.excludedMembers = [identity]
        source.excludedPatterns = [pattern]
        let result = try XCTUnwrap(ProjectLifecycleResolver.combined(source, into: entry("target")))
        XCTAssertTrue(result.excludedMembers.isEmpty)
        XCTAssertTrue(result.excludedPatterns.isEmpty)
    }

    func testUnrelatedExclusionsSurviveCombine() throws {
        var source = entry()
        let excluded = ProjectWindowIdentity(windowId: "99", pid: 9, processLaunchedAt: identity.processLaunchedAt)
        let excludedPattern = ProjectWindowPattern(bundleIdentifier: "com.example.editor", title: "Private notes")
        source.excludedMembers = [excluded]
        source.excludedPatterns = [excludedPattern]
        let result = try XCTUnwrap(ProjectLifecycleResolver.combined(source, into: entry("target")))
        XCTAssertEqual(result.excludedMembers, [excluded])
        XCTAssertEqual(result.excludedPatterns, [excludedPattern])
    }

    func testIncludedMembershipOverridesGlobalButNotOtherDesktopExclusions() throws {
        var source = entry()
        var global = pattern
        global.spaceUuid = nil
        var elsewhere = pattern
        elsewhere.spaceUuid = "elsewhere"
        source.excludedPatterns = [global, elsewhere]
        let result = try XCTUnwrap(ProjectLifecycleResolver.combined(source, into: entry("target")))
        XCTAssertEqual(result.excludedPatterns, [elsewhere])
    }

    func testCombineRejectsSelfClosedDesktopAndMovedTargets() {
        let source = entry()
        XCTAssertNil(ProjectLifecycleResolver.combined(source, into: source))
        XCTAssertNil(ProjectLifecycleResolver.combined(ProjectLifecycleResolver.closed(source), into: entry("target")))
        XCTAssertNil(ProjectLifecycleResolver.combined(source, into: ProjectLifecycleResolver.closed(entry("target"))))
        var target = entry("target")
        target.homeSpaceUuid = "other"
        XCTAssertNil(ProjectLifecycleResolver.combined(source, into: target))
        target.homeSpaceUuid = source.homeSpaceUuid
        target.kind = "desktop"
        XCTAssertNil(ProjectLifecycleResolver.combined(source, into: target))
    }

    func testWindowIdReuseDoesNotDeduplicateDifferentProcesses() throws {
        var source = entry()
        source.members = [.init(windowId: identity.windowId, pid: 43, processLaunchedAt: Date(timeIntervalSince1970: 50))]
        let result = try XCTUnwrap(ProjectLifecycleResolver.combined(source, into: entry("target")))
        XCTAssertEqual(result.members.count, 2)
    }

    private func emptyAlias(of canonical: ProjectEntry, closed: Bool) -> ProjectEntry {
        var alias = ProjectEntry(id: "desktop-" + canonical.labelUuid!, kind: "custom", spaceUuid: nil,
            homeSpaceUuid: canonical.homeSpaceUuid, name: canonical.name, autoName: canonical.autoName, labelUuid: canonical.labelUuid, isClosed: closed)
        alias.closedWindows = closed ? [] : nil
        return alias
    }

    func testClosingEmptyDesktopAliasClosesOriginalWithoutLosingHistory() throws {
        let canonical = entry()
        let alias = emptyAlias(of: canonical, closed: true)
        let repaired = ProjectLifecycleResolver.repairingEmptyDesktopAliases([canonical, alias])
        let project = try XCTUnwrap(repaired.first)
        XCTAssertEqual(repaired.count, 1)
        XCTAssertEqual(project.id, canonical.id)
        XCTAssertTrue(project.isClosed)
        XCTAssertEqual(project.members, canonical.members)
        XCTAssertEqual(project.memberPatterns, canonical.memberPatterns)
        XCTAssertEqual(project.windowHistory, canonical.windowHistory)
        let restored = ProjectLifecycleResolver.reopened(project, on: "desktop-13")
        XCTAssertEqual(restored.homeSpaceUuid, "desktop-13")
        XCTAssertEqual(restored.windowHistory, canonical.windowHistory)
    }

    func testAliasRepairRemovesClosedProjectDesktopClaims() {
        let canonical = entry()
        let alias = emptyAlias(of: canonical, closed: true)
        var desktop = entry("desktop-record")
        desktop.kind = "desktop"
        desktop.linkedProjectIds = ["neighbor", canonical.id, alias.id]
        let repaired = ProjectLifecycleResolver.repairingEmptyDesktopAliases([desktop, canonical, alias])
        XCTAssertEqual(repaired[0].linkedProjectIds, ["neighbor"])
        XCTAssertEqual(repaired[0].linkedProjectId, "neighbor")
        XCTAssertEqual(ProjectLifecycleResolver.repairingEmptyDesktopAliases(repaired), repaired)
    }

    func testOpenAliasRepairKeepsOneOriginalDesktopClaim() {
        let canonical = entry()
        let alias = emptyAlias(of: canonical, closed: false)
        var desktop = entry("desktop-record")
        desktop.kind = "desktop"
        desktop.linkedProjectIds = ["neighbor", alias.id, canonical.id]
        let repaired = ProjectLifecycleResolver.repairingEmptyDesktopAliases([desktop, alias, canonical])
        XCTAssertEqual(repaired[0].linkedProjectIds, ["neighbor", canonical.id])
        XCTAssertFalse(repaired[1].isClosed)
    }

    func testAliasWithItsOwnHistoryIsNotDiscarded() {
        let canonical = entry()
        var alias = emptyAlias(of: canonical, closed: true)
        alias.windowHistory = [pattern]
        XCTAssertEqual(ProjectLifecycleResolver.repairingEmptyDesktopAliases([canonical, alias]), [canonical, alias])
        alias.windowHistory = []
        alias.excludedMembers = [identity]
        XCTAssertEqual(ProjectLifecycleResolver.repairingEmptyDesktopAliases([canonical, alias]), [canonical, alias])
    }

    func testAliasRepairDoesNotGuessFromNamesOrAmbiguousLabelOwners() {
        let canonical = entry()
        var alias = emptyAlias(of: canonical, closed: true)
        alias.labelUuid = "different-label"
        XCTAssertEqual(ProjectLifecycleResolver.repairingEmptyDesktopAliases([canonical, alias]), [canonical, alias])
        alias = emptyAlias(of: canonical, closed: true)
        var other = canonical
        other.id = "another-project"
        let entries = [canonical, other, alias]
        XCTAssertEqual(ProjectLifecycleResolver.repairingEmptyDesktopAliases(entries), entries)
    }
}
