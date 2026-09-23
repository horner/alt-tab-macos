# Project rows in the window switcher

With Projects enabled, the window switcher is at least wide enough for its Project buttons, independently of the number of windows. The Project strip grows up to 90% of the preferred screen's usable width, including panel padding. A small Project list keeps one compact row. Lists wider than that limit wrap to a second row. The header reserves both rows before choosing thumbnail size, and the window viewport remains centered and large enough for its tiles in either writing direction.

Buttons use their measured label width, bounded to 58–160 points, and keep the existing numbering and order across rows. Long names retain full tooltips and accessibility labels. Rows are 30 points high with six-point horizontal gaps. When all buttons fit in two rows, their total widths are balanced; each row is centered. All Projects is always present at the trailing end of the final row; if two rows cannot show every Project, it provides the complete scrollable list. Disabling Projects restores the ordinary width and removes both rows. Search, Back, Project selection and each switcher style share this layout.

## Test scenarios

- **testSmallProjectListUsesOneCompactRow** — the required width and positions include each Project, spacing and All Projects.
- **testManyProjectsUseFullAvailableWidthAndTwoRows** — a representative large list stays entirely visible across two rows at the maximum width.
- **testExactFitStaysOnOneRow** — exact boundary fits do not add unnecessary height.
- **testTwoRowsBalanceProjectsWithTheAllProjectsButton** — two rows share the Projects instead of isolating All Projects on its own row.
- **testOverflowKeepsAllProjectsReachableWithinTwoRows** — excess Projects are hidden without covering the complete-list action.
- **testEmptyProjectListStillOffersAllProjects** — an empty list keeps its complete-list control accessible.
- **testRightToLeftMirrorsButtonsWithoutChangingOrderOrRows** — visual direction mirrors frames while preserving semantic order and row allocation.
- **testNarrowAndZeroWidthLayoutsStayWithinScreenBounds** — constrained layouts never overlap controls or exceed their available bounds.
- **testFractionalMetricsRoundWithoutOverflow** — measured widths round up and available width rounds down before packing.
