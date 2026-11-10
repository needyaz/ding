# Drift report: Ding baseline recovery

Everything here is recorded, not fixed. No code, test or document was changed apart from one pointer line in `SPEC.md`.
Line numbers refer to the files as of this recovery.

## 1. Conflicts (status X, left open)

| Id | Side A | Side B |
|---|---|---|
| DING-NOTIF-013 | `SPEC.md:94` says the screen-reminder style defaults to **None**, and `Ding/Preferences.swift:47` (`Pref.Default.alertMode = .off`) agrees, asserted by `DingTests/PreferencesTests.swift` "testRegisteredDefaults". | `SPEC.md:99` says "The default is a 5-minute notification followed by a full-screen reminder 1 minute before." |
| DING-NOTIF-028 | `SPEC.md:87` says the UI says "screen reminder", not "alert", because macOS already uses "Alerts" for a notification style. | `Ding/SettingsView.swift:214` labels the third style "Full-screen alert". |
| DING-MCP-019 | `Ding/ControlService.swift:82` replies `{"opened": true}`, asserted by `DingTests/ControlServiceTests.swift` "testJoinWithoutAnIDJoinsTheNextLinkedMeeting" and "testJoiningWithoutScheduleAccessConfirmsWithoutSayingWhichMeeting", and `SPEC.md:142` agrees. | The `open_meeting` tool description that every MCP client receives (`Sources/DingMCP/Tools.swift:45`) says "The reply confirms it with joined: true". No test reads that sentence. |
| DING-TEST-001 | `SPEC.md:220`: "Nothing in tests touches the real system. The notification center, browsers and workspace, EventKit, login items and windows all sit behind protocols or closures". | `DingTests/AssistantsTabTests.swift:47` builds `AppModel()`, whose `UserNotificationScheduler` installs a delegate and categories on `UNUserNotificationCenter.current()`. `DingTests/CalendarStoreTests.swift` (class `CalendarStoreTests`) builds the real `CalendarStore`/`EventKitStore`. `DingTests/SystemWorkspaceTests.swift` queries Launch Services and needs Safari installed. `DingTests/CalendarStoreTests.swift` "testTheRealEventKitStoreAdapterIsConstructible" and `DingTests/LaunchAtLoginTests.swift` "testTheRealServiceIsReadable" read real system state. |
| DING-REL-002 | `DISTRIBUTION.md:14`: preflight checks that `git`, `xcodebuild` and `xcodegen` are on PATH. | `make/store.mk:22`: `RELEASE_TOOLS := git xcodebuild xcodegen deno`, so preflight also requires `deno`. |
| DING-REL-019 | `SPEC.md:239-240` (Milestones): "Remaining: … signing and notarization, App Store submission". `SPEC.md:227`: "notarized DMG and Homebrew cask possible later". | `make/store.mk` and `scripts/` already implement TestFlight upload, listing, screenshots, `submit`, `withdraw` and `github-release` (a notarized **zip**, not a DMG), described in `DISTRIBUTION.md`. `README.md:21` sends users to notarized builds on GitHub Releases. `DISTRIBUTION.md:64,76` say the tooling is untested on the real box. |
| DING-PROC-005 | `SPEC.md:267` (Decisions): the GitHub repo `needyaz/ding` is private for now, so Send Feedback and the issues link reach no one else. | `README.md:21` tells readers that notarized builds are attached to the GitHub Releases. The repo's real visibility can't be checked offline. |

## 2. Unspecced behavior (built, documents silent)

Rows marked US, plus C or IU rows whose `src` is `-`:

