# ProjectNameResolver

A Desktop displays its owning Project's resolved name, or `Desktop N` when it has no owner.
Desktop records do not carry editable names; the runtime adapter never passes an independent
Desktop name to the resolver. Project names resolve to a nonblank user name, a sticky automatic
name, then `Project N` for legacy records.
Claiming a name only fills an unnamed record once. Forgetting operates only on the automatic name,
so a user's name is preserved when all windows close. New custom projects receive a
permanent unique name. Rename prompts reject blank or duplicate names and keep the entered
text for correction. Archived and deleted project names remain reserved.

Project for This Desktop uses a single owner picker and one Project-name field. Save can create
an owner, choose an existing Project, rename the owner, or leave the Desktop without a Project.
Replacing an owner preserves the previous Project, its windows and history without a desktop
assignment. Selecting a Project assigned elsewhere transfers that assignment. Cancel leaves all
ownership and names unchanged. A changed or removed Desktop invalidates the pending save.
New Project naming creates an unassigned draft until accepted, so cancellation cannot displace
the Desktop's existing owner. Rename Project accepts only a Project, never a desktop adapter.
In Project for This Desktop, creating with an existing open Project's name or folder key reuses
that Project, including when it owns another Desktop. Reuse preserves its name, ID, folder,
windows and history, and transfers its Desktop assignment through the existing-owner path.
The lookup uses the current open Projects at Save, including Projects added after the picker
opened. Archived or deleted names still require the existing Attic or recovery workflow.

Names share the same filesystem key after case, accent and width folding, whitespace
and punctuation become hyphens, and keys are limited to 60 characters. Such collisions
are rejected in both the UI and file store. Generated suggestions use distinct names
such as Finder 2 instead of a random folder suffix. Renaming preserves the project ID
and moves its folder, including all user files.

## Test scenarios

- **testUserNameWins** — a user name takes precedence over automatic and fallback names.
- **testDesktopIgnoresSavedAutomaticAppName** — Desktop numbers take precedence over automatic names.
- **testCustomProjectKeepsAutomaticAppName** — legacy custom projects retain their automatic name.
- **testDesktopFallbackUsesDesktopNumber** — an unnamed Desktop resolves to its Desktop number.
- **testCustomFallbackUsesCreationNumber** — an unnamed custom Project resolves to its creation number.
- **testClaimUsesFirstAppName** — the first nonblank application name is claimed and trimmed.
- **testClaimKeepsStandingAutoName** — another application cannot replace a standing automatic name.
- **testClaimNeverOverridesUserName** — a user name prevents an automatic claim.
- **testForgetDropsAutoNameWhenEmpty** — an empty Project loses its automatic name.
- **testForgetKeepsAutoNameWithLiveWindows** — a Project with live windows keeps its automatic name.
- **testForgettingAutoNamePreservesUserName** — forgetting the automatic name leaves the user's name in charge.
- **testWhitespaceClearsToAutomatic** — blank input clears to automatic naming.
- **testBlankAppCannotClaimName** — blank application names cannot claim a record.

- **testProjectNamesReserveTheSameCaseInsensitiveFolder** — names cannot collide after filesystem normalization.
- **testAutomaticProjectNamesAreDistinctWithoutRandomSuffixes** — generated suggestions have distinct names, even after truncation.
- **testMatchingFindsExistingProjectByNameOrFolderKey** — reuse accepts the same case, accent, width and punctuation variants as folder validation, keeping distinct folder keys separate.
- **testMatchingDoesNotReuseProjectForBlankOrDifferentName** — empty and unmatched input cannot select an existing Project.
- **testMatchingUsesTheSameTruncatedFolderKeyAsValidation** — matching and collision validation agree at the folder length limit.
