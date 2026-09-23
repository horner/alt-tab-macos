# ProjectReattachResolver

Ordinary new windows inherit the custom Project captured when they were discovered, regardless
of their initial title or matching history. Creation markers, discovery time and the active Project
are captured before asynchronous work; actual Desktop membership is captured after admission in
the next main-queue turn. Switching Projects while identity or URL reads run cannot change the
creation destination. Existing assignments and explicit removals take priority.

The owning app must have launched at least 30 seconds before discovery for a creation marker to
count as an ordinary new window. Startup discovery and re-admission use restoration instead.
This is a conservative heuristic: a manually created window in an app's first 30 seconds cannot
be distinguished reliably from that app's restored windows. An ordinary new window with no
captured custom Project remains unassigned rather than inheriting historical ownership.

Restoration first uses live membership, then saved window ID/PID/process-launch identity.
Existing live ownership is never expanded or switched by title, URL, or Desktop observations.
A live identity can restore multiple memberships and outranks broad pattern exclusions; explicit
identity exclusions still prevent restoration.

Across app launches, exact app/URL evidence takes priority over exact app/title evidence.
Different known URLs do not match by title. Desktop UUIDs only break ties between matching
observations; same-app/same-Desktop history alone cannot claim a changed or unrelated title.
Blank/app-only titles and recognized placeholders (Start Page, New Tab, Loading, Untitled,
sign-in and error titles, including common browser suffixes) are not title evidence. HTTP(S)
URLs can supply evidence before titles arrive; recognized authentication/error URL path segments
are not restoration evidence. These filters are conservative known-placeholder rules, not a
complete classification of every app or language's titles and URLs.

VS Code's startup title “Visual Studio Code” is also a placeholder. It differs from the app's
localized name “Code”, so comparing only against the app name cannot exclude it.
`testVSCodeStartupTitleCannotRestoreAProjectBeforeItsWorkspaceLoads` covers the startup-to-workspace
transition and legacy history containing that startup title.

History and matching evidence are separate. Window history can keep transient observations;
member/exclusion patterns contain useful evidence only, including when loading legacy data.
Older meaningful patterns remain when a title or URL becomes temporarily unavailable. Title
notifications debounce for 350 ms, trigger bounded off-main browser URL reads, and learn for the
window's existing owners. Metadata writes coalesce for 500 ms. Close saves cached observations;
normal termination flushes pending writes without querying other apps. Shutdown is not required
for persistence. Last-seen timestamps do not change a pattern's identity.

Ambiguous evidence stays unassigned and is offered to the user through
[ProjectRestoreNoticeSpecs.md](ProjectRestoreNoticeSpecs.md). Neither linked-Desktop capture nor
switcher repair may silently resolve an ambiguity, pending placeholder, or declined restoration.
Unassigned local windows remain accessible in the switcher. Dismissal suppresses restoration for
the rest of that live window's lifetime; a later explicit assignment clears that suppression.

A Project choice confirms the current useful observation and persists with its pattern. A single
confirmed candidate can resolve an otherwise ambiguous match after Desktop disambiguation. If
multiple Projects have confirmed the same evidence, it remains ambiguous; last-used time cannot
identify which of two indistinguishable restored windows the user intended. Confirmations survive
metadata refresh and encoding. Old data without confirmation timestamps remains compatible.

## Regression coverage

ProjectReattachResolverTests covers placeholder/legacy rejection, positive URL evidence, changed
and unrelated titles on the same Desktop, URL priority, known URL conflicts, Desktop tie-breaking,
creation/startup boundaries, stable live ownership, shared identity ownership, explicit exclusions,
ambiguous/dismissed candidates, confirmation persistence/conflicts, and stale review evidence.
ProjectWindowIdentityTests covers PID/window-ID reuse; ProjectMenuResolverTests covers weak original
window targets, closed windows and replacement objects.
