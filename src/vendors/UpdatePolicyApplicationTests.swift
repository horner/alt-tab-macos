import XCTest

final class UpdatePolicyApplicationTests: XCTestCase {
    func testAllPolicyTransitionsReachSelectedFlags() {
        let policies = [(checks: false, installation: false), (checks: true, installation: false), (checks: true, installation: true)]
        for initial in policies {
            for selected in policies {
                let updater = GatedUpdater(checks: initial.checks, storedDownloads: initial.installation)
                apply(selected.checks, selected.installation, updater)
                XCTAssertEqual(updater.checks, selected.checks)
                XCTAssertEqual(updater.downloads, selected.installation)
            }
        }
    }

    func testDisablingInstallationClearsItsStoredChoiceBeforeChecksStop() {
        let updater = GatedUpdater(checks: true, storedDownloads: true)
        apply(false, false, updater)
        updater.setChecks(true)
        XCTAssertFalse(updater.downloads)
    }

    func testCheckOnlyPolicyClearsHiddenInstallationChoice() {
        let updater = GatedUpdater(checks: false, storedDownloads: true)
        apply(true, false, updater)
        XCTAssertTrue(updater.checks)
        XCTAssertFalse(updater.downloads)
    }

    private func apply(_ checks: Bool, _ installation: Bool, _ updater: GatedUpdater) {
        UpdatePolicyApplication.apply(automaticChecks: checks, automaticInstallation: installation,
            setChecks: updater.setChecks, setDownloads: updater.setDownloads)
    }

    private final class GatedUpdater {
        var checks: Bool
        var storedDownloads: Bool
        var downloads: Bool { checks && storedDownloads }

        init(checks: Bool, storedDownloads: Bool) {
            self.checks = checks
            self.storedDownloads = storedDownloads
        }

        func setChecks(_ value: Bool) {
            checks = value
        }

        func setDownloads(_ value: Bool) {
            guard checks else { return }
            storedDownloads = value
        }
    }
}
