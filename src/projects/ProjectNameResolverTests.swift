import XCTest

final class ProjectNameResolverTests: XCTestCase {
    func testUserNameWins() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: "Work", autoName: "Safari", desktopNumber: 2, projectNumber: 1), "Work")
    }

    func testDesktopIgnoresSavedAutomaticAppName() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: nil, autoName: "Safari", desktopNumber: 2, projectNumber: 1), "Desktop 2")
    }

    func testCustomProjectKeepsAutomaticAppName() {
        XCTAssertEqual(ProjectNameResolver.resolved(name: nil, autoName: "Safari", desktopNumber: nil, projectNumber: 1), "Safari")
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
        XCTAssertEqual(ProjectNameResolver.resolved(name: " \n ", autoName: "Safari", desktopNumber: 2, projectNumber: 1), "Desktop 2")
    }

    func testBlankAppCannotClaimName() {
        XCTAssertNil(ProjectNameResolver.claim(name: nil, autoName: nil, appName: " \t "))
    }

    func testProjectNamesReserveTheSameCaseInsensitiveFolder() {
        for name in ["work", " WORK ", "Wörk", "Ｗｏｒｋ"] {
            XCTAssertNotNil(ProjectNameResolver.validationError(name, existing: ["Work"]))
        }
        XCTAssertNotNil(ProjectNameResolver.validationError("My_Project", existing: ["My Project"]))
        XCTAssertNotNil(ProjectNameResolver.validationError("\n ", existing: []))
        XCTAssertNil(ProjectNameResolver.validationError("Personal", existing: ["Work"]))
        XCTAssertEqual(ProjectNameResolver.folderName("Alt Tab Projects"), "alt-tab-projects")
    }

    func testAutomaticProjectNamesAreDistinctWithoutRandomSuffixes() {
        XCTAssertEqual(ProjectNameResolver.available("Work", existing: ["Work", "Work 2"]), "Work 3")
        XCTAssertEqual(ProjectNameResolver.available("Finder", existing: ["Work"]), "Finder")
        let long = String(repeating: "a", count: 80)
        let available = ProjectNameResolver.available(long, existing: [long])
        XCTAssertNotEqual(ProjectNameResolver.folderName(available), ProjectNameResolver.folderName(long))
    }
}
