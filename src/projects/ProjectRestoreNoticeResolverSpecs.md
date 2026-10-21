# Project restoration conflict placement

A restored assignment needs a Desktop conflict notice only when its window has exactly one
Project owner and can move from its current Desktop to that Project's available home Desktop.
Assignments already on their Project Desktop are silent. Saved historical Desktop observations
do not replace the Project's current home as the destination.

Unassigned windows, multiple owners, Projects without an available home Desktop, and unsupported
windows produce no placement. Multiple owners remain unresolved even when their home Desktop
values match. Unknown, fullscreen, and all-Desktop source memberships cannot offer a move.

A placement captures the Project ID, exact source membership, and destination Desktop ID/UUID.
Comparing it with a freshly resolved placement invalidates a queued action after ownership,
source, or destination changes. Destination selection follows the home UUID through Desktop
renumbering.

`ProjectRestoreNoticeResolverTests` covers same-Desktop silence, actionable conflicts, absent or
multiple owners, unavailable destinations, unsupported sources, stale placement invalidation,
and stable destination identity.
