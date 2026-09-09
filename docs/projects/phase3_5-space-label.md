# Space labels

![Large white-on-black Space label with Menu, Show All, Bring All to Front, Minimize All and Close All buttons](phase3_5-space-label-controls.png)

Native AppKit render of the production label: one bold white line on solid black, using half the
screen’s usable width. The font fills the available width and the window height follows the text.
New windows start at the lower-right corner, inset 24 points from the screen's usable edges. Users
can drag the title bar or background; each label remembers its display and position across label
recreation and app restarts. Disconnected displays fall back to the owning screen, with placement
kept inside the usable area. On the current screen, “3 · Research” uses a 735 × 217 point window.
Native close and minimize buttons stay above the text at the upper left. Very long names
truncate before the font becomes too small; the full name remains in the tooltip and accessible title.

AltTab’s menu, **Settings → Controls → Projects**, and the buttons below each label provide four actions:

- **Show Space Labels** creates the set and restores individually closed labels.
- **Bring Space Labels to Front** raises the existing set once and restores minimized labels. It also creates the set if no label session exists.
- **Minimize All Space Labels** minimizes the set; the yellow button minimizes just one label.
- **Close All Space Labels** removes the set; the red button closes just one label.

The window buttons use the shorter names Show All, Bring All to Front, Minimize All and Close All;
all four operate on the whole set. Native close/minimize controls operate on just their own label.
A **Menu** button opens the same live AltTab menu as the menu-bar icon, including Settings, Projects,
updates and Quit. **Project windows in switcher** offers **Show** and **Hide**, defaulting to Hide
independently of the menu-bar icon. Show includes open labels in AltTab's window list, including during
a temporary reveal. Preference changes update existing labels without recreating them.
Labels bypass custom-Project membership filtering and do not automatically become Project members;
the usual app, Space, screen and minimized-window filters still apply.

**Show label after switching Spaces** sets an optional 0–3000 ms reveal in 100 ms steps. It defaults
to 1500 ms. Zero disables it, and explicitly saved durations are preserved. After arriving on a different Space, its open, non-minimized labels rise to the
floating level, without taking keyboard focus. The original level and front/back presentation return
after the interval. Closed and minimized labels stay hidden. Repeated notifications do not restart
the interval; rapid switching cancels older timers. Interacting with a label or its buttons supersedes
the timer, and clicking elsewhere dismisses the temporary reveal. Destination-app activation during
the Space transition does not dismiss the cue.

Outside a temporary reveal, clicking outside the labels or switching to another app sends them behind ordinary windows. They
remain open for Exposé. Routine name/Space refreshes do not raise or restore them. Closing one label
keeps it closed until another Show request. Labels start hidden after restarting AltTab.

[AppKit’s normal-level back ordering](https://developer.apple.com/documentation/appkit/nswindow/orderback(_:))
preserves open windows without changing keyboard focus. Local and global mouse monitors handle
clicks in AltTab and other apps; workspace activation handles app switching. Monitors stop after the
labels move back, minimize or close. Revision checks cancel outdated batches and deferred clicks.

Validation: 115 tests cover label behavior, window admission and ordinary switcher filters. Native
AppKit checks verified the menu button and four label actions, conditional accessibility subroles,
live Show/Hide rediscovery and admission updates, default placement, rename
stability, saved-position recreation, timed level restoration without changing the active application,
minimized-set suppression, manual-action precedence and cleanup. The image renders the production
window's content view. Live Space-transition animation, fullscreen and multiple-display behavior
still need an interactive check.

The label Menu button was verified to open the full menu, including Settings. The rebuilt app was
restarted and the Project windows in switcher dropdown was checked with both Show and Hide, then
returned to Hide. The menu-bar icon stayed enabled, and the saved 1600 ms reveal duration was preserved.


A Desktop can link multiple Projects through **Name this Desktop → Projects on this Desktop**.
Closing a Desktop moves its Projects to the destination Desktop without combining memberships.
Each Project keeps its own label window, identity and saved placement; colliding migrated labels
are repositioned so both can be seen. The Spaces view displays both Project names. Existing windows
are reused, and closing or minimizing one label leaves the other label alone. Returning to the
shared Desktop retains the active linked Project when possible. Display disconnection and exiting
fullscreen do not merge Projects.

The merge change passed 175 focused tests and a production-adapter simulation checking separate
memberships, window reuse, both reveal timers, label closure, legacy decoding and persisted links.
No real user Desktop was deleted during validation.
