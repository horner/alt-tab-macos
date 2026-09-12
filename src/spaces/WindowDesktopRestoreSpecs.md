# Restore All Windows to Project Desktops

The top-level AltTab menu offers Restore All Windows to Project Desktops when Projects and the
window-moving bridge are available. It operates on currently tracked open windows from all
Projects. It does not reopen closed windows or infer a Project for an unassigned window.

Each custom Project's `homeSpaceUuid` identifies its proper Desktop. Shared windows move once when
all their Projects have the same home UUID. Conflicting homes and missing home Desktops are
skipped. Already-home windows are counted without a move. The same source eligibility rules as
[WindowDesktopMoveSpecs.md](WindowDesktopMoveSpecs.md) apply: fullscreen windows, tab groups,
multiple/unknown Space membership and AltTab-owned windows are not moved.

The action snapshots a finite list of window objects and destinations after menu dismissal.
One window moves at a time through the existing CGS scheduler, yielding between requests. Before
each move, the batch rechecks the live object, unchanged source, current Project homes and Desktop
UUID. Membership edits, deleted Projects/Desktops and user moves cannot retarget a queued entry.
Closing an in-flight window completes that entry as unsuccessful and advances the batch. Disabling
Projects stops the remaining batch. Repeated Restore clicks cannot create overlapping batches.

Moves preserve Project membership, do not select Projects, and do not request window focus or a
Desktop switch. Existing Project visibility rules continue to apply. Explicitly restoring a window
overrides its earlier Bring to This Desktop location and temporary visibility exception.

The menu displays Restoring Project Desktops… while a batch is active. After completion, the
existing non-activating restoration notice reports moved, already-home, skipped and unsuccessful
counts, followed by each skipped or unsuccessful window's app, title and specific reason. Conflicts
name every owning Project and its current home Desktop number. Missing homes name the Project;
unassigned, fullscreen, grouped, unavailable and multiple-Desktop windows have separate reasons.
Queued candidates retain their names so even a closed window can be identified. Details are also
included in debug logging. Confirmed WindowServer membership is required to count a
move as successful. Per-window errors do not open modal dialogs during a batch.

Show Last Desktop Restore Results reopens the last completed summary without moving windows.
It becomes visible after completion, is disabled during a batch, and retains the result until
the next completed restore or app exit. Results snapshot names and reasons from that operation;
later Project edits do not rewrite what happened.
Each detail also retains a weak link to the original Window. Clicking its name focuses that
window through [ProjectRestoreNotice](../projects/ProjectRestoreNoticeSpecs.md), including when
reopening results. Identical titles stay separate; closed windows cannot resolve to reused IDs.

## Verification

`WindowDesktopRestoreResolverTests` covers shared-home agreement and conflict, no owner, missing
and renumbered Desktops, unsupported sources, ownership changes and confirmed-result accounting.
The movement and Project-visibility suites continue to cover bridge admission and Bring behavior.
Summary tests also pin the association between a window and its reason, including failed moves,
and keep successful decisions out of the detail list.

The Debug build and 84 focused tests passed on macOS 26.6.2. An isolated harness compiled the
production batch coordinator and mover against simulated WindowServer responses: six scenarios
and 75 checks covered serial completion, duplicate starts, changed ownership/location, in-flight
closure, rejected and unconfirmed moves, disabling Projects, queued closure and a deleted home.
These checks also asserted that bulk restoration never focuses windows or grants Bring visibility
exceptions, identifies affected windows and Project homes, and can replay results without submitting
another move or rebinding a result to a replacement window. An isolated AppKit fixture exercised
16 link checks against the production notice: full-text tooltips, bounds, first-click handling,
dismissal before deferred focus, exact targets, closure races, weak lifetime, result replay,
assignment notices and paired-row pagination. A rendered preview confirmed link styling.
