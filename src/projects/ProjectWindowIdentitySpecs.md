# ProjectWindowIdentity

Membership restoration identifies a live window by its tracked WindowServer ID, owning PID, and process launch time. It does not use mutable window titles or claim newly opened windows by title matching.

## Test scenarios

- **testIdentitySurvivesEncoding** — encoding and decoding preserves an exact window identity.
- **testDifferentWindowDoesNotMatch** — another window in the same process is distinct.
- **testDifferentProcessDoesNotMatch** — another process cannot inherit the mapping.
- **testReusedPidDoesNotMatch** — a later process using the same PID cannot inherit the mapping.