- **DING-NOTIF-016 (US):** the one "Also for events without a meeting link" switch sits only in the *Screen reminder* section (`Ding/SettingsView.swift:224`) but `AlertPlanner` applies it to notifications too. A user who turns it on for the edge flash also starts getting notifications for linkless events.
- **DING-NOTIF-027 (US):** Preview and the screen-reminder timing picker are disabled while the style is None.
- **DING-REFRESH-006 (US):** the app skips `AppModel.start()` when hosted by XCTest and in `--screenshots` mode.
- **DING-MCP-020 (US):** the helper exits 1 with a message on stderr when its bundle has no `DingAppGroup`.
- **DING-BUILD-006 (US):** `make logs`, `make reset-calendar-permission`, `make clean`, `make xcode`.
- **DING-NOTIF-025:** the full-screen live line has a "Started Ns ago" stage (5 to 59 s after the start). The documents mention only "Starting now" and "Started 2 min ago".
- **DING-DROPDOWN-006:** the range defaults to 3 days. The documents list the options but not the default.
- **DING-CAL-001:** restricted and write-only calendar access count as denied.
- **DING-CAL-003:** a refused or throwing access request still resets the store and reports a change.
- **DING-CAL-007:** empty titles become "Untitled", and event ids are `<identifier>@<start epoch seconds>` so recurring occurrences stay distinct.
- **DING-JOIN-004:** how the installed-browser list is built (excludes Ding, deduplicated, sorted, ".app" stripped).
- **DING-JOIN-008:** the Webex fallback bundle `com.cisco.webexmeetingsapp`.
- **DING-LINK-008:** `zoommtg://` URLs on any host count as Zoom.
- **DING-NOTIF-008, DING-NOTIF-010:** notification ids `ding.<event id>`, and notifications presented as banners with sound even while Ding is frontmost.
- **DING-PREFS-002, DING-PREFS-005, DING-PREFS-006, DING-PREFS-008:** registering defaults never overwrites stored values, the Launch at login switch reverts after a failure, the Preferences window is a reusable non-resizable "Ding Preferences" window, and preference changes are debounced by 250 ms.
- **DING-REFRESH-004, DING-REFRESH-005:** start-up and reload sequencing.
- **DING-MCP-010, DING-MCP-013, DING-MCP-014, DING-MCP-017, DING-MCP-021:** tool annotations, the whole-number-as-double rule, `structuredContent` plus a text copy, distinct tool errors for timeout, refusal and garbled replies, and a 10 s helper timeout.
- **DING-CTRL-003, DING-CTRL-018, DING-CTRL-023:** `unknown_method` and `invalid_request` codes, no listener without an app group, and the helper path is offered only if it is executable.
- **DING-IPC-005, DING-IPC-007, DING-IPC-011, DING-IPC-014:** team-ID parsing, path-length rejection, concurrency, and JSON round-tripping.
- **Two "screen reminder lead" defaults:** `Sources/DingCore/Alerts.swift:49` defaults `AlertSettings.alertLeadMinutes` to 0, while the app's preference default is 1 (`Ding/Preferences.swift:49`). The app always passes the preference, so users see 1, but any new caller of `AlertSettings()` gets 0.
- **Picker fallback differs from the registered default:** `Ding/SettingsView.swift:173` gives every service picker the fallback value "default", while `Pref.registerDefaults()` registers "native" for Zoom. This only shows if a view reads the key before defaults are registered (previews, tests).
- **AI Access wording:** `Ding/AssistantsTab.swift:42` tells the user an assistant learns "whether each is Zoom, Meet, Teams or Webex", but summaries also report "Other link" as a service.

## 3. Stale or unverifiable statements in documents and comments

- `SPEC.md:99`: the default reminder setup (see DING-NOTIF-013).
- `SPEC.md:87` vs the "Full-screen alert" label (DING-NOTIF-028).
- `SPEC.md:220`: "Nothing in tests touches the real system" (DING-TEST-001).
- `SPEC.md:221`: "about 99.6% for core and 93% for the app". Nothing records or checks these figures. `Makefile:132-133` hard-codes `.build/arm64-apple-macosx/...`, so `make coverage` can't report core coverage on an Intel Mac.
- `SPEC.md:227`: "notarized DMG … possible later". `make github-release` already produces a notarized zip (DING-REL-019).
- `SPEC.md:239-240` and `README.md:70`: milestone status says signing, notarization and submission remain, but the tooling exists (DING-REL-019).
- `SPEC.md:267`: repo private vs README pointing at GitHub Releases (DING-PROC-005).
- `DISTRIBUTION.md:14`: preflight tool list omits `deno` (DING-REL-002).
- `listing/README.md:12`: "Keywords carry no trademarked terms" is presented as part of what `make listing-check` validates. `scripts/listing_metadata.ts:83` checks only spaces around commas (DING-REL-010, NI).
- `Sources/DingMCP/Tools.swift:45`: "joined: true" (DING-MCP-019).
- `Ding/Screenshots/ScreenshotMode.swift:77-79`: the comment says the mode shows a small window "for `make screenshots` to click (see scripts/bring_ding_forward.sh)". That script does not exist. `Makefile:68-71` brings the app forward with a second `open` instead.
- `Ding/AssistantsTab.swift:42`: omits "Other link" from the services an assistant can see (see section 2).
- `DingTests/PreferencesTests.swift` "testHotkeysAndAlertsAreOffByDefault": the name claims hotkeys (see section 4).

