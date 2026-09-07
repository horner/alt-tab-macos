# SpacesOrderResolver — Specs

## Summary

`SpacesOrderResolver` is the pure decision kernel for the Spaces switcher's list: given the Spaces the
WindowServer reports, in what order are they drawn, where does the highlight start, and where does it
move? Extracted from `SpacesList` so the ordering rules and the wrap arithmetic are unit-tested without
a live WindowServer. `SpacesList` is the adapter that gathers the inputs from SkyLight
(`CGSCopyManagedDisplaySpaces`) and keeps the visit history.

A `Space` carries three facts:

- `id` — the WindowServer's `id64`, the only stable identity across refreshes.
- `desktopNumber` — 1-based "Desktop N" as macOS itself numbers user Spaces. **0 means fullscreen**,
  because macOS gives fullscreen Spaces no number (Mission Control names them after their app), and the
  Ctrl+N fallback in `SpaceItem.activate` can only address numbered desktops.
- `enumerationRank` — position in `CGSCopyManagedDisplaySpaces`' own display-then-Space walk. The
  tie-break, and the *entire* order among fullscreen Spaces, which have no number to sort by.

## Ordering rules

### `.desktopOrder`
Ascending `desktopNumber`, `enumerationRank` breaking ties. Fullscreen Spaces (0) sort **last**, not
first: a naive numeric sort puts them ahead of Desktop 1, which is the opposite of where Mission Control
shows them.

### `.recentlyFocused`
Ascending position in `mru` (most-recently-visited first). A Space **absent** from `mru` has never been
visited while AltTab was running — at launch that is every Space but the current one — so it takes rank
`Int.max` and sorts after every visited Space, in `enumerationRank` order. Without that floor, unvisited
Spaces would land wherever the sort happened to leave them and the list would reshuffle as history
accumulated.

## Selection rules

`initialSelection` puts the highlight on the first Space that is **not** the current one, so a
press-and-release round-trips to the previously-visited Space the way alt-tab round-trips to the
previous window. With `.recentlyFocused` the current Space is index 0, so this lands on index 1 — the
last Space visited. It wraps, so when the current Space is last in the list the highlight lands on
index 0. A single Space has nowhere else to go and stays put.

`cycle` is modular arithmetic that wraps in both directions; a negative `step` must not produce a
negative index.

## Layout rule

`gridColumns` decides how many tiles the panel puts on a row. The caller measures how many fit across
the screen and passes it as `maxColumns`; below that limit everything stays on one row. Above it the
rows are balanced rather than filled greedily, because a full row trailed by a stub of 2 reads as a
rendering bug: the tile count is divided by the number of rows the limit forces.

---

## Test scenarios

Mirrors `SpacesOrderResolverTests.swift` 1:1.

### A. `.desktopOrder`
- **testDesktopOrderSortsByDesktopNumber** — desktops given out of order come back 1, 2, 3.
- **testDesktopOrderPutsFullscreenSpacesLast** — a fullscreen Space (`desktopNumber` 0) sorts after
  every numbered desktop rather than before Desktop 1.
- **testDesktopOrderBreaksTiesByEnumerationRank** — two fullscreen Spaces keep the WindowServer's walk order.

### B. `.recentlyFocused`
- **testRecentlyFocusedFollowsMruOrder** — the list matches `mru` exactly when every Space is in it.
- **testRecentlyFocusedPutsUnvisitedSpacesAfterVisitedOnes** — a Space missing from `mru` sorts after
  all visited ones.
- **testRecentlyFocusedOrdersUnvisitedSpacesByEnumerationRank** — with an empty `mru`, the WindowServer's
  walk order is preserved instead of an arbitrary one.

### C. `initialSelection`
- **testInitialSelectionPicksTheSpaceAfterTheCurrentOne** — current at 0 of 3 → 1.
- **testInitialSelectionWrapsPastTheLastSpace** — current at 2 of 3 → 0.
- **testInitialSelectionStaysPutWithASingleSpace** — count 1 → 0.
- **testInitialSelectionFallsBackToZeroWhenCurrentIsUnknown** — `nil` or out-of-range current → 0.
- **testInitialSelectionIsZeroForAnEmptyList** — count 0 → 0, so callers can't index out of range.

### D. `cycle`
- **testCycleAdvancesForward** — 0 of 3, step +1 → 1.
- **testCycleWrapsForwardPastTheEnd** — 2 of 3, step +1 → 0.
- **testCycleWrapsBackwardBelowZero** — 0 of 3, step -1 → 2.
- **testCycleIsZeroForAnEmptyList** — count 0 → 0.

### E. `gridColumns`
- **testGridColumnsKeepsEverythingOnOneRowWhenItFits** — 5 of a possible 11 → 5, so the panel is only
  as wide as it needs to be.
- **testGridColumnsBalancesRowsWhenItWraps** — 13 with a max of 11 → 7, giving 7 + 6 rather than 11 + 2.
- **testGridColumnsBalancesAcrossThreeRows** — 25 with a max of 11 → 9, giving 9 + 9 + 7.
- **testGridColumnsNeverExceedsTheMeasuredMaximum** — the balanced count stays within `maxColumns` at the
  boundary, where rounding up could otherwise push it one tile past the screen edge.
- **testGridColumnsIsOneForAnEmptyOrDegenerateGrid** — count 0 or `maxColumns` 0 → 1, so the caller's
  `% columns` can't divide by zero.
