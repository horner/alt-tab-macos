import XCTest

final class ProjectsSetupResolverTests: XCTestCase {
    func testDistributionDefaultsEnableProjectsAndLabelsFor1500Milliseconds() {
        let defaults = ProjectsSetupResolver.defaults(distribution: true)
        XCTAssertEqual(defaults["projectsEnabled"], "true")
        XCTAssertEqual(defaults["spaceLabelsOnLaunch"], "true")
        XCTAssertEqual(defaults["spaceLabelRevealDuration"], "1500")
        XCTAssertEqual(defaults["projectsInitialSetupCompleted"], "false")
    }

    func testDebugDefaultsKeepProjectsAndLabelsOptIn() {
        let defaults = ProjectsSetupResolver.defaults(distribution: false)
        XCTAssertEqual(defaults["projectsEnabled"], "false")
        XCTAssertEqual(defaults["spaceLabelsOnLaunch"], "false")
        XCTAssertEqual(defaults["spaceLabelRevealDuration"], "0")
    }

    func testRegisteringDistributionDefaultsPreservesUserChoices() {
        let suite = "ProjectsSetupResolverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "projectsEnabled")
        defaults.set(false, forKey: "spaceLabelsOnLaunch")
        defaults.set(700, forKey: "spaceLabelRevealDuration")
        defaults.register(defaults: ProjectsSetupResolver.defaults(distribution: true))
        XCTAssertFalse(defaults.bool(forKey: "projectsEnabled"))
        XCTAssertFalse(defaults.bool(forKey: "spaceLabelsOnLaunch"))
        XCTAssertEqual(defaults.integer(forKey: "spaceLabelRevealDuration"), 700)
    }

    func testFirstEnableLinksEveryDesktopWithoutAnExistingProject() {
        let desktops = [desktop("a"), desktop("b", linked: true), desktop("c")]
        XCTAssertEqual(ProjectsSetupResolver.desktopsToLink(enabled: true, completed: false, desktops: desktops), ["a", "c"])
    }

    func testDisabledProjectsDeferSetup() {
        XCTAssertNil(ProjectsSetupResolver.desktopsToLink(enabled: false, completed: false, desktops: [desktop("a")]))
    }

    func testUnavailableTopologyDoesNotMarkSetupComplete() {
        XCTAssertNil(ProjectsSetupResolver.desktopsToLink(enabled: true, completed: false, desktops: []))
        XCTAssertEqual(ProjectsSetupResolver.desktopsToLink(enabled: true, completed: false, desktops: [desktop("a")]), ["a"])
    }

    func testExistingLinksCompleteSetupWithoutReplacement() {
        XCTAssertEqual(ProjectsSetupResolver.desktopsToLink(enabled: true, completed: false, desktops: [desktop("a", linked: true)]), [])
    }

    func testRelaunchAndReenableDoNotRecreateDeletedOrUnlinkedProjects() {
        XCTAssertNil(ProjectsSetupResolver.desktopsToLink(enabled: true, completed: true, desktops: [desktop("a")]))
    }

    private func desktop(_ uuid: String, linked: Bool = false) -> ProjectsSetupResolver.Desktop {
        .init(uuid: uuid, hasLinkedProject: linked)
    }
}
