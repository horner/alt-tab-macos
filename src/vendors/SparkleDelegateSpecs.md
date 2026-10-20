# Projects automatic updates

Projects builds use the bundle's `SUFeedURL` and Projects Ed25519 public key. They never fall back to the upstream feed or key. The Projects feed has no additional query parameters and licensing state changes do not write the upstream license cookie. Every Projects user accepts the `beta` Sparkle channel as well as its default channel; GitHub prerelease status does not determine eligibility.

The existing Sparkle controller starts 30 seconds after application setup. The manual Settings action starts it immediately when needed and uses Sparkle's standard progress, download, installation and relaunch UI. General Settings exposes manual checks, scheduled checks and automatic installation; Projects continues to hide crash-report controls.

New installations default to daily checks with installation approved by the user. A saved `updatePolicy` remains authoritative at startup, including manual-only and automatic-install choices. It is applied before registering subsequent Sparkle-default observations. Initial KVO delivery must not overwrite it. Sparkle-default changes are coalesced onto the next main-queue turn so both updater flags have settled before updating the application preference and dropdown. Enabling automatic installation also enables scheduled checks.

## Runtime validation

- Relaunch with each policy selected and confirm both Sparkle flags and the General dropdown retain that choice. With no stored policy, confirm scheduled checks are enabled and automatic installation is disabled.
- Invoke a manual check before the delayed startup, and again after it, against the local signed test feed. Confirm a `beta` item is offered without a beta opt-in control.
- Complete a signed A → B download, install and relaunch. Preserve existing Projects, settings, license data and macOS permissions; retain a rollback bundle and preferences.
- Exercise no update, offline, cancel/later/skip and an invalid update signature. Repeat the successful upgrade with a Homebrew-installed copy and identify any untested runtime platforms.

Feed metadata, package verification and publication ordering are tested by the Projects release tooling. The updater's UI and policy synchronization require the runtime checks above.
