# Desktop navigation in the window switcher

Windows on another Desktop show an accent-colored `↗ D:N` badge. Fullscreen destinations show `↗ Fullscreen`. The tooltip and accessibility help name the destination. Windows already visible on any display, pinned windows, windowless apps and unknown locations have no badge. This indication is independent of the optional Space-number status icons and appears in all three switcher styles.

Each actual Desktop change remembers the Desktop, selected Project and most recently focused eligible window being left. The next window-switcher invocation offers a `Back to …` button as one stop between the last and first visible windows. Forward cycling reaches it after the last window, then wraps to the first; backward cycling reaches it before the first window, then continues to the last. Shift keeps its ordinary previous-window action. Release the switcher's hold shortcut or press Return to commit the selected stop; Escape cancels. The initial window selection remains unchanged. Key repeat stops at the ends of the extended list, and spatial navigation without wrapping does not enter Back. Search keeps its window-only cycle. Back is reachable with one or no visible windows, and clicking it is supported.

Command-Z returns directly while the window switcher is open, regardless of the selected stop. Its label appears on Back. The adapter accepts the configured hold modifiers alongside Command and ignores key repeats. Command-Z stays with the text field while editing search, and other applications retain their normal undo outside the switcher.

Returning focuses the remembered window if still eligible, otherwise the destination's most recent window or empty-Desktop system-shortcut fallback. The fallback honors configured shortcuts, including Command–function-key bindings, and does not send disabled or malformed bindings. Without an explicit binding it retains the Control-digit fallback; macOS must have that shortcut enabled for an empty Desktop to be reachable. A confirmed return restores the saved Project if it still exists; ordinary Desktop following handles deleted Projects. The Desktop just left becomes the reverse destination. History is session-local. Duplicate notifications do not overwrite it; deleted Desktops have no return button. Pending Project restoration expires after three seconds and is cancelled by an unrelated Desktop transition.

## Test scenarios

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
