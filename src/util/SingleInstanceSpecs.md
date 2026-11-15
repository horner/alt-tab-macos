# Single app instance

Only one updated AltTab process per user may initialize the app, regardless of bundle location or
bundle-ID variant. An exclusive file lock is acquired in main before AppKit starts, preferences are
loaded, event taps are installed, or signal cleanup can change global shortcuts. A duplicate exits
successfully with a diagnostic; a lock/open failure exits unsuccessfully instead of running unguarded.
CLI commands remain usable while the app holds the lock because command dispatch precedes acquisition.

The lock lives in a fixed per-user Application Support directory. It stays held through termination,
including capture draining and preference saves. The operating system releases it on normal exit or
crash. Its descriptor is close-on-exec so launched tools cannot extend its lifetime. The file is never
unlinked: deleting a locked file could let another process acquire a separate inode at the same path.
A stale file without an owner does not prevent launch.

Intentional restart launches the same bundle with `--wait-for-instance`. The replacement blocks on
the kernel lock before initializing the app, then proceeds after the old process exits. Ordinary
second launches, including `open -n`, never wait or take over. Moving to Applications already waits
for the old process to exit before relaunching. Older binaries without this guard cannot participate
in its exclusion; quit those copies when switching to the updated build.

## Tests

- `testDuplicateCannotAcquireLock`
- `testOwnerExitAllowsNextLaunchWithoutDeletingFile`
- `testRestartWaitsUntilOwnerReleasesLock`
- `testLockOpenFailureDoesNotAllowStartup`

Process-level validation should race separate launchers, kill a lock owner, and exercise a waiting
replacement against the production lock implementation without installing event taps or creating
Desktop labels.
