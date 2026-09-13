import XCTest

final class DesktopNavigationResolverTests: XCTestCase {
    private let first = DesktopNavigationResolver.Destination(spaceUuid: "first", projectId: "research", windowId: "editor")
    private let second = DesktopNavigationResolver.Destination(spaceUuid: "second", projectId: "work", windowId: "browser")

    func testStartupHasNoReturnDestination() {
        var history = DesktopNavigationResolver.History()
        XCTAssertNil(history.entered("first", leaving: nil, now: 0))
        XCTAssertNil(history.target(currentSpaceUuid: "first", availableSpaceUuids: ["first", "second"]))
    }

    func testDesktopChangeRemembersProjectAndWindow() {
        var history = DesktopNavigationResolver.History()
        XCTAssertNil(history.entered("second", leaving: first, now: 0))
        XCTAssertEqual(history.target(currentSpaceUuid: "second", availableSpaceUuids: ["first", "second"]), first)
    }

    func testDuplicateSpaceNotificationPreservesReturnDestination() {
        var history = DesktopNavigationResolver.History()
        _ = history.entered("second", leaving: first, now: 0)
        _ = history.entered("second", leaving: second, now: 1)
        XCTAssertEqual(history.previous, first)
    }

    func testReturnRestoresProjectAndCreatesReverseDestination() {
        var history = DesktopNavigationResolver.History()
        _ = history.entered("second", leaving: first, now: 0)
        history.beginReturn(first, now: 1)
        XCTAssertEqual(history.entered("first", leaving: second, now: 2), first)
        XCTAssertEqual(history.target(currentSpaceUuid: "first", availableSpaceUuids: ["first", "second"]), second)
        history.beginReturn(second, now: 3)
        XCTAssertEqual(history.entered("second", leaving: first, now: 4), second)
    }

    func testUnrelatedTransitionCancelsPendingRestoration() {
        var history = DesktopNavigationResolver.History()
        history.beginReturn(first, now: 0)
        XCTAssertNil(history.entered("third", leaving: second, now: 1))
        let third = DesktopNavigationResolver.Destination(spaceUuid: "third", projectId: nil, windowId: nil)
        XCTAssertNil(history.entered("first", leaving: third, now: 2))
    }

    func testFailedReturnCannotRestoreProjectOnALaterManualSwitch() {
        var history = DesktopNavigationResolver.History()
        history.beginReturn(first, now: 0)
        XCTAssertNil(history.entered("first", leaving: second, now: 4))
    }

    func testDeletedDesktopAndUnknownCurrentDesktopHaveNoReturnTarget() {
        var history = DesktopNavigationResolver.History()
        _ = history.entered("second", leaving: first, now: 0)
        XCTAssertNil(history.target(currentSpaceUuid: "second", availableSpaceUuids: ["second"]))
        XCTAssertNil(history.target(currentSpaceUuid: nil, availableSpaceUuids: ["first", "second"]))
        XCTAssertNil(history.target(currentSpaceUuid: "first", availableSpaceUuids: ["first", "second"]))
    }

    func testEmptyDesktopCanBeRememberedWithoutAProjectOrWindow() {
        var history = DesktopNavigationResolver.History()
        let empty = DesktopNavigationResolver.Destination(spaceUuid: "empty", projectId: nil, windowId: nil)
        _ = history.entered("second", leaving: empty, now: 0)
        XCTAssertEqual(history.target(currentSpaceUuid: "second", availableSpaceUuids: ["empty", "second"]), empty)
    }

    func testOtherDesktopAndFullscreenSpacesHaveADestination() {
        XCTAssertEqual(destination([2]), 2)
        XCTAssertEqual(destination([3]), 3)
    }

    func testCurrentPinnedAndOtherVisibleDisplayWindowsDoNotSwitchDesktop() {
        XCTAssertNil(destination([1]))
        XCTAssertNil(destination([1, 2, 3]))
        XCTAssertNil(destination([2], visible: [1, 2]))
    }

    func testUnknownDeletedAndWindowlessDestinationsAreNotAdvertised() {
        XCTAssertNil(destination([]))
        XCTAssertNil(destination([99]))
        XCTAssertNil(destination([2], windowless: true))
    }

    func testBackwardStepKeepsOrdinaryWindowSelection() {
        XCTAssertEqual(cycle(-1, selected: 5), .windows)
        XCTAssertEqual(cycle(-1, selected: 9), .windows)
    }

    func testForwardCycleIncludesBackAfterLastWindow() {
        XCTAssertEqual(cycle(1, selected: 9), .back)
        XCTAssertEqual(cycle(1, selected: 9, back: true), .window(2))
        XCTAssertEqual(cycle(1, selected: 2), .windows)
    }

    func testBackwardCycleIncludesBackBeforeFirstWindow() {
        XCTAssertEqual(cycle(-1, selected: 2), .back)
        XCTAssertEqual(cycle(-1, selected: 2, back: true), .window(9))
    }

    func testBackParticipatesInSingleAndEmptyWindowLists() {
        XCTAssertEqual(cycle(1, selected: 5, visible: [5]), .back)
        XCTAssertEqual(cycle(-1, selected: 5, visible: [5]), .back)
        XCTAssertEqual(cycle(1, selected: 5, back: true, visible: [5]), .window(5))
        XCTAssertEqual(cycle(-1, selected: 5, back: true, visible: [5]), .window(5))
        XCTAssertEqual(cycle(1, selected: 0, visible: []), .back)
        XCTAssertEqual(cycle(-1, selected: 0, back: true, visible: []), .back)
    }

