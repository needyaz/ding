# Ding: baseline living spec

Ding is a macOS 14+ menu bar app that counts down to the next calendar meeting and joins it in one click. It reads calendars
through EventKit, detects Zoom, Google Meet, Microsoft Teams and Webex links, sends notifications and optional screen reminders, and
bundles an opt-in MCP helper (`ding-mcp`) that lets AI assistants read the schedule or open a meeting over a Unix socket. The unit is
the whole repository: the `DingCore`, `DingIPC` and `DingMCP` Swift packages, the `Ding` app, the `ding-mcp` helper, and the
Deno release tooling in `scripts/`.

This baseline was recovered from the code, the tests and the documents as they stand. It changes no behavior. Every
requirement lives in `spec/requirements.tsv`; the sections below are generated from it. Status meanings:

- **C**: a named test asserts all of the statement (the evidence column names the test and what it leaves out).
- **IU**: implemented, but nothing asserts it.
- **NI**: specified, not built.
- **US**: built, but the documents are silent.
- **X**: sources conflict; both sides are recorded and the conflict is left open.
- **R**: retired.

Where the documents (`SPEC.md`, `README.md`, `DISTRIBUTION.md`, `CONTRIBUTING.md`, `listing/README.md`) disagree with the
code or tests, nothing was resolved here: see `spec/DRIFT_REPORT.md`. Proposed gates are in `spec/PROPOSALS.md` and the test commands
in `spec/TEST_LANES.md`.

<!-- BEGIN GENERATED: counts -->
Counts: 232 requirements — Confirmed 156, Implemented, untested 69, Unspecced behavior 4, Conflict 0, Not implemented 2, Retired 1.
<!-- END GENERATED: counts -->

<!-- BEGIN GENERATED: requirements -->
## Platform, packaging and privacy

- **DING-PLAT-001** Ding requires macOS 14 or later. _(SPEC SPEC.md Platform & Stack; README.md Requirements)_
- **DING-PLAT-002** The app is sandboxed with exactly three entitlements (app sandbox, calendars, and the application group derived from the team and DING_BUNDLE_ID) and has no network entitlement. _(SPEC SPEC.md Privacy; DISTRIBUTION.md Checked before the first upload)_
- **DING-PLAT-003** The bundled helper ding-mcp is sandboxed with only the app sandbox and the same application group entitlement. _(SPEC SPEC.md AI assistants (MCP) Transport; DISTRIBUTION.md Checked before the first upload)_
- **DING-PLAT-004** Ding runs as a menu bar agent (LSUIElement) and macOS allows only one running instance (LSMultipleInstancesProhibited). _(SPEC SPEC.md AI assistants (MCP) last bullet)_
- **DING-PLAT-005** The calendar permission text says Ding reads the calendar to show the next meeting and that the calendar stays on the Mac unless the user lets an AI assistant see it. _(SPEC SPEC.md Privacy)_
- **DING-PLAT-006** The privacy manifest declares no tracking, no collected data types and UserDefaults access with reason CA92.1. _(SPEC DISTRIBUTION.md One-time setup; SPEC.md Distribution & License)_
- **DING-PLAT-007** The app declares ITSAppUsesNonExemptEncryption as false. _(SPEC DISTRIBUTION.md One-time setup)_
- **DING-PLAT-008** KeyboardShortcuts and MenuBarExtraAccess are pinned to the exact versions 3.1.0 and 1.3.1. _(SPEC SPEC.md Privacy; project.yml comment)_
- **DING-PLAT-009** No code in the app, the helper or the libraries makes network calls. _(SPEC SPEC.md Goals; SPEC.md Privacy; README.md intro)_
- **DING-PLAT-010** The helper identifier Ding accepts is the app's own bundle ID followed by .mcp. _(SPEC SPEC.md Build & tooling; README.md Building your own copy)_
- **DING-PLAT-011** The app bundle ID, the helper bundle ID (<bundle ID>.mcp) and the app group (<team>.<bundle ID>) all derive from DING_BUNDLE_ID, and make TEAM=… BUNDLE_ID=… overrides them. _(SPEC SPEC.md Build & tooling; README.md Building your own copy)_
- **DING-PLAT-012** All UI strings are hard-coded English. _(SPEC SPEC.md Non-goals (v1); SPEC.md Known limitations)_
- **DING-PLAT-013** Calendars are read only through EventKit, with no direct Google or Microsoft API integration. _(SPEC SPEC.md Non-goals (v1); SPEC.md Platform & Stack)_
- **DING-PLAT-014** Ding has no paid tier, licensing code, saved-link speed dial or alternative UI styles. _(SPEC SPEC.md Non-goals (v1))_

## Menu bar item

