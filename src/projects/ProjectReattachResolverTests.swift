import XCTest

final class ProjectReattachResolverTests: XCTestCase {
    private let cloud = ProjectWindowPattern(bundleIdentifier: "com.google.Chrome", title: "Cloud")

    func testPlaceholderTitlesNeverBecomeRestorationEvidence() {
        for title in ["", " ", ". — Start Page", "New Tab - Google Chrome", "Loading…", "Untitled 2", "Safari", "Sign in", "Error"] {
            let pattern = ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: title, spaceUuid: "desktop")
            XCTAssertNil(ProjectReattachResolver.evidence(pattern), title)
            XCTAssertTrue(ProjectReattachResolver.owners(of: pattern, assignments: ["old": [pattern]]).isEmpty, title)
        }
    }

    func testVSCodeStartupTitleCannotRestoreAProjectBeforeItsWorkspaceLoads() {
        let startup = ProjectWindowPattern(bundleIdentifier: "com.microsoft.VSCode", title: "Visual Studio Code", spaceUuid: "ui-desktop")
        let workspace = ProjectWindowPattern(bundleIdentifier: "com.microsoft.VSCode", title: "ui-artipod-integration", spaceUuid: "ui-desktop")
        XCTAssertNil(ProjectReattachResolver.evidence(startup))
        XCTAssertTrue(ProjectReattachResolver.owners(of: startup, assignments: ["alt-tab": [startup]]).isEmpty)
        XCTAssertTrue(ProjectReattachResolver.owners(of: workspace, assignments: ["alt-tab": [startup]]).isEmpty)
        XCTAssertEqual(ProjectReattachResolver.owners(of: workspace, assignments: ["ui": [workspace], "alt-tab": [startup]]), ["ui"])
    }

    func testTransientURLCannotBecomeEvidenceEvenWithAUsefulTitle() {
        for url in ["about:blank", "chrome://newtab", "https://example.com/login", "https://example.com/oauth2/authorize"] {
            XCTAssertNil(ProjectReattachResolver.evidence(ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", url: url)))
        }
    }

    func testUsefulURLCanArriveBeforeTitle() {
        let pending = ProjectWindowPattern(bundleIdentifier: "Safari", title: "Start Page", url: "https://example.com/work")
        let evidence = ProjectReattachResolver.evidence(pending)
        XCTAssertEqual(evidence?.title, "")
        XCTAssertEqual(evidence?.url, pending.url)
        XCTAssertEqual(ProjectReattachResolver.owners(of: pending, assignments: ["work": [pending]]), ["work"])
    }

    func testLegacyPlaceholderDoesNotClaimAnUnrelatedWindowOnSameDesktop() {
        let old = ProjectWindowPattern(bundleIdentifier: "Safari", title: "Start Page", spaceUuid: "a")
        let current = ProjectWindowPattern(bundleIdentifier: "Safari", title: "Documentation", spaceUuid: "a")
        XCTAssertTrue(ProjectReattachResolver.owners(of: current, assignments: ["old": [old]]).isEmpty)
    }

    func testTitleAndURLChangesCannotAddAnOwnerToAnAssignedWindow() {
        XCTAssertTrue(ProjectReattachResolver.restorationCandidates(liveOwners: ["ui"], identityOwners: [], savedOwners: ["old"], declined: false).isEmpty)
        XCTAssertTrue(ProjectReattachResolver.restorationCandidates(liveOwners: ["ui", "work"], identityOwners: ["old"], savedOwners: ["old"], declined: false).isEmpty)
    }

    func testLiveIdentityWinsBeforeTitleRestorationAndPreservesSharedMembership() {
        XCTAssertEqual(ProjectReattachResolver.restorationCandidates(liveOwners: [], identityOwners: ["ui", "work"], savedOwners: ["old"], declined: false), ["ui", "work"])
    }

    func testDismissedAndAmbiguousWindowsHaveNoAutomaticRestorationCandidate() {
        XCTAssertTrue(ProjectReattachResolver.restorationCandidates(liveOwners: [], identityOwners: [], savedOwners: ["ui"], declined: true).isEmpty)
        XCTAssertTrue(ProjectReattachResolver.restorationCandidates(liveOwners: [], identityOwners: [], savedOwners: ["ui", "work"], declined: false).isEmpty)
    }

    func testExplicitChoiceIsLearnedWithoutGuessingBetweenConflictingChoices() throws {
        let confirmed = ProjectWindowPattern(bundleIdentifier: cloud.bundleIdentifier, title: cloud.title, confirmedAt: Date(timeIntervalSince1970: 100))
        let decoded = try JSONDecoder().decode(ProjectWindowPattern.self, from: JSONEncoder().encode(confirmed))
        XCTAssertEqual(decoded.confirmedAt, confirmed.confirmedAt)
        XCTAssertEqual(ProjectReattachResolver.owners(of: cloud, assignments: ["ui": [decoded], "old": [cloud]]), ["ui"])
        XCTAssertEqual(ProjectReattachResolver.owners(of: cloud, assignments: ["ui": [decoded], "old": [confirmed]]), ["ui", "old"])
    }

    func testConfirmationDoesNotOverrideDesktopDisambiguation() {
        let first = ProjectWindowPattern(bundleIdentifier: "Editor", title: "Document", spaceUuid: "a", confirmedAt: Date())
        let second = ProjectWindowPattern(bundleIdentifier: "Editor", title: "Document", spaceUuid: "b")
        XCTAssertEqual(ProjectReattachResolver.owners(of: second, assignments: ["a": [first], "b": [second]]), ["b"])
    }

    func testReviewEvidenceRejectsNavigationOrDesktopChanges() {
        let original = ProjectWindowPattern(bundleIdentifier: "Safari", title: "Docs", spaceUuid: "a", url: "https://example.com/docs")
        var updated = original
        updated.url = "https://example.com/other"
        XCTAssertFalse(ProjectReattachResolver.sameEvidence(original, updated))
        updated = original
        updated.spaceUuid = "b"
        XCTAssertFalse(ProjectReattachResolver.sameEvidence(original, updated))
        updated = original
        updated.url = nil
        XCTAssertFalse(ProjectReattachResolver.sameEvidence(original, updated))
        let renamed = ProjectWindowPattern(bundleIdentifier: original.bundleIdentifier, title: "New title", spaceUuid: "a", url: original.url)
        XCTAssertTrue(ProjectReattachResolver.sameEvidence(original, renamed))
    }

    func testExactAppAndTitleRestoreOwner() {
        XCTAssertEqual(ProjectReattachResolver.owners(of: cloud, assignments: ["cloud": [cloud]]), ["cloud"])
    }

    func testDifferentAppOrChangedTitleDoesNotGuess() {
        let assignments = ["cloud": [cloud]]
        XCTAssertTrue(ProjectReattachResolver.owners(of: ProjectWindowPattern(bundleIdentifier: "com.google.Chrome.beta", title: "Cloud"), assignments: assignments).isEmpty)
        XCTAssertTrue(ProjectReattachResolver.owners(of: ProjectWindowPattern(bundleIdentifier: "com.google.Chrome", title: "Cloud settings"), assignments: assignments).isEmpty)
    }

    func testConflictingProjectsRemainDetectablyAmbiguous() {
        XCTAssertEqual(ProjectReattachResolver.owners(of: cloud, assignments: ["cloud": [cloud], "case": [cloud]]).count, 2)
    }

    func testEmptyTitlesCannotClaimWindows() {
        let empty = ProjectWindowPattern(bundleIdentifier: "com.google.Chrome", title: " ")
        XCTAssertTrue(ProjectReattachResolver.owners(of: empty, assignments: ["cloud": [empty]]).isEmpty)
    }

    func testAppStartupWindowsDoNotJoinActiveProject() {
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 2, onCurrentDesktop: true))
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 29.9, onCurrentDesktop: true))
    }

    func testOrdinaryNewWindowJoinsActiveProject() {
        XCTAssertTrue(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 30, onCurrentDesktop: true))
    }

    func testNewWindowContextDoesNotConsultSavedTitles() {
        XCTAssertTrue(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 60, onCurrentDesktop: true))
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 60, onCurrentDesktop: false))
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: false, applicationAge: 60, onCurrentDesktop: true))
    }

    func testDesktopProjectCannotResolveAmbiguousSavedOwners() {
        XCTAssertFalse(ProjectReattachResolver.allowsAutomaticAssignment(to: "desktop-project",
            savedOwners: ["desktop-project", "other"], liveOwners: []))
        XCTAssertFalse(ProjectReattachResolver.allowsAutomaticAssignment(to: "unrelated",
            savedOwners: ["desktop-project", "other"], liveOwners: []))
    }

    func testAutomaticAssignmentPreservesLiveAndUniqueSavedOwners() {
        XCTAssertFalse(ProjectReattachResolver.allowsAutomaticAssignment(to: "desktop-project",
            savedOwners: ["desktop-project", "other"], liveOwners: ["other"]))
        XCTAssertFalse(ProjectReattachResolver.allowsAutomaticAssignment(to: "desktop-project",
            savedOwners: ["other"], liveOwners: []))
    }

    func testAutomaticAssignmentAcceptsUnownedAndSameProjectWindows() {
        XCTAssertTrue(ProjectReattachResolver.allowsAutomaticAssignment(to: "desktop-project", savedOwners: [], liveOwners: []))
        XCTAssertTrue(ProjectReattachResolver.allowsAutomaticAssignment(to: "desktop-project",
            savedOwners: ["desktop-project"], liveOwners: ["desktop-project"]))
    }

    func testPatternsSurviveEncodingWithoutRunningApp() throws {
        XCTAssertEqual(try JSONDecoder().decode(ProjectWindowPattern.self, from: JSONEncoder().encode(cloud)), cloud)
    }
    func testMovingOneOfTwoIdenticallyTitledWindowsPreservesTheirSeparateAssignments() {
        XCTAssertTrue(ProjectReattachResolver.shouldRestore(hasLiveIdentity: true, identityExcluded: false,
            patternExcluded: true, isUniquePatternOwner: false))
        XCTAssertFalse(ProjectReattachResolver.shouldRestore(hasLiveIdentity: false, identityExcluded: true,
            patternExcluded: false, isUniquePatternOwner: true))
        XCTAssertFalse(ProjectReattachResolver.shouldRestore(hasLiveIdentity: true, identityExcluded: true,
            patternExcluded: false, isUniquePatternOwner: true))
    }

    func testNewIdentityRequiresUniqueUnexcludedPattern() {
        XCTAssertTrue(ProjectReattachResolver.shouldRestore(hasLiveIdentity: false, identityExcluded: false,
            patternExcluded: false, isUniquePatternOwner: true))
        XCTAssertFalse(ProjectReattachResolver.shouldRestore(hasLiveIdentity: false, identityExcluded: false,
            patternExcluded: true, isUniquePatternOwner: true))
        XCTAssertFalse(ProjectReattachResolver.shouldRestore(hasLiveIdentity: false, identityExcluded: false,
            patternExcluded: false, isUniquePatternOwner: false))
    }

    func testChangedTitleCannotRestoreFromAppDesktopHistory() {
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", spaceUuid: "desktop-case")
        let reopened = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Shared document", spaceUuid: "desktop-case")
        XCTAssertTrue(ProjectReattachResolver.owners(of: reopened, assignments: ["case": [saved]]).isEmpty)
    }

    func testExactTitleRestoresEvenOnAnotherDesktop() {
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", spaceUuid: "desktop-case")
        let reopened = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", spaceUuid: "desktop-other")
        XCTAssertEqual(ProjectReattachResolver.owners(of: reopened, assignments: ["case": [saved]]), ["case"])
    }

    func testDesktopSeparatesIdenticalTitlesInDifferentProjects() {
        let caseWindow = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Shared document", spaceUuid: "desktop-case")
        let cloudWindow = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Shared document", spaceUuid: "desktop-cloud")
        XCTAssertEqual(ProjectReattachResolver.owners(of: cloudWindow, assignments: ["case": [caseWindow], "cloud": [cloudWindow]]), ["cloud"])
    }

    func testUnknownDesktopAndConflictingDesktopHistoryDoNotGuess() {
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", spaceUuid: "desktop-case")
        let elsewhere = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Sign in", spaceUuid: "desktop-other")
        XCTAssertTrue(ProjectReattachResolver.owners(of: elsewhere, assignments: ["case": [saved]]).isEmpty)
        let sameSpace = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Shared document", spaceUuid: "desktop-case")
        XCTAssertTrue(ProjectReattachResolver.owners(of: sameSpace, assignments: ["case": [saved], "cloud": [saved]]).isEmpty)
    }

    func testLegacyPatternWithoutDesktopStillDecodes() throws {
        let json = Data(#"{"bundleIdentifier":"Chrome","title":"Work"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ProjectWindowPattern.self, from: json).spaceUuid)
    }

    func testLastSeenDoesNotChangeMatchingIdentity() {
        let earlier = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", spaceUuid: "case", lastSeenAt: Date(timeIntervalSince1970: 100))
        let later = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", spaceUuid: "case", lastSeenAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(earlier, later)
        XCTAssertEqual(ProjectReattachResolver.owners(of: later, assignments: ["case": [earlier]]), ["case"])
    }

    func testLastSeenTimestampSurvivesEncoding() throws {
        let seen = Date(timeIntervalSince1970: 100)
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", lastSeenAt: seen)
        let decoded = try JSONDecoder().decode(ProjectWindowPattern.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.lastSeenAt, seen)
    }

    func testURLRestoresProjectDespiteSignInTitleChange() {
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", url: "https://example.com/work")
        let reopened = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Sign in", url: "https://example.com/work")
        let other = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Sign in")
        XCTAssertEqual(ProjectReattachResolver.owners(of: reopened, assignments: ["work": [saved], "other": [other]]), ["work"])
    }

    func testDifferentKnownURLsDoNotMatchOnlyByTitle() {
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Sign in", url: "https://example.com/work")
        let reopened = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Sign in", url: "https://example.com/personal")
        XCTAssertTrue(ProjectReattachResolver.owners(of: reopened, assignments: ["work": [saved]]).isEmpty)
    }

    func testSharedURLUsesDesktopToResolveProject() {
        let first = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Old", spaceUuid: "a", url: "https://example.com/docs")
        let second = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Old", spaceUuid: "b", url: "https://example.com/docs")
        let reopened = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Sign in", spaceUuid: "b", url: "https://example.com/docs")
        XCTAssertEqual(ProjectReattachResolver.owners(of: reopened, assignments: ["a": [first], "b": [second]]), ["b"])
    }

    func testURLSurvivesEncodingAndOlderHistoryStillLoads() throws {
        let saved = ProjectWindowPattern(bundleIdentifier: "Chrome", title: "Work", url: "https://example.com/work")
        XCTAssertEqual(try JSONDecoder().decode(ProjectWindowPattern.self, from: JSONEncoder().encode(saved)).url, saved.url)
        XCTAssertNil(try JSONDecoder().decode(ProjectWindowPattern.self, from: Data(#"{"bundleIdentifier":"Chrome","title":"Work"}"#.utf8)).url)
    }

    func testObservationMatchesChangedTitleByURLWithoutConflatingDifferentURLs() {
        let saved = ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Work", url: "https://example.com/work")
        XCTAssertTrue(ProjectReattachResolver.matchesObservation(saved, ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Sign in", url: saved.url)))
        XCTAssertFalse(ProjectReattachResolver.matchesObservation(saved, ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Work", url: "https://example.com/other")))
        XCTAssertTrue(ProjectReattachResolver.matchesObservation(saved, ProjectWindowPattern(bundleIdentifier: "com.apple.Safari", title: "Work")))
        XCTAssertFalse(ProjectReattachResolver.matchesObservation(saved, ProjectWindowPattern(bundleIdentifier: "com.google.Chrome", title: "Work", url: saved.url)))
    }

}
