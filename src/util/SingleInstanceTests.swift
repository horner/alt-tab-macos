import XCTest

final class SingleInstanceTests: XCTestCase {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("instance.lock") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testDuplicateCannotAcquireLock() throws {
        let owner = try SingleInstance(url: url)
        try withExtendedLifetime(owner) {
            XCTAssertThrowsError(try SingleInstance(url: url)) { error in
                guard case SingleInstance.Failure.alreadyRunning = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testOwnerExitAllowsNextLaunchWithoutDeletingFile() throws {
        var owner: SingleInstance? = try SingleInstance(url: url)
        XCTAssertNotNil(owner)
        owner = nil
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let replacement = try SingleInstance(url: url)
        withExtendedLifetime(replacement) {}
    }

    func testRestartWaitsUntilOwnerReleasesLock() throws {
        var owner: SingleInstance? = try SingleInstance(url: url)
        let acquired = expectation(description: "Replacement acquires released lock")
        let started = DispatchSemaphore(value: 0)
        let lockURL = url
        DispatchQueue.global().async {
            started.signal()
            do {
                let replacement = try SingleInstance(url: lockURL, wait: true)
                withExtendedLifetime(replacement) { acquired.fulfill() }
            } catch {
                XCTFail("Restart failed: \(error)")
                acquired.fulfill()
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        XCTAssertNotNil(owner)
        owner = nil
        wait(for: [acquired], timeout: 2)
    }

    func testLockOpenFailureDoesNotAllowStartup() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try SingleInstance(url: url))
    }
}
