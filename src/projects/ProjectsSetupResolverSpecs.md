# First enable of Projects

AltTabProjects distribution builds default to Projects enabled, label windows open behind other
windows, and a 1,500 ms label reveal when switching Spaces. Debug builds keep the opt-in defaults.
Registered defaults preserve saved choices, including a disabled feature or a different duration.

After permissions and Space discovery, the first enable creates one linked Project for each live
Desktop or fullscreen Space without an existing link. Existing names, links, custom Projects,
memberships and exclusions are preserved. The setup-completed preference is saved after the
Projects collection. Missing topology defers setup. Relaunching or toggling the feature later does
not recreate Projects that the user deleted or unlinked. Upgrading from 0.1.0 runs this setup once
when Projects is enabled.

Linking captures already discovered windows. The enable handler also refreshes browser metadata
and restores identities before capturing windows; asynchronous launch discovery uses the same
Desktop links as windows arrive. Windows keep existing owners and explicit exclusions. Minimized
and hidden windows are included; windowless app placeholders and phantom windows are excluded.

Names use the first available application name on the Desktop, with Desktop N / Project N fallbacks
for empty entries. Automatic names appear in Desktop tiles, navigation, labels and Project lists.
An explicit user name always wins. Setup does not display a naming wizard.

## Tests

- **testDistributionDefaultsEnableProjectsAndLabelsFor1500Milliseconds** — release defaults.
- **testDebugDefaultsKeepProjectsAndLabelsOptIn** — Debug defaults remain independent.
- **testRegisteringDistributionDefaultsPreservesUserChoices** — saved settings beat defaults.
- **testFirstEnableLinksEveryDesktopWithoutAnExistingProject** — seed only missing links.
- **testDisabledProjectsDeferSetup** — a saved disabled choice defers initialization.
- **testUnavailableTopologyDoesNotMarkSetupComplete** — discovery may arrive later.
- **testExistingLinksCompleteSetupWithoutReplacement** — existing links are sufficient.
- **testRelaunchAndReenableDoNotRecreateDeletedOrUnlinkedProjects** — one-time initialization.

Membership restoration and exclusion rules are covered by ProjectReattachResolverTests. Validate
the full discovery path on a Mac with windows across Desktops, including a browser, minimized and
hidden windows, then relaunch and disable/re-enable Projects to check saved state.
