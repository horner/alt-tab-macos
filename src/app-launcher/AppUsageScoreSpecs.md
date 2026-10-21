# Adaptive app frequency

Each successful picker action adds one to the app installation's lifetime count. Bringing an app to the foreground updates its last-used date but does not increment frequency; a picker action and its resulting activation must not count twice. Failed or ambiguous actions do not add a count.

The raw count is retained for history and never participates in ranking. Two weighted counts track recent activity with a one-day half-life and the baseline with a seven-day half-life. Both are normalized to uses per day by multiplying by `ln(2) / halfLifeInDays`. Trend is the recent rate minus the baseline rate. Ranking uses `recentRate + max(0, trend)`, giving rising usage at most twice its recent rate. Scores below 0.01 uses per day become zero so an old, negligible tail cannot permanently outrank an app with no picker history.

Weights decay lazily when recording an event or opening the picker. There are no timers, event lists, or daily reset jobs. Ranking is fixed for the current picker session. Lifetime counts, both weights, and their update timestamp persist under `appPickerFrequencyV1`; last-used dates continue using `appPickerLastUsed`. Loading old recency-only data does not invent historical counts. Dates use wall-clock time so decay includes downtime; a backward clock adjustment cannot increase an existing weight.

Among matching apps, frequency ranks first, followed by last-used date, match quality, name, and installation path. A nonmatching app cannot enter the results regardless of frequency. This is a heuristic for changing habits, not a guarantee that every new app outranks a still heavily used app after one day.

Tests:
- `testRawCountDoesNotDecayButRecentWeightHalvesDaily`
- `testNewCanaryHabitOvertakesTwoYearsOfChromeWithinADay` — six opens per day for Chrome over two years, followed by six Canary opens over a day, leaves Canary first despite lifetime counts of 6 versus 4,380.
- `testSteadyUseDoesNotAccumulateAnEverGrowingRankingAdvantage`
- `testEncodingAndReloadPreserveCountsAndDecayAcrossDowntime`
- `testClockMovingBackDoesNotInflateExistingWeights`
- `testLongAbsenceRemovesRankingInfluenceButKeepsRawHistory`
- `testNegligibleFrequencyYieldsToRecency`
- `AppCatalogTests.testTrendingFrequencyRanksMatchingAppsAheadOfRecency`
