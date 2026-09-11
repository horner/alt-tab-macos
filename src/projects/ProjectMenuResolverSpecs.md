# Project menus and label actions

The menu bar provides Current window, Project: <name>, Other Projects and Desktop: <name>.
Show Windows, Settings, license/account actions and Quit remain directly accessible, with
maintenance under Help. Permission callouts still appear at the top when action is needed.
Projects disabled hides the first three entries and label controls; desktop naming remains available.

Restore All Windows to Project Desktops is a top-level action after Other Projects. It is hidden
with Projects disabled and disabled while a restoration is running or the movement bridge is
unavailable. The operation follows [WindowDesktopRestoreSpecs.md](../spaces/WindowDesktopRestoreSpecs.md).
After a batch finishes, Show Last Desktop Restore Results appears immediately below it. This
reopens the saved details without moving any windows and is disabled during a new restore.

Project: <name> opens its window list directly, followed by Unassigned and Manage… submenus.
With no custom Project selected it reads Project: None, explains that no Project is active, and
still provides unassigned windows and management. Other Projects lists every other custom Project
as a peer, each opening its own window list. Empty Projects display No Open Windows; no other
Projects displays No other projects. The Desktop title uses the contextual Desktop's name.
Browsing a branch does not activate a Project; selecting Show Window in its window submenu does. Window branches refresh
when opened. History is available through the label button and Manage…, and populates on opening.

Current window displays the last focused eligible app window's title and every custom Project
it belongs to, or Unassigned. AltTab's own windows, labels, windowless entries, phantoms and
inactive tabs are excluded. The known focused window takes precedence over MRU ranks; when AltTab
has focus, the most recent eligible app window is used. An empty candidate list displays No current window.
Label buttons capture this target before mouse tracking can let label activation focus another app.
The captured object is held weakly and remains fixed throughout the menu presentation, even if
focus changes. Closing it disables the operation; a new window reusing its ID cannot replace it.

Move to Project lists all custom Projects and checks current memberships. The sole existing owner
is disabled, but a member of multiple Projects can move exclusively to any one of them. Choosing
a destination moves the captured window's membership after menu dismissal, removes its other
custom memberships using the existing explicit-exclusion rules, and saves the assignment. It
does not physically move the window to another Desktop or switch the active Project. Both the
target window's live identity and destination Project are revalidated before the assignment.

Each live window opens an operations submenu with Show Window, Bring to This Desktop and Move to
Project. Current window also offers Bring to This Desktop. Physical movement and its availability
follow [WindowDesktopMoveSpecs.md](../spaces/WindowDesktopMoveSpecs.md); the destination is captured
when the enclosing menu opens, including direct Project Windows lists opened from labels.

Project labels provide Project Windows, History, Rename, Add All Visible Windows and Menu buttons. The first two open
their lists directly, with no intermediate menu. Rename opens the name prompt for that label's
Project. Unlinked Desktop labels provide Rename and Menu; Rename opens desktop naming.
The native close/minimize controls affect one label. Set-wide Show, Bring to Front, Minimize
and Close live under Menu → Desktop: <name> and retain their separate visibility semantics.

Actions capture the clicked label's Project ID and Desktop UUID before focus changes and run
on the next main-loop turn. They never fall back to the globally active Project. This applies
to direct buttons and contextual Project/Desktop actions in the full Menu, including two linked
Projects on one Desktop. A deleted Project invalidates its action. Menu-bar openings take a fresh
snapshot of the active Project and current Desktop; a label menu's context lasts only for that
presentation. Other Projects excludes the contextual Project, and each entry targets its own Project.
Current window is independent of this Project context and retains the app window captured before opening.

Add All Visible Windows is a direct label button and an action under Current window. The menu
action names the contextual destination Project and is disabled without a Project or visible
candidates; it remains present even without a current app window. The label button uses the clicked
label's Project and Desktop, including when a different Project was active. It is absent from
unlinked Desktop labels and from Manage…. The label captures visible candidates before button
tracking can minimize other Projects' windows; the menu uses its opening snapshot. A deleted
Project or Desktop invalidates the action. Both routes retain the existing membership conflict prompt.

The Add Windows picker remains under Project → Manage…, beneath the contextual Project's name. Add Windows
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
- `testCurrentWindowPrefersTheFocusedAppWindowOverStaleRanks`
- `testCurrentWindowSurvivesLabelAndSettingsFocus`
- `testCurrentWindowIsEmptyWithoutAnEligibleAppWindow`
- `testMoveKeepsCapturedWindowWhenFocusChanges`
- `testClosedMoveTargetCannotBeReplacedByAReusedWindowId`
- `testMoveAllowsUnassignedAndMultipleMembershipsButDisablesSoleOwner`

## AppKit verification

- Open the menu from the status icon, a linked label and an unlinked Desktop label. Check
  the context, disabled actions, account state and permission callout independently.
- Open Project: <name> and verify its windows appear directly. Open Other Projects and verify
  it excludes that Project. Choose Show Window for another Project's window and verify it activates that Project;
  hovering its branch must not do so.
- Focus an app window, then open a label's Menu. Verify Current window still names that app window,
  including when automatic Project visibility is enabled. Check single, multiple and no memberships.
  Move a window to another Project and verify exclusive assignment without changing Desktops.
- Close the captured window or delete the destination while a move menu is open; neither action
  may assign another window or recreate the deleted Project.
- Reopen a Project branch after a window opens or closes and verify its window list refreshes.
  Verify History populates only when opened and still supports focusing/reopening its entries.
- With two Projects linked to one Desktop, open Windows/History and Rename on each label.
  Verify each list and prompt belongs to the clicked label, including on the first click
  when AltTab is inactive. Cancel naming to leave saved names unchanged.
- Verify Add All Visible Windows is directly available on linked labels and under Current window,
  and absent from Manage…. With two Projects on one Desktop, invoke the label button and verify
  the conflict prompt names that label's Project. Cancel to keep membership unchanged. Check that
  covered windows are included, while minimized, hidden and label windows are excluded.
- In Add Windows, select multiple rows, scroll away/back and verify checkbox states persist.
  Close a selected window before Add and verify it is skipped. Cancel both the picker and
  conflict prompt; neither should change membership.
- Verify direct window/history selection still focuses across Spaces, and label Show All
  restores individual closures while Bring All to Front preserves them.
