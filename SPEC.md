# Ding — Spec

> The living baseline spec is in [`spec/`](spec/BASELINE.md) (requirements in `spec/requirements.tsv`); where this document disagrees, see `spec/DRIFT_REPORT.md`.

A free, open-source macOS menu bar app that shows your next meeting and lets you join it in one click. A spiritual replacement for the abandoned "Meeter".

## Goals

- Always-visible countdown to the next meeting in the menu bar.
- One click (or one hotkey) to join, in the app or browser you choose per service.
- Tiny, fast, native, private: no accounts, no servers, no telemetry.

## Non-goals (v1)

- Windows/Linux support.
- Direct Google/Microsoft API integration (EventKit only).
- Speed Dial / saved links.
- Multiple UI styles (ship one design).
- Paid tier or licensing code.
- Localization: the UI is English only.
- Outside code contributions (see Distribution & License).

## Platform & Stack

- Swift + SwiftUI, macOS 14 Sonoma or later. Built and checked on macOS 26.
- `MenuBarExtra` for the menu bar item, with `MenuBarExtraAccess` so a hotkey can open it programmatically.
- EventKit for calendar data. Reads any account configured in System Settings (iCloud, Google, Exchange, subscribed).
- App Store sandbox compatible: calendar entitlement, no network access needed.
- Global hotkeys via `KeyboardShortcuts` (sandbox-safe).
- Launch at login via `SMAppService`.
- Bundle ID `blue.luci.Ding`.

## Features (v1)

### Menu bar item
- A bell glyph (a template image, so it follows light/dark and highlighted menu bars) plus optional text.
- Text is "Standup in 12m", "Standup now", "in 12m" or just the title, depending on options: show countdown, show title, show countdown only for today (otherwise icon only).
- "Next" is the first timed event that hasn't ended. A meeting that just started stays "next", shown as "now", for 5 minutes. All-day events are never "next".
- Countdown reads "now", "12m", "1h 5m" or "2d 3h"; minutes round up so it never shows "0m" before the start.
- Long titles truncate with an ellipsis (24 characters); newlines collapse to spaces.

### Dropdown
- A **Next meeting** card at the top, mirroring the menu bar: "Next · in 12m" (or "Happening now"), the title, the time, and a **Join** button when
  the meeting has a link. Joining the meeting in the menu bar shouldn't need a hotkey or a hunt through the list.
