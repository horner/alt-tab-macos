import XCTest

final class AppCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testScanFindsAppsInSubfoldersWithoutEmbeddedHelpers() throws {
        let app = try makeApp("Utilities/Browser.app", bundle: "com.example.Browser")
        _ = try makeApp("Utilities/Browser.app/Contents/Helpers/Helper.app", bundle: "com.example.Helper")
        let found = AppCatalog.scan(roots: [root])
        XCTAssertEqual(found.map { $0.url }, [app.resolvingSymlinksInPath()])
        XCTAssertEqual(found.first?.name, "Browser")
    }

    func testScanDeduplicatesRootsAndLinksButKeepsSeparateInstallations() throws {
        let first = try makeApp("Browser.app", bundle: "com.example.Browser")
        let second = try makeApp("Other/Browser.app", bundle: "com.example.Browser")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: first)
        let found = AppCatalog.scan(roots: [root, root.appendingPathComponent("Other")])
        XCTAssertEqual(Set(found.map { $0.url }), Set([first, second].map { $0.resolvingSymlinksInPath() }))
    }

    func testScanSkipsBackgroundAndInvalidApps() throws {
        _ = try makeApp("Agent.app", bundle: "com.example.Agent", background: true)
        let broken = try makeApp("Broken.app", bundle: "com.example.Broken")
        try FileManager.default.removeItem(at: broken.appendingPathComponent("Contents/MacOS/main"))
        XCTAssertTrue(AppCatalog.scan(roots: [root, root.appendingPathComponent("missing")]).isEmpty)
    }

    func testScanIncludesHiddenFlagAppsButSkipsDotDirectories() throws {
        let safari = try makeApp("Safari.app", bundle: "com.apple.Safari")
        var flagged = safari
        var values = URLResourceValues()
        values.isHidden = true
        try flagged.setResourceValues(values)
        _ = try makeApp(".Trash/Discarded.app", bundle: "com.example.Discarded")
        XCTAssertEqual(AppCatalog.scan(roots: [root]).map { $0.bundleIdentifier }, ["com.apple.Safari"])
    }

    func testNamesFallBackToFilenameAndUseDisplayName() throws {
        let first = try makeApp("Fallback.app", bundle: "com.example.Fallback")
        let second = try makeApp("Other.app", bundle: "com.example.Other", displayName: "Localized App")
        XCTAssertEqual(AppCatalog.item(at: first)?.name, "Fallback")
        XCTAssertEqual(AppCatalog.item(at: second)?.name, "Localized App")
    }

    func testMessageAliasesAndAppNamesSelectTheirActions() {
        let messages = item("Messages", "com.apple.MobileSMS")
        let chrome = item("Google Chrome", "com.google.Chrome")
        let safari = item("Safari", "com.apple.Safari")
        for query in ["sms", "text", "message"] {
            XCTAssertEqual(AppCatalog.matching(query, in: [chrome, safari, messages]).first?.action, .message)
        }
        XCTAssertEqual(AppCatalog.matching("chr", in: [messages, chrome, safari]).first?.action, .chromeWindow)
        XCTAssertEqual(AppCatalog.matching("safari", in: [chrome, safari]).first?.action, .safariWindow)
    }

    func testEmptySearchSortsAndUnmatchedSearchIsEmpty() {
        let items = [item("Zebra", nil), item("Alpha", nil)]
        XCTAssertEqual(AppCatalog.matching("  ", in: items).map { $0.name }, ["Alpha", "Zebra"])
        XCTAssertTrue(AppCatalog.matching("qzxwvu", in: items).isEmpty)
    }

    func testRecentlyUsedAppsLeadEmptySearchWithAlphabeticalFallback() {
        let chrome = item("Google Chrome", "com.google.Chrome")
        let safari = item("Safari", "com.apple.Safari")
        let calculator = item("Calculator", nil)
        let calendar = item("Calendar", nil)
        let matches = AppCatalog.matching("", in: [calculator, safari, chrome, calendar],
            recentlyUsed: [chrome.url: 200, safari.url: 100])
        XCTAssertEqual(matches.map { $0.name }, ["Google Chrome", "Safari", "Calculator", "Calendar"])
    }

    func testRecentChromeLeadsCSearchAheadOfAlphabeticalPrefixMatches() {
        let chrome = item("Google Chrome", "com.google.Chrome")
        let calculator = item("Calculator", nil)
        let safari = item("Safari", "com.apple.Safari")
        let matches = AppCatalog.matching("C", in: [calculator, safari, chrome],
            recentlyUsed: [chrome.url: 200, calculator.url: 100, safari.url: 300])
        XCTAssertEqual(matches.map { $0.name }, ["Google Chrome", "Calculator"])
        XCTAssertEqual(AppCatalog.matching("safari", in: [chrome, safari],
            recentlyUsed: [chrome.url: 400]).map { $0.name }, ["Safari"])
    }

    func testRecencyBelongsToTheSelectedInstallation() {
        let first = item("Google Chrome", "com.google.Chrome")
        let second = AppCatalogItem(url: URL(fileURLWithPath: "/Users/me/Applications/Google Chrome.app"),
            name: first.name, bundleIdentifier: first.bundleIdentifier)
        XCTAssertEqual(AppCatalog.matching("chr", in: [first, second], recentlyUsed: [second.url: 100]).map { $0.url },
            [second.url, first.url])
    }

    func testTrendingFrequencyRanksMatchingAppsAheadOfRecency() {
        let chrome = item("Google Chrome", "com.google.Chrome")
        let canary = item("Google Chrome Canary", "com.google.Chrome.canary")
        let safari = item("Safari", "com.apple.Safari")
        let matches = AppCatalog.matching("C", in: [chrome, canary, safari],
            recentlyUsed: [chrome.url: 200, canary.url: 100],
            frequencyScores: [chrome.url: 2, canary.url: 5, safari.url: 100])
        XCTAssertEqual(matches.map { $0.url }, [canary.url, chrome.url])
    }

    private func item(_ name: String, _ bundle: String?) -> AppCatalogItem {
        AppCatalogItem(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleIdentifier: bundle)
    }

    private func makeApp(_ relative: String, bundle: String, background: Bool = false, displayName: String? = nil) throws -> URL {
        let app = root.appendingPathComponent(relative)
        let executable = app.appendingPathComponent("Contents/MacOS/main")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var info: [String: Any] = ["CFBundleIdentifier": bundle, "CFBundlePackageType": "APPL", "CFBundleExecutable": "main", "LSBackgroundOnly": background]
        info["CFBundleDisplayName"] = displayName
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
}
