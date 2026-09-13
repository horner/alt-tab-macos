import XCTest

final class SpaceLabelResolverTests: XCTestCase {
    func testNamingDesktopShowsOnlyItsProjectLabels() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.show(["project-a", "project-b"])
        XCTAssertTrue(visibility.isRequested)
        XCTAssertTrue(visibility.includes("project-a"))
        XCTAssertTrue(visibility.includes("project-b"))
        XCTAssertFalse(visibility.includes("another-desktop"))
        XCTAssertFalse(visibility.includes("new-desktop"))
    }

    func testNamingReopensItsLabelWithoutRestoringOtherClosedLabels() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.close("project-a")
        visibility.close("project-b")
        visibility.minimizeAll()
        let revision = visibility.presentationRevision
        visibility.show(["project-a"])
        XCTAssertTrue(visibility.includes("project-a"))
        XCTAssertFalse(visibility.includes("project-b"))
        XCTAssertEqual(visibility.presentation, .minimized)
        XCTAssertEqual(visibility.presentationRevision, revision)
    }

    func testSelectiveLabelsCloseAndShowAllStillRestoresEveryDesktop() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.show(["project-a"])
        visibility.close("project-a")
        XCTAssertFalse(visibility.isRequested)
        visibility.show(["project-a"])
        visibility.hideAll()
        XCTAssertFalse(visibility.includes("project-a"))
        visibility.showAll()
        XCTAssertTrue(visibility.includes("project-a"))
        XCTAssertTrue(visibility.includes("new-desktop"))
    }

    func testTwoProjectLabelsKeepSeparateIdentitiesOnOneDesktop() {
        let space = SpaceLabelResolver.Space(id: 1, uuid: "destination", displayIdentifier: "display", desktopNumber: 1, ordinal: 1)
        let labels = [SpaceLabelResolver.Label(space: space, name: "First", identity: "project-a"),
            SpaceLabelResolver.Label(space: space, name: "Second", identity: "project-b", stackIndex: 1)]
        XCTAssertEqual(Set(labels.map { $0.id }), ["project-a", "project-b"])
        XCTAssertEqual(Set(labels.map { $0.space.id }), [1])
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.close("project-a")
        XCTAssertFalse(visibility.includes(labels[0].id))
        XCTAssertTrue(visibility.includes(labels[1].id))
    }

    func testMergedLabelsAvoidOverlapWithDifferentHeights() {
        let visible = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let resident = SpaceLabelResolver.frame(visibleFrame: visible, height: 300)
        let incoming = SpaceLabelResolver.frame(visibleFrame: visible, height: 180, stackIndex: 1)
        XCTAssertTrue(resident.intersects(incoming))
        let placed = SpaceLabelResolver.avoidingOverlap(incoming, in: visible, occupied: [resident])
        XCTAssertFalse(resident.intersects(placed))
        XCTAssertTrue(visible.contains(placed))
    }

    func testUnobstructedUserPositionSurvivesDesktopMerge() {
        let visible = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let resident = CGRect(x: 700, y: 24, width: 600, height: 220)
        let incoming = CGRect(x: 10, y: 200, width: 600, height: 220)
        XCTAssertEqual(SpaceLabelResolver.avoidingOverlap(incoming, in: visible, occupied: [resident]), incoming)
    }

    func testDefaultRevealDurationIsFifteenHundredMilliseconds() {
        XCTAssertEqual(SpaceLabelResolver.defaultRevealDuration, 1500)
        XCTAssertEqual(SpaceLabelResolver.revealDuration(0), 0)
    }

    func testLabelsFollowSwitcherVisibilityPreference() {
        XCTAssertEqual(SpaceLabelResolver.switcherVisibility(windowId: 7, pid: 100, ownerPid: 100,
            labelWindowIds: [7], showInSwitcher: true), true)
        XCTAssertEqual(SpaceLabelResolver.switcherVisibility(windowId: 7, pid: 100, ownerPid: 100,
            labelWindowIds: [7], showInSwitcher: false), false)
    }

    func testSwitcherAccessDoesNotVouchForOtherWindowsOrProcesses() {
        XCTAssertNil(SpaceLabelResolver.switcherVisibility(windowId: 7, pid: 200, ownerPid: 100,
            labelWindowIds: [7], showInSwitcher: true))
        XCTAssertNil(SpaceLabelResolver.switcherVisibility(windowId: 8, pid: 100, ownerPid: 100,
            labelWindowIds: [7], showInSwitcher: true))
        XCTAssertNil(SpaceLabelResolver.switcherVisibility(windowId: nil, pid: 100, ownerPid: 100,
            labelWindowIds: [7], showInSwitcher: true))
        XCTAssertNil(SpaceLabelResolver.switcherVisibility(windowId: 0, pid: 100, ownerPid: 100,
            labelWindowIds: [0], showInSwitcher: true))
    }

    func testShowRequestsFrontPresentation() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        XCTAssertEqual(visibility.presentation, .front)
    }

    func testClickAwaySendsLabelsBackWithoutClosingThem() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        XCTAssertTrue(visibility.sendToBack(after: visibility.presentationRevision))
        XCTAssertEqual(visibility.presentation, .back)
        XCTAssertTrue(visibility.includes("a"))
    }

    func testBringToFrontPreservesIndividuallyClosedLabels() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.close("a")
        visibility.minimizeAll()
        visibility.bringToFront()
        XCTAssertEqual(visibility.presentation, .front)
        XCTAssertFalse(visibility.includes("a"))
        XCTAssertTrue(visibility.includes("b"))
    }

    func testOldClickCannotUndoANewerBringToFront() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        let oldRevision = visibility.presentationRevision
        visibility.bringToFront()
        XCTAssertFalse(visibility.sendToBack(after: oldRevision))
        XCTAssertEqual(visibility.presentation, .front)
    }

    func testOldSessionClickCannotLowerRecreatedLabels() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        let oldRevision = visibility.presentationRevision
        visibility.hideAll()
        visibility.showAll()
        XCTAssertFalse(visibility.sendToBack(after: oldRevision))
        XCTAssertEqual(visibility.presentation, .front)
    }

    func testMinimizeAllPreservesTheOpenSession() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.minimizeAll()
        XCTAssertEqual(visibility.presentation, .minimized)
        XCTAssertTrue(visibility.includes("a"))
        XCTAssertTrue(visibility.includes("new-space"))
    }

    func testQueuedClickCannotOverrideMinimizeAll() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        let oldRevision = visibility.presentationRevision
        visibility.minimizeAll()
        XCTAssertFalse(visibility.sendToBack(after: oldRevision))
        XCTAssertEqual(visibility.presentation, .minimized)
    }

    func testPresentationActionsDoNotStartAClosedSession() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.bringToFront()
        visibility.minimizeAll()
        XCTAssertFalse(visibility.sendToBack(after: visibility.presentationRevision))
        XCTAssertFalse(visibility.isRequested)
        XCTAssertEqual(visibility.presentation, .back)
    }

    func testLabelsStartUnrequested() {
        let visibility = SpaceLabelResolver.Visibility()
        XCTAssertFalse(visibility.isRequested)
        XCTAssertFalse(visibility.includes("a"))
    }

    func testShowAllIncludesExistingAndNewSpaces() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        XCTAssertTrue(visibility.includes("a"))
        XCTAssertTrue(visibility.includes("new-space"))
    }

    func testClosedLabelStaysClosedAcrossRefreshes() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.close("a")
        XCTAssertFalse(visibility.includes("a"))
        XCTAssertTrue(visibility.includes("b"))
        XCTAssertFalse(visibility.includes("a"))
    }

    func testShowAllExplicitlyRestoresClosedLabels() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.close("a")
        visibility.showAll()
        XCTAssertTrue(visibility.includes("a"))
    }

    func testCloseAllSuppressesExistingAndNewSpaces() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.hideAll()
        XCTAssertFalse(visibility.isRequested)
        XCTAssertFalse(visibility.includes("a"))
        XCTAssertFalse(visibility.includes("new-space"))
    }

    func testShowingAfterCloseAllStartsFresh() {
        var visibility = SpaceLabelResolver.Visibility()
        visibility.showAll()
        visibility.close("a")
        visibility.hideAll()
        visibility.showAll()
        XCTAssertTrue(visibility.includes("a"))
    }

    private func space(_ uuid: String = "a", id: UInt64 = 1, desktop: Int = 1, ordinal: Int = 1,
                       display: String = "display") -> SpaceLabelResolver.Space {
        SpaceLabelResolver.Space(id: id, uuid: uuid, displayIdentifier: display, desktopNumber: desktop, ordinal: ordinal)
    }

    private func labels(_ spaces: [SpaceLabelResolver.Space], name: String? = nil,
                        automatic: String? = nil, enabled: Bool = true) -> [SpaceLabelResolver.Label] {
        SpaceLabelResolver.labels(spaces: spaces, names: ["a": .init(explicit: name, automatic: automatic)], enabled: enabled)
    }

    private func raw(_ id: UInt64, _ uuid: String, type: Int = 0) -> NSDictionary {
        ["id64": id, "uuid": uuid, "type": type]
    }

    func testExplicitNameWinsAndTrimsWhitespace() {
        XCTAssertEqual(labels([space()], name: "  Research\n", automatic: "Safari").first?.name, "Research")
    }

    func testClearedNameFallsBackToAutomaticName() {
        XCTAssertEqual(labels([space()], name: " \n", automatic: " Safari ").first?.name, "Safari")
    }

    func testEmptySpaceKeepsNumberWithoutAName() {
        let label = labels([space(desktop: 7)], name: "", automatic: "\n")[0]
        XCTAssertNil(label.name)
        XCTAssertEqual(label.number, 7)
    }

    func testRenamingUsesLatestSavedName() {
        let original = labels([space()], name: "Research")
        let renamed = labels([space()], name: "Writing")
        XCTAssertNotEqual(original, renamed)
        XCTAssertEqual(renamed.first?.name, "Writing")
    }

    func testNamesFollowUuidAcrossSessionIdChanges() {
        let label = labels([space(id: 88)], name: "Research")[0]
        XCTAssertEqual(label.space.id, 88)
        XCTAssertEqual(label.name, "Research")
    }

    func testReorderingChangesNumbersWithoutSwappingNames() {
        let names: [String: SpaceLabelResolver.Name] = ["a": .init(explicit: "Research", automatic: nil), "b": .init(explicit: "Writing", automatic: nil)]
        let result = SpaceLabelResolver.labels(spaces: [space("b", id: 2), space("a", desktop: 2, ordinal: 2)], names: names, enabled: true)
        XCTAssertEqual(result.map { $0.name }, ["Writing", "Research"])
        XCTAssertEqual(result.map { $0.number }, [1, 2])
    }

    func testDuplicateNamesRemainSeparateSpaces() {
        let result = SpaceLabelResolver.labels(spaces: [space(), space("b", id: 2, desktop: 2)],
            names: ["a": .init(explicit: "Work", automatic: nil), "b": .init(explicit: "Work", automatic: nil)], enabled: true)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map { $0.space.uuid }).count, 2)
        XCTAssertEqual(result.map { $0.name }, ["Work", "Work"])
    }

    func testLongUnicodeNameIsPreservedForAccessibleText() {
        let name = String(repeating: "研究 👩🏽‍💻 ", count: 50).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(labels([space()], name: name).first?.name, name)
    }

    func testFullscreenUsesSpaceOrdinalInsteadOfDesktopZero() {
        let result = labels([space(desktop: 0, ordinal: 4)])[0]
        XCTAssertTrue(result.isFullscreen)
        XCTAssertEqual(result.number, 4)
    }

    func testDisabledProducesNoLabels() {
        XCTAssertTrue(labels([space()], name: "Research", enabled: false).isEmpty)
    }

    func testTopologyIncludesFullscreenAndNumbersDesktopsAcrossDisplays() {
        let result = SpaceLabelResolver.spaces(from: [
            ["Display Identifier": "left", "Spaces": [raw(10, "a"), raw(20, "b", type: 4)]],
            ["Display Identifier": "right", "Spaces": [raw(30, "c")]],
        ])!
        XCTAssertEqual(result.map { $0.desktopNumber }, [1, 0, 2])
        XCTAssertEqual(result.map { $0.ordinal }, [1, 2, 3])
        XCTAssertEqual(result.map { $0.displayIdentifier }, ["left", "left", "right"])
    }

    func testUnifiedDisplayTopologyPreservesMainIdentifier() {
        let result = SpaceLabelResolver.spaces(from: [["Display Identifier": "Main", "Spaces": [raw(1, "a")]]])
        XCTAssertEqual(result?.first?.displayIdentifier, "Main")
    }

    func testIncompleteTopologyCannotDeleteExistingLabels() {
        XCTAssertNil(SpaceLabelResolver.spaces(from: [["Display Identifier": "display"]]))
        XCTAssertNil(SpaceLabelResolver.spaces(from: [["Display Identifier": "display", "Spaces": [raw(1, "")]]]))
        XCTAssertNil(SpaceLabelResolver.spaces(from: [["Display Identifier": "display", "Spaces": [["id64": 1, "uuid": "a"]]]]))
    }

    func testDuplicateUuidRejectsAmbiguousTopology() {
        XCTAssertNil(SpaceLabelResolver.spaces(from: [["Display Identifier": "display", "Spaces": [raw(1, "a"), raw(2, "a")]]]))
    }

    func testRemovedSpaceIsAbsentFromNextSnapshot() {
        let before = SpaceLabelResolver.spaces(from: [["Display Identifier": "display", "Spaces": [raw(1, "a"), raw(2, "b")]]])!
        let after = SpaceLabelResolver.spaces(from: [["Display Identifier": "display", "Spaces": [raw(2, "b")]]])!
        XCTAssertEqual(labels(before).count, 2)
        XCTAssertEqual(labels(after).map { $0.space.uuid }, ["b"])
        XCTAssertEqual(labels(after).map { $0.number }, [1])
    }

    func testFrameUsesHalfTheScreenWidthAndTextHeight() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = SpaceLabelResolver.frame(visibleFrame: visible, height: 180)
        XCTAssertEqual(frame.width, 960)
        XCTAssertEqual(frame.height, 180)
        XCTAssertEqual(frame.maxX, 1896)
        XCTAssertEqual(frame.minY, 24)
    }

    func testFrameScalesWithLandscapeAndPortraitScreens() {
        for size in [CGSize(width: 1512, height: 900), CGSize(width: 1080, height: 1920), CGSize(width: 3840, height: 2160)] {
            let visible = CGRect(origin: .zero, size: size)
            let frame = SpaceLabelResolver.frame(visibleFrame: visible, height: 180)
            XCTAssertEqual(frame.width / size.width, 0.5)
            XCTAssertEqual(frame.height, 180)
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testFrameUsesDisplayOrigin() {
        let visible = CGRect(x: -1920, y: 80, width: 1920, height: 1080)
        let frame = SpaceLabelResolver.frame(visibleFrame: visible, height: 180)
        XCTAssertEqual(frame, CGRect(x: -984, y: 104, width: 960, height: 180))
    }

    func testOddScreenDimensionsMatchAppKitFrameRounding() {
        let frame = SpaceLabelResolver.frame(visibleFrame: CGRect(x: 0, y: 0, width: 1471, height: 923), height: 179.5)
        XCTAssertEqual(frame, CGRect(x: 711, y: 24, width: 736, height: 180))
    }

    func testSavedPositionSurvivesLabelHeightChanges() {
        let visible = CGRect(x: 0, y: 40, width: 1920, height: 1040)
        let position = SpaceLabelResolver.Position(displayIdentifier: "display", x: 50, y: 100)
        for height in [180.0, 240.0] {
            let frame = SpaceLabelResolver.frame(visibleFrame: visible, height: height, position: position)
            XCTAssertEqual(frame.origin, CGPoint(x: 50, y: 140))
        }
    }

    func testSavedPositionFollowsDisplayOrigin() {
        let position = SpaceLabelResolver.Position(displayIdentifier: "display", x: 80, y: 120)
        let frame = SpaceLabelResolver.frame(visibleFrame: CGRect(x: -1920, y: 70, width: 1920, height: 1080), height: 180, position: position)
        XCTAssertEqual(frame.origin, CGPoint(x: -1840, y: 190))
    }

    func testOffscreenPositionIsClampedAfterDisplayChanges() {
        let visible = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let position = SpaceLabelResolver.Position(displayIdentifier: "disconnected", x: 1800, y: -200)
        let frame = SpaceLabelResolver.frame(visibleFrame: visible, height: 200, position: position)
        XCTAssertEqual(frame, CGRect(x: 512, y: 0, width: 512, height: 200))
        XCTAssertTrue(visible.contains(frame))
    }

    func testOversizedLabelRemainsInsideUsableScreen() {
        let visible = CGRect(x: 0, y: 40, width: 800, height: 160)
        XCTAssertTrue(visible.contains(SpaceLabelResolver.frame(visibleFrame: visible, height: 300)))
    }

    func testInvalidSavedPositionUsesDefaultCorner() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let position = SpaceLabelResolver.Position(displayIdentifier: "display", x: .nan, y: .infinity)
        XCTAssertEqual(SpaceLabelResolver.frame(visibleFrame: visible, height: 180, position: position),
            SpaceLabelResolver.frame(visibleFrame: visible, height: 180))
    }

    func testPositionRoundTripPreservesDisplayAndOffsets() throws {
        let position = SpaceLabelResolver.Position(displayIdentifier: "display", x: 200, y: 65)
        let restored = try JSONDecoder().decode(SpaceLabelResolver.Position.self, from: JSONEncoder().encode(position))
        XCTAssertEqual(restored, position)
    }

    func testInitialTopologyDoesNotRevealLabels() {
        var arrival = SpaceLabelResolver.Arrival()
        XCTAssertTrue(arrival.update(["left": 1, "right": 2], didSwitch: true).isEmpty)
    }

    func testSpaceSwitchRevealsOnlyChangedDisplays() {
        var arrival = SpaceLabelResolver.Arrival()
        _ = arrival.update(["left": 1, "right": 2], didSwitch: false)
        XCTAssertEqual(arrival.update(["left": 3, "right": 2], didSwitch: true), [3])
        XCTAssertEqual(arrival.update(["left": 4, "right": 5], didSwitch: true), [4, 5])
    }

    func testDuplicateNotificationDoesNotRestartReveal() {
        var arrival = SpaceLabelResolver.Arrival()
        _ = arrival.update(["left": 1], didSwitch: false)
        XCTAssertEqual(arrival.update(["left": 2], didSwitch: true), [2])
        XCTAssertTrue(arrival.update(["left": 2], didSwitch: true).isEmpty)
    }

    func testNewDisplayAndRoutineRefreshDoNotRevealLabels() {
        var arrival = SpaceLabelResolver.Arrival()
        _ = arrival.update(["left": 1], didSwitch: false)
        XCTAssertTrue(arrival.update(["left": 1], didSwitch: false).isEmpty)
        XCTAssertTrue(arrival.update(["left": 1, "right": 3], didSwitch: true).isEmpty)
    }

    func testBackgroundTopologyCannotConsumeSpaceArrival() {
        var arrival = SpaceLabelResolver.Arrival()
        _ = arrival.update(["left": 1], didSwitch: false)
        XCTAssertTrue(arrival.update(["left": 2], didSwitch: false).isEmpty)
        XCTAssertEqual(arrival.update(["left": 2], didSwitch: true), [2])
    }

    func testVisibleSpacesAreReadPerDisplay() {
        XCTAssertEqual(SpaceLabelResolver.visibleSpaces(from: [
            ["Display Identifier": "left", "Current Space": ["id64": 3]],
            ["Display Identifier": "right", "Current Space": ["id64": 7]],
        ]), ["left": 3, "right": 7])
        XCTAssertNil(SpaceLabelResolver.visibleSpaces(from: [["Display Identifier": "left"]]))
        XCTAssertNil(SpaceLabelResolver.visibleSpaces(from: [
            ["Display Identifier": "left", "Current Space": ["id64": 3]],
            ["Display Identifier": "left", "Current Space": ["id64": 7]],
        ]))
    }

    func testDisabledRevealHasNoTargets() {
        var reveal = SpaceLabelResolver.Reveal()
        reveal.start(["a"], duration: 0)
        XCTAssertTrue(reveal.targets.isEmpty)
    }

    func testOldTimerCannotEndNewerRevealOfSameSpace() {
        var reveal = SpaceLabelResolver.Reveal()
        reveal.start(["a"], duration: 1000)
        let oldRevision = reveal.revision
        reveal.start(["b"], duration: 1000)
        reveal.start(["a"], duration: 1000)
        XCTAssertFalse(reveal.finish("a", after: oldRevision))
        XCTAssertEqual(reveal.targets, ["a"])
    }

    func testExplicitActionCancelsPendingRevealTimers() {
        var reveal = SpaceLabelResolver.Reveal()
        reveal.start(["a", "b"], duration: 1000)
        let revision = reveal.revision
        reveal.cancel()
        XCTAssertFalse(reveal.finish("a", after: revision))
        XCTAssertTrue(reveal.targets.isEmpty)
    }

    func testInteractingWithOneLabelPreservesOtherDisplayTimer() {
        var reveal = SpaceLabelResolver.Reveal()
        reveal.start(["a", "b"], duration: 1000)
        XCTAssertTrue(reveal.finish("a", after: reveal.revision))
        XCTAssertFalse(reveal.finish("a", after: reveal.revision))
        XCTAssertEqual(reveal.targets, ["b"])
        XCTAssertTrue(reveal.finish("b", after: reveal.revision))
    }

    func testRevealDurationIsBounded() {
        XCTAssertEqual(SpaceLabelResolver.revealDuration(-100), 0)
        XCTAssertEqual(SpaceLabelResolver.revealDuration(1000), 1000)
        XCTAssertEqual(SpaceLabelResolver.revealDuration(Int.max), 3000)
    }
}
