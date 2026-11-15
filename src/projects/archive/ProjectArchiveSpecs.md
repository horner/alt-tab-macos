# Desktop visual archives

Closing a desktop label opens a confirmation with Archive and Close Desktop, Hide Label, and Cancel.
The dialog identifies the desktop, projects, and number of local application windows to close. An
unnamed desktop asks for a unique project name and creates its folder in the existing Projects store.
Fullscreen labels hide; they do not remove an application's fullscreen Space.

Archive folders are `archives/<UTC timestamp>-<UUID>/` inside each affected project folder. They contain:

- `README.md`: project and desktop names, capture time, window titles and app names, available file/URL
  references, geometry, minimized state, relative screenshot embeds, and recorded close outcomes.
- `screenshots/window-N.png`: fresh per-window images, captured before issuing any close request.
- `snapshot.json`: the versioned visual checkpoint and closure status.
- `projects.json`: project restoration entries saved before window destruction changes the live model.

Capture includes application windows on the desktop and linked projects' windows on other desktops.
Only ordinary windows exclusive to the selected desktop are closed. Shared and off-desktop windows
are recorded as kept open. Tabbed companion surfaces and the app's own labels/helpers are excluded.
This is a reopening plan and visual reminder, not a backup of unsaved document contents or browser tabs.

The writer uses private staging directories and publishes each completed archive through a rename.
A disk, project-folder, encoding, or PNG write failure prevents all close requests. Repeated snapshots
never overwrite older ones. A moved project directory fails instead of being recreated. If one of several
project-folder writes fails, any already-published archive remains valid, but no windows close.
Missing images are explicitly recorded, and the user chooses whether to continue without them.

Close requests are sequential. Each request's unconfirmed status is saved before it is sent. The
coordinator advances only after the tracked window is removed, not when an AX press returns success.
A save prompt can remain open while the user responds. Stop Closing stops subsequent requests;
an already-submitted close may still finish. After 60 seconds without closure the sequence stops,
records that the window remains open, and keeps the Desktop and Projects open. A late close after
that timeout does not resume desktop removal. An interrupted app run leaves the durable checkpoint
with an explicit unconfirmed status rather than claiming all windows closed.

Moved windows, changed projects, or newly opened local windows prevent desktop removal. Once all
selected windows are gone, the app opens Mission Control, invokes Dock's `AXRemoveDesktop` action,
matches the current number using Dock’s localized `DesktopNum` title, and requires the desktop UUID to disappear before moving Projects to the Attic. The last desktop on
a display cannot be removed. Unavailable Dock controls, unrecognized Desktop titles, or an
unconfirmed removal leave the projects open with their snapshots intact; the completion notice
explains that removal can be finished in Mission Control. No direct CGS Space destruction is used.

## Validation

- `ProjectArchivePolicyTests`: durable-save gate, save-prompt wait, confirmed destruction, moved windows,
  new windows, project changes, and empty desktops.
- `ProjectArchiveSnapshotTests`: safe Markdown, relative images, missing-image explanations, restoration
  metadata round trip, partial-close outcomes, empty desktops, and collision-free folder names.
- `ProjectArchiveStoreTests`: actual PNG encode/decode and complete archive files; missing capture;
  moved-folder failure; preservation of older archives.
- Live macOS 26.5.1 probe created a temporary eighth Desktop, removed that exact Desktop through
  `AXRemoveDesktop`, and confirmed the original seven remained.
- Live close-dialog and Cancel were verified on an existing label without closing user windows.
  The full save-prompt/close/archive flow still needs an interactive run with disposable app windows.

## Manual snapshots

Every desktop label offers Take Snapshot. Named/linked Desktops capture immediately without a
close confirmation. An unlinked Desktop asks for a Project name so its snapshot has a permanent
folder. The captured scope is the same Desktop and linked projects used by the close archive.

Manual snapshots use an explicit snapshot-only mode: projects.json records open Project entries,
all captured windows are marked left open, and no close commands, desktop removal, or Attic
transition may occur. Missing screenshots are recorded in the saved snapshot and reported on
completion without offering a close action. A second snapshot cannot start while another capture
or archive-and-close operation is active. Completed files refresh cached snapshot history, including
when capture finishes after cancellation; final status updates refresh it again.

`testSnapshotOnlyNeverClosesWindowsOrRemovesDesktop` pins the non-destructive policy for populated
and empty Desktops. History browsing and file discovery are specified in ProjectArchiveHistorySpecs.md.

Manual capture cancellation is serialized with publication. Cancellation before publication discards
staged files and creates no history link; once publication begins, the UI waits for the saved snapshot
instead of reporting cancellation. Store tests pin both outcomes.
