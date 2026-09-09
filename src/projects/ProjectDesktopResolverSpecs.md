# ProjectDesktopResolver

A Desktop may link several Projects. Removing a Desktop carries all of its linked Projects to a
surviving Desktop, appending them after its resident Projects without merging their memberships.
Project identities, names, history, label identities and user placements survive. A Desktop without
a linked Project is preserved as a custom Project when it participates in a merge.

The actual destination of a label window takes priority, followed by the destination receiving the
most previously local member windows. Empty projects use the nearest surviving predecessor, then
successor, on the same display. A vanished display is not a deleted Desktop; its links are retained.
Fullscreen exits do not merge Projects. Invalid topology reads retain the last valid state.

Multiple links and label identities persist. Legacy single links load as one-element lists. The
Desktop naming dialog edits all links, and each linked Project has a separate label window. The
Space switcher and Desktop context show all linked names. The active linked Project is retained
when returning to a shared Desktop; otherwise its first linked Project is selected. Unassigned
windows join that selected/default Project, without being copied into every Project on the Desktop.

## Tests

- `testLabelFollowsItsActualDestinationBeforeMemberHistory`
- `testClosedLabelUsesSurvivingMemberWindows`
- `testEmptyProjectUsesNearestSurvivingDesktopOnSameDisplay`
- `testDisplayDisconnectionDoesNotMergeItsProjects`
- `testFullscreenExitAndUnchangedDesktopDoNotMerge`
- `testMergePreservesEveryProjectWithoutDuplicates`
- `testRepeatedDesktopClosuresKeepAllProjects`
