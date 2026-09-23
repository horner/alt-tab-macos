# First enable of Projects

AltTabProjects distribution builds default to Projects enabled. Debug builds keep Projects opt-in.
Whenever Projects is enabled, label windows open behind other windows, with a 1,500 ms reveal when
switching Spaces. Registered defaults preserve a saved disabled feature or a different duration.
Label visibility follows SpaceLabelResolver; the obsolete spaceLabelsOnLaunch preference is unused.

After permissions, YAML loading and Desktop discovery, the first enable creates one linked Project
for each live Desktop without an existing link. Existing names, links, custom Projects, memberships
and exclusions are preserved. Missing storage or topology defers setup. Relaunching or toggling the
feature after setup does not recreate Projects that the user deleted or unlinked. Upgrading from
0.1.0 runs this setup once when Projects is enabled.

The setup-completed preference is saved only after the persistence queue has finished writing the
snapshot without file errors. The completion runs on main after that queue check, so another
Desktop update cannot seed duplicate Projects while the save is pending. A failed write leaves
setup incomplete for a later topology update or relaunch; existing links are never replaced during
a retry. Setup also validates the saved snapshot when every Desktop already has a link.

Linking captures already discovered windows. Asynchronous launch discovery uses the same Desktop
links as windows arrive. Windows keep existing owners and explicit exclusions. Minimized and
hidden windows are included; windowless app placeholders and phantom windows are excluded.

Newly linked Projects use the Desktop’s explicit name, then its automatic name, then the generated
Project name. A numeric suffix keeps names unique when several Desktops share a name. Existing
Projects keep their names. Setup does not display a naming wizard.

## Tests

- **testDistributionDefaultsEnableProjectsWith1500MillisecondReveal** — release defaults.
- **testDebugDefaultsKeepProjectsOptInWith1500MillisecondReveal** — Debug enablement stays independent.
- **testRegisteringDistributionDefaultsPreservesUserChoices** — saved settings beat defaults.
- **testFirstEnableLinksEveryDesktopWithoutAnExistingProject** — seed only missing links.
- **testDisabledProjectsDeferSetup** — a saved disabled choice defers initialization.
- **testStorageLoadingDefersSetupUntilExistingLinksAreKnown** — loaded links determine setup.
- **testUnavailableTopologyDoesNotMarkSetupComplete** — discovery may arrive later.
- **testExistingLinksCompleteSetupWithoutReplacement** — existing links are sufficient.
- **testRelaunchAndReenableDoNotRecreateDeletedOrUnlinkedProjects** — one-time initialization.

Membership restoration and exclusion rules are covered by ProjectReattachResolverTests. Validate
the full discovery path on a Mac with windows across Desktops, including a browser, minimized and
hidden windows, then relaunch and disable/re-enable Projects to check saved state.