- **DING-MENUBAR-001** The menu bar glyph is an 18-point template image whose accessibility description is Ding. _(SPEC SPEC.md Menu bar item)_
- **DING-MENUBAR-002** The glyph is a horizontally centred bell with clock hands knocked out of the dome and a transparent margin on every edge. _(SPEC SPEC.md Menu bar item; SPEC.md Build & tooling)_
- **DING-MENUBAR-003** The bell's clapper is drawn separate from its lip so it survives at small sizes. _(SPEC Ding/MenuBarGlyph.swift comment)_
- **DING-MENUBAR-004** The text beside the icon is '<title> in <countdown>', '<title> now', 'in <countdown>', '<title>' or nothing, according to the show countdown and show title options. _(SPEC SPEC.md Menu bar item)_
- **DING-MENUBAR-005** With 'only show the countdown for today's meetings' on, the menu bar shows the icon alone when the next meeting is not today. _(SPEC SPEC.md Menu bar item)_
- **DING-MENUBAR-006** The countdown reads 'now' at or after the start, otherwise whole minutes rounded up as Nm, Nh, Nh Mm, Nd or Nd Nh, and never 0m before the start. _(SPEC SPEC.md Menu bar item)_
- **DING-MENUBAR-007** Truncation collapses newlines to spaces, trims surrounding spaces and shortens text longer than the limit to at most limit-1 characters plus an ellipsis. _(SPEC SPEC.md Menu bar item)_
- **DING-MENUBAR-008** The menu bar truncates titles at 24 characters. _(SPEC SPEC.md Menu bar item)_
- **DING-MENUBAR-009** The next meeting is the earliest timed event that has not ended and started less than 5 minutes ago; all-day events are never next. _(SPEC SPEC.md Menu bar item; SPEC.md Dropdown)_
- **DING-MENUBAR-010** Of meetings that start together an accepted one is next before an unconfirmed one, then by title, and an earlier unconfirmed meeting is still next. _(SPEC SPEC.md Dropdown (Next meeting tie-break))_
- **DING-MENUBAR-011** The countdown refresh is scheduled 0.1 s after the label next changes, at most 60.1 s away and never sooner than 0.6 s. _(SPEC SPEC.md Refresh behavior)_
- **DING-MENUBAR-012** The next meeting is chosen from the events left after calendar selection and dropdown filters, and may lie beyond the dropdown range. _(SPEC SPEC.md Calendar selection; SPEC.md Refresh behavior)_

## Dropdown

- **DING-DROPDOWN-001** With calendar access granted and a next meeting, a Next meeting card at the top shows the headline, the title, the time and, when the meeting has a link, a Join button. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-002** The card headline reads 'Next · in <countdown>' before the start and 'Happening now' from the start. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-003** Events are grouped by day over the chosen range starting today; finished events are dropped and days without events are omitted, also across DST changes. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-004** Day headers read Today, Tomorrow, or the weekday, month and day such as 'Monday, Nov 2'. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-005** The range setting offers 1, 3, 7 or 14 days. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-006** The range defaults to 3 days and is never read as fewer than 1.
- **DING-DROPDOWN-007** Within a day all-day events come first, then events by start time, then by title. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-008** A multi-day all-day event appears on each day it covers, whether it ends at 23:59:59 on its last day or at the next midnight. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-009** All-day rows are italic on a tinted background, an in-progress meeting's row is highlighted and every row shows a calendar-colour dot. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-010** A row's time reads 'All day' or 'start – end' in the chosen clock format, followed by ' · Maybe' or ' · Not responded' for unconfirmed meetings. _(SPEC SPEC.md Dropdown (Response state))_
- **DING-DROPDOWN-011** Unconfirmed meetings are dimmed to 60 percent and their dot is a ring instead of a filled circle. _(SPEC SPEC.md Dropdown (Response state))_
- **DING-DROPDOWN-012** The 'show meetings marked maybe or not yet answered' toggle hides both maybe and not-responded meetings, and its stored key is still showMaybe. _(SPEC SPEC.md Dropdown (Toggles))_
- **DING-DROPDOWN-013** The 'show events without a meeting link' toggle hides every event without a link, all-day ones included. _(SPEC SPEC.md Dropdown (Toggles))_
- **DING-DROPDOWN-014** Timed meetings whose times intersect directly or through a chain form one run marked first, middle and last, while back-to-back meetings and all-day events never join a run. _(SPEC SPEC.md Dropdown (Overlap))_
- **DING-DROPDOWN-015** A zero-length meeting joins a run when it sits inside or starts with another meeting, and not when it only touches its end. _(SPEC SPEC.md Dropdown (Overlap))_
- **DING-DROPDOWN-016** Inside a run accepted meetings are listed before unconfirmed ones, and outside a run the order stays chronological. _(SPEC SPEC.md Dropdown (Overlap))_
- **DING-DROPDOWN-017** A run is drawn as one bracket along the left edge, rounded at its first and last row, and an overlapping row's accessibility hint includes 'Overlaps another meeting'. _(SPEC SPEC.md Dropdown (Overlap))_
- **DING-DROPDOWN-018** Overlapping meetings never cause a conflict notification. _(SPEC SPEC.md Dropdown (Overlap))_
- **DING-DROPDOWN-019** Clicking a row that has a link joins it, rows are one accessibility element with the button trait and a 'Joins with <service>' hint, and day headers carry the header trait. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-020** A short list is shown at its natural height and a long list scrolls inside a capped height, so a long list neither collapses nor grows without bound. _(SPEC SPEC.md Dropdown; SPEC.md Testing)_
- **DING-DROPDOWN-021** The scroll cap is exactly 460 pt and the dropdown is 340 pt wide. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-022** Without calendar access the dropdown offers Allow Calendar Access (not determined) or Open Privacy Settings (denied), and with access but nothing to show it says 'No upcoming meetings'. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-023** The footer has Preferences…, Send Feedback and Quit, and Send Feedback opens the issues page in the default browser. _(SPEC SPEC.md Dropdown)_
- **DING-DROPDOWN-024** The feedback URL is the ding repository's GitHub issues page. _(SPEC SPEC.md Dropdown; CONTRIBUTING.md)_

