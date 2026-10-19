# Project folder launchers

Each Project may store one primary `folderPath`. The Project label always shows iTerm2,
VS Code, and Folder… controls. Desktop-only labels do not show these controls. Folder…
selects or replaces the primary folder. A tool click without a configured folder opens
the picker and launches only after selection. Cancel leaves the Project unchanged.
The first pass supports one folder; it does not create symlinks.

A normal tool click focuses the most recently focused eligible window of that application
already belonging to the Project. Minimized windows can be reused; phantom windows,
inactive tabs, and application placeholders cannot. Reuse never changes an existing
terminal's working directory or an editor's workspace, even after changing folderPath.
Right-click a tool button for New Window to bypass reuse.

Folder paths survive settings/YAML round trips, external edits, closing, and reopening
Projects. Missing fields in older records decode to nil. Missing folders and missing
applications produce actionable errors without silently falling back to another folder.

LaunchServices lookup and process execution run off-main. iTerm2 creates a new window
using the default profile with a login shell in the selected folder; its profile command
is overridden for this launch. AppleScript arguments and nested shell quoting preserve
spaces, quotes, dollar signs, backticks, and newlines. macOS may request Automation
permission for iTerm2. VS Code uses its bundled CLI with --new-window, without requiring
a code command on PATH. An ordinary first launch passes the primary folder unchanged.
Explicit New VS Code Window instead writes a distinct single-folder `.code-workspace`
document under `~/Library/Application Support/AltTabProjects/ProjectWorkspaces/<request UUID>/`.
The document's friendly filename uses the folder name, or `Root` for `/`, and its JSON
stores the absolute primary path as literal data. Nothing is written into the primary
folder, and the user's VS Code profile and extension settings are unchanged.

VS Code reuses an already-open folder even with --new-window. A distinct workspace
document gives each explicit New Window request its own window identity. It also has
independent workspace UI/editor state; it does not clone the existing editor session or
its workspace settings. These documents remain available for VS Code to reopen or restore,
including after a timeout or CLI error that may still produce a late window.

Window association uses existing discovery/identity events, never polling. iTerm2 returns
an exact WindowServer window ID. VS Code does not return a window ID: the first newly
created VS Code window observed during the launch is associated, so a simultaneous manual
VS Code window creation can be ambiguous. Preexisting windows and discovery readmissions
are excluded. Association moves the new window to the Project's Desktop through the
existing assignment path. One launch per application can be pending; repeated clicks
while pending do not create duplicates. Requests expire after 30 seconds, and child
processes receive termination after 25 seconds. Late results cannot claim windows.

## Automated scenarios

- **testEditorWorkspacePreservesLiteralAbsoluteFolderPaths** — JSON round trips spaces, quotes, shell metacharacters, backslashes, newlines and Unicode without changing the folder path.
- **testEditorWorkspaceRequestsUseDistinctDurableDocumentsWithFriendlyNames** — each request has a separate app-support document; retrying the same request retains its identity, and trailing folder separators do not change its friendly filename.
- **testEditorWorkspaceRootFolderUsesFriendlyFilenameWithinRequestDirectory** — the filesystem root receives a normal filename without escaping its request directory.

## Manual validation on a running development build

- Set a folder, launch each tool, and verify its directory/workspace and Project membership.
- Change focus among two member windows; a normal click focuses the most recent one.
- Change a terminal's directory, then click iTerm2 again; the directory stays unchanged.
- Right-click New Window and verify a separate member window opens in the primary folder.
- Cancel the folder picker; no application launches and the stored path stays unchanged.
- Try a moved/deleted folder, a missing app, and denied iTerm2 Automation permission.
- Close/reopen the Project and restart the app; the folder remains configured.
