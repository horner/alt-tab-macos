import XCTest

final class WindowDesktopMoveResolverTests: XCTestCase {
    private let destination = WindowDesktopMoveResolver.Destination(id: 2, uuid: "second")
    private let desktops: [UInt64: String] = [1: "first", 2: "second"]

    func testIndividualWindowCanBeBroughtFromAnotherDesktop() {
        XCTAssertTrue(WindowDesktopMoveResolver.canMove(isEligible: true, spaces: [1], destination: destination, desktops: desktops))
    }

    func testAlreadyLocalUnknownAndAllDesktopWindowsAreNotMoved() {
        for spaces: [UInt64] in [[], [2], [1, 2]] {
            XCTAssertFalse(WindowDesktopMoveResolver.canMove(isEligible: true, spaces: spaces, destination: destination, desktops: desktops))
        }
    }

    func testFullscreenAndMissingSourceDesktopAreNotMoved() {
        XCTAssertFalse(WindowDesktopMoveResolver.canMove(isEligible: true, spaces: [3], destination: destination, desktops: desktops))
        XCTAssertFalse(WindowDesktopMoveResolver.canMove(isEligible: false, spaces: [1], destination: destination, desktops: desktops))
    }

    func testDeletedDestinationCannotBecomeAnotherDesktopWithTheSameId() {
        XCTAssertFalse(WindowDesktopMoveResolver.canMove(isEligible: true, spaces: [1], destination: destination, desktops: [1: "first"]))
        XCTAssertFalse(WindowDesktopMoveResolver.canMove(isEligible: true, spaces: [1], destination: destination, desktops: [1: "first", 2: "replacement"]))
    }

    func testMissingDestinationDoesNotFallBackToCurrentDesktop() {
        XCTAssertFalse(WindowDesktopMoveResolver.canMove(isEligible: true, spaces: [1], destination: nil, desktops: desktops))
    }

    func testConfirmationRequiresExclusiveDestinationMembership() {
        XCTAssertTrue(WindowDesktopMoveResolver.confirmed([2], destination: destination))
        for spaces: [UInt64] in [[], [1], [1, 2]] {
            XCTAssertFalse(WindowDesktopMoveResolver.confirmed(spaces, destination: destination))
        }
    }
}