## 4. Tests that cannot fail or assert less than their names say

| Test | Problem |
|---|---|
| `DingTests/ControlServiceTests.swift` "testTheSelectionTheUserMadeIsWhatAssistantsSee" | Feeds an empty event list and asserts an empty answer, so it passes whatever filtering does. DING-CTRL-016 stays IU. |
| `DingTests/PreferencesTests.swift` "testHotkeysAndAlertsAreOffByDefault" | Asserts only the alert mode and the linkless-alert switch. Nothing about hotkeys. DING-HOTKEY-001 stays IU. |
| `DingTests/MenuBarGlyphTests.swift` "testClapperIsSeparatedFromTheLip" | Requires at least two solid runs on the centre line. Its own comment says the clock hands already create a gap, so a clapper fused to the lip still passes. DING-MENUBAR-003 stays IU. |
| `Tests/DingIPCTests/ProtocolTests.swift` "testSocketPathIsShortEnoughForAUnixSocket" | Measures a path it builds itself and never calls `DingIPC.socketURL`. DING-IPC-008 stays IU. |
| `Tests/DingMCPTests/EndToEndTests.swift` "testLinesWithSurroundingWhitespaceAreAccepted", "testAWindowsLineEndingIsAccepted" | Count one output line, which a -32700 parse-error reply would also produce. `serve` trims only spaces and tabs, so a trailing CR reaches the JSON parser. DING-MCP-003 stays IU. |
| `Tests/DingCoreTests/ControlTests.swift` "testTheWholeDocumentFormIsGone" | Repeats an assertion already in "testTheEntryHasNoOuterBraces". |
| `Tests/DingCoreTests/ControlTests.swift` "testAddedToAConfigThatAlreadyHasOtherMCPServersIsNotCovered" | Asserts only that the entry contains the key once. It documents a limitation rather than testing behavior. |
| `DingTests/ViewSmokeTests.swift`, `DingTests/SettingsTabTests.swift`, `DingTests/AssistantsTabTests.swift` render tests | Assert only a non-zero fitting size. "testTheSettingsWindowHasAnAssistantsTab" does not check that the tab exists. "testCalendarsTabExplainsWhyItIsEmpty" checks no text. "testPickerReflectsTheStoredChoice" asserts `OpenTarget.current`, not the picker. "testCalendarColorConversion" asserts nothing. |
| `DingTests/CalendarStoreTests.swift` "testWithoutAccessNothingIsReturned", "testWithAccessQueriesDoNotCrashAndAreOrdered" | Each returns early depending on the machine's calendar grant, so one of the two always passes vacuously. "testChangeCallbackIsSettable" only calls a closure it set. "testTheRealEventKitStoreAdapterIsConstructible" asserts a non-optional is non-nil. |
| `DingTests/LaunchAtLoginTests.swift` "testTheRealServiceIsReadable" | No assertion. |
| `DingTests/AlertControllerTests.swift` "testTakeoverCanBeBuiltForAMultiDisplaySetup" | Returns early with no screens (a headless runner), passing vacuously. "testAlertViewsRender" only lays views out. |
| `DingTests/ScreenshotTests.swift` "testEveryTabCanBeShown" | Asserts the enum has six cases, not that each tab can be shown. "testTheFullScreenViewCanShowAFixedMoment" asserts a stored property. |
| `DingTests/PreferencesTests.swift` "testDefaultClockMatchesTheSystemLocale" | Close to tautological, since `registerDefaults` is defined with `systemUses24Hour`. It also creates a defaults suite it never removes. |
| `DingTests/AssistantsTabTests.swift` "testControlServerIsNotStartedByTestModels" | Asserts a flag only, and builds a real `AppModel()` (see DING-TEST-001). |
| `DingTests/AppModelLifecycleTests.swift` timer tests | Depend on wall-clock waits (`settle(2.5)`, `settle(4)`) and real timers, so they may be flaky on a loaded machine. |

## 5. Untested defaults worth noting

These are implemented but no test pins the value: the menu bar's 24-character limit, the 460 pt scroll cap and 340 pt width, the 1/3/7/14 range options, the Off/1/2/5/10/15 notification options, the 60 s snooze, the 15-minute safety reload, and the socket server's 16-connection cap and 30 s idle timeout.
