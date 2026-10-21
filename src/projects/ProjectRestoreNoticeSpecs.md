# Project restoration notice

Ordinary new-window assignment, linked-Desktop capture and historical membership restored on
the Project's current home Desktop are silent. Their assignment source, window ID and Project ID
are available in debug logs, without a notification. Retaining a live identity, changing a
title/URL, and explicitly assigning a Project do not produce a restoration notice. Ambiguous
historical matches still offer a choice.

A unique historical restoration only produces a notice when the window is on a different
ordinary Desktop from its Project's available home and a physical move is supported. The Project's
current home is authoritative; historical observation Desktops do not determine conflicts.
Unassigned, shared, fullscreen, all-Desktop and unknown-location windows stay quiet. The pure
placement policy and regression cases are in [ProjectRestoreNoticeResolverSpecs.md](ProjectRestoreNoticeResolverSpecs.md).

Each conflict names the window and Project and offers “Move to Project’s Desktop”. Moving is
optional and does not change membership or switch the user's Desktop. The action closes the
notice, yields a main-loop turn, then rechecks the original live Window and Project objects,
sole ownership, source Desktop, destination ID/UUID, and move availability before submitting.
Changed or resolved conflicts are discarded before display and again on action; a failed move
produces a completion detail through this same panel.

Restore All Windows to Project Desktops uses the same non-activating panel for its completion
summary. A summary waits for any visible page to finish, then appears before queued conflict
pages. Its rows report move counts followed by individual window names and skip/failure reasons.
Summaries paginate at five rows per page, keeping each window with its reason; multi-page headings
show the page number. Full text is available in label tooltips. Closing the panel clears queued
pages but the latest Desktop restore result can be reopened from the menu until app exit.

Window names in both conflict notices and Desktop restore details are link-styled buttons.
They accept the first click while another app is active. Clicking dismisses the notice and its
queued pages, then focuses the original live window on the next main-loop turn. Focus uses the
normal window path, including unminimizing and switching Desktops when necessary; it does not
change Project membership or choose between conflicting Project assignments.

Targets hold weak references to their original Window objects. The live registry and focus
eligibility are checked when rendering, on click and again before deferred focus. Closed or
unavailable targets are disabled, and a new window with the same ID or title cannot replace them.
The last restore result retains those same weak targets when reopened. Counts and reasons are
plain text; only window names focus windows.

Restoration conflicts are grouped over one second and displayed one window at a time so each
move button targets one window. Window titles fall back to the app name. Each page initially
stays visible for four seconds.

Hovering anywhere inside the notice, including the close button, cancels the hide timer. Moving
away starts a two-second countdown. Hover works while another app is active and when the
notice appears underneath a stationary pointer. New conflicts wait behind the hovered page.

The close button immediately dismisses the notice and discards its queued pages and pending
one-second batch. Later restorations can show a new notice. Clicking the button works on the
first click while another app is active and does not take keyboard focus from that app.

The localized heading reserves space for the close button. The button has a localized tooltip
and accessibility label. Canceled timers must not hide a later page or reopen a dismissed batch.

## Ambiguous restoration

Useful observations matching multiple Projects enter a one-second batch in this same panel.
Placeholder-only windows wait for metadata without a question or restoration notice. Several
ambiguous windows produce one count and a “Review windows…” button; review proceeds one window
at a time. A single window opens its choices directly. The panel remains non-activating and does
not expire while a choice is pending. New questions wait in the same queue.

Each question shows the app, current window title, and URL when available. Up to three candidate
Projects have direct buttons; “Other Project…” lists all custom Projects. “Leave unassigned” skips
one window; closing the panel skips all queued questions. Both suppress automatic assignment and
re-prompting for those live windows. Window links retain their existing explicit focus behavior;
focusing from a question dismisses the questions and leaves them unassigned.

Choosing a Project changes membership. “Also move to the Project’s Desktop” is unchecked by default
and explicitly opts into the existing asynchronous physical move path. The notice closes before
assignment/move work runs. A choice revalidates the original live Window object, metadata readiness,
meaningful URL/title evidence, Desktop, candidate set, current ownership, and original destination
Project object. Stale choices are discarded and restoration reconsidered. Closed windows or reused
IDs cannot substitute for the original target. Manual assignments remove pending questions.

Useful confirmed observations are persisted; generic titles never become rules. Multiple confirmed
owners of indistinguishable evidence still require a choice on a future restoration.