## Calendar access and selection

- **DING-CAL-001** Calendar access is granted only for EventKit full access; not determined maps to not determined and denied, restricted or write-only map to denied.
- **DING-CAL-002** Without granted access no events or calendars are queried and both come back empty. _(SPEC SPEC.md Dropdown (Calendar access states))_
- **DING-CAL-003** Requesting access resets the EventKit store and reports a change, also when the request is refused or throws.
- **DING-CAL-004** On every change notification from its own store the EventKit store is reset before the change is reported, and notifications from other stores are ignored. _(SPEC SPEC.md Refresh behavior)_
- **DING-CAL-005** Canceled events, events without dates and events the user declined are dropped when mapping. _(SPEC SPEC.md Dropdown)_
- **DING-CAL-006** A meeting is maybe for EventKit tentative, not responded for pending and accepted for anything else, including events with no attendee record for the user. _(SPEC SPEC.md Dropdown (Response state))_
- **DING-CAL-007** A mapped event carries its title (Untitled when missing or empty), start, end, all-day flag, calendar title, sRGB calendar colour (gray when missing) and an id ending in @<start in epoch seconds>.
- **DING-CAL-008** A mapped event's link is detected from its location, URL field and notes, with location before notes. _(SPEC SPEC.md Link detection)_
- **DING-CAL-009** Calendars without a source are grouped under 'Other' and the calendars of an account are sorted case-insensitively by title. _(SPEC SPEC.md Calendar selection)_
- **DING-CAL-010** Preferences list calendars grouped by their account's title, accounts sorted case-insensitively, each calendar with a colour dot and a checkbox. _(SPEC SPEC.md Calendar selection)_
- **DING-CAL-011** The stored calendar preference is the set of disabled calendar IDs, written sorted, so a calendar that appears later is on by default. _(SPEC SPEC.md Calendar selection)_
- **DING-CAL-012** Hidden calendars are left out of the dropdown, the menu bar, the join hotkey and screen reminders. _(SPEC SPEC.md Calendar selection)_
- **DING-CAL-013** Events on hidden calendars or hidden by the dropdown toggles get no notification, and events hidden by the toggles get no screen reminder. _(SPEC SPEC.md Calendar selection; SPEC.md Notifications and screen reminders)_

## Link detection

- **DING-LINK-001** Zoom (any zoom.us or zoomgov.com subdomain with /j, /my, /s, /w or /wc/join, and zoommtg), Google Meet (codes and lookup), Microsoft Teams (meetup-join and meet on teams.microsoft.com or teams.live.com) and Webex (meet, join, j.php, m.php, wbxmjs) links are recognised. _(SPEC SPEC.md Link detection)_
- **DING-LINK-002** The search order is conference URLs, location, URL field, then notes, and the first URL of a known service wins, also within one field. _(SPEC SPEC.md Link detection)_
- **DING-LINK-003** The app never fills the structured conference slot, because EventKit exposes no public conference data. _(SPEC SPEC.md Link detection; SPEC.md Known limitations)_
- **DING-LINK-004** Outlook SafeLinks (url parameter) and Google redirect (q or url on google.com/url) wrappers are replaced by their inner http(s) URL, and a wrapper without a usable inner URL is kept as it is. _(SPEC SPEC.md Link detection)_
- **DING-LINK-005** Escaped ampersands are decoded, trailing . , ; : ! ? are trimmed and a URL ends at whitespace, quotes, angle brackets or closing brackets. _(SPEC SPEC.md Link detection)_
- **DING-LINK-006** Lookalike hosts such as zoom.us.evil.com and non-meeting pages on known hosts such as zoom.us/pricing are not matched as that service. _(SPEC SPEC.md Link detection)_
- **DING-LINK-007** When no known service matches and exactly one distinct http(s) URL is present it becomes an Other link, and with none or several there is no link. _(SPEC SPEC.md Link detection)_
- **DING-LINK-008** Only http, https and zoommtg URLs are extracted, case-insensitively, so mailto, tel, ftp, file and scheme-less text give no link, and any zoommtg URL counts as Zoom.
- **DING-LINK-009** Every detectable service has a row in the single LinkPatterns table. _(SPEC SPEC.md Link detection)_
- **DING-LINK-010** Service display names are Zoom, Google Meet, Microsoft Teams, Webex and Other link. _(SPEC SPEC.md AI assistants (MCP))_

## Joining meetings

