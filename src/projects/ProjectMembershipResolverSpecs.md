# ProjectMembershipResolver

A disabled feature or an active Desktop returns `nil`, leaving all existing window filters in charge.
An enabled custom Project returns its members plus live, unassigned windows on the current Desktop.
Windows assigned to another custom Project and unassigned windows on other Desktops are not added.
The current Desktop is the single active Space, not every visible Space across displays. Empty or
unavailable Space information cannot establish local membership; a later Space update can.
An empty Project with no local unassigned windows returns an empty set. Membership
narrows the live window list; it never creates candidates or claims exclusive ownership of a window.
A stale member id therefore cannot make a closed window appear. Window removal also prunes registry
membership before that id can be reused.

The adapter excludes placeholders, phantom surfaces, and Project label controls from automatic membership.
The label Show/Hide preference remains independent. Ordinary window filters still apply to the union.
Linked Desktop assignment is retried after discovery, late Space updates and browser URL restoration.
AltTab's own windows use the same off-main Space query as other ordinary windows; only adopted inactive
tabs deliberately start without a Space. Switcher rendering uses cached membership immediately, then
defers assignment of eligible local windows to the active Project. Deferred work rechecks the active
Project, current Space and live ownership; identity restoration must finish first so a still-pending
saved assignment cannot be overwritten. Unique saved owners and explicit exclusions are respected;
the linked or active Project can resolve ambiguous history when it is among the possible owners.
Explicitly excluded local windows remain accessible through the fallback without being reassigned.
QA snapshots use the same per-window filter as the live switcher and never perform assignment.

## Test scenarios

- **testDisabledFiltersNothing** — disabled Projects return no filter even with custom members.
- **testDesktopFiltersNothing** — a Desktop returns no filter, leaving `spacesToShow` in charge.
- **testCustomKeepsOnlyMembers** — only the custom Project's members pass through a live candidate list.
- **testGoneWindowDoesNotCreateACandidate** — a stale member id cannot introduce a window absent from the live list.
- **testEmptyCustomKeepsNothing** — an empty custom Project returns an empty set and excludes all candidates.
- **testWindowMayBelongToSeveralProjects** — overlapping Projects retain independent member sets.
- **testCustomIncludesMembersAndUnassignedDesktopWindows** — combines remote members with local unassigned windows without borrowing another Project's members.
- **testLateSpaceInformationMakesUnassignedWindowEligible** — an empty initial Space cannot strand a window once its Desktop is known.
- **testOtherVisibleDesktopDoesNotCountAsCurrentDesktop** — another display's visible Space is not the current Desktop; an all-Spaces window includes it.
- **testRepairedMembershipKeepsWindowVisible** — deferred assignment preserves the visible candidate set.
- **testMovedUnassignedWindowLeavesOldDesktopFallback** — movement updates eligibility to the destination Desktop.
- **testDesktopAndDisabledProjectsIgnoreFallbackMembership** — ordinary Desktop and disabled modes retain existing filters.
