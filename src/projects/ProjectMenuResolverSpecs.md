# Project menus and label actions

The menu bar groups Project commands under “Projects · <name>”, desktop naming and label
visibility under “Desktop & Labels”, and maintenance under “Help”. Show Windows, Settings,
license/account actions and Quit remain directly accessible. Permission callouts still appear
at the top when action is needed. Projects disabled hides the Projects entry and label controls;
desktop naming remains available.

Project labels provide Project Windows, History, Rename and Menu buttons. The first two open
their lists directly, with no intermediate menu. Rename opens the name prompt for that label's
Project. Unlinked Desktop labels provide Rename and Menu; Rename opens desktop naming.
The native close/minimize controls affect one label. Set-wide Show, Bring to Front, Minimize
and Close live under Menu → Desktop & Labels and retain their separate visibility semantics.

Actions capture the clicked label's Project ID and Desktop UUID before focus changes and run
on the next main-loop turn. They never fall back to the globally active Project. This applies
to direct buttons and the full Menu, including two linked Projects on one Desktop. A deleted
Project invalidates its action. Menu-bar openings take a fresh snapshot of the active Project
and current Desktop; a label menu's context lasts only for that menu presentation.

Manual assignment is below navigation and management in the Projects submenu. Add Windows
opens an explicit checklist, with app names and window titles, for the chosen Project. The
picker includes minimized/hidden windows and windows on other Desktops, excludes existing
members, and starts with nothing selected. Add is disabled until a window is selected. Cancel
does not assign anything; an empty candidate list explains why no windows can be added.
Assignment retains the existing Move / Keep in Both / Cancel conflict prompt.
Project naming, the picker and assignment conflicts opened from a label appear as sheets attached to
that label. Opening a prompt must not activate an unrelated AltTab window on another Desktop.

All manual capture paths exclude windowless, phantom, tabbed and owned label windows,
independently of the label switcher-visibility preference. Selected Window objects must still
be live and eligible at assignment, including after a conflict prompt. Closed windows cannot
be replaced by a different Window object that reuses an ID. Bulk capture uses the menu's
Desktop snapshot. Menus opened from labels omit creation from the active window.

## Regression coverage

- `testLabelTargetsItsOwnProjectWhenAnotherProjectIsActive`
- `testLabelsOnTheSameDesktopKeepSeparateTargets`
- `testUnlinkedOrDeletedLabelNeverFallsBackToActiveProject`
- `testMenubarUsesCurrentProjectAndDesktop`
- `testLabelWindowsCannotBeAssignedRegardlessOfSwitcherPreference`
- `testWindowlessPhantomAndTabbedEntriesCannotBeAssigned`

## AppKit verification

- Open the menu from the status icon, a linked label and an unlinked Desktop label. Check
  the context, disabled actions, account state and permission callout independently.
- With two Projects linked to one Desktop, open Windows/History and Rename on each label.
  Verify each list and prompt belongs to the clicked label, including on the first click
  when AltTab is inactive. Cancel naming to leave saved names unchanged.
- In Add Windows, select multiple rows, scroll away/back and verify checkbox states persist.
  Close a selected window before Add and verify it is skipped. Cancel both the picker and
  conflict prompt; neither should change membership.
- Verify direct window/history selection still focuses across Spaces, and label Show All
  restores individual closures while Bring All to Front preserves them.
