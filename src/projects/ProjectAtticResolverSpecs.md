# Project Attic

Closed and combined-away Projects remain in Project Attic with their identity, name, icon,
history and exclusions intact. This menu is independent of any custom Project named Attic.
Closing also saves a snapshot of the member windows using cached titles and browser URLs.
The snapshot is optional for older archives; an empty snapshot means no windows were open.
History never stands in for a snapshot. A later close captures the then-current windows again.
Snapshot-only records join Window History on restore so they remain available after leaving the Attic.

Project Attic → Project → Restore on This Desktop… previews restoration onto that ordinary
Desktop. Cancel changes nothing. Restore keeps the original Project identity and history,
adds its label and Desktop claim, and selects it if that Desktop is still current. A removed
or fullscreen destination leaves the Project in the Attic. Projects already restored elsewhere
and disabled Projects cannot trigger a stale restore or browser launch.
Every Desktop label also offers Restore from Attic…, including Unnamed Space. Its menu captures
the clicked label's Desktop UUID and parent window; a later active-Desktop change cannot substitute
another restore destination. Rename… remains available beside it for naming the Desktop.

Still-open windows must match the saved window ID, PID and process launch date, have no other
active Project owner and pass the ordinary assignment eligibility checks. They reattach when
the Project returns. The checked Bring option also moves those windows to the chosen Desktop;
unchecked leaves their positions unchanged. Moves use the existing asynchronous Desktop mover
and report unconfirmed or unsupported moves. Other active memberships take precedence.

The browser page checklist is initially unchecked. Saved-at-close pages appear first, then older
history in descending observation order. Duplicate browser/normalized-URL pairs collapse across
titles and Desktops; the latest record supplies the title. Equal dates sort by stable keys.
Safari and Chrome HTTP(S) pages are supported, using the same URL sanitation and transient-page
exclusions as membership restoration. Other app titles remain in saved history without a launch
action. A virtualized table displays large histories without creating a view for every entry.

Pages already observed open in their original browser are disabled. Selected URLs are revalidated
against the archive and current open-page cache at confirmation and again before each browser
request. LaunchServices requests run off the main thread after dialog dismissal. Failure leaves
the Project restored and its history available for retry, with an explanatory notice. Requests for
later browsers stop if the restored Project closes or Projects is disabled. An already submitted
browser request cannot be recalled.

Page recovery opens the recorded page in its original browser. The browser chooses whether to use
tabs or windows and where they appear; ordinary membership restoration handles newly observed
windows. It cannot reconstruct hidden tabs, window geometry, editor buffers, terminal processes or
other application session state. Existing windows owned by another Project are never reassigned
or moved by Attic restoration. Desktop creation and deletion are outside this operation.

## Validation

ProjectAtticResolverTests covers archive migration and snapshot round trips, snapshot/history
separation, normalized deduplication and ordering, explicit page selection, duplicate-open checks,
unsupported and transient URLs, exact live identities and other-owner/exclusion precedence.
Manual checks: preview with a long history, cancel, restore with Bring on and off, remove the
destination before confirming, close again, restart and restore, and simulate a missing browser.
Browser opening must be tested only with disposable pages and Projects.

## Validation — 2026-09-13

Debug compilation passed using ai/build.sh's command, with the existing signing identity and
bundle ID. The full suite passed 1,617 tests; after adding snapshot-only history retention, all
24 Attic/lifecycle tests passed, including 13 Attic cases. The production AppKit prompt was also
exercised in a disposable fixture: cancellation, a 139-entry history, selections surviving row
reuse, disabled already-open pages, Bring on/off, an empty page list and a missing browser.
The fixture's fake browser opener confirmed only selected URLs were requested and failure retained
the restored Project. No personal Project, Desktop or browser page was changed. Actual browser
tab/window placement and physical Desktop moves remain integration checks using the existing movers.

The D1/D13 regression repair passed 120 focused lifecycle, Desktop, menu, Attic and label tests.
A copy of the affected saved state confirmed consolidation preserves the original Project and all
10 history entries, with only the empty synthetic alias removed. After a graceful restart with
debug logging, production state showed that original only in the Attic and no D1 claim. From D13's
label, Rename opened its naming panel (cancelled without saving); Restore from Attic opened the
original Project's preview explicitly targeting Desktop 13. Restoration was left for the user to
confirm, so no browser page or application window was reopened or moved during this check.
