# ProjectMembershipResolver

A disabled feature or an active Desktop returns `nil`, leaving all existing window filters in charge.
An enabled custom Project returns the union of its explicit members and live windows on the current
Desktop. Local windows remain eligible when assigned to another Project, and the selected Project's
home Desktop does not affect this union. Showing a local window does not alter its memberships.
Remote nonmembers are not added.
The current Desktop is the single active Space, not every visible Space across displays. Empty or
unavailable Space information cannot establish local membership; a later Space update can.
An empty Project with no local windows returns an empty set. Membership
narrows the live window list; it never creates candidates or claims exclusive ownership of a window.
A stale member id therefore cannot make a closed window appear. Window removal also prunes registry
membership before that id can be reused.

The adapter excludes placeholders, phantom surfaces, and Project label controls from automatic membership.
The label Show/Hide preference remains independent. Ordinary window filters still apply to the union.
Linked Desktop assignment is retried after discovery, late Space updates and browser URL restoration.
AltTab's own windows use the same off-main Space query as other ordinary windows; only adopted inactive
tabs deliberately start without a Space. Switcher rendering uses cached membership immediately, then
defers assignment of eligible local windows only to the active Project that owns the current Desktop.
Deferred work rechecks the active Project, current Space, and Desktop ownership; identity restoration must finish first so a still-pending
saved assignment cannot be overwritten. Unique saved owners and explicit exclusions are respected;
ambiguous history requires a user choice in the restoration notification. Pending metadata and
explicitly declined restoration cannot be captured by the linked or active Project.
Explicitly excluded local windows remain accessible through the fallback without being reassigned.
QA snapshots use the same per-window filter as the live switcher and never perform assignment.

Explicit Move actions replace the selected windows' custom Project memberships, then send them to
the destination Project's home Desktop. This applies to Move in both the window menu and the
assignment conflict prompt. Add and Keep in Both change membership without moving windows.
Desktop movement runs after dismissal and rechecks the original live objects, target membership,
Project identity and unchanged home UUID. It uses the verified, non-focusing move path in
[WindowDesktopMoveSpecs.md](../spaces/WindowDesktopMoveSpecs.md), without selecting a Project or
switching the active Desktop. Already-home windows need no move. Move to Project is disabled in
the window menu when that Project's Desktop is unavailable. The assignment conflict prompt can
still move membership to an unassigned Project and explains that the windows stay in place.
Assignment checks Desktop availability again after dismissal. Unsupported windows and unconfirmed
moves retain their new membership and produce one non-activating notice listing affected windows. Assignment moves are independent of bulk restore.

## Test scenarios

- **testDisabledFiltersNothing** — disabled Projects return no filter even with custom members.
- **testDesktopFiltersNothing** — a Desktop returns no filter, leaving `spacesToShow` in charge.
- **testCustomIncludesRemoteMembersAndEveryCurrentDesktopWindow** — remote members join local unassigned windows and another Project's local members.
- **testSelectingDifferentProjectsRetainsCurrentDesktopWindowsWithoutChangingMembership** — selecting another Project changes remote membership scope while local visibility remains independent of ownership.
- **testGoneWindowDoesNotCreateACandidate** — a stale member id cannot introduce a window absent from the live list.
- **testEmptyCustomShowsOnlyCurrentDesktopWindows** — an empty Project still shows eligible local windows and returns an empty set when none exist.
- **testWindowMayBelongToSeveralProjects** — overlapping Projects retain independent member sets.
- **testAutomaticAssignmentCandidatesExcludeOtherProjectsMembers** — visibility can include another Project's local members without making them automatic assignment candidates.
- **testLateSpaceInformationMakesWindowEligible** — an empty initial Space cannot strand a window once its Desktop is known.
- **testOtherVisibleDesktopDoesNotCountAsCurrentDesktop** — another display's visible Space is not the current Desktop; an all-Spaces window includes it.
- **testRepairedMembershipKeepsWindowVisible** — deferred assignment preserves the visible candidate set.
- **testMovingNonmemberChangesVisibilityWithoutChangingProject** — leaving the current Desktop removes fallback eligibility without changing the selected Project's memberships.
