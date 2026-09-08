# ProjectNumberResolver

Physical top-row and keypad digits select numbered entries in the open window switcher’s Project strip.
1 is the current Desktop (normal filtering); custom Projects follow in creation order. Labels run
1–9, then 0. Later entries have names only and are click-only; All Projects includes every entry. The caller disables routing outside an enabled
Project window-switcher session, during search editing, and for repeated/non-key-down events.

## Test scenarios

- **testTopRowDigitsMatchTheirLabels** — ANSI top-row key codes map to their displayed digits.
- **testKeypadDigitsMatchTheirLabels** — numeric keypad keys use the same labels.
- **testOtherKeysAreNotProjectChoices** — Tab, Escape and letter keys pass through.

- **testLabelsFollowKeyboardOrderAndStopAfterTen** — labels run 1–9 then 0; later entries have no numeric prefix.