- **DING-JOIN-001** Zoom links open in the desktop app by default and every other service in the default browser. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-002** A stored desktop-app choice for Google Meet or Other links resolves to the default browser. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-003** The Meetings tab offers Desktop app only for Zoom, Teams and Webex, plus Default browser and each installed browser. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-004** The browser list comes from the apps that open https URLs, leaves out Ding, has no duplicates, drops the .app suffix and is sorted by name.
- **DING-JOIN-005** In desktop-app mode a Zoom /j/ link opens as zoommtg://<host>/join?confno=<id> with the original query when that scheme has a handler, and personal-room or other links open the web URL in us.zoom.xos. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-006** In desktop-app mode a Teams link opens with the msteams scheme when that has a handler, otherwise the web URL in com.microsoft.teams2, then com.microsoft.teams. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-007** In desktop-app mode a Webex link opens its web URL in the Webex app Cisco-Systems.Spark. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-008** When Cisco-Systems.Spark is missing a Webex link tries com.cisco.webexmeetingsapp before the browser.
- **DING-JOIN-009** When the desktop app or chosen browser is missing the link opens in the default browser, and a link is opened exactly once. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-010** Each service's open choice is stored on its own as native, default or a browser bundle ID and applied when its links open. _(SPEC SPEC.md Join behavior)_
- **DING-JOIN-011** Joining closes the menu and opens the event's link, and joining an event without a link does nothing. _(SPEC SPEC.md Dropdown)_

## Notifications and screen reminders

- **DING-NOTIF-001** A notification is planned the chosen number of minutes before each eligible event's start, and 0 turns notifications off. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-002** The notification time choices are Off, 1, 2, 5, 10 or 15 minutes before. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-003** Notifications default to 5 minutes before, with sound and the Join button on. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-004** A notification's title is the event title and its body reads 'Starts in N minutes', 'Starts in 1 minute' or 'Starting now', followed by ' · <service>' when the event has a link. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-005** The Join button appears only when its setting is on and the event has a link, and the sound plays only when the sound setting is on. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-006** A click on the banner or its Join action yields the event's link from the notification payload, and a dismissal yields none. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-007** The notification delegate opens the clicked notification's link with the user's per-service open settings. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-008** Each notification has the id ding.<event id>, a non-repeating calendar trigger at its fire time and the link in its payload, so occurrences of a recurring event stay distinct.
- **DING-NOTIF-009** Every rebuild removes all pending notifications before adding the new set. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-010** Notifications show as banners with sound even while Ding is frontmost, with a Join action category, and Ding asks for alert and sound permission.
- **DING-NOTIF-011** At most 50 notifications are planned at once, soonest first. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-012** The screen reminder style is None, Flash the screen edges or Full screen, None by default, and an unknown stored value reads as None. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-013** A fresh install notifies 5 minutes before each meeting and has the screen reminder style None, as shipped. SPEC.md says so in one place, with no contradicting line. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-014** The screen reminder fires at the start or 1, 2 or 5 minutes before, 1 by default, independently of the notification's time, and the two may coincide. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-015** By default only timed events with a meeting link get a notification or screen reminder, one setting includes events without a link for both, and all-day events never get either. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-016** One switch decides whether events without a meeting link get reminders, for both notifications and the screen reminder. It sits in the Reminders settings above both sections (not inside the Screen reminder section), labelled "Remind me about events without a meeting link". Its stored key and existing value carry over. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-017** Maybe and not-responded meetings get notifications by default and screen reminders only when that separate setting is on, and neither setting affects accepted meetings. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-018** A notification or screen reminder whose time has already passed is not planned, even before the meeting starts, so a meeting created inside the lead time gets none. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-019** A screen reminder that comes due more than 2 minutes late, as after sleep, is dropped, and a timer up to 0.5 s early still shows it. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-020** Screen reminders fire in time order with the style currently chosen, and are re-planned when events, the timing or the style change. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-021** The edge flash puts a borderless, mouse-transparent window at screen-saver level on every display without taking focus, and the windows close by themselves. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-022** The full-screen reminder covers every display, makes exactly one window key, activates Ding, replaces a takeover already showing, and Esc dismisses it. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-023** Only the primary display shows the card with the title, the live line and Join <service>, Snooze 1 min and Dismiss, and the other displays are only dimmed. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-024** Snooze hides the takeover and shows it again after 60 seconds, and Join opens the link and dismisses it. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-025** The live line reads 'Starts in M:SS' before the start, 'Starting now' for the first 5 seconds, 'Started Ns ago' until a minute and then 'Started N min ago'. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-026** Preview shows the chosen style for a sample linked meeting, 'Preview: Team standup', that starts as far ahead as the chosen screen-reminder timing. _(SPEC SPEC.md Notifications and screen reminders)_
- **DING-NOTIF-028** The bolder reminder style is labelled "Full-screen alert" in Settings. SPEC.md no longer carries the rule that the UI must say "screen reminder" for it. _(SPEC SPEC.md Notifications and screen reminders)_

## Hotkeys

- **DING-HOTKEY-001** There are two global hotkeys, Open Ding menu and Join next meeting, recorded on the Shortcuts tab and off until the user records a shortcut. _(SPEC SPEC.md Hotkeys)_
- **DING-HOTKEY-002** Join next opens the next visible event that has a link, or one with a link that started within the last 15 minutes. _(SPEC SPEC.md Hotkeys)_
- **DING-HOTKEY-003** The Open Ding menu hotkey toggles the dropdown. _(SPEC SPEC.md Hotkeys; SPEC.md Platform & Stack)_

## Preferences

