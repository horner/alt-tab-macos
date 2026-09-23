# Snapshot history

Current Project, Other Projects, and Project Attic menus expose Snapshot History. The existing
project History popup also lists snapshots above individual window history. Each link opens the
saved `README.md`, with its relative window screenshots, in the built-in Snapshot Viewer.
The viewer offers Show in Finder and Open Externally; details are in SnapshotViewerSpecs.md.
Snapshot entries display local capture date/time and window count, newest first. Their tooltip
includes the saved status and file location. Historical snapshots remain available after a Project
moves to the Attic and follow project folder renames.

The Desktop menu offers Take Desktop Snapshot. It explicitly captures the Desktop and its linked
Projects while keeping windows open; it does not imply a narrower single-project capture.

Only cached history is read while constructing a menu. Startup, snapshot creation/status updates,
project folder changes, and filesystem events refresh metadata on the existing persistence queue.
Snapshot writes and observer callbacks share a 350 ms deferred refresh to combine bursts of changes.
The observer coalesces each event batch and routes archive changes separately from project YAML
changes, so snapshot writes do not request another project save. Screenshots are never loaded for
history, and window metadata is decoded only far enough to count entries.

Hidden staging directories, missing README files, directories masquerading as files, and symbolic
links are excluded. A readable README remains available if its metadata is missing or malformed;
its folder timestamp provides the capture date where available, and its tooltip explains the missing
details. A missing archives directory produces an empty history. Opening a link is deferred until
menu dismissal. The viewer reads files on its background queue; a removed or unopenable file produces
an error in the viewer and refreshes cached history.

`ProjectSnapshotHistoryTests` verifies ordering/counts/status, publication boundaries, malformed
metadata, updates/deletions, folder moves, symbolic links, and atomic metadata saves reaching the
filesystem observer.
