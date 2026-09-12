# Bring to This Desktop

Current window and each live window's submenu in Project, Other Projects, Unassigned and the
label's Project Windows list offer Bring to This Desktop. Show Window focuses the listed window
and retains the existing Project-selection behavior. Bring moves the window physically while
preserving its Project membership and the active Project.

The destination is the current normal Desktop when the menu opens, captured by both Space ID and
UUID. Focus changes and later submenu openings cannot retarget it. A deleted Desktop, a reused
Space ID, a closed/replaced Window object or an already local window invalidates the request.
Fullscreen windows, tab groups, borrowed/unknown Space membership, windows on multiple Spaces and
AltTab's own windows are ineligible. A missing bridge disables the action.

SkyLight IPC runs on CGSCallScheduler after menu dismissal. Before submission, the worker checks
the owning PID, unchanged source membership and a fresh normal-Desktop topology. The bridge call
has no success reply: observed exclusive destination membership confirms arrival. Existing Space
notifications and one immediate read handle completion; a single four-second deadline read reports
unconfirmed moves without retrying the write. Window removal cancels queued work.

On arrival, the window is focused only if the user is still on the captured Desktop with the same
Project selection and no open switcher or modal dialog. Manual placement suppresses automatic
membership capture for that live Window until it closes or AltTab exits. An in-flight restoration
read must recheck this exception before applying its result. Other Project windows brought here
remain visible until the next Project selection; later visibility changes follow the normal rules.

The same mover also serves [Restore All Windows to Project Desktops](WindowDesktopRestoreSpecs.md).
That caller receives completion instead of a per-window alert and never requests focus or a
temporary visibility exception. Closing a pending window completes its callback once.

## Private API evidence

Yabai's `space_manager_move_window_to_space` constructs
`SLSBridgedMoveWindowsToManagedSpaceOperation` with `initWithWindows:spaceID:` and submits it through
an internal bridge function. On macOS 26.6.2, the operation's inherited
`performWithWMBridgeDelegate` method can submit it directly. A separate-process Swift fixture moved
to another Desktop and back, with WindowServer membership confirming both moves and the active
Desktop unchanged. The wrapper checks Objective-C method signatures before calling them and retains
the initialized operation for the submission. No private symbol offsets, compatibility-ID changes
or Dock injection are used.

## Verification

- `WindowDesktopMoveResolverTests` covers source/destination eligibility, unknown and multi-Space
  membership, deleted/reused destinations and exclusive confirmation.
- `testBroughtWindowStaysVisibleUntilItsExceptionIsCleared` and
  `testBringCompensatesAnAlreadyIssuedAutomaticMinimize` cover Project visibility interaction.
- In the running app, bring a disposable window from another Desktop using its menu. Confirm the
  active Desktop and Project stay unchanged, membership stays unchanged, and focus follows arrival.
- With an unsupported window, missing destination or closed target, verify there is no move.

Verified on macOS 26.6.2: the Debug build compiled and 71 focused tests passed across movement,
Project menus, reattachment and visibility. The production menu brought a separate-process fixture
from Space 387 (Desktop 1) to Space 3 (Desktop 2). QA snapshots confirmed exclusive destination
membership, unchanged Project membership and active Desktop, and focus on the arriving window.
The fixture had no bundle identifier, so its closed window left no app/title history pattern.

The `/rework-comments` audit of the four new Swift files found no drift or edits needed: four
comment lines across 238 code lines (ratio 0.017). The retained comments state thread ownership,
the private bridge's behavior and the requirement to confirm a move from observed membership.
