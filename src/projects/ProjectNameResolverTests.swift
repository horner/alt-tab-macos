import XCTest

final class ProjectNameResolverTests: XCTestCase {
    func testUserNameWins() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: "Work", autoName: "Safari", desktopNumber: 2, projectNumber: 1), "Work")
    }

    func testAutoNameWinsOverFallback() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: nil, autoName: "Safari", desktopNumber: 2, projectNumber: 1), "Safari")
    }

    func testDesktopFallbackUsesDesktopNumber() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: nil, autoName: nil, desktopNumber: 7, projectNumber: 1), "Desktop 7")
    }

    func testCustomFallbackUsesCreationNumber() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: nil, autoName: nil, desktopNumber: nil, projectNumber: 3), "Project 3")
    }

    func testClaimUsesFirstAppName() {
        XCTAssertEqual(ProjectNameResolver.claim(name: nil, autoName: nil, appName: " Safari "), "Safari")
    }

    func testClaimKeepsStandingAutoName() {
        XCTAssertEqual(ProjectNameResolver.claim(name: nil, autoName: "iTerm2", appName: "Safari"), "iTerm2")
    }

    func testClaimNeverOverridesUserName() {
        XCTAssertNil(ProjectNameResolver.claim(name: "Work", autoName: nil, appName: "Safari"))
    }

    func testForgetDropsAutoNameWhenEmpty() {
        XCTAssertNil(ProjectNameResolver.forget(autoName: "Safari", hasLiveWindows: false))
    }

    func testForgetKeepsAutoNameWithLiveWindows() {
        XCTAssertEqual(ProjectNameResolver.forget(autoName: "Safari", hasLiveWindows: true), "Safari")
    }

    func testForgettingAutoNamePreservesUserName() {
        let autoName = ProjectNameResolver.forget(autoName: "Safari", hasLiveWindows: false)
        XCTAssertEqual(ProjectNameResolver.resolved(name: "Work", autoName: autoName, desktopNumber: 2, projectNumber: 1), "Work")
    }

    func testWhitespaceClearsToAutomatic() {
        XCTAssertNil(ProjectNameResolver.normalized(" \n\t "))
        XCTAssertEqual(ProjectNameResolver.resolved(name: " \n ", autoName: "Safari", desktopNumber: 2, projectNumber: 1), "Safari")
    }

    func testBlankAppCannotClaimName() {
        XCTAssertNil(ProjectNameResolver.claim(name: nil, autoName: nil, appName: " \t "))
    }
}
