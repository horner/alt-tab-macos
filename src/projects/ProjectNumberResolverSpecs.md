# ProjectNumberResolver

Project strip numbers match the live Desktop number derived from each Project's authoritative
home assignment. The strip sorts by Desktop number, followed by unassigned Projects in their
existing order. Each live Desktop has at most one owning Project. Missing, explicitly unassigned,
or fullscreen home Spaces have no Desktop number and remain click-accessible at the end.
One-Desktop configurations use the same rule; startup without topology never invents numbers.
An unowned current Desktop retains a `Desktop N` entry for normal filtering.

All Desktop numbers remain visible, including 10 and above. Top-row and keypad digits 1–9
select the Project owning that Desktop; 0 selects Desktop 10. Reordering or deleting Desktops
updates both numbers and shortcuts on the next layout. Other keys, including F1–F12, pass
through for the user's macOS Desktop shortcuts. The All Projects popover uses the same numbers
and targets as the strip.

Digit routing applies only while the Project-enabled window switcher is open. Search editing keeps
its normal text input, holding a digit does not auto-repeat selection, and unmatched digits pass
through. Clicking any Project explicitly selects it, including an unassigned Project.

## Test scenarios

- `testProjectNumbersFollowDesktopOrderInsteadOfCreationOrder`
- `testUnassignedProjectCannotClaimOwnedDesktopNumber`
- `testDigitSelectsItsOwnerRegardlessOfCurrentSelection`
- `testDesktopNumbersAboveNineStayVisibleAndZeroSelectsTen`
- `testSingleDesktopDoesNotInventNumbersForUnassignedProjects`
- `testUnknownTopologyLeavesAllProjectsUnnumbered`
- `testDesktopRenumberingUpdatesLabelsAndDigitDestinations`
- `testUnknownDesktopsRemainUnnumberedAndCannotStealDigits`
- `testFunctionKeysRemainDesktopShortcuts`
- `testTopRowDigitsMatchTheirLabels`
- `testKeypadDigitsMatchTheirLabels`
- `testOtherKeysAreNotProjectChoices`
- `testLabelsFollowKeyboardOrderAndStopAfterTen`
