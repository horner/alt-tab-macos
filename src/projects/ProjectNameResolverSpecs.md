# ProjectNameResolver

Names resolve in order: a nonblank user name, a sticky automatic name, then `Desktop N` or `Project N`.
Claiming a name only fills an unnamed record once. Forgetting operates only on the automatic name,
so a user's name is preserved when all windows close. Whitespace-only input clears a user name.
Desktop tiles, navigation and context headers use explicit or automatic names when available.
The initial Projects setup claims names from existing windows as well as newly discovered windows.

## Test scenarios

- **testUserNameWins** — a user name takes precedence over automatic and fallback names.
- **testAutoNameWinsOverFallback** — the automatic name takes precedence over a numbered fallback.
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
