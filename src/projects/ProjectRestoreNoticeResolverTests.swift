import XCTest

final class ProjectRestoreNoticeResolverTests: XCTestCase {
    private typealias Resolver = ProjectRestoreNoticeResolver
    private let desktops: [UInt64: String] = [1: "first", 2: "second", 3: "third"]

    private func placement(_ homes: [String: String] = ["work": "second"], spaces: [UInt64] = [1], eligible: Bool = true) -> Resolver.Placement? {
        Resolver.placement(isEligible: eligible, spaces: spaces, projectHomes: homes, desktops: desktops)
    }

    func testRestorationOnTheProjectDesktopIsSilent() {
        XCTAssertNil(placement(["work": "first"]))
    }

    func testWrongDesktopCapturesAnActionableOriginalPlacement() {
        XCTAssertEqual(placement(), .init(projectId: "work", spaces: [1], destination: .init(id: 2, uuid: "second")))
    }

    func testUnownedAndSharedWindowsDoNotChooseAProject() {
        XCTAssertNil(placement([:]))
        XCTAssertNil(placement(["work": "second", "personal": "third"]))
        XCTAssertNil(placement(["work": "second", "personal": "second"]))
    }

    func testUnassignedAndDeletedProjectDesktopsAreSilent() {
        XCTAssertNil(placement(["work": ""]))
        XCTAssertNil(placement(["work": "deleted"]))
    }

    func testUnsupportedFullscreenUnknownAndAllDesktopWindowsAreSilent() {
        XCTAssertNil(placement(eligible: false))
        for spaces: [UInt64] in [[], [4], [1, 2]] {
            XCTAssertNil(placement(spaces: spaces))
        }
    }

    func testChangedOwnerSourceOrDestinationInvalidatesTheOriginalPlacement() {
        let original = placement()
        XCTAssertNotNil(original)
        XCTAssertNotEqual(placement(["personal": "second"]), original)
        XCTAssertNotEqual(placement(spaces: [3]), original)
        XCTAssertNotEqual(placement(["work": "third"]), original)
        XCTAssertNotEqual(placement(["work": "first"]), original)
    }

    func testDesktopUUIDSelectsTheDestinationAfterRenumbering() {
        XCTAssertEqual(Resolver.placement(isEligible: true, spaces: [1], projectHomes: ["work": "second"],
            desktops: [1: "first", 27: "second"]),
            .init(projectId: "work", spaces: [1], destination: .init(id: 27, uuid: "second")))
    }
}