- **DING-PREFS-001** Show countdown and show title default to on, countdown only for today to off, and both dropdown toggles to on. _(SPEC SPEC.md Menu bar item; SPEC.md Dropdown)_
- **DING-PREFS-002** Registering defaults never overwrites a value the user has stored.
- **DING-PREFS-003** The clock defaults to the system's 12- or 24-hour setting, and the user's choice alone decides the time format. _(SPEC SPEC.md General settings; SPEC.md Known limitations)_
- **DING-PREFS-004** Launch at login registers or unregisters the main app as a login item and reports a failure without changing the state. _(SPEC SPEC.md General settings; SPEC.md Platform & Stack)_
- **DING-PREFS-005** The Launch at login switch shows the real login item state again after a failed change.
- **DING-PREFS-006** Preferences open in one reusable window titled 'Ding Preferences', titled and closable but not resizable, and opening it activates Ding.
- **DING-PREFS-007** Preferences has six tabs: General, Calendars, Meetings, Notifications, Shortcuts and AI Access. _(SPEC SPEC.md Notifications and screen reminders; SPEC.md AI assistants (MCP))_
- **DING-PREFS-008** Preference changes are debounced and coalesced before the derived state refreshes and the schedule is rebuilt.
- **DING-PREFS-009** Every settings tab and the root settings view lay out without crashing, with and without calendars. _(SPEC SPEC.md Testing)_

## Refresh and lifecycle

- **DING-REFRESH-001** Events are fetched for 14 days starting at today's midnight, whatever the dropdown range. _(SPEC SPEC.md Refresh behavior)_
- **DING-REFRESH-002** Ding reloads on a calendar change, wake, a clock change, a time zone change, a day change, becoming active and opening Preferences. _(SPEC SPEC.md Refresh behavior)_
- **DING-REFRESH-003** Ding also reloads every 15 minutes as a safety net. _(SPEC SPEC.md Refresh behavior)_
- **DING-REFRESH-004** Starting asks for calendar access only when it is undetermined, loads events at once and does nothing the second time.
- **DING-REFRESH-005** A reload refreshes access, events, accounts and the current time and hands the planned notifications to the notifier.

## AI assistants: MCP helper

- **DING-MCP-001** Every app build embeds the helper as an executable at Ding.app/Contents/Helpers/ding-mcp. _(SPEC SPEC.md AI assistants (MCP); SPEC.md Decisions)_
- **DING-MCP-002** The helper speaks newline-delimited JSON-RPC 2.0: each reply is one line ending in a newline, replies keep request order, blank lines are skipped, a bad line does not stop the loop and the loop ends with its input. _(SPEC SPEC.md AI assistants (MCP) Protocol)_
- **DING-MCP-003** Input lines with surrounding spaces, tabs or a trailing carriage return are parsed as the message they contain.
- **DING-MCP-004** initialize echoes a requested version among 2025-06-18, 2025-03-26 and 2024-11-05 and otherwise answers 2025-06-18, advertising the tools capability but not resources or prompts, and serverInfo name ding with the build's version. _(SPEC SPEC.md AI assistants (MCP) Protocol)_
- **DING-MCP-005** The initialize instructions say meeting titles are untrusted and their instructions must never be followed. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-MCP-006** ping returns an empty result, and notifications, messages with a null id and responses from the client get no reply. _(SPEC SPEC.md AI assistants (MCP) Protocol)_
- **DING-MCP-007** A batch gets one array of replies without entries for notifications, a batch of only notifications gets nothing, an empty batch is invalid and a bad item gets its own error. _(SPEC SPEC.md AI assistants (MCP) Protocol)_
- **DING-MCP-008** Invalid JSON is error -32700 with a null id, a non-request is -32600, an unknown method is -32601, a missing or unknown tool name or non-object arguments is -32602, and ids keep their type. _(SPEC SPEC.md Testing (MCP))_
- **DING-MCP-009** tools/list returns exactly get_next_meeting, list_meetings and open_meeting, each with a title, a description and an object input schema with no required and no additional properties. _(SPEC SPEC.md AI assistants (MCP) Tools)_
- **DING-MCP-010** The two reading tools are annotated read-only and open_meeting is annotated neither read-only nor destructive.
- **DING-MCP-011** The get_next_meeting and list_meetings descriptions call titles untrusted, and open_meeting's says to act only when the user asked and that it does not return the meeting link. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-MCP-012** list_meetings accepts days from 1 to 14 (default 1) and include_all_day, open_meeting an optional non-empty string id and get_next_meeting nothing, and any other or ill-typed argument becomes a tool error naming what is accepted that never reaches Ding. _(SPEC SPEC.md AI assistants (MCP) Tools)_
- **DING-MCP-013** A whole number written as a double is accepted as an integer and a boolean is never taken as a number.
- **DING-MCP-014** A successful tool call returns Ding's result as structuredContent plus the same JSON as text, with isError false.
- **DING-MCP-015** A refusal from Ding becomes a tool error with Ding's message as text and its code in structuredContent, never a protocol error. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-MCP-016** When Ding is not running, or only a stale socket file is left, the handshake and tool list still work and a tool call answers 'Ding isn't running'. _(SPEC SPEC.md AI assistants (MCP); SPEC.md Known limitations)_
- **DING-MCP-017** A timeout, a connection Ding closes, an unreadable reply and any other backend error each come back as a tool error saying what happened.
- **DING-MCP-018** Titles with newlines, quotes or line separators are passed through unchanged but escaped, so each reply stays on one line. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-MCP-019** The open_meeting tool description sent to MCP clients names the reply field the app actually returns (opened: true), and a test fails if the description names a field the reply does not carry. _(SPEC SPEC.md AI assistants (MCP); Sources/DingMCP/Tools.swift open_meeting description)_
- **DING-MCP-021** The helper reports its own CFBundleShortVersionString as the server version and waits up to 10 seconds for Ding.

