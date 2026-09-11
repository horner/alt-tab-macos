# SpaceLabelResolver — Specs

## Summary

Labels start hidden. Saving “Name this Desktop…” explicitly opens or restores the labels on that
Desktop, including each of its linked Projects. This does not open labels on other Desktops or
restore their closed/minimized windows. Cancel leaves labels unchanged.

“Show Project Labels” requests one window per linked Project on each live Desktop,
or one Desktop label when it has no linked Projects. New Spaces are included while the set is open.
Closing a window suppresses only its stable label identity across naming and topology refreshes.
“Show Project Labels” explicitly restores closed windows. “Close All Project Labels”, disabling Projects,
and restarting AltTab end the session; subsequent refreshes or re-enabling Projects do not reopen it.

Labels normally use the normal window level. “Bring Project Labels to Front” raises the existing set once and
restores minimized labels, preserving individual close decisions. If no session exists, it creates
one. “Show Project Labels” creates or restores the whole set and raises it. A click outside a label,
including our own settings, or activation of another app sends the set to the back of the normal
window level. Labels remain open for Exposé. Event handlers defer ordering and ignore stale clicks
from before a newer bring-to-front, minimize or session request. Click monitoring stops when no front
presentation, reveal or interacted label needs it.

The native yellow button minimizes one label; “Minimize All Project Labels” minimizes the set.
Minimizing does not close the session. Newly discovered labels and pending assignments follow the
latest front/back/minimized request. Routine name and topology refreshes never raise labels or
restore an individually minimized window; another explicit Show or Bring request restores it.

Each linked Project label provides Project Windows, History, Rename, Add All Visible Windows and Menu
buttons below the name. Unlinked Desktop labels provide Rename and Menu. Project buttons target that label's Project,
as specified in `../projects/ProjectMenuResolverSpecs.md`. Native title-bar controls affect only their
own window. Set-wide controls live under Menu → Desktop: <name>; Show All restores closed labels,
while Bring All to Front respects closures.
Menu opens the same live AltTab menu as the status icon with the clicked label's Project and Desktop
context. It includes Current window, Project: <name>, Other Projects, Desktop: <name>, Settings, Help
and Quit, works with the status icon hidden, and retains
the existing menu delegate's refreshes.
“Project windows in switcher” offers Show and Hide, defaulting to Hide independently of the menu-bar
icon. Show makes live label windows switch destinations. The explicit ownership check uses this process's
registered window IDs; it does not loosen admission for other floating windows. Changing the preference
updates existing windows without reopening them. Shown labels remain selectable during their
temporary reveal and bypass custom-Project membership filtering, while ordinary shortcut filters still
apply. They do not claim automatic Project names or membership.

“Show label after switching Spaces” accepts 0–3000 ms in 100 ms increments and defaults to 1500 ms.
Zero disables the reveal; an explicitly saved duration is preserved when defaults change.
An active-Space notification requests an asynchronous topology read. Only changed Spaces on existing
displays reveal their open, non-minimized labels; startup, wake, duplicate notifications, new displays
and ordinary topology/name refreshes do not trigger a reveal. First topology establishes a baseline.
The temporary floating level preserves keyboard focus and restores the original level afterward;
labels return behind ordinary windows unless their presentation was explicitly front. The duration
starts on the next main-runloop turn after ordering. Newly assigned labels start their timer after
assignment succeeds. A new arrival cancels previous reveals; timer revisions prevent an old visit
from ending a later visit to the same Space. Automatic destination-app activation does not dismiss
the reveal. Clicking outside dismisses it early. Interacting with a revealed label keeps it at the
front at its ordinary level until a subsequent outside click or explicit presentation action.
Manual Show, Bring, Minimize, Close and disabling the preference cancel pending timers. A hidden
label session is never created by an automatic reveal.

A linked Project has a persistent label identity independent of its current Desktop. Legacy single
links retain the original Desktop UUID as their label identity, preserving saved positions. Project
names label linked windows; an unlinked Desktop uses its explicit or automatic name, then “Unnamed Space”.
When a Desktop closes, ProjectDesktopResolver relocates its Projects and reuses their label windows
on the destination Desktop alongside its resident Projects. Closing or minimizing one label does not
affect the other Projects there. Interacting with a Project label selects that Project.
Desktop numbers follow WindowServer display/Space order. Fullscreen Spaces retain their ordinal in
that complete order and display “Fullscreen · Space N”; they do not consume a Desktop number.
Project shortcut numbers never affect the Desktop numbers on these labels.

