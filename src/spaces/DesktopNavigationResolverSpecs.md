# Desktop navigation in the window switcher

Windows on another Desktop show an accent-colored `↗ D:N` badge. Fullscreen destinations show `↗ Fullscreen`. The tooltip and accessibility help name the destination. Windows already visible on any display, pinned windows, windowless apps and unknown locations have no badge. This indication is independent of the optional Space-number status icons and appears in all three switcher styles.

Each actual Desktop change remembers the Desktop, selected Project and most recently focused eligible window being left. The next window-switcher invocation offers a `Back to …` button as one stop between the last and first visible windows. Forward cycling reaches it after the last window, then wraps to the first; backward cycling reaches it before the first window, then continues to the last. Shift keeps its ordinary previous-window action. Release the switcher's hold shortcut or press Return to commit the selected stop; Escape cancels. The initial window selection remains unchanged. Key repeat stops at the ends of the extended list, and spatial navigation without wrapping does not enter Back. Search keeps its window-only cycle. Back is reachable with one or no visible windows, and clicking it is supported.

Command-Z returns directly while the window switcher is open, regardless of the selected stop. Its label appears on Back. The adapter accepts the configured hold modifiers alongside Command and ignores key repeats. Command-Z stays with the text field while editing search, and other applications retain their normal undo outside the switcher.

Returning focuses the remembered window if still eligible, otherwise the destination's most recent window or navigation anchor. While an anchor is unavailable, the system-shortcut fallback honors configured shortcuts, including Command–function-key bindings, and does not send disabled or malformed bindings. Without an explicit binding it retains the Control-digit fallback; macOS must have that shortcut enabled for this fallback to reach an empty Desktop. A confirmed return restores the saved Project if it still exists; ordinary Desktop following handles deleted Projects. The Desktop just left becomes the reverse destination. History is session-local. Duplicate notifications do not overwrite it; deleted Desktops have no return button. Pending Project restoration expires after three seconds and is cancelled by an unrelated Desktop transition.

Each ordinary Desktop also has an invisible, click-through navigation anchor so it remains reachable when no eligible application window is available, including when Project labels are hidden or minimized. Anchors are confined to their assigned Desktop and can become key without becoming main. They are excluded from accessibility so their invisible key windows do not displace visible controls in accessibility clients. At rest, stationary collection behavior excludes them from App Exposé without changing the managed behavior of visible Project labels. Navigation temporarily makes its destination anchor managed before ordering it and activating the application; stationary anchors cannot trigger the Desktop transition. A fresh visibility readback confirming the destination restores stationary behavior while retaining the key window. Ordering out the key anchor can refocus a window on another Desktop and reverse the completed transition.

Each activation has a generation that is captured before asynchronous topology reads. Earlier reads and watchdogs cannot complete a newer request, including a repeated request for the same Desktop. A newly requested read confirms an already-current destination without waiting for a Space-change event. Superseding activation, destination deletion, and a guarded three-second watchdog restore idle behavior without ordering anchors out. No polling is used.

## Runtime scenarios

- Focus a Project label, then open App Exposé with Control–Down. Visible labels remain selectable, and the invisible navigation anchors contribute no blank entries.
- Hide or minimize Project labels and navigate to a Desktop with no eligible application window. The destination Desktop becomes current; repeated navigation between empty and occupied Desktops still works.
- Show Project labels again after anchor navigation. Their Desktop assignments and Exposé participation remain unchanged.
- After navigation to an empty Desktop, confirm the Desktop remains current and the key anchor contributes no blank App Exposé entry. Repeat navigation in both directions.

## Test scenarios

- **testAnchorActivationRequiresConfirmedDestinationFromTheSameRequest** — unrelated visibility cannot settle navigation; a fresh destination readback does.
- **testAlreadyCurrentAnchorSettlesWithoutASpaceChangeEvent** — a destination already visible completes from readback alone.
- **testNewAnchorActivationRejectsEarlierVisibilityAndTimeoutCallbacks** — superseded callbacks cannot settle a newer destination.
- **testRepeatedActivationOfTheSameAnchorStillRejectsEarlierCallbacks** — generation checks distinguish repeated requests for the same Desktop.
- **testAnchorWatchdogCompletesOnlyItsPendingRequest** — timeout completes once and invalidates late readbacks.
- **testDesktopRemovalCancelsOnlyAnUnavailableAnchorDestination** — removing the destination cancels its pending activation and invalidates its callbacks.
- **testStartupHasNoReturnDestination** — startup does not invent a previous Desktop.
- **testDesktopChangeRemembersProjectAndWindow** — an ordinary change retains the complete origin.
- **testDuplicateSpaceNotificationPreservesReturnDestination** — duplicate notifications do not destroy history.
- **testReturnRestoresProjectAndCreatesReverseDestination** — repeated returns round-trip both contexts.
- **testUnrelatedTransitionCancelsPendingRestoration** — unrelated navigation cannot apply an old Project selection.
- **testFailedReturnCannotRestoreProjectOnALaterManualSwitch** — expired focus requests cannot affect later navigation.
- **testDeletedDesktopAndUnknownCurrentDesktopHaveNoReturnTarget** — unavailable and current destinations are suppressed.
- **testEmptyDesktopCanBeRememberedWithoutAProjectOrWindow** — a Desktop remains a destination without windows.
- **testOtherDesktopAndFullscreenSpacesHaveADestination** — known off-screen Spaces are decorated.
- **testCurrentPinnedAndOtherVisibleDisplayWindowsDoNotSwitchDesktop** — visible windows are not mislabelled.
- **testUnknownDeletedAndWindowlessDestinationsAreNotAdvertised** — unknown locations and app placeholders do not imply a transition.
- **testBackwardStepKeepsOrdinaryWindowSelection** — backward steps inside the window list retain normal navigation.
- **testForwardCycleIncludesBackAfterLastWindow** — forward cycling visits Back, then the first window.
- **testBackwardCycleIncludesBackBeforeFirstWindow** — backward cycling visits Back, then the last window.
- **testBackParticipatesInSingleAndEmptyWindowLists** — Back remains reachable with one or no windows.
- **testRepeatsStopAtCycleEndsWithoutTrappingBack** — repeat stops at the extended list's ends; backward movement leaves Back and a fresh forward press wraps.
- **testSearchAndSpatialNavigationKeepWindowCycling** — search and non-wrapping movement do not enter Back.
- **testMissingDestinationAndUnsupportedStepsDoNotInterceptWindows** — absent history and non-unit movement use existing navigation.
- **testUndoRequiresCommandZWithoutExtraModifiers** — only Command-Z with no unexpected modifiers is undo.
- **testUndoPreservesSearchEditing** — text editing retains Command-Z.
- **testEmptyDesktopUsesConfiguredCommandFunctionShortcut** — custom key codes and Fn modifier flags survive the fallback.
- **testDisabledAndMalformedSystemShortcutsAreNotSent** — invalid and disabled bindings cannot trigger unrelated commands.
- **testUnconfiguredShortcutRetainsControlDigitFallback** — standard digit fallback keeps its existing key codes and supported range.
