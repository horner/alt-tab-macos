# Project lifecycle and Desktop ownership

A custom Project owns its saved name, records, and optional Desktop assignment.
`homeSpaceUuid` is the sole assignment authority. Every Project has at most one Desktop,
and every Desktop has at most one owner. Empty `homeSpaceUuid` with
`desktopOwnershipVersion: 1` means explicitly unassigned. Desktop names and reverse links
are legacy migration input only; normalized Desktop records contain neither authority.

## Migration

Records without `desktopOwnershipVersion` are legacy. A version 1 Project assignment
wins over stale legacy Desktop links, including after an interrupted multi-file save.
Legacy Desktop link order chooses one open owner; conflicting Projects remain intact and
unassigned. A Project linked by multiple Desktops claims the first Desktop in stable UUID
order. Legacy Projects without an explicit Desktop link use their saved home; competing
homes choose the lowest stable Project ID. Closed Projects never own a Desktop.

Normalization marks every record version 1. Explicitly unassigned Projects are never
reassigned from stale Desktop links, names, or label identities. Repeated normalization,
serialization, and reload produce the same assignments. A saved UUID absent from runtime
topology is retained for reconnection; normalization does not guess that a disconnected
Desktop was deleted. Runtime behavior is specified in ProjectDesktopResolverSpecs.md.

An otherwise unowned, named legacy Desktop becomes a custom Project with deterministic
`project-desktop-<UUID>` identity, preserving membership, history, exclusions, icon, and
legacy label identity. ID and name collisions receive stable numeric suffixes. Desktop
records already referencing an existing Project, or matching a Project's label identity
and saved names, do not recreate that Project. Archived aliases remain archived. A
versioned unowned Desktop never creates a Project from a manually reintroduced old name.

Custom Project files are saved before the cleaned Desktop collection. If saving stops
between those stages, the new Project assignment is authoritative when migration resumes.
All losing Projects and all their records remain available for explicit reassignment.

## Close, restore, and identity

Closing archives the Project name, window identities, membership evidence, exclusions,
history, icon, and label identity. It clears ownership and pending removal state, removes
the Project from active labels and automatic restoration, and keeps it in Project Attic.
Application windows and macOS Desktops remain open. Restoring keeps the same Project
identity and records; runtime validates the chosen Desktop and resolves ownership.

An empty synthetic custom record whose ID is `desktop-<label UUID>` is consolidated only
when exactly one other custom Project has the same label UUID and saved names. The original
identity and records survive. A closed alias closes the original. Aliases with their own
records, exclusions or icon, and ambiguous matches, remain preserved. Names alone never
establish identity. This alias repair runs before ownership migration.

The combine resolver accepts only distinct open custom Projects with the same nonempty
Desktop UUID. It preserves destination identity, name, and label; unions memberships and
history; and keeps the latest observation and confirmation times. Included members take
precedence over matching exclusions. Empty assignments do not imply a shared Desktop.

## Validation

ProjectLifecycleResolverTests covers migration precedence, deterministic conflicts,
explicit unassignment, archived aliases, preservation of named Desktop metadata,
identity/name collisions, missing Desktops, JSON reload, close/reopen, and combination.
ProjectFileStoreTests covers ownership schema validation, unassigned and archived file
roundtrips, interrupted migrations, YAML reload, and rejection of unsupported versions.

Manual integration: after migration and relaunch, compare all visible label names and
window titles with the sole owner saved in each Project file. Reassign a disposable
Desktop and verify its prior owner remains intact and unassigned. Confirm that an
unowned Desktop shows Desktop N and that archived Projects do not recreate labels.
