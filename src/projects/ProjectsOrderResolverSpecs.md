# ProjectsOrderResolver

The current Desktop is first, followed by custom Projects in most-recently-activated order.
Unvisited custom Projects keep their input creation order. History may contain deleted ids;
it cannot add a Project to the list. Selection, cycling and grid sizing reuse `SpacesOrderResolver`.

## Test scenarios

- **testCurrentDesktopAlwaysComesFirst** — the current Desktop precedes even the most recent custom Project.
- **testActivatedProjectsFollowRecency** — visited custom Projects follow activation history.
- **testNeverActivatedProjectsKeepCreationOrder** — unvisited Projects retain their creation order.
- **testActivatedProjectsPrecedeNeverActivatedProjects** — visited Projects precede unvisited ones without disturbing their creation order.
- **testDesktopRemainsWhenThereAreNoCustomProjects** — an empty custom collection still leaves the current Desktop.
- **testMissingDesktopDoesNotHideCustomProjects** — missing Space topology does not hide customs or create a phantom Desktop.
- **testDeletedProjectsInHistoryAreIgnored** — stale history cannot reintroduce a deleted Project.
