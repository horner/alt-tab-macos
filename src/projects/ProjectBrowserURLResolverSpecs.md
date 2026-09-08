# ProjectBrowserURLResolver

Safari and Google Chrome document metadata supplies the active-tab URL per window. Reads use the existing off-main AX scheduler and bounded traversal of browser UI to the first web area; page links, embedded-frame contents, and editable address-bar values are not inspected. Failure leaves the current URL unknown; earlier URLs remain in Project history. Supported URL schemes are HTTP and HTTPS.

Refreshes occur at discovery, existing title/window-refresh events, and menu opening. They do not poll or activate the browser. History stores normalized URLs without user/password or common transient OAuth/SAML parameters; document query parameters and application fragments remain significant. URLs are not written to debug logs.

## Test scenarios

- **testOnlySupportedBrowsersAreRead** — capture is restricted to Safari and Google Chrome main app identifiers.
- **testCanonicalOriginAndDefaultPortMatch** — equivalent origin spellings normalize together.
- **testCredentialsAndTransientSignInParametersAreNotStored** — credentials and common authentication tokens are omitted while return destinations remain.
- **testDocumentQueriesAndApplicationRoutesRemainDistinct** — document identifiers and SPA routes remain part of the URL.
- **testUnavailableOrNonWebURLsRemainUnknown** — unavailable, incomplete, and non-web addresses are not guessed.