- Upcoming events grouped by day (Today, Tomorrow, then weekday and date). Days with no events are skipped.
- Range setting: 1, 3, 7 or 14 days.
- All-day events show first in each day, italic with a tinted row. A multi-day all-day event appears on each day it covers.
- A meeting in progress is highlighted. Finished events are hidden.
- Calendar color dot on each event. Declined and canceled events are never shown.
- **Response state.** Each meeting is *accepted*, *maybe* (tentative) or *not responded* (an invitation not answered yet); EventKit `.tentative` is maybe,
  `.pending` is not responded, and everything else (accepted, delegated, no attendee record, as on the user's own events) is accepted. Maybe and not
  responded are both **unconfirmed**: one behaviour everywhere (dimmed to 60%, hidden by the same toggle, same reminder rules), with different labels,
  "· Maybe" and "· Not responded". The dot is a filled circle for an accepted meeting and a ring for an unconfirmed one.
- **Overlap.** Timed meetings whose times intersect, directly or through a chain, share one bracket along the left edge of the run, rounded at the
  first and last row. Back-to-back meetings don't overlap, all-day events never join a run, and a zero-length meeting counts only inside what it sits in.
  Inside a run accepted meetings are listed before unconfirmed ones; outside a run the order stays chronological. A row's accessibility hint says
  "Overlaps another meeting". Overlap is shown, not warned about: there is no conflict notification.
- Toggles: show events without a meeting link; show meetings marked "maybe" or not yet answered (the stored key is still `showMaybe`, so existing choices carry over).
- "Next meeting" is the first timed event that hasn't ended, as before, with one tie-break: of meetings that start together an accepted one comes before
  an unconfirmed one, so a maybe invitation doesn't take the countdown or the Join button from a meeting the user accepted. The "join next" hotkey shares it.
  An earlier unconfirmed meeting is still next.
- Clicking an event with a link joins it. Rows are accessible (one element, button role, hint) and day headers are marked as headers.
- A short list is a plain stack; a long one scrolls inside a fixed 460pt. A scroll view reports no height of its own in the self-sizing menu bar
  window, so without an explicit height the list collapses to nothing (this shipped once: a 340x36 popover with only the footer). The size is
  right from the first layout, with no measure-and-resize step.
- Calendar access states: a prompt to allow access, a button to open Privacy settings when denied, and an empty state when there are no meetings.
- Footer: Preferences, Send Feedback (opens the GitHub issues page in the default browser), Quit.

### Calendar selection
- Preferences list calendars grouped by account, each with a checkbox.
- The *disabled* calendars are what's stored, so calendars that appear later default to on and ones that disappear are harmless.
- Calendar selection applies everywhere: dropdown, menu bar, notifications and screen reminders.

### Link detection
- Services: Zoom, Google Meet, Microsoft Teams, Webex.
- Search order: structured conference data, location, URL field, notes. EventKit has no public conference-data API, so the structured slot exists in `LinkSource` but is currently empty; Google's conference link normally surfaces in the URL field (see Known limitations).
- Outlook SafeLinks and Google redirect wrappers are unwrapped before matching; HTML-escaped ampersands are decoded; trailing punctuation is trimmed.
- Lookalike hosts (`zoom.us.evil.com`) and non-meeting pages on known hosts (pricing, downloads) don't match.
- Fallback: if no known service matches and exactly one distinct web URL is present, offer it as "Other link".
- Link patterns live in one table (`LinkPatterns`) so adding a service is a new enum case plus one row.

### Join behavior
- Per-service setting for how to open: desktop app, default browser, or a specific installed browser. Zoom defaults to its desktop app, others to the default browser. Services with no desktop app (Google Meet, Other) can't be set to it.
- Desktop app routing: Zoom uses a `zoommtg://` deep link (personal-room and webinar links open in the app instead), Teams uses `msteams://`, Webex opens the web URL in the Webex app. If the app isn't installed, or a chosen browser is missing, the link falls back to the default browser.
- "Other links" use the default browser unless overridden.

### Notifications and screen reminders

Two separate things, each with its own timing. (The code calls the second an "alert"; the UI says "screen reminder", because macOS already uses
"Alerts" for a notification style.) Both live on Preferences' **Notifications** tab.

- **Notification:** a standard macOS notification N minutes before an event (Off, 1, 2, 5, 10 or 15; default 5), with an optional sound and an
  optional Join button. Clicking the banner or Join opens the link. Body reads "Starts in 5 minutes · Zoom".
- **Screen reminder:** a bolder reminder on top of the notification, shown at its own time: at the start time, or 1, 2 or 5 minutes before
  (default 1). Style setting, three options:
  1. **None** — just the notification (the default).
  2. **Flash the screen edges** — a brief screen-edge pulse on every display.
  3. **Full screen** — a takeover with the title, a live line, and Join, Snooze (1 minute) and Dismiss. Esc dismisses. The primary display
     shows the card; other displays are dimmed. The live line counts down before the start ("Starts in 0:59"), then reads "Starting now" and
     "Started 2 min ago".
- The two times are independent and may coincide. The default is a 5-minute notification followed by a full-screen reminder 1 minute before.
- A **Preview** button shows the chosen reminder for a sample meeting that starts when a real one would.
- Both only fire for timed events with a meeting link by default (setting to include events without one). All-day events never fire.
- Two settings cover unconfirmed meetings (maybe or not yet answered), one in each section, independent of each other and never affecting accepted
  meetings: **"Also for meetings marked 'maybe' or not yet answered"** for the notification (default **on**, as before) and for the screen reminder
  (default **off**: the edge flash and full-screen takeover are loud, and a meeting the user hasn't accepted shouldn't take over the screen).
- Hidden calendars and events hidden by the dropdown toggles don't fire either.
- Something whose time has already passed is not shown late, even if the meeting hasn't started. The schedule is rebuilt on every reload, so
  replanning it would show the same reminder again each time. For the same reason, a meeting created inside the lead window gets none.
- At most 50 notifications are scheduled at once (macOS allows 64). Reminders that would fire more than 2 minutes late, such as after a Mac wakes
  from sleep, are skipped.

### Hotkeys
- Open the Ding menu.
- Join next meeting: the next event with a link, or one with a link that started within the last 15 minutes.
- Both user-configurable, off by default.

### General settings
- Launch at login.
- 12/24-hour clock (defaults to the system setting).
- Upcoming days range.

### Refresh behavior
- Events are fetched for the next 14 days regardless of the dropdown range, so the menu bar can show a meeting beyond it.
- Reloaded on calendar changes, wake from sleep, clock changes, time zone changes, midnight, when Ding becomes active, when Preferences opens,
  and every 15 minutes as a safety net.
- On every calendar change the EventKit store is reset before reloading. EventKit caches its reads, so without this a newly added account or
  calendar doesn't appear in Preferences.
- The countdown refreshes exactly when its label changes, and at least once a minute.

### AI assistants (MCP)
- Ding bundles an MCP server, `Ding.app/Contents/Helpers/ding-mcp`: a stdio program that Claude Desktop, Claude Code or any other MCP client starts, and
  which relays to the running app. Every install has it; nothing else to install.
- Tools: **get_next_meeting**, **list_meetings** (`days` 1–14, `include_all_day`; at most 50, with a `truncated` flag) and **open_meeting** (an optional
  `id`; with none it opens the current or next meeting that has a link, the same one the "join next" hotkey picks).
- **Off by default.** Preferences → AI Access has two switches, *Let AI assistants see my schedule* and *Let AI assistants open my meetings*, checked on every request, so
  turning one off takes effect immediately. *Copy Entry* (Claude Desktop) and *Copy Command* (Claude Code) and *Copy Path* (any other MCP app) give the client the helper's real path. The Claude Desktop entry is the `"mcpServers"` piece without outer braces, because that config file normally holds other settings and a complete document pasted into it breaks it.
- What a client can see per meeting: id, title, start and end (local time with its UTC offset), all-day, in progress, minutes until start, calendar name,
  the service name, whether it can be opened, tentative (`is_tentative` is true for maybe and for not yet answered; the summary's shape is unchanged). Never notes, attendees, locations or meeting links: a link can carry a passcode. Inapplicable
  fields are explicit nulls so the shape never changes. The user's calendar selection and dropdown filters apply.
- `open_meeting` opens the meeting inside Ding, using the user's per-service open settings, and returns no link. It only opens meetings on Zoom, Google Meet,
  Microsoft Teams or Webex (`can_open` is false for an "Other link" and with no id those are skipped): an invitation's arbitrary URL can't be opened by an
  assistant that a malicious invitation has talked into it. A refusal never includes the meeting's title. The two switches are independent:
  opening works without schedule access, and then the reply is only `{"opened": true}`. The meeting's details are included only if schedule access is also on.
- Meeting titles are written by whoever sent the invitation, so the server's instructions and tool descriptions tell the model to treat them as untrusted.
- Argument mistakes and refusals come back as tool errors written for the model ("The user hasn't allowed AI assistants to see their schedule. They can turn it
  on in Ding → Preferences → AI Access."), not as protocol errors.
- Ding must be running. If it isn't, the handshake and tool list still work and a tool call says "Ding isn't running".
- Protocol: MCP over newline-delimited JSON-RPC 2.0; versions 2025-06-18, 2025-03-26 and 2024-11-05; tools only. Batches, notifications and pings are handled.
- Transport: a Unix socket (owner-only) in the app group container, so the sandboxed helper and sandboxed app need no network entitlement. Ding checks the
  code signature of every program that connects and hangs up on any that isn't the helper (identifier `blue.luci.Ding.mcp`) signed by the same team. The helper can't do the same in reverse (the sandbox
  forbids inspecting another process), but it only ever sends a method name and small arguments. The server holds at most 16 connections, drops a peer that goes 30 seconds without a request, and refuses a second `open_meeting` within 3 seconds.
- One Ding instance at a time (`LSMultipleInstancesProhibited`), so there is one owner of the socket.

## Privacy

- Calendar data never leaves the device, with one user-controlled exception: if the user turns on assistant access, the details listed under AI assistants (MCP)
  go to the MCP client they connected, and from there to wherever that client sends them.
- No analytics, no network calls, no network entitlement (verified on the Release build: sandbox, calendars and app group only).
- Third-party packages (KeyboardShortcuts, MenuBarExtraAccess) are pinned to exact, reviewed versions in `project.yml`; neither touches the network.
- The calendar permission prompt says the calendar stays on the Mac unless the user lets an AI assistant see it.

## Architecture

Two layers. `DingCore` (a Swift package) is pure logic with no UI or system dependencies; the app target wires it to macOS.
Anything that touches the system sits behind a small protocol or closure so tests can fake it.

**`DingCore`**
- `MeetingLinkDetector` + `LinkPatterns`: event text to `MeetingLink?`. One pattern table; heavily unit-tested.
- `MeetingOpener` + `OpenTarget`: resolves a link and the user's per-service choice to an app or browser (via `WorkspaceOpening`).
- `DayGrouping`, `Countdown`, `NextEvent`, `MenuBarText`, `EventDisplay`: what the menu bar and dropdown show.
- `AlertPlanner`, `AlertQueue`, `NotificationPlanner`, `TickPlanner`, `JoinSelection`: what fires and when (notification and alert timing are separate settings).
- `ControlAPI`, `MeetingSummary`, `ControlFailure`: what an assistant may see and do, as pure functions; a summary has no field for notes, attendees, locations or links.
- `MCPConfig`: the text to paste into a client.

**`DingIPC`** (a second library in the same package)
- `ControlSocketServer` / `ControlSocketClient`: length-prefixed frames over a Unix socket; the server verifies each peer's code signature (`PeerVerifier`).
- `ControlRequest`, `ControlResponse`, `ControlMethod`, `JSONValue`: the wire protocol between the helper and the app.

**`DingMCP`** (a third library)
- `MCPServer`: the MCP/JSON-RPC protocol, tool definitions and argument checking. `SocketBackend` reaches the app; the stdio loop is `MCPServer.serve`.

**`ding-mcp`** (`DingMCPHelper/`): a tiny sandboxed executable that wires stdin and stdout to `MCPServer`. Embedded in the app bundle.

**`Ding` (app)**
- `AppModel`: observable state and the glue between the calendar, timers and alerts.
- `CalendarStore`: EventKit behind `CalendarSource`/`EventStoring`; maps `EKEvent` to `DingEvent`.
- `Scheduler`: countdown and alert timers; system notifications go through `NotificationScheduling`.
- `AlertController`: edge-flash and full-screen windows.
- `ControlService`: answers the helper's requests and enforces the user's assistant permissions. `ControlListener`: the socket in front of it.
- `Preferences` (`Pref`): UserDefaults keys, defaults and typed reads; views bind them with `@AppStorage`.
- `MenuContentView`, `SettingsView`, `AssistantsTab`, `MenuBarLabel`, `MenuBarGlyph`: the UI.

## Build & tooling

- `project.yml` (XcodeGen) generates `Ding.xcodeproj`, which isn't checked in.
- A `Makefile` with the same conventions as the author's other projects: `make` lists targets, `make menu` is an fzf picker, `make run` builds and launches, `make test`, `make coverage`, `make mcp-smoke` (handshake and tool list through the bundled helper). The app tests run inside Ding, which allows only one instance, so `make test-app` quits a running Ding first.
- The App Store listing is declared in `listing/`: `metadata.json` (text, URLs, copyright, release type, App Review notes), `app.json` (category,
  age rating, content rights, price, availability) and `screenshots/`. On the build box `make release` uploads to TestFlight, applies all of it through the
  App Store Connect API with read-back (`store-setup-`, `listing-` and `screenshots-` `dump`/`diff`/`apply` targets, as in Mylo) and submits the version to
  App Review (`make submit`, also usable alone); `make beta` promotes a build to the public TestFlight beta. The App Review contact comes from the build box's
  environment, never the repo. The release version is `1.0.<commit count>`. `make release` stops before building if a version is with App Review (Apple allows no second
  version then); `make withdraw` takes the waiting version back. `make test-listing` tests the Deno tools offline.
- The app identity is one build setting, `DING_BUNDLE_ID` (with `DEVELOPMENT_TEAM`): the bundle IDs, the app group and the helper identifier Ding accepts all derive
  from it, and `make TEAM=… BUNDLE_ID=…` overrides them so anyone can build a copy under their own identity.
- `make github-release` (build box only) builds a Developer ID-signed, notarized Ding and attaches it to the GitHub Release `v<VERSION>`; it is separate from `make release`,
  the binary is never committed, and that build has no updater.
- `make screenshots` renders the App Store screenshots from the real views with fixture data (debug builds only; see `listing/README.md`).
- `design/make_icon.py` builds the app icon set from the source art in `design/`. The menu bar glyph is drawn in code (`MenuBarGlyph`).

## Testing

- **Core (`swift test`):** link detection against a fixture corpus of real-world invite shapes plus edge cases (wrappers, lookalike hosts, unicode, punctuation), opener routing for every service and mode, countdown and scheduling math, day grouping including DST, alert and notification planning.
- **App (`make test-app`):** tests hosted inside the app covering preferences, EventKit mapping, the model's lifecycle (wake, clock, preference changes), real timers, notification content, alert windows, and every view and settings tab rendering.
- The dropdown's sizing is tested as logic (a short list is a plain stack, a long one is capped and scrolls, the next-meeting card adds height).
  The original collapse only reproduced in the real menu bar window, so layout changes there are checked by hand against the running app.
- **MCP:** the protocol is tested against the spec's message rules (handshake and version negotiation, batches, notifications, error codes, id types, malformed
  input); the transport against real Unix sockets (framing, concurrency, a refused peer, an oversized or half-sent frame, a server that never answers); and
  the two together end to end with a stand-in for the app. The app side tests the permissions, the privacy guarantee (no response ever contains a link or
  passcode) and the real listener in the app's sandbox. Test models never start the control server, because the socket belongs to the running app.
- The screenshot mode's fixtures and output shape are pinned by tests (size, file naming, a frozen clock, nothing real in the data).
- Nothing in tests touches the real system. The notification center, browsers and workspace, EventKit, login items and windows all sit behind protocols or closures, and tests use fakes. (An early version of the tests scheduled real notifications; this is the rule that came out of it.)
- `make coverage` prints line coverage: about 99.6% for core and 93% for the app. The uncovered remainder is code whose only job is to call the real OS (opening apps, the live notification center, registering a login item) and a few view button closures.
- **Still manual:** a pass of the test matrix on a real Mac (iCloud, Google and Exchange accounts; sleep/wake; time zone and DST changes; multiple displays for alerts; notifications and hotkeys).
- No CI: tests run locally with `make test`.

## Distribution & License

- Free on the Mac App Store; notarized DMG and Homebrew cask possible later.
- TestFlight builds are archived and uploaded from the build box only, with `make testflight`, gated by `make/local.mk` like the author's other apps
  (see `DISTRIBUTION.md`). The build number is the git commit count; the marketing version is `1.0.<commit count>`, stamped at archive time (as in Mylo); `MARKETING_VERSION` in `project.yml` only labels dev builds. The app carries a
  privacy manifest declaring its UserDefaults use.
- License: GPLv3. The repo is public, but outside code contributions aren't accepted (see `CONTRIBUTING.md`). The author holds the copyright
  on all of it, which is what allows the App Store build despite the GPL; no CLA is needed. Issues are welcome.
- Dependencies are MIT-licensed (KeyboardShortcuts, MenuBarExtraAccess), which is compatible with the GPLv3.
- The app icon was generated with Midjourney on a paid plan and is not covered by the GPL: the name and artwork are all rights reserved.
- Before flipping the repo public: enable Issues, restrict who can open pull requests, and skim the history for anything that shouldn't be public.

## Milestones

Status: 1–5 are implemented and the icon from 6 is done. Remaining: the manual test pass, signing and notarization,
App Store submission, and flipping the GitHub repo public.

1. Skeleton: menu bar item, EventKit permission, next-event countdown.
2. Dropdown with grouping, color dots, calendar picker.
3. Link detection + join + per-service open settings.
4. Notifications, hotkeys, launch at login.
5. Screen reminders (edge flash, full screen).
6. Polish, icon, App Store submission.

## Known limitations

- **Structured conference data:** EventKit exposes no public conference field, so Google Meet detection relies on the link appearing in the URL, location or notes. Needs checking against real Google events.
- **English only:** all strings are hard-coded and times use fixed locales so the 12/24-hour choice decides the format. Translating the UI is not planned for v1.
- **Icon:** a single flat render, not built with Icon Composer (a deliberate choice). macOS 26's Dark and Tinted icon styles haven't been checked.

- **Assistant access needs a running Ding,** and a crash can leave a stale socket file behind; the helper treats a stale file as "Ding isn't running".
- **The helper can't verify it is talking to Ding** (the sandbox forbids inspecting another process's signature); only Ding verifies its callers.

## Decisions

- The name is **Ding**. Trademark and App Store availability checks are not being pursued.
- The icon stays a plain asset-catalog icon; Icon Composer is not needed.
- The App Store name is **Ding: Meeting Countdown**. The app is called **Ding** everywhere else: on the Mac, in the menu bar and on the website.
- The spec is updated in the same change as any behavior change.
- No CI. Tests run locally (`make test`).
- The MCP server ships **inside the app bundle**, so people get it automatically. No separate install, and no command-line tool unless one is
  explicitly wanted.
- The GitHub repo (`needyaz/ding`) is **private** for now and will be flipped public later. Until then the Send Feedback link and the
  issues link in `CONTRIBUTING.md` aren't reachable by anyone else.
