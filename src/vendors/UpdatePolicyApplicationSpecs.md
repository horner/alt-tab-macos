# Applying update policies

The application maps its manual, check-only and automatic-install policies to Sparkle's check and download preferences. Setter order must honor Sparkle's `allowsAutomaticUpdates` gate: enable scheduled checks before enabling downloads, and clear downloads before disabling scheduled checks. `SPUUpdaterSettings.setAutomaticallyDownloadsUpdates` ignores writes while that gate is closed.

## Test scenarios

- **testAllPolicyTransitionsReachSelectedFlags** — All nine transitions among the three policies reach the selected flags.
- **testDisablingInstallationClearsItsStoredChoiceBeforeChecksStop** — Switching to manual clears installation consent before disabling checks, so later enabling checks cannot restore it.
- **testCheckOnlyPolicyClearsHiddenInstallationChoice** — Check-only clears a retained download preference when starting with checks disabled.

The stateful test updater reproduces Sparkle's download setter gate and effective download value. The production helper operates on the real Sparkle setters; runtime validation covers KVO synchronization, preference persistence and visible Settings controls.
