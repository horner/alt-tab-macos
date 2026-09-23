import XCTest

final class ProjectWindowIdentityTests: XCTestCase {
    private func identity(_ windowId: String = "wid-1", _ pid: Int32 = 42, _ launch: TimeInterval = 100) -> ProjectWindowIdentity {
        ProjectWindowIdentity(windowId: windowId, pid: pid, processLaunchedAt: Date(timeIntervalSince1970: launch))
    }

    func testIdentitySurvivesEncoding() throws {
        let saved = identity()
        XCTAssertEqual(try JSONDecoder().decode(ProjectWindowIdentity.self, from: JSONEncoder().encode(saved)), saved)
    }

    func testDifferentWindowDoesNotMatch() {
        XCTAssertNotEqual(identity(), identity("wid-2"))
    }

    func testDifferentProcessDoesNotMatch() {
        XCTAssertNotEqual(identity(), identity("wid-1", 43))
    }

    func testReusedPidDoesNotMatch() {
        XCTAssertNotEqual(identity(), identity("wid-1", 42, 200))
    }
}