A malformed or ambiguous topology returns nil so the adapter retains its last valid state. A valid
new snapshot replaces the previous topology, allowing creation, removal, renumbering and display
changes. The adapter reuses windows by label identity and never persists WindowServer IDs.

The frame uses half the selected screen's visible width, independent of Retina density. Height follows
the fitted text and button rows instead of the screen height. New labels default to the lower-right
corner, inset 24 points from the usable screen edges above the Dock. Geometry rounds to whole points.
Users can drag the title bar or label background. A per-label identity preference stores the display UUID
and offsets within its usable frame; name changes, Space changes and close/reopen preserve placement.
Saved positions survive app restarts even though the label session starts hidden. The preferred
display is used while connected, falling back to the Space's display when unavailable. Frames are
clamped to the usable area after display changes. Move notifications update in-memory placement;
a cancellable delayed write coalesces drag events, and closing flushes the pending position.
Additional labels stack above the lower-right anchor. New or migrated labels are moved to an
unoccupied area when possible; any adjusted placement is saved. Ordinary refreshes preserve user
placements, including intentional overlap. If the screen cannot fit every label, placement cascades
within its usable bounds. Non-finite saved coordinates use the default.
The number and name share one bold white
line on solid black. The font grows to fill the available width, with a height limit of one third of
the usable screen for very short names. Long names stop shrinking at a readable minimum and truncate
at the tail, keeping the leading number visible. Fullscreen ordinals retain their explicit prefix.
Embedded whitespace collapses to spaces for presentation; the complete name remains in the model,
tooltip and accessible label. Native close and minimize buttons remain above the text. The
small action buttons wrap into additional rows when needed.

## Test scenarios

- **testTwoProjectLabelsKeepSeparateIdentitiesOnOneDesktop** — separate label identities and close controls share one physical Desktop.
- **testMergedLabelsAvoidOverlapWithDifferentHeights** — incoming labels avoid taller resident windows.
- **testUnobstructedUserPositionSurvivesDesktopMerge** — a free user position remains unchanged.

- **testDefaultRevealDurationIsFifteenHundredMilliseconds** — New installations default to 1500 ms; zero still disables.
- **testLabelsFollowSwitcherVisibilityPreference** — Show includes registered labels; Hide excludes them.
- **testSwitcherAccessDoesNotVouchForOtherWindowsOrProcesses** — Only live, nonzero IDs belonging to this process receive explicit control-window treatment.

