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
        source.homeSpaceUuid = ""
        source.desktopOwnershipVersion = 1
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

    private func desktop(_ uuid: String = "desktop", name: String? = nil, linked: [String] = []) -> ProjectEntry {
        ProjectEntry(id: "desktop-" + uuid, kind: "desktop", spaceUuid: uuid, homeSpaceUuid: uuid,
            name: name, autoName: nil, linkedProjectIds: linked)
    }

    func testOwnershipMigrationPrefersLinkedOwnerAndPreservesConflictingProjectsUnassigned() throws {
        var first = entry("first")
        first.homeSpaceUuid = "other"
        let second = entry("second")
        let saved = [desktop(name: "Separate desktop name", linked: [second.id, first.id]), first, second]
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership(saved)
        XCTAssertEqual(migrated.count, 3)
        XCTAssertEqual(migrated[1].homeSpaceUuid, "")
        XCTAssertEqual(migrated[2].homeSpaceUuid, "desktop")
        XCTAssertEqual(migrated[1].windowHistory, first.windowHistory)
        XCTAssertEqual(migrated[1].members, first.members)
        XCTAssertEqual(migrated[2].name, second.name)
        XCTAssertNil(migrated[0].name)
        XCTAssertNil(migrated[0].autoName)
        XCTAssertTrue(migrated[0].linkedProjectIds.isEmpty)
        XCTAssertTrue(migrated.allSatisfy { $0.desktopOwnershipVersion == 1 })
        let reloaded = try JSONDecoder().decode([ProjectEntry].self, from: JSONEncoder().encode(migrated))
        XCTAssertEqual(ProjectLifecycleResolver.normalizingDesktopOwnership(reloaded), migrated)
    }

    func testHomeAssignmentRepairsLegacyProjectEvenWhenItAlreadyHasALabelIdentity() {
        let source = entry()
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership([desktop(), source])
        XCTAssertEqual(migrated[1].homeSpaceUuid, "desktop")
        XCTAssertEqual(migrated[1].labelUuid, source.labelUuid)
        XCTAssertTrue(migrated[0].linkedProjectIds.isEmpty)
    }

    func testCompetingLegacyHomesChooseStableOwnerRegardlessOfFileOrder() {
        let first = entry("a")
        let second = entry("z")
        for saved in [[first, second], [second, first]] {
            let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership(saved)
            XCTAssertEqual(migrated.first { $0.id == first.id }?.homeSpaceUuid, "desktop")
            XCTAssertEqual(migrated.first { $0.id == second.id }?.homeSpaceUuid, "")
            XCTAssertEqual(migrated.count, 2)
        }
    }

    func testVersionedAssignmentWinsOverStaleLegacyDesktopLinksAfterInterruptedSave() {
        var owner = entry("owner")
        owner.desktopOwnershipVersion = 1
        let stale = entry("stale")
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership([desktop(linked: [stale.id]), stale, owner])
        XCTAssertEqual(migrated.first { $0.id == owner.id }?.homeSpaceUuid, "desktop")
        XCTAssertEqual(migrated.first { $0.id == stale.id }?.homeSpaceUuid, "")
    }

    func testExplicitlyUnassignedProjectNeverRegainsDesktopFromLegacyLinksOrName() {
        var source = entry()
        source.homeSpaceUuid = ""
        source.desktopOwnershipVersion = 1
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership([desktop(name: "Stale name", linked: [source.id]), source])
        XCTAssertEqual(migrated.count, 2)
        XCTAssertEqual(migrated[1], source)
        XCTAssertTrue(migrated[0].linkedProjectIds.isEmpty)
        XCTAssertNil(migrated[0].name)
    }

    func testNamedUnownedLegacyDesktopBecomesProjectWithoutLosingRecords() throws {
        var source = desktop(name: "Saved name")
        source.members = [identity]
        source.windowHistory = [pattern]
        source.excludedPatterns = [pattern]
        source.iconFileName = "icon.png"
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership([source])
        let project = try XCTUnwrap(migrated.first { $0.kind == "custom" })
        XCTAssertEqual(project.id, "project-desktop-desktop")
        XCTAssertEqual(project.homeSpaceUuid, source.homeSpaceUuid)
        XCTAssertEqual(project.name, source.name)
        XCTAssertEqual(project.members, source.members)
        XCTAssertEqual(project.windowHistory, source.windowHistory)
        XCTAssertEqual(project.excludedPatterns, source.excludedPatterns)
        XCTAssertEqual(project.iconFileName, source.iconFileName)
        XCTAssertEqual(project.labelUuid, "desktop")
        XCTAssertEqual(ProjectLifecycleResolver.normalizingDesktopOwnership(migrated), migrated)
    }

    func testNamedDesktopMigrationKeepsDistinctNamesAndNeverOverwritesAnExistingId() throws {
        var existing = entry("project-desktop-desktop")
        existing.homeSpaceUuid = "other"
        existing.name = "Saved name"
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership([desktop(name: "Saved name"), existing])
        let project = try XCTUnwrap(migrated.first { $0.id == "project-desktop-desktop-2" })
        XCTAssertEqual(project.name, "Saved name 2")
        XCTAssertEqual(project.homeSpaceUuid, "desktop")
        XCTAssertEqual(migrated.first { $0.id == existing.id }?.windowHistory, existing.windowHistory)
        XCTAssertEqual(ProjectLifecycleResolver.normalizingDesktopOwnership(migrated), migrated)
    }

    func testArchivedProjectRemainsUnassignedAndIsNotRecreatedByItsDesktopAlias() {
        var source = entry()
        source.isClosed = true
        var alias = desktop(name: source.name)
        alias.labelUuid = source.labelUuid
        let migrated = ProjectLifecycleResolver.normalizingDesktopOwnership([alias, source])
        XCTAssertEqual(migrated.count, 2)
        XCTAssertTrue(migrated[1].isClosed)
        XCTAssertEqual(migrated[1].homeSpaceUuid, "")
        XCTAssertEqual(migrated[1].windowHistory, source.windowHistory)
    }

    func testUnavailableDesktopAssignmentIsPreservedUntilRuntimeCanResolveIt() {
        var source = entry()
        source.desktopOwnershipVersion = 1
        XCTAssertEqual(ProjectLifecycleResolver.normalizingDesktopOwnership([source]), [source])
    }

    func testUnassignedProjectsCannotCombineBecauseEmptyHomesDoNotIdentifyADesktop() {
        var source = entry()
        var target = entry("target")
        source.homeSpaceUuid = ""
        target.homeSpaceUuid = ""
        XCTAssertFalse(ProjectLifecycleResolver.canCombine(source, into: target))
    }
}
