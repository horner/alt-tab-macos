# ProjectMembershipResolver

A disabled feature or an active Desktop returns `nil`, leaving all existing window filters in charge.
An enabled custom Project returns its members, including an empty set when it has none. Membership
narrows the live window list; it never creates candidates or claims exclusive ownership of a window.
A stale member id therefore cannot make a closed window appear. Window removal also prunes registry
membership before that id can be reused.

## Test scenarios

- **testDisabledFiltersNothing** — disabled Projects return no filter even with custom members.
- **testDesktopFiltersNothing** — a Desktop returns no filter, leaving `spacesToShow` in charge.
- **testCustomKeepsOnlyMembers** — only the custom Project's members pass through a live candidate list.
- **testGoneWindowDoesNotCreateACandidate** — a stale member id cannot introduce a window absent from the live list.
- **testEmptyCustomKeepsNothing** — an empty custom Project returns an empty set and excludes all candidates.
- **testWindowMayBelongToSeveralProjects** — overlapping Projects retain independent member sets.