- **testShowRequestsFrontPresentation** — Showing the set requests one front presentation.
- **testClickAwaySendsLabelsBackWithoutClosingThem** — Clicking away sends labels behind ordinary windows while retaining the session.
- **testBringToFrontPreservesIndividuallyClosedLabels** — Raising a minimized set keeps individually closed UUIDs suppressed.
- **testOldClickCannotUndoANewerBringToFront** — A deferred click cannot lower a more recent explicit front request.
- **testOldSessionClickCannotLowerRecreatedLabels** — Deferred clicks from a closed session cannot lower a new session.
- **testMinimizeAllPreservesTheOpenSession** — Minimize All keeps the session open and applies to later Spaces too.
- **testQueuedClickCannotOverrideMinimizeAll** — A deferred click cannot replace a newer minimize request with back ordering.
- **testPresentationActionsDoNotStartAClosedSession** — The presentation kernel does not implicitly start a session; creation is the adapter's explicit decision.
- **testLabelsStartUnrequested** — Starting a session does not create label windows automatically.
- **testShowAllIncludesExistingAndNewSpaces** — An explicit show request includes current and newly created Spaces.
- **testClosedLabelStaysClosedAcrossRefreshes** — Closing one UUID keeps it suppressed while other labels remain requested.
- **testShowAllExplicitlyRestoresClosedLabels** — A new show request restores individually closed labels.
- **testCloseAllSuppressesExistingAndNewSpaces** — Closing all ends the request, including labels for Spaces created later.
- **testShowingAfterCloseAllStartsFresh** — Reopening the set clears individual close decisions from the previous session.
- **testExplicitNameWinsAndTrimsWhitespace** — Explicit names take precedence over automatic names and lose surrounding whitespace.
- **testClearedNameFallsBackToAutomaticName** — Clearing the explicit name reveals the normalized automatic name.
- **testEmptySpaceKeepsNumberWithoutAName** — An unnamed Space still has its current Desktop number.
- **testRenamingUsesLatestSavedName** — A rename changes the label without changing its Space identity.
- **testNamesFollowUuidAcrossSessionIdChanges** — The UUID preserves the name when a session assigns a different Space ID.
- **testReorderingChangesNumbersWithoutSwappingNames** — Reordering updates Desktop numbers while each name follows its UUID.
- **testDuplicateNamesRemainSeparateSpaces** — Equal names never merge windows belonging to different UUIDs.
- **testLongUnicodeNameIsPreservedForAccessibleText** — Long Unicode names remain intact for accessibility and presentation.
- **testFullscreenUsesSpaceOrdinalInsteadOfDesktopZero** — A fullscreen label uses the complete Space ordinal, never Desktop 0.
- **testDisabledProducesNoLabels** — Projects disabled means no label windows.
- **testTopologyIncludesFullscreenAndNumbersDesktopsAcrossDisplays** — Fullscreen Spaces are included without incrementing Desktop numbering across displays.
- **testUnifiedDisplayTopologyPreservesMainIdentifier** — Shared Spaces retain the Main display identifier for screen resolution.
- **testIncompleteTopologyCannotDeleteExistingLabels** — Missing topology fields invalidate the snapshot instead of implying deletion.
- **testDuplicateUuidRejectsAmbiguousTopology** — Duplicate UUIDs invalidate an ambiguous topology.
- **testRemovedSpaceIsAbsentFromNextSnapshot** — A valid replacement snapshot removes an absent Space and renumbers the survivor.
- **testFrameUsesHalfTheScreenWidthAndTextHeight** — Labels use half the visible width and the supplied height at the lower-right anchor.
- **testFrameScalesWithLandscapeAndPortraitScreens** — Different display sizes and orientations retain half-screen width without increasing the supplied height.
- **testFrameUsesDisplayOrigin** — The frame respects a display's nonzero origin.
- **testOddScreenDimensionsMatchAppKitFrameRounding** — Odd screen dimensions match the native rounded frame instead of triggering a resize on every refresh.
- **testSavedPositionSurvivesLabelHeightChanges** — Renaming preserves the user's origin when it still fits.
- **testSavedPositionFollowsDisplayOrigin** — Placement follows its display when the display arrangement moves.
- **testOffscreenPositionIsClampedAfterDisplayChanges** — Reduced or disconnected screens cannot strand the label.
- **testOversizedLabelRemainsInsideUsableScreen** — Label height cannot exceed the available screen height.
- **testInvalidSavedPositionUsesDefaultCorner** — Non-finite coordinates fall back to the lower-right corner.
- **testPositionRoundTripPreservesDisplayAndOffsets** — Persisted placement retains its display and offsets.
- **testInitialTopologyDoesNotRevealLabels** — The first snapshot establishes a baseline without revealing.
- **testSpaceSwitchRevealsOnlyChangedDisplays** — Only destination Spaces on changed displays qualify.
- **testDuplicateNotificationDoesNotRestartReveal** — Repeated notifications for the same topology do not request a new reveal.
- **testNewDisplayAndRoutineRefreshDoNotRevealLabels** — Screen attachment and refreshes do not qualify as arrivals.
- **testBackgroundTopologyCannotConsumeSpaceArrival** — A Dock topology refresh preceding the workspace notification cannot suppress the reveal.
- **testVisibleSpacesAreReadPerDisplay** — Active Space parsing rejects partial or duplicate display data.
- **testDisabledRevealHasNoTargets** — Zero duration suppresses automatic reveals.
- **testOldTimerCannotEndNewerRevealOfSameSpace** — Rapid A/B/A switching invalidates A's first timer.
- **testExplicitActionCancelsPendingRevealTimers** — A manual action invalidates all outstanding timers.
- **testInteractingWithOneLabelPreservesOtherDisplayTimer** — Per-window interaction cancels only that reveal.
- **testRevealDurationIsBounded** — External preference values remain within 0–3000 ms.

## Naming and selective visibility tests

- `testNamingDesktopShowsOnlyItsProjectLabels` — naming opens just the selected Desktop’s labels.
- `testNamingReopensItsLabelWithoutRestoringOtherClosedLabels` — naming overrides its own closure, retaining other closures and bulk presentation state.
- `testSelectiveLabelsCloseAndShowAllStillRestoresEveryDesktop` — selective sessions close normally and remain compatible with Show All and Close All.
