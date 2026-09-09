# ProjectNumberResolver

Physical top-row and keypad digits select numbered entries in the open window switcher’s Project strip.
An unlinked current Desktop comes first (normal filtering); custom Projects follow in creation order.
A linked Desktop appears only as its custom Project, following `ProjectsOrderResolver`. Labels run
1–9, then 0. Later entries have names only and are click-only; All Projects includes every entry. The caller disables routing outside an enabled
Project window-switcher session, during search editing, and for repeated/non-key-down events.

## Test scenarios

- **testTopRowDigitsMatchTheirLabels** — ANSI top-row key codes map to their displayed digits.
- **testKeypadDigitsMatchTheirLabels** — numeric keypad keys use the same labels.
- **testOtherKeysAreNotProjectChoices** — Tab, Escape and letter keys pass through.

- **testLabelsFollowKeyboardOrderAndStopAfterTen** — labels run 1–9 then 0; later entries have no numeric prefix.
