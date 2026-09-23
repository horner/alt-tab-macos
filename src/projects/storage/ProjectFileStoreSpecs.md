# Project files

`~/.alt-tab-projects/projects/<project-name-slug>/project.yaml` is the source of
truth for durable custom project data. Folder names are lowercase with punctuation
and whitespace converted to hyphens; they contain no random suffix. Project renames
move the entire folder, preserving notes, attachments and Git history. Folder names
are reconciled to the YAML name after manual moves. IDs inside YAML remain immutable.
Names must be nonblank and their folder names must be unique, including archived and
tombstoned projects. Case, accents, width and punctuation cannot create folder collisions.
Existing custom projects with only an automatic name receive a permanent distinct name;
a numeric suffix is part of the project name when a generated suggestion is already taken.

`~/.alt-tab-projects/desktops.yaml` holds Desktop records in an ID-keyed `desktops`
mapping. Its root `schemaVersion: 2` identifies the separated storage layout. Each
record and `project.yaml` retain their unchanged version 1 record schema. Unsupported
versions are rejected without writes. `order` preserves ordering across both files.
YAML uses a single block mapping with unique keys; merge keys and layouts that cannot
be safely patched are rejected with an error.

Names, Desktop/label associations, membership and exclusion patterns, browser
URLs, history, confirmed restoration evidence, links and closed state are durable.
Window IDs, PIDs, launch times, observation timestamps, pending Desktop removal,
active selection and minimization ownership remain runtime data in UserDefaults.
Pattern lists have deterministic ordering. Observations do not rewrite YAML.

Migration imports missing IDs from the legacy `projects` preference, verifies the
written YAML, then sets `projectsFileStoreMigrated`. The original preference is
retained unchanged as a recovery copy. Existing YAML always wins over legacy data;
an interrupted migration resumes without duplicating IDs. A separate defaults
recovery cache retains last valid files for invalid YAML at the next launch. This
cache is not authoritative when a valid file exists. Its version 2 wrapper separately
stores projects and desktops and can read the original folder-keyed recovery cache.

The layout migration collects version 1 `kind: desktop` folders into `desktops.yaml`,
verifies and atomically commits the collection, then moves each original folder intact
to `migration-backups/v1-desktop-folders/`. Notes and original YAML comments remain in
these backups, which are outside the transient `.state` tree and can be tracked in Git.
Existing collection entries win on an interrupted migration retry. Backup collisions
preserve both folders. Custom project folders lose their generated suffixes after name
validation; an occupied destination is never overwritten. Classification uses `kind`,
so a custom project's old `desktop-` ID prefix does not move it into Desktop storage.

Folders and README.md are created once. Notes, unknown files and unknown YAML keys
are user-owned. AltTab updates changed block fields only, including fields within each Desktop record. Untouched fields keep
formatting and comments verbatim. Comments inside a changed field are preserved
immediately before its replacement. Changed block scalar content is data, not a
comment. Unsupported layouts remain untouched and report an error.

FSEvents observes atomic saves, additions and folder moves without polling. Reads,
YAML parsing and coalesced atomic writes run on a utility queue. External edits win
field-level conflicts; independent app changes merge. Invalid YAML, duplicate IDs,
missing files, duplicate project names, unsupported versions and I/O failures preserve last valid projects
and report an in-app notice plus diagnostic errors. While errors exist, durable
writes are suspended. Missing files are not recreated. To remove a project without
losing its folder or notes, use `isDeleted: true`; app deletion writes this tombstone.
Closing projects writes `isClosed: true`. Git checkout can restore either flag.

`.state/<Mac-boot-time-in-UTC>/state.json` is a diagnostic snapshot, never a restore
source. AltTab restarts reuse the boot folder; Mac restarts create a new one. It
contains timestamps, app version, bundle ID, active selection, runtime project
identities and observations, auto-minimized windows, live window metadata, resolved
owners, restoration status and file errors. Snapshot creation adds no AX or CGS
reads. It is updated after relevant model events; shutdown drains pending writes.
Old boots are retained for troubleshooting. The initial `.gitignore` excludes
`.state/`; AltTab does not initialize Git or alter an existing `.gitignore`.

A libyaml event pass enforces depth and node limits before Yams recursively constructs
the document. This also covers flow collections that the upstream nesting check can
scan ahead through. Event parsing ignores brackets inside quoted and block scalars.
Aliases, including cyclic aliases, are rejected before composition and decoding;
invalid edits preserve the file and last valid project.

ProjectFileStoreTests exercises migration/relaunch, runtime separation, no-op
writes, comments, conflict merging, validation, recovery, duplicate IDs, archives,
deletes, named/moved folders, interrupted layout migration, backup preservation,
distinct names, Desktop comment merging, diagnostic boot naming and atomic editor events.
Manual integration: launch the app, rename a project in YAML, verify its menu and
label update, introduce/fix an invalid field, and restart AltTab without closing
other apps to verify live identity restoration and the same diagnostic boot folder.

## Opening folders

Open Projects Folder in the main menu and Projects settings opens `~/.alt-tab-projects`.
Open Diagnostics Folder opens the current boot's `.state/<bootdate>` directory. Both
remain available when Projects is disabled. Open Project Folder appears in the current
Project, Other Projects and Project Attic menus, including window lists opened
from a Project label. The Desktop menu provides Show Desktops File in Finder, which
selects the shared `desktops.yaml`. Actions retain the selected Project ID, resolve its current folder
on the storage queue after queued saves, and open Finder after the menu closes. Folder
renames and archives do not change the target identity. Missing folders report an error.

## Quit ordering

Application termination returns `terminateLater` while the final snapshot drains, then
replies on main. It must not synchronously wait on the storage queue: UserDefaults writes
synchronously deliver main-queue notification observers. Sampling a hung quit showed main
waiting in `ProjectPersistence.flush` while the save waited in `NSOperation.waitUntilFinished`
for that notification. New snapshot scheduling stops during termination. A real app quit
and restart verifies the final diagnostic snapshot is written and the instance lock released.

Manual verification on macOS 26.5.1: both Projects settings buttons opened their expected
Finder directories, including the hidden current-boot diagnostics folder. Quitting through
the settings button completed and a replacement process acquired the instance lock; its
snapshot continued updating without storage errors.

Manual verification of layout version 2: restarting migrated 16 mixed folders into nine
custom project folders with plain names and seven records in desktops.yaml. All existing
non-YAML file checksums were preserved in the project or migration-backup folders. Finder
opened the nine-folder projects directory, and the running app reported no storage errors.
