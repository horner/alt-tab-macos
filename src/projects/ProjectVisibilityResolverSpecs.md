# ProjectVisibilityResolver

Bring to This Desktop temporarily exempts that window from automatic minimizing until the next
Project selection. An already issued automatic minimize is compensated by a restore. The exemption
does not change Project membership or override a later manual minimize.

“Minimize inactive projects” is optional and off by default. With a custom Project selected,
only ordinary windows assigned exclusively to other Projects on the current Desktop are minimized.
Active members, shared members and unassigned windows remain visible. Selecting a Project restores
only windows this feature minimized; manually minimized windows retain their state. A Project's
most recently used eligible local member receives focus after restoration. Project menus, label
selection and the Project switcher use the same behavior. Selecting normal Desktop scope restores
managed windows on that Desktop. Disabling the option or Projects restores managed windows across
Desktops, without activating their apps or deliberately changing Spaces.
Selecting a Project with no local members preserves existing cross-Desktop navigation. A Project
with neither a local member nor its home on the current Desktop does not change that Desktop's windows.

Full-screen windows, native tab groups, phantom surfaces, placeholders, AltTab's own windows (including
Project labels), windows without AX access and borrowed/unknown locations are excluded. Windows on
multiple Spaces are never automatically minimized. These exclusions also apply to restoration when
a previously managed window becomes ineligible; ownership is retained for a later eligible event.

The adapter coalesces Project, preference, membership and Space events on the main queue after UI
dismissal. It schedules restores before minimizes on the existing bounded accessibility command pool.
Each window has at most one command in flight. Workers check cancellation before reads and before the
write, read the live minimized/full-screen state, and check whether minimization is supported. Commands
set an explicit Boolean; they never toggle. An AX timeout can still execute, so a sent write that times
out retains recovery ownership and is not retried automatically. Other failures also have no automatic
retry. New selection, membership or location events can request another attempt.

A newer selection cancels queued work. An already-issued stale minimize is recorded and undone,
including after leaving that Desktop. An issued restore is followed by the latest desired state even
if the main-thread window cache has not caught up. A cancelled minimize which now matches the latest
selection can remain minimized. An external restore relinquishes ownership, as does an explicit
minimize/restore action through AltTab. Observer notifications update the cache; commands never predict
changes in the switcher's tracked window model.

Recovery ownership is saved separately from Project membership using ProjectWindowIdentity (window ID,
PID and process launch time). Discovery only recovers an exact identity which is still minimized.
Closed windows lose ownership and invalidate pending work before IDs can be reused. An app relaunch
can therefore restore live windows it minimized before quitting, including when the option is disabled.
Crash recovery is limited to commands whose ownership was saved before the process exited.

## Test scenarios

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

## Manual validation

On one Desktop, assign ordinary windows to two Projects, sharing one member and leaving another
unassigned. Enable the setting and switch through the Project shortcut, menu and labels. Check
restoration, focus and rapid reversals, including windows from the same app. Minimize an active member
manually and repeat. Verify another Desktop, full-screen windows and labels retain their state.
Disable the setting, then repeat with Projects disabled. Relaunch AltTab with automatically minimized
windows and confirm their recovery, while manually minimized windows remain minimized.