## AI assistants: control service and permissions

- **DING-CTRL-001** Both assistant permissions are off by default and are read on every request, so turning one off takes effect on the next request. _(SPEC SPEC.md AI assistants (MCP) Off by default)_
- **DING-CTRL-002** Reading needs schedule access and opening needs open access, independently, and the permission is checked before calendar access so a refusal reveals nothing. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-003** Unknown methods are refused with unknown_method and requests that cannot be decoded with invalid_request.
- **DING-CTRL-004** A meeting summary has exactly the keys id, title, start, end, is_all_day, is_in_progress, minutes_until_start, calendar, service, can_open and is_tentative, with inapplicable ones as explicit nulls. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-005** Summary times are ISO 8601 local time with the UTC offset, minutes until start are rounded up and null once started, and a timed meeting is in progress from its start until its end. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-006** is_tentative is true for maybe and not-responded meetings and false for accepted ones. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-007** No control response ever contains a meeting link, its host or its passcode. _(SPEC SPEC.md AI assistants (MCP); SPEC.md Testing (MCP))_
- **DING-CTRL-008** get_next_meeting returns the meeting the menu bar shows as next, or a null meeting when there is none. _(SPEC SPEC.md AI assistants (MCP) Tools)_
- **DING-CTRL-009** list_meetings returns unfinished meetings from now to the end of calendar day N (1 is the rest of today), soonest first, all-day ones only on request, at most 50 with a truncated flag. _(SPEC SPEC.md AI assistants (MCP) Tools)_
- **DING-CTRL-010** Assistants may open only Zoom, Google Meet, Teams or Webex meetings: can_open is false for an Other link or no link, such an id is refused with cannot_open and without an id they are skipped. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-011** open_meeting without an id opens the meeting the join hotkey would pick, and with an id opens that unfinished meeting or fails with meeting_not_found, opening nothing on any failure. _(SPEC SPEC.md AI assistants (MCP) Tools)_
- **DING-CTRL-012** open_meeting hands the real meeting to Ding to open and replies only opened true, adding the meeting's summary only when schedule access is also on. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-013** A cannot_open refusal does not include the meeting's title. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-014** A second open_meeting less than 3 seconds after the last one is refused with too_fast. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-CTRL-015** Every failure has a distinct code without spaces and a message written for the reader, and the access-off messages point to Preferences. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-016** Assistants see only the events left after calendar selection and dropdown filters. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-017** The listener answers requests over a real socket in the app's sandbox, performs opens on the main actor and stops listening when stopped. _(SPEC SPEC.md Testing (MCP))_
- **DING-CTRL-018** A build whose bundle has no DingAppGroup key creates no listener and no socket.
- **DING-CTRL-019** Test models never start the control server, while a normal model does. _(SPEC SPEC.md Testing (MCP))_
- **DING-CTRL-020** On quit Ding stops the control server and removes the socket file. _(SPEC SPEC.md Known limitations)_
- **DING-CTRL-021** The desktop-client entry is the mcpServers object without outer braces, with slashes unescaped, that parses once pasted into an empty or an existing config, including for paths with quotes, spaces or backslashes. _(SPEC SPEC.md AI assistants (MCP))_
- **DING-CTRL-022** AI Access shows the two permission switches, Copy Entry, Copy Command and Copy Path rows and the helper's path, or says the build has no helper. _(SPEC SPEC.md AI assistants (MCP); README.md Building)_
- **DING-CTRL-023** The helper's path is offered only when Contents/Helpers/ding-mcp exists and is executable.
- **DING-CTRL-024** The command-line client command is '<client> mcp add ding -- <path>', leaving plain paths bare and single-quoting any path with spaces, quotes or shell metacharacters. _(SPEC SPEC.md AI assistants (MCP))_

## App-helper socket transport

