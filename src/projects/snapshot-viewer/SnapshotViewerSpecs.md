# Snapshot Viewer

Snapshot History links open a native AppKit window containing a bundled TypeScript Markdown viewer.
The preview reads the saved README directly, so snapshots remain readable when snapshot.json is
missing or damaged. Show in Finder reveals the saved Markdown; Open Externally uses the user's
configured application. Browsing a snapshot does not capture, close, restore, or modify any windows
or archive files.

The viewer formats headings, lists, tables, code, and screenshot embeds, follows the system's light
or dark appearance, and lets the user enlarge a screenshot. All renderer assets are bundled with the
app. Markdown HTML is disabled, and images must match the native document's screenshot allowlist.
The preview does not fetch scripts, styles, fonts, or images from the network.

Swift prepares the document on a background queue after the native window can display loading
feedback. It reads at most 4 MiB of UTF-8 Markdown and writes one generated HTML file to a private
temporary directory. Each allowed image must be a direct, regular, non-hidden PNG file inside the
archive's screenshots directory with a PNG signature. The preparer hard-links these images into
the private directory, falling back to filesystem copies when hard links are unavailable or cross
volumes. It does not decode images. Missing, unreadable, non-PNG, nested, and symbolic-link images
are omitted from the allowlist. The README, archive path, and screenshot paths cannot traverse
symbolic links or contain parent-directory traversal.

The JSON payload escapes HTML delimiters and JavaScript line separators before being inserted into
the bundled template, including when Markdown contains a closing script tag. The native web view
grants file read access only to the private viewer directory and controls navigation; Markdown cannot
grant itself access to another local file or an external image. Failed or removed files produce a
readable error while leaving the original snapshot untouched. Closing the viewer removes its entire
temporary directory, including the prepared images.

Opening another snapshot or closing the viewer invalidates pending work. Minimizing or hiding the
window allows the current load to finish, so restoring it does not leave a loading placeholder.
Opening a snapshot from History brings the viewer onto the current Desktop, including when the retained viewer is
visible, closed, or minimized on another Desktop. The viewer takes keyboard focus without activating
the app or bringing its other windows forward. It remains a normal-level, resizable window and
preserves its saved frame.

The existing archive layout, snapshot creation, and close outcomes remain defined in
ProjectArchiveSpecs.md. History discovery, ordering, and refresh events remain defined in
ProjectArchiveHistorySpecs.md. The preview adds no migration or archive format version.

## Validation

`SnapshotViewerDocumentTests` verifies preserved Markdown and images, absent/corrupt metadata,
script-tag injection, local PNG selection, symlink and traversal rejection, malformed/oversized
Markdown, preservation of existing destination files, hard-link fallback, and prepared-image access
after archive removal. Frontend tests cover Markdown rendering and source restrictions. Native
build and live preview checks cover integration.

A signed development build opened an existing snapshot with three screenshots, enlarged an image
and dismissed it with Escape, removed its temporary directory on close, reopened through History,
and displayed the loaded preview after minimizing and restoring the window.

On macOS 26.5.1, a native probe using the viewer sources verified first open and visible, closed, and
minimized reuse with the viewer assigned to another Desktop. Each open kept the active Desktop
unchanged, brought the viewer onto it, and left another probe window on its original Desktop. The
running development app also opened a saved snapshot from Desktop 3's History menu without leaving
Desktop 3, enlarged a screenshot, and dismissed the enlargement with Escape.

The app's minimum macOS deployment target remains unchanged. The oldest supported macOS runtime
is not available for interactive validation; the bundled renderer must avoid newer WebKit-only APIs.