    func testRepeatsStopAtCycleEndsWithoutTrappingBack() {
        XCTAssertEqual(cycle(1, selected: 9, repeating: true), .back)
        XCTAssertEqual(cycle(1, selected: 9, back: true, repeating: true), .stay)
        XCTAssertEqual(cycle(-1, selected: 2, repeating: true), .stay)
        XCTAssertEqual(cycle(-1, selected: 9, back: true, repeating: true), .window(9))
        XCTAssertEqual(cycle(1, selected: 9, back: true), .window(2))
    }

    func testSearchAndSpatialNavigationKeepWindowCycling() {
        XCTAssertEqual(cycle(1, selected: 9, searching: true), .windows)
        XCTAssertEqual(cycle(-1, selected: 2, searching: true), .windows)
        XCTAssertEqual(cycle(1, selected: 9, allowWrap: false), .windows)
        XCTAssertEqual(cycle(-1, selected: 2, allowWrap: false), .windows)
        XCTAssertEqual(cycle(1, selected: 9, back: true, allowWrap: false), .stay)
    }

    func testMissingDestinationAndUnsupportedStepsDoNotInterceptWindows() {
        XCTAssertEqual(cycle(1, selected: 9, hasDestination: false), .windows)
        XCTAssertEqual(cycle(-1, selected: 2, back: true, hasDestination: false), .windows)
        XCTAssertEqual(cycle(0, selected: 9), .windows)
        XCTAssertEqual(cycle(2, selected: 9), .windows)
    }

    func testUndoRequiresCommandZWithoutExtraModifiers() {
        XCTAssertTrue(DesktopNavigationResolver.isUndoShortcut(characters: "z", hasCommand: true, hasOtherModifiers: false, isSearchEditing: false))
        XCTAssertTrue(DesktopNavigationResolver.isUndoShortcut(characters: "Z", hasCommand: true, hasOtherModifiers: false, isSearchEditing: false))
        XCTAssertFalse(DesktopNavigationResolver.isUndoShortcut(characters: "z", hasCommand: false, hasOtherModifiers: false, isSearchEditing: false))
        XCTAssertFalse(DesktopNavigationResolver.isUndoShortcut(characters: "z", hasCommand: true, hasOtherModifiers: true, isSearchEditing: false))
        XCTAssertFalse(DesktopNavigationResolver.isUndoShortcut(characters: "x", hasCommand: true, hasOtherModifiers: false, isSearchEditing: false))
        XCTAssertFalse(DesktopNavigationResolver.isUndoShortcut(characters: nil, hasCommand: true, hasOtherModifiers: false, isSearchEditing: false))
    }

    func testUndoPreservesSearchEditing() {
        XCTAssertFalse(DesktopNavigationResolver.isUndoShortcut(characters: "z", hasCommand: true, hasOtherModifiers: false, isSearchEditing: true))
    }

    private func cycle(_ step: Int, selected: Int, back: Bool = false, visible: [Int] = [2, 5, 9],
                       hasDestination: Bool = true, searching: Bool = false, allowWrap: Bool = true,
                       repeating: Bool = false) -> DesktopNavigationResolver.CycleDecision {
        DesktopNavigationResolver.cycle(step: step, visibleIndices: visible, selectedIndex: selected, returnSelected: back,
            hasDestination: hasDestination, isSearching: searching, allowWrap: allowWrap, isRepeating: repeating)
    }

    private func destination(_ spaces: [UInt64], visible: [UInt64] = [1], windowless: Bool = false) -> UInt64? {
        DesktopNavigationResolver.destinationSpace(windowSpaces: spaces, currentSpace: 1, visibleSpaces: visible,
            availableSpaces: [1, 2, 3], isWindowlessApp: windowless)
    }

    func testEmptyDesktopUsesConfiguredCommandFunctionShortcut() {
        let keys: [String: Any] = ["119": ["enabled": true, "value": ["parameters": [65535, 120, 9437184]]]]
        XCTAssertEqual(DesktopNavigationResolver.systemShortcut(desktopNumber: 2, hotKeys: keys), .init(keyCode: 120, modifiers: 9437184))
    }

    func testDisabledAndMalformedSystemShortcutsAreNotSent() {
        let keys: [String: Any] = ["118": ["enabled": false], "119": ["enabled": true, "value": ["parameters": [65535, -1, 0]]]]
        XCTAssertNil(DesktopNavigationResolver.systemShortcut(desktopNumber: 1, hotKeys: keys))
        XCTAssertNil(DesktopNavigationResolver.systemShortcut(desktopNumber: 2, hotKeys: keys))
        XCTAssertNil(DesktopNavigationResolver.systemShortcut(desktopNumber: 0, hotKeys: keys))
    }

    func testUnconfiguredShortcutRetainsControlDigitFallback() {
        XCTAssertEqual(DesktopNavigationResolver.systemShortcut(desktopNumber: 6, hotKeys: [:]), .init(keyCode: 0x16, modifiers: 1 << 18))
        XCTAssertNil(DesktopNavigationResolver.systemShortcut(desktopNumber: 10, hotKeys: [:]))
    }
}
