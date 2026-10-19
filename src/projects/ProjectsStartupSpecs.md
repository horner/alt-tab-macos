# AltTabProjects startup policy

`ProjectsStartup.configure()` runs once per launch before preferences are registered.
It applies only when the bundle product name is `AltTabProjects`.

- Shortcut 1 defaults to Command-Tab, all applications, visible Spaces, the screen showing AltTab, and minimized windows shown.
- Shortcut 2 defaults to Command as its hold key. Projects starts enabled, with Option as its hold key, matching the saved local settings.
- Defaults are registered, not forced: saved preferences win and users can edit them. Resetting preferences returns to these product defaults.
- All features stay available through an in-memory Pro state. No trial is started and no license validation request is sent. Existing license keys, trial dates, signing identities and bundle IDs are untouched.
- Settings and the menu bar hide purchase/account UI; Pro badges are hidden and the upgrade page cannot be opened.
- Other product names retain the ordinary defaults and licensing behavior.

LicenseManagerTests.testProductOverrideSurvivesRefreshWithoutStartingTrial and
LicenseManagerTests.testProductOverridePreservesStoredLicenseWithoutRevalidation
cover refresh, trial, persistence and validation behavior.
