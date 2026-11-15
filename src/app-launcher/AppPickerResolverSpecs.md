# App picker decisions

Cmd+N replaces the active switcher with an independent picker. The picker stays open after modifier release; Escape closes it. An existing matching shortcut wins a conflict. Creation commands belong only to Chrome, Safari, and Messages; other applications open normally.

The picker inherits the invoking switcher's theme and background material, with a borderless rounded panel, app logos, and the same accent-colored selection outline. Each row separates the app name from its action. Duplicate app names also show their installation path. The list shows six rows before scrolling; keyboard selection and Return remain available while the search field has focus.

Menu matching targets specific native commands. Safari's default-profile identifier is accepted even when its title contains a profile name or its keyboard shortcut changes with tab preferences. Chrome currently requires its English New Window title and dispatch identifier; an unrecognized localized command returns an error instead of guessing. Message actions never select Send or open an existing conversation.

Tests:
- `testKnownAppsCreateAndOtherAppsOpen`
- `testEntryRequiresCommandNWithoutExtraModifiersOrConflict`
- `testSelectionFollowsInstallationAndHandlesRemovalOrEmptyResults`
- `testChromeDoesNotChooseTabOrPrivateWindow`
- `testSafariUsesWindowIdentifierIncludingDefaultProfile`
- `testMessageCommandNeverSelectsSendOrExistingConversation`

Live checks cover held modifiers, window search, IME composition, fast cancellation, running/stopped apps, Safari tab/fullscreen preferences, and Messages composition without sending. Accessibility creation runs once on the non-retrying executor. An ambiguous error cannot automatically create a second window or message.