- **DING-IPC-001** Frames are a 4-byte big-endian length and then the payload, at most 1 MiB either way; a clean close between frames reads as the end and a close inside a frame is an error. _(SPEC SPEC.md Architecture (DingIPC))_
- **DING-IPC-002** The socket file is owner-only, replaces a stale file left by a crash and is removed when the server stops. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-IPC-003** Every connection is checked against the code-signing requirement before a byte is read, and the handler never runs for a peer that fails it or when the requirement is malformed. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-IPC-004** The requirement pins an Apple anchor, the team ID as the leaf certificate's OU and the helper identifier. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-IPC-005** The team ID is the part of the app group before its first dot.
- **DING-IPC-006** The socket is c.sock in the app group container. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-IPC-007** A socket path too long for sockaddr_un is rejected when the server starts.
- **DING-IPC-008** The real socket path in the user's group container fits in sockaddr_un.
- **DING-IPC-009** The server drops a peer that stays silent past the idle timeout, closes connections beyond its cap at once and frees a slot when one closes. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-IPC-010** The server's defaults are at most 16 connections and a 30-second idle timeout. _(SPEC SPEC.md AI assistants (MCP) Transport)_
- **DING-IPC-011** Concurrent clients are all answered, many requests in a row each get their answer and async handlers are awaited.
- **DING-IPC-012** The client times out instead of hanging, even with a sub-second timeout, and reports not listening for a missing or unbound socket file. _(SPEC SPEC.md Testing (MCP))_
- **DING-IPC-013** A request announcing an oversized frame makes the server hang up without replying. _(SPEC SPEC.md Testing (MCP))_
- **DING-IPC-014** Control requests, responses and JSON values round-trip through JSON, and params default to empty.
- **DING-IPC-015** The helper does not verify the code signature of the process it connects to. _(SPEC SPEC.md Known limitations; SPEC.md AI assistants (MCP) Transport)_

## Screenshot mode

- **DING-SHOTS-001** Screenshots are 2880 by 1800 PNGs drawn from 1280 by 800-point scenes at 2.25x, showing the views' real pixels. _(SPEC listing/README.md Screenshots)_
- **DING-SHOTS-002** There are six scenes with ordered, unique file names of the form NN_name. _(SPEC listing/README.md Screenshots)_
- **DING-SHOTS-003** The fixtures freeze the clock at Tuesday 9:48 with Team standup on Google Meet 12 minutes away, use only example.com links and include all-day, maybe, not-responded, linkless and overlapping rows. _(SPEC listing/README.md Screenshots)_
- **DING-SHOTS-004** Screenshot mode uses its own preferences suite and leaves the real preferences unchanged. _(SPEC listing/README.md Screenshots)_
- **DING-SHOTS-005** Screenshot mode exists only in debug builds, runs with --screenshots, never reads a calendar, writes the PNGs and status.txt to the sandbox temporary folder and quits. _(SPEC listing/README.md Screenshots)_
- **DING-SHOTS-006** make screenshots builds a debug Ding, launches it in screenshot mode, brings it forward with a second open and replaces listing/screenshots/en-US with the new set. _(SPEC listing/README.md Screenshots)_

## Testing

- **DING-TEST-001** No app-hosted test constructs the real AppModel() or otherwise installs a delegate or categories on the real UNUserNotificationCenter. "testControlServerIsNotStartedByTestModels" checks the same thing through a model built with fakes. _(SPEC SPEC.md Testing)_
- **DING-TEST-002** App tests read and write an isolated UserDefaults suite, never the user's preferences. _(SPEC SPEC.md Testing; DingTests/TestSupport.swift comment)_
- **DING-TEST-004** make coverage prints line coverage for DingCore and for the app. _(SPEC SPEC.md Testing)_

## Build tooling

- **DING-BUILD-001** make test runs swift test, then the app tests hosted in Ding after quitting a running Ding, then the Deno listing tests. _(SPEC README.md Building; SPEC.md Build & tooling; CONTRIBUTING.md)_
- **DING-BUILD-002** make with no target lists the annotated targets by category, and make menu is an fzf picker. _(SPEC SPEC.md Build & tooling; README.md Building)_
- **DING-BUILD-003** make mcp-smoke builds Ding and runs the handshake and tool list through the bundled helper, without Ding running. _(SPEC SPEC.md Build & tooling)_
- **DING-BUILD-004** Ding.xcodeproj is generated from project.yml by XcodeGen and is not checked in. _(SPEC SPEC.md Build & tooling; README.md Project layout)_
- **DING-BUILD-005** design/make_icon.py builds the app icon set, and the menu bar glyph is drawn in code. _(SPEC SPEC.md Build & tooling)_

## Release and distribution

