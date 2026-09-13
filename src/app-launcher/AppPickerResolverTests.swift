import XCTest

final class AppPickerResolverTests: XCTestCase {
    func testKnownAppsCreateAndOtherAppsOpen() {
        XCTAssertEqual(AppPickerResolver.action(bundleIdentifier: "com.google.Chrome"), .chromeWindow)
        XCTAssertEqual(AppPickerResolver.action(bundleIdentifier: "com.apple.Safari"), .safariWindow)
        XCTAssertEqual(AppPickerResolver.action(bundleIdentifier: "com.apple.MobileSMS"), .message)
        XCTAssertEqual(AppPickerResolver.action(bundleIdentifier: "com.apple.iChat"), .message)
        XCTAssertEqual(AppPickerResolver.action(bundleIdentifier: "com.example.Chrome"), .open)
        XCTAssertEqual(AppPickerResolver.action(bundleIdentifier: nil), .open)
    }

    func testEntryRequiresCommandNWithoutExtraModifiersOrConflict() {
        XCTAssertTrue(AppPickerResolver.isEntryKey(characters: "n", command: true, extraModifiers: false, hasConflict: false))
        XCTAssertTrue(AppPickerResolver.isEntryKey(characters: "N", command: true, extraModifiers: false, hasConflict: false))
        XCTAssertFalse(AppPickerResolver.isEntryKey(characters: "n", command: false, extraModifiers: false, hasConflict: false))
        XCTAssertFalse(AppPickerResolver.isEntryKey(characters: "n", command: true, extraModifiers: true, hasConflict: false))
        XCTAssertFalse(AppPickerResolver.isEntryKey(characters: "n", command: true, extraModifiers: false, hasConflict: true))
        XCTAssertFalse(AppPickerResolver.isEntryKey(characters: nil, command: true, extraModifiers: false, hasConflict: false))
    }

    func testSelectionFollowsInstallationAndHandlesRemovalOrEmptyResults() {
        let first = URL(fileURLWithPath: "/Applications/Chrome.app")
        let second = URL(fileURLWithPath: "/Users/me/Applications/Chrome.app")
        XCTAssertEqual(AppPickerResolver.selection(previous: second, in: [first, second]), 1)
        XCTAssertEqual(AppPickerResolver.selection(previous: second, in: [second, first]), 0)
        XCTAssertEqual(AppPickerResolver.selection(previous: second, in: [first]), 0)
        XCTAssertNil(AppPickerResolver.selection(previous: first, in: []))
    }

    func testChromeDoesNotChooseTabOrPrivateWindow() {
        XCTAssertTrue(AppPickerResolver.isCreationMenu(.chromeWindow, identifier: "commandDispatch:", title: "New Window"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.chromeWindow, identifier: "commandDispatch:", title: "New Incognito Window"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.chromeWindow, identifier: "commandDispatch:", title: "New Tab"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.chromeWindow, identifier: "unknown:", title: "New Window"))
    }

    func testSafariUsesWindowIdentifierIncludingDefaultProfile() {
        XCTAssertTrue(AppPickerResolver.isCreationMenu(.safariWindow, identifier: "NewWindow", title: "Une fenêtre"))
        XCTAssertTrue(AppPickerResolver.isCreationMenu(.safariWindow, identifier: "New.Window?isDefaultProfile=true", title: "New . Window"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.safariWindow, identifier: "NewDougWindow?isDefaultProfile=false", title: "New Doug Window"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.safariWindow, identifier: "NewPrivateWindow", title: "New Private Window"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.safariWindow, identifier: "NewTab", title: "New Tab"))
    }

    func testMessageCommandNeverSelectsSendOrExistingConversation() {
        XCTAssertTrue(AppPickerResolver.isCreationMenu(.message, identifier: "new_message", title: "Nouveau message"))
        XCTAssertTrue(AppPickerResolver.isCreationMenu(.message, identifier: "newMessage:", title: "New Message"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.message, identifier: "send:", title: "Send Message"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.message, identifier: "keyCommandOpenConversationInNewWindow:", title: "Open Conversation in New Window"))
        XCTAssertFalse(AppPickerResolver.isCreationMenu(.open, identifier: "new_message", title: "New Message"))
    }
}
