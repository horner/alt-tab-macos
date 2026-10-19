# ProjectVisibilityResolver

Project selection never automatically minimizes or restores ordinary windows and never intercepts
focus. Switching Projects uses normal window focus and Desktop navigation. The retired
`projectsMinimizeInactive` preference is ignored, including a saved `true` value. Manual window
minimize/restore commands and Project label controls remain independent.

The runtime adapter uses only `Session.restorationPlan`. It restores windows automatically minimized
by an earlier session, using saved ProjectWindowIdentity values (window ID, PID and process launch
time). Discovery recovers only an exact identity that is still minimized. This cleanup applies
across Desktops, even with Projects disabled, without activating apps or deliberately changing Spaces.
It cannot claim a manually minimized or newly discovered window. Saved ownership is loaded once
before either window registration or a manual action, even if Project persistence has not started;
startup cannot reload a record that a manual action already released.

Full-screen windows, native tab groups, phantom surfaces, placeholders, AltTab's own windows,
windows without AX access and borrowed locations are excluded from recovery. Ownership is
retained if a recorded window becomes temporarily ineligible. Explicit minimize/restore actions
relinquish ownership and cancel a pending recovery. Closing a window invalidates pending work before
its ID can be reused.

Recovery coalesces window events on the main queue after UI dismissal and uses the existing bounded
accessibility command pool. Workers check cancellation before reads and before the write, read the
live minimized/full-screen state, and check whether minimization is supported. Commands set an
explicit Boolean; they never toggle. An AX timeout can still execute, so a sent write that times out
is treated as completed and is not retried automatically. Other failures also have no automatic
retry and retain recovery ownership. Subsequent membership, location or eligibility events may request another attempt. Project
selection does not cancel an in-flight recovery.

## Runtime recovery tests

- **testRecoveryRequiresSavedIdentityAndMinimizedState** — a reused PID, new process launch, different
  window or already-restored window cannot be claimed from a saved record.
- **testRestorationPlanNeverMinimizesOrClaimsUnmanagedWindows** — newly seen, inactive, unassigned,
  remote and manually minimized windows retain their state.
- **testRestorationPlanRestoresOnlyRecordedEligibleWindowsAcrossDesktops** — exact recovered ownership
  limits cleanup; temporarily ineligible windows retain their record and manual windows stay minimized.
- **testRestorationPlanKeepsInFlightRecoveryAcrossProjectAndDesktopChanges** — navigation cannot cancel
  cleanup or create another command for the same window.
- **testRestorationPlanPreservesManualMinimizeBeforeRecoveryCompletion** — manual control wins over
  a pending recovery and prevents another restore.

## Session state-machine safety tests

The reusable session planner retains cancellation, ownership and late-completion safeguards. These
lower-level scenarios cover issued writes and recovery without enabling the retired runtime mode.

- **testSwitchMinimizesOnlyOtherProjectsOnCurrentDesktop** — active members and remote windows are excluded.
- **testSwitchBackRestoresOnlyAutomaticallyMinimizedWindows** — restores precede minimizes and preserve manual choices.
- **testSharedAndUnassignedWindowsStayVisible** — neither class is hidden.
- **testManuallyMinimizedInactiveWindowIsNeverClaimed** — existing minimized state creates no ownership.
- **testLiveReadProtectsManualMinimizeAfterSnapshot** — a manual minimize between snapshot and AX read stays manual.
- **testDisabledOptionRestoresManagedWindowsAcrossDesktops** — disabling cleans up managed windows only.
- **testNormalDesktopScopeRestoresOnlyCurrentDesktop** — normal Desktop mode leaves remote state alone.
- **testAllSpacesAndUnknownLocationsAreNotMinimized** — broad or missing location data cannot hide windows.
- **testSelectingRemoteProjectLeavesOriginDesktopAlone** — selecting a remote Project preserves the origin workspace.
- **testIneligibleWindowsAreExcludedEvenDuringCleanup** — unsupported surfaces retain their state.
- **testRemovingMembershipRestoresManagedWindow** — unassigned windows reappear.
- **testAddingActiveMembershipRestoresSharedWindow** — sharing with the active Project restores visibility.
- **testQueuedMinimizeIsCancelledByNewSelection** — obsolete commands perform no write.
- **testIssuedMinimizeIsRestoredAfterSelectionChanges** — already-issued work is compensated.
- **testIssuedMinimizeIsUndoneAfterLeavingItsDesktop** — compensation also covers a Desktop transition.
- **testReturningToOriginalSelectionKeepsCompletedMinimize** — rapid reversals settle on the latest selection.
- **testIssuedRestoreIsCorrectedDespiteStaleMinimizedSnapshot** — completed AX state bridges observer latency.
- **testOneCommandPerWindowWhileOtherWindowsProgress** — coalescing does not serialize unrelated windows.
- **testFailedMinimizeDoesNotClaimWindowOrRequestRetry** — a refused command leaves manual state intact.
- **testFailedRestoreRetainsRecoveryOwnershipWithoutRetry** — failed cleanup remains recoverable.
- **testNativeRestoreRelinquishesOwnershipBeforeManualMinimize** — a subsequent manual minimize stays minimized.
- **testManualActionRelinquishesPendingOwnership** — an explicit action takes control from automation.
- **testNativeRestoreDuringMinimizeRelinquishesPendingOwnership** — a native restore overrides an in-flight minimize.
- **testNativeMinimizeDuringRestorePreservesManualChoice** — a native minimize overrides an in-flight restore.
- **testClosedWindowCannotTransferOwnershipToReusedId** — a stale callback cannot claim a replacement.
- **testOwnershipSurvivesExpectedNotificationsDuringCommands** — observer delivery before completion is safe.

## Runtime validation

Launch with a saved `projectsMinimizeInactive=true` and switch Projects. Confirm that ordinary windows
are not minimized and focus follows the selected window's Desktop. Relaunch with recorded automatically
minimized windows and confirm that only those exact live windows are restored. Manually minimized
windows and Project label controls must retain their state. Bring a window to the current Desktop,
then change Projects; its visibility and membership must remain unchanged.
