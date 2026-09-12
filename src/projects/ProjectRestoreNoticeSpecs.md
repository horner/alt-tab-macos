# Project restoration notice

Restore All Windows to Project Desktops uses the same non-activating panel for its completion
summary. A summary waits for any visible page to finish, then appears before queued assignment
pages. Its rows report move counts followed by individual window names and skip/failure reasons.
Summaries paginate at five rows per page, keeping each window with its reason; multi-page headings
show the page number. Full text is available in label tooltips. Closing the panel clears queued
pages but the latest Desktop restore result can be reopened from the menu until app exit.

Window names in both assignment notices and Desktop restore details are link-styled buttons.
They accept the first click while another app is active. Clicking dismisses the notice and its
queued pages, then focuses the original live window on the next main-loop turn. Focus uses the
normal window path, including unminimizing and switching Desktops when necessary; it does not
change Project membership or choose between conflicting Project assignments.

Targets hold weak references to their original Window objects. The live registry and focus
eligibility are checked when rendering, on click and again before deferred focus. Closed or
unavailable targets are disabled, and a new window with the same ID or title cannot replace them.
The last restore result retains those same weak targets when reopened. Counts and reasons are
plain text; only window names focus windows.

Restored assignments are grouped over one second and displayed in pages of up to five entries.
Each entry shows its window title (falling back to the app name), destination Project, and whether
the window is on a different Desktop. Each page initially stays visible for four seconds.

Hovering anywhere inside the notice, including the close button, cancels the hide timer. Moving
away starts a two-second countdown. Hover works while another app is active and when the
notice appears underneath a stationary pointer. New assignments wait behind the hovered page.

The close button immediately dismisses the notice and discards its queued pages and pending
one-second batch. Later restorations can show a new notice. Clicking the button works on the
first click while another app is active and does not take keyboard focus from that app.

The localized heading reserves space for the close button. The button has a localized tooltip
and accessibility label. Canceled timers must not hide a later page or reopen a dismissed batch.