- **DING-REL-001** The release targets exist only on a machine whose make/local.mk declares BOX_NAME := prod-build. _(SPEC DISTRIBUTION.md; SPEC.md Distribution & License)_
- **DING-REL-002** DISTRIBUTION.md lists the release preflight's required tools exactly as make/store.mk defines them (git, xcodebuild, xcodegen, deno). _(SPEC DISTRIBUTION.md What make testflight does step 1)_
- **DING-REL-003** A release refuses a dirty working tree and then runs git pull --ff-only. _(SPEC DISTRIBUTION.md What make testflight does step 2)_
- **DING-REL-004** The build number is the git commit count and the marketing version is 1.0.<commit count>, stamped into the app and the helper at archive time. _(SPEC DISTRIBUTION.md; SPEC.md Distribution & License)_
- **DING-REL-005** The duplicate-build check calls a build number REUSE when valid or processing, BURNED when failed, invalid or expired and ABSENT otherwise, comparing numbers as exact strings. _(SPEC DISTRIBUTION.md One command: make release step 1)_
- **DING-REL-006** An error in the duplicate-build check never blocks a release: the build goes ahead. _(SPEC make/store.mk comment)_
- **DING-REL-007** The version plan is blocked while a different version is waiting for or in App Review, and none when re-running the version already in review. _(SPEC DISTRIBUTION.md One command: make release step 0)_
- **DING-REL-008** The editable version is renamed or created so it carries exactly the stamped version string. _(SPEC DISTRIBUTION.md One command: make release step 3)_
- **DING-REL-009** The listing check enforces Apple's limits (name and subtitle 30, keywords 100, promotional text 170, description 4000, counted as characters), known fields, https URLs and no spaces around keyword commas, and the committed listing passes with the name 'Ding: Meeting Countdown'. _(SPEC listing/README.md Text; DISTRIBUTION.md)_
- **DING-REL-011** The listing diff covers only the fields the file mentions, and only promotional text on an existing locale may change without an editable version. _(SPEC listing/README.md; DISTRIBUTION.md)_
- **DING-REL-012** The App Review contact is taken only from the REVIEW_CONTACT_* environment variables that are set. _(SPEC DISTRIBUTION.md App Review contact)_
- **DING-REL-013** Any difference in the screenshots (missing, extra, reordered, changed or still processing) replaces the whole set, a set must be one Mac size with at most ten images, and the committed set passes. _(SPEC listing/README.md Screenshots; DISTRIBUTION.md)_
- **DING-REL-014** The app settings check validates content rights, category and age-rating values, reports only the settings that differ, and the committed app.json passes. _(SPEC DISTRIBUTION.md One command: make release step 2)_
- **DING-REL-015** The submit logic reads the build number from 1.0.<n>, submits only versions being prepared or rejected, classifies a build as missing, processing, ready or unusable and explains a missing privacy answer. _(SPEC DISTRIBUTION.md One command: make release step 5)_
- **DING-REL-016** make withdraw takes back the version waiting for App Review, and DRY=1 previews it. _(SPEC DISTRIBUTION.md; SPEC.md Build & tooling)_
- **DING-REL-017** make github-release builds a Developer ID-signed, notarized, stapled and Gatekeeper-checked zip and attaches it to GitHub Release v<VERSION>, separately from make release. _(SPEC DISTRIBUTION.md Downloads outside the App Store; SPEC.md Build & tooling)_
- **DING-REL-018** make beta promotes the current build to the public TestFlight beta. _(SPEC DISTRIBUTION.md)_
- **DING-REL-019** SPEC.md's Milestones and Distribution sections describe the release tooling that exists: TestFlight upload, listing, submission, withdrawal, and a notarized zip on GitHub Releases. Ding is live on the Mac App Store (since 2026-11-09). A DMG or Homebrew cask is only a possible later option. _(SPEC SPEC.md Milestones; SPEC.md Distribution & License)_
- **DING-REL-020** README.md says Ding is on the Mac App Store and links its listing (https://apps.apple.com/app/id6829270522?mt=12) as the way to install it and get updates. Building your own copy and the notarized GitHub Releases download stay as alternatives. _(SPEC README.md Install)_

## Project decisions and process

- **DING-PROC-001** There is no CI, and tests run locally with make test. _(SPEC SPEC.md Decisions; SPEC.md Testing; README.md Building)_
- **DING-PROC-002** Outside code contributions are not accepted, and issues are welcome. _(SPEC CONTRIBUTING.md; SPEC.md Non-goals (v1))_
- **DING-PROC-003** The code is GPLv3, while the Ding name and the icon artwork are not covered by it. _(SPEC SPEC.md Distribution & License; README.md License)_
- **DING-PROC-005** SPEC.md's Decisions section says the GitHub repository is public (as it is: needyaz/ding), consistent with README.md sending users to GitHub Releases. _(SPEC SPEC.md Decisions)_
- **DING-PROC-006** The App Store name is 'Ding: Meeting Countdown' and the app is called Ding everywhere else. _(SPEC SPEC.md Decisions)_

## Built, not in the old spec

- **DING-NOTIF-027** **[Unspecced behavior]** The Preview button and the screen reminder timing picker are disabled while the style is None.
- **DING-REFRESH-006** **[Unspecced behavior]** When hosted by XCTest, or started with --screenshots in a debug build, the app never starts the model, so it asks for nothing and schedules nothing.
- **DING-MCP-020** **[Unspecced behavior]** The helper exits with status 1 and a message on stderr when its bundle has no app group, and writes nothing but protocol messages to stdout.
- **DING-BUILD-006** **[Unspecced behavior]** make logs, make reset-calendar-permission, make clean and make xcode stream logs, reset the calendar grant, remove build output and open the project.
<!-- END GENERATED: requirements -->

<!-- BEGIN GENERATED: conflicts -->
None open.
<!-- END GENERATED: conflicts -->

<!-- BEGIN GENERATED: planned -->
- **DING-TEST-003** A manual pass on a real Mac (iCloud, Google and Exchange accounts, sleep and wake, time zone and DST changes, several displays, notifications and hotkeys) has been done. _(SPEC SPEC.md Testing; SPEC.md Milestones; README.md Status)_
- **DING-REL-010** _Retired:_ no trademarked-keyword check is promised, and listing/README.md no longer claims one. _(SPEC listing/README.md Text)_
- **DING-PROC-004** The spec is updated in the same change as any behavior change. _(SPEC SPEC.md Decisions)_
<!-- END GENERATED: planned -->
