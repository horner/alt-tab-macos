# ProjectNameResolver

Desktop names resolve to a nonblank user name or `Desktop N`; a saved automatic app
name cannot label a Desktop. Custom project names resolve to a nonblank user name,
a sticky automatic name, then `Project N` for legacy records.
Claiming a name only fills an unnamed record once. Forgetting operates only on the automatic name,
so a user's name is preserved when all windows close. New custom projects receive a
permanent unique name. Their name prompts reject blank or duplicate names and keep the
entered text for correction. Archived and deleted project names remain reserved.

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
