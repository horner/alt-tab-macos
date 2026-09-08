import XCTest

final class ProjectReattachResolverTests: XCTestCase {
    private let cloud = ProjectWindowPattern(bundleIdentifier: "com.google.Chrome", title: "Cloud")

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
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 2, onCurrentDesktop: true, hasSavedOwner: false))
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 29.9, onCurrentDesktop: true, hasSavedOwner: false))
    }

    func testOrdinaryNewWindowJoinsActiveProject() {
        XCTAssertTrue(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 30, onCurrentDesktop: true, hasSavedOwner: false))
    }

    func testSavedOwnerOtherDesktopAndRediscoveryBlockActiveAssignment() {
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 60, onCurrentDesktop: true, hasSavedOwner: true))
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: true, applicationAge: 60, onCurrentDesktop: false, hasSavedOwner: false))
        XCTAssertFalse(ProjectReattachResolver.allowsActiveAssignment(isNew: false, applicationAge: 60, onCurrentDesktop: true, hasSavedOwner: false))
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

}
