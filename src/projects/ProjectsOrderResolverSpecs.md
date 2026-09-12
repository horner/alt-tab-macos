# ProjectsOrderResolver

The current Desktop appears first only when it is not linked to an existing custom Project.
A linked Desktop is represented by its custom Project alone, using the Project's name and position.
The link's id determines equivalence; names need not match. A missing or deleted link target leaves
the Desktop available, and unlinking restores its separate entry.

Custom Projects follow most-recently-activated order. Unvisited custom Projects keep their input
creation order. History may contain deleted ids; it cannot add a Project to the list. The Project
switcher uses this list directly. The numbered strip passes empty history for stable input, then
ProjectNumberResolver orders and numbers it by Desktop (or retains creation order on one Desktop).
All Projects uses the strip's same entries. Selection, cycling and grid
sizing reuse `SpacesOrderResolver`. Normal Desktop filtering remains available through the menu's
Use Desktop (No Project) action; choosing it does not highlight a custom Project.

## Test scenarios

- **testCurrentDesktopAlwaysComesFirst** — an unlinked current Desktop precedes even the most recent custom Project.
- **testActivatedProjectsFollowRecency** — visited custom Projects follow activation history.
- **testNeverActivatedProjectsKeepCreationOrder** — unvisited Projects retain their creation order.
- **testActivatedProjectsPrecedeNeverActivatedProjects** — visited Projects precede unvisited ones without disturbing their creation order.
- **testDesktopRemainsWhenThereAreNoCustomProjects** — an empty custom collection still leaves the current Desktop.
- **testMissingDesktopDoesNotHideCustomProjects** — missing Space topology does not hide customs or create a phantom Desktop.
- **testDeletedProjectsInHistoryAreIgnored** — stale history cannot reintroduce a deleted Project.
- **testLinkedDesktopAppearsOnlyAsItsProjectInCreationOrder** — the strip's base list contains the linked Project once without a separate Desktop entry or changes to creation order.
- **testLinkedDesktopAppearsOnlyAsItsProjectInRecencyOrder** — the Project switcher removes the linked Desktop without disturbing Project recency.
- **testDeletedLinkedProjectRestoresDesktopEntry** — a stale link cannot hide the Desktop, even when no custom Projects remain.
- **testUnlinkingRestoresSeparateDesktopEntry** — a lone linked Project remains selectable, and unlinking restores the Desktop alongside it.
