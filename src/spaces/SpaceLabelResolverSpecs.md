# SpaceLabelResolver — Specs

## Summary

Labels start hidden. “Show Space Labels” requests one window per live Space, including Spaces added
while the set is open. Closing a window suppresses only its UUID across naming and topology refreshes.
“Show Space Labels” explicitly restores closed windows. “Close All Space Labels”, disabling Projects,
and restarting AltTab end the session; subsequent refreshes or re-enabling Projects do not reopen it.

Labels normally use the normal window level. “Bring Space Labels to Front” raises the existing set once and
restores minimized labels, preserving individual close decisions. If no session exists, it creates
one. “Show Space Labels” creates or restores the whole set and raises it. A click outside a label,
including our own settings, or activation of another app sends the set to the back of the normal
window level. Labels remain open for Exposé. Event handlers defer ordering and ignore stale clicks
from before a newer bring-to-front, minimize or session request. Click monitoring stops when no front
presentation, reveal or interacted label needs it.

The native yellow button minimizes one label; “Minimize All Space Labels” minimizes the set.
Minimizing does not close the session. Newly discovered labels and pending assignments follow the
latest front/back/minimized request. Routine name and topology refreshes never raise labels or
restore an individually minimized window; another explicit Show or Bring request restores it.

Each window also provides Show All, Bring All to Front, Minimize All and Close All buttons below the
name. These invoke the same set-wide operations as the menu; native title-bar controls affect only
their own window. Show All restores closed labels, while Bring All to Front respects closures.

“Show label after switching Spaces” accepts 0–3000 ms in 100 ms increments and defaults to 0 (disabled).
An active-Space notification requests an asynchronous topology read. Only changed Spaces on existing
displays reveal their open, non-minimized label; startup, wake, duplicate notifications, new displays
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

Each live Space has one label window, keyed by its persistent UUID. Names resolve from the Desktop
record's explicit name, then its automatic name; a missing name is rendered as “Unnamed Space”.
Desktop numbers follow WindowServer display/Space order. Fullscreen Spaces retain their ordinal in
that complete order and display “Fullscreen · Space N”; they do not consume a Desktop number.
Project shortcut numbers and the current custom Project never affect these labels.

A malformed or ambiguous topology returns nil so the adapter retains its last valid state. A valid
new snapshot replaces the previous topology, allowing creation, removal, renumbering and display
changes. The adapter reuses windows by UUID and never persists WindowServer IDs.

The frame uses half the selected screen's visible width, independent of Retina density. Height follows
the fitted text and button rows instead of the screen height. New labels default to the lower-right
corner, inset 24 points from the usable screen edges above the Dock. Geometry rounds to whole points.
Users can drag the title bar or label background. A per-Space UUID preference stores the display UUID
and offsets within its usable frame; name changes, Space changes and close/reopen preserve placement.
Saved positions survive app restarts even though the label session starts hidden. The preferred
display is used while connected, falling back to the Space's display when unavailable. Frames are
clamped to the usable area after display changes. Move notifications update in-memory placement;
a cancellable delayed write coalesces drag events, and closing flushes the pending position.
Programmatic layout never saves a new user position. Non-finite saved coordinates use the default.
The number and name share one bold white
line on solid black. The font grows to fill the available width, with a height limit of one third of
the usable screen for very short names. Long names stop shrinking at a readable minimum and truncate
at the tail, keeping the leading number visible. Fullscreen ordinals retain their explicit prefix.
Embedded whitespace collapses to spaces for presentation; the complete name remains in the model,
tooltip and accessible label. Native close and minimize buttons remain above the text. The four
small action buttons wrap into additional rows when needed.

## Test scenarios

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
