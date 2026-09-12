# ProjectDesktopResolver

A Desktop may link several Projects. Removing a Desktop carries all of its linked Projects to a
surviving Desktop, appending them after its resident Projects without merging their memberships.
Project identities, names, history, label identities and user placements survive. A Desktop without
a linked Project is preserved as a custom Project when it participates in a merge.

The actual destination of a label window takes priority, followed by the destination receiving the
most previously local member windows. Empty projects use the nearest surviving predecessor, then
successor, on the same display. A vanished display is not a deleted Desktop; its links are retained.
Fullscreen exits do not merge Projects. Invalid topology reads retain the last valid state.

Moving a Project label window to another live Desktop transfers that Project's link to the actual
destination. The source keeps its other claims, and the destination keeps its existing claims ahead
of the arrival. The Project retains its name, members, exclusions, history and label identity. Its
label, numbered button and Desktop listing use the new link. If the selected Project leaves the
current Desktop, Follow Desktop selects the remaining first claimant or the Desktop itself.

WindowServer membership notifications trigger a coalesced topology and label-location read even
when Project windows are hidden from the switcher. Mission Control exit and Desktop arrival also
recheck the live label windows. Reads run on the CGS scheduler. Empty, ambiguous, unknown and
fullscreen destinations do not relink Projects. A removed source Desktop uses the separate merge
rules above. Observations from an in-flight or superseded app assignment, retired window or edited
Project link cannot override the newer state. Labels without a linked Project return to their own
Desktop when moved; they do not create a Project by moving.

Multiple links and label identities persist. Legacy single links load as one-element lists. The
Desktop naming panel edits all links without activating AltTab or focusing windows on other Desktops.
Save dismisses the panel before applying changes and opens or restores every Project label on the
edited Desktop. Cancel, Escape and closing the panel make no changes. If the Desktop was deleted
while editing, Save is ignored. Each linked Project has a separate label window. The
Space switcher and Desktop context show all linked names. Automatic arrival on a Desktop selects its first linked Project (FIFO) when Desktop following is
enabled. Ordinary topology/name refreshes preserve an explicit Project selection, so secondary
Projects remain usable until the next Desktop change. Explicit Back navigation retains its saved
Project restoration; disabling Desktop following also keeps an explicit Project selected. Unassigned
windows join that selected/default Project, without being copied into every Project on the Desktop.

## Tests

- `testMovedLabelUsesItsActualDesktopWhileBothDesktopsRemain`
- `testUnchangedAndAmbiguousLabelLocationsDoNotRelink`
- `testLabelRelocationDoesNotOverrideDesktopDeletionOrDisconnection`
- `testFullscreenLocationsDoNotRelinkProjects`
- `testMovingALabelToAnotherConnectedDisplayUpdatesItsDesktop`
- `testLabelFollowsItsActualDestinationBeforeMemberHistory`
- `testClosedLabelUsesSurvivingMemberWindows`
- `testEmptyProjectUsesNearestSurvivingDesktopOnSameDisplay`
- `testDisplayDisconnectionDoesNotMergeItsProjects`
- `testFullscreenExitAndUnchangedDesktopDoNotMerge`
- `testMergePreservesEveryProjectWithoutDuplicates`
- `testRepeatedDesktopClosuresKeepAllProjects`

The link list is a claim queue: saving existing links preserves their order and appends newly linked
Projects. Removing the first promotes the next; relinking a removed Project appends it. Desktop
merges append incoming claims after resident claims. The strip uses this same queue to break ties
between Projects with the same Desktop number.

- `testSavingLinksKeepsClaimOrderInsteadOfCheckboxOrder`
- `testRemovingFirstClaimPromotesNextAndRelinkingAppends`
- `testDesktopArrivalSelectsFirstClaimEvenWhenAnotherProjectWasSelected`
- `testRoutineRefreshPreservesAnExplicitProjectChoice`
- `testDesktopFollowingCanStillBeDisabled`
- `testStartupAndDeletedSelectionUseFirstClaimOrDesktop`
