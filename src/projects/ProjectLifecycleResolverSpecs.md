# Project lifecycle

Closing a custom Project archives its name, window identities, membership evidence, exclusions,
history, icon and label identity. It disappears from active Project menus, numbering, labels,
automatic membership restoration and Desktop claims. It does not close or move application windows
or remove a macOS Desktop. Shared Projects on the Desktop remain open. Closing requires confirmation;
cancel makes no changes. Closed Projects persist across restarts and are available in the root menu.
An otherwise unlinked Desktop does not substitute a label for a closed Project or recreate it when
that Desktop is subsequently removed.

An unlinked Desktop record must not become a second Project when its label UUID is already owned
by a relocated or archived Project. On loading saved state, an empty synthetic custom record whose
ID is `desktop-<label UUID>` is consolidated only when exactly one other custom Project has that
same label UUID and the same saved names. The original identity and records survive. A closed alias
applies its close to the original and removes its Desktop claims. Aliases with their own records,
exclusions or icon, and ambiguous matches, are retained. Names alone never establish identity.

Project Attic → Project name → Restore on This Desktop… restores the same Project identity and saved
history, appends its Desktop claim, and shows its label. Membership restoration uses the ordinary
identity/evidence rules; an existing assignment to another open Project takes precedence. The restore
preview offers to bring still-open windows and reopen selected browser pages, as specified in
ProjectAtticResolverSpecs.md. A missing or fullscreen destination is rejected.

Desktop removal uses ProjectDesktopResolver's stable UUID comparison, same-display destination and
fullscreen/disconnection exclusions. The existing relocation preserves the Project temporarily, and
marks each incoming Project with a persistent unanswered question. After Mission Control exits, a
nonactivating panel offers Keep on Desktop N, Close Project… and Combine…. Keep (also the panel close
button) accepts the separate Project on its destination. Close asks for confirmation and archives it.
Questions are serialized per Project; another removal updates the destination, and closing/deleting
a Project invalidates its question. Disabling Projects hides the panel without discarding the question.
Only future observed removals of Desktops with linked Projects create questions; Desktops without
Projects close without a question. Old relocations are not guessed from saved links.

Combine is also available under Project → Manage… → Combine with for other open Projects on the same
Desktop. Its confirmation previews source window and history counts. Combining adds memberships and
history without duplicates, preserves the destination identity/name/label, and archives the source's
original records. Included members take precedence over matching exclusions. History keeps the latest
observation and confirmation times. Reopening the source restores its saved Project; it does not undo
the records already added to the destination. No application window is closed or moved. If the data
changes during confirmation, the preview is presented again; closed, deleted or relocated targets
cannot receive a stale combination.

## Tests

- `testClosePreservesAllRecordsAndClearsPendingRemoval`
- `testReopenKeepsIdentityAndHistoryOnChosenDesktop`
- `testLegacyEntriesRemainOpenWithoutPendingQuestion`
- `testPendingQuestionSurvivesRestart`
- `testCombinePreservesDestinationIdentityAndDeduplicatesMembersAndHistory`
- `testCombineRetainsNewestHistoryAndConfirmationTimes`
- `testIncludedMembersWinOverExclusionsFromEitherProject`
- `testUnrelatedExclusionsSurviveCombine`
- `testIncludedMembershipOverridesGlobalButNotOtherDesktopExclusions`
- `testCombineRejectsSelfClosedDesktopAndMovedTargets`
- `testWindowIdReuseDoesNotDeduplicateDifferentProcesses`

## Manual validation

Close and reopen a Project sharing a Desktop; verify its neighbor and application windows remain
open. Restart between closing and reopening and verify history survives. Remove a disposable Desktop
in Mission Control; exercise Keep, close cancellation, Close, combine cancellation and Combine.
Repeat with multiple linked Projects, another Desktop removal while a question is pending, display
disconnection and fullscreen exit. Restart with an unanswered question and disable/re-enable Projects.

## Validation — 2026-09-13

Debug compilation succeeded using the command in ai/build.sh. The full working-tree Test scheme
passed all 1,604 tests, including 11 lifecycle cases. The isolated commit also compiled successfully
and passed all 54 focused lifecycle, Desktop-resolution and restoration tests. Native AppKit dialogs were exercised in a disposable fixture
app using the production ProjectLifecyclePrompt: Keep, Close, Combine and both cancellations.
Visual inspection caught and corrected the panel's horizontal insets. Fixture state confirmed
that Close/Combine archive only the source, while Keep retains both Projects. Production Desktop
removal and relaunch/reopening remain manual integration checks; no personal Desktop was removed.
