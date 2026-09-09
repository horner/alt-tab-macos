# ProjectNumberResolver

With multiple ordinary Desktops, Project strip numbers match the live Desktop number. The strip
sorts by Desktop number, then the persisted claim order of linked Projects on that Desktop.
Projects sharing a Desktop display the same number. The first linked Project receives its digit
shortcut; a Project merely created on that Desktop follows its linked Projects. An explicit link
controls the number even when an older saved home location differs. Missing or fullscreen home
Spaces have no Desktop number and remain click-accessible at the end.

All Desktop numbers remain visible, including 10 and above. Top-row and keypad digits 1–9 select
the first Project with that Desktop number; 0 selects Desktop 10. Reordering or deleting Desktops
updates both numbers and shortcuts on the next layout. Other keys, including F1–F12, pass through
for the user's macOS Desktop shortcuts.

With one ordinary Desktop, entries retain their creation order and distinct 1–9, then 0 shortcuts,
so multiple Projects on that Desktop can each be selected. Entries beyond the tenth are click-only.
Until topology is available, the same sequential fallback applies. An unlinked current Desktop
retains its existing first entry for normal filtering. The All Projects popover uses the same
numbers and targets as the strip.

Digit routing applies only while the Project-enabled window switcher is open. Search editing keeps
its normal text input, repeated key-down events do not change selection, and unmatched digits pass
through. Clicking any Project explicitly selects it, including a secondary Project on a shared
Desktop. Automatic Desktop arrival follows the FIFO rule in ProjectDesktopResolver.

## Test scenarios

- `testProjectNumbersFollowDesktopOrderInsteadOfCreationOrder`
- `testSharedDesktopUsesItsFirstClaimForBothDigitKeyboards`
- `testDesktopNumbersAboveNineStayVisibleAndZeroSelectsTen`
- `testSingleDesktopKeepsUniqueProjectDigitsInCreationOrder`
- `testDesktopRenumberingUpdatesLabelsAndDigitDestinations`
- `testUnknownDesktopsRemainUnnumberedAndCannotStealDigits`
- `testFunctionKeysRemainDesktopShortcuts`
- `testTopRowDigitsMatchTheirLabels`
- `testKeypadDigitsMatchTheirLabels`
- `testOtherKeysAreNotProjectChoices`
- `testLabelsFollowKeyboardOrderAndStopAfterTen`
