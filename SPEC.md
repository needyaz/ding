# Ding — Spec

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
- Upcoming events grouped by day (Today, Tomorrow, then weekday and date). Days with no events are skipped.
- Range setting: 1, 3, 7 or 14 days.
- All-day events show first in each day, italic with a tinted row. A multi-day all-day event appears on each day it covers.
- A meeting in progress is highlighted. Finished events are hidden.
- Calendar color dot on each event; "maybe" events are dimmed and marked "· Maybe". Declined and canceled events are never shown.
- Toggles: show events without a meeting link; show events marked "maybe".
- Clicking an event with a link joins it. Rows are accessible (one element, button role, hint) and day headers are marked as headers.
- Calendar access states: a prompt to allow access, a button to open Privacy settings when denied, and an empty state when there are no meetings.
- Footer: Preferences, Send Feedback (opens the GitHub issues page in the default browser), Quit.

### Calendar selection
- Preferences list calendars grouped by account, each with a checkbox.
- The *disabled* calendars are what's stored, so calendars that appear later default to on and ones that disappear are harmless.
- Calendar selection applies everywhere: dropdown, menu bar, notifications and alerts.

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

### Notifications and alerts
- A standard macOS notification N minutes before an event (Off, 1, 2, 5, 10 or 15; default 5), with an optional sound and an optional Join button. Clicking the banner or Join opens the link. Body reads "Starts in 5 minutes · Zoom".
- Alert mode setting, three options:
  1. **Off** — notification only.
  2. **Edge flash** — brief screen-edge pulse at start time plus the notification.
  3. **Full screen** — takeover at start time with the title, a live "Starting now / Started 2 min ago" line, and Join, Snooze (1 minute) and Dismiss. Esc dismisses. The primary display shows the card; other displays are dimmed.
- Alerts only fire for timed events with a meeting link by default (setting to include events without one). All-day events never alert.
- Hidden calendars and events hidden by the dropdown toggles don't alert either.
- At most 50 notifications are scheduled at once (macOS allows 64). Alerts that would fire more than 2 minutes late, such as after a Mac wakes from sleep, are skipped.

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
- Reloaded on calendar changes, wake from sleep, clock changes, time zone changes, midnight, and every 15 minutes as a safety net.
- The countdown refreshes exactly when its label changes, and at least once a minute.

## Privacy

- Calendar data never leaves the device.
- No analytics, no network calls, no network entitlement.

## Architecture

Two layers. `DingCore` (a Swift package) is pure logic with no UI or system dependencies; the app target wires it to macOS.
Anything that touches the system sits behind a small protocol or closure so tests can fake it.

**`DingCore`**
- `MeetingLinkDetector` + `LinkPatterns`: event text to `MeetingLink?`. One pattern table; heavily unit-tested.
- `MeetingOpener` + `OpenTarget`: resolves a link and the user's per-service choice to an app or browser (via `WorkspaceOpening`).
- `DayGrouping`, `Countdown`, `NextEvent`, `MenuBarText`, `EventDisplay`: what the menu bar and dropdown show.
- `AlertPlanner`, `AlertQueue`, `NotificationPlanner`, `TickPlanner`, `JoinSelection`: what fires and when.

**`Ding` (app)**
- `AppModel`: observable state and the glue between the calendar, timers and alerts.
- `CalendarStore`: EventKit behind `CalendarSource`/`EventStoring`; maps `EKEvent` to `DingEvent`.
- `Scheduler`: countdown and alert timers; system notifications go through `NotificationScheduling`.
- `AlertController`: edge-flash and full-screen windows.
- `Preferences` (`Pref`): UserDefaults keys, defaults and typed reads; views bind them with `@AppStorage`.
- `MenuContentView`, `SettingsView`, `MenuBarLabel`, `MenuBarGlyph`: the UI.

## Build & tooling

- `project.yml` (XcodeGen) generates `Ding.xcodeproj`, which isn't checked in.
- A `Makefile` with the same conventions as the author's other projects: `make` lists targets, `make menu` is an fzf picker, `make run` builds and launches, `make test`, `make coverage`.
- `design/make_icon.py` builds the app icon set from the source art in `design/`. The menu bar glyph is drawn in code (`MenuBarGlyph`).

## Testing

- **Core (`swift test`):** link detection against a fixture corpus of real-world invite shapes plus edge cases (wrappers, lookalike hosts, unicode, punctuation), opener routing for every service and mode, countdown and scheduling math, day grouping including DST, alert and notification planning.
- **App (`make test-app`):** tests hosted inside the app covering preferences, EventKit mapping, the model's lifecycle (wake, clock, preference changes), real timers, notification content, alert windows, and every view and settings tab rendering.
- Nothing in tests touches the real system. The notification center, browsers and workspace, EventKit, login items and windows all sit behind protocols or closures, and tests use fakes. (An early version of the tests scheduled real notifications; this is the rule that came out of it.)
- `make coverage` prints line coverage: about 99.6% for core and 93% for the app. The uncovered remainder is code whose only job is to call the real OS (opening apps, the live notification center, registering a login item) and a few view button closures.
- **Still manual:** a pass of the test matrix on a real Mac (iCloud, Google and Exchange accounts; sleep/wake; time zone and DST changes; multiple displays for alerts; notifications and hotkeys).
- No CI: tests run locally with `make test`.

## Distribution & License

- Free on the Mac App Store; notarized DMG and Homebrew cask possible later.
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
5. Alerts (edge flash, full screen).
6. Polish, icon, App Store submission.

## Known limitations

- **Structured conference data:** EventKit exposes no public conference field, so Google Meet detection relies on the link appearing in the URL, location or notes. Needs checking against real Google events.
- **English only:** all strings are hard-coded and times use fixed locales so the 12/24-hour choice decides the format. Translating the UI is not planned for v1.
- **Icon:** a single flat render, not built with Icon Composer (a deliberate choice). macOS 26's Dark and Tinted icon styles haven't been checked.

## Decisions

- The name is **Ding**. Trademark and App Store availability checks are not being pursued.
- The icon stays a plain asset-catalog icon; Icon Composer is not needed.
- The spec is updated in the same change as any behavior change.
- No CI. Tests run locally (`make test`).
- The GitHub repo (`needyaz/ding`) is **private** for now and will be flipped public later. Until then the Send Feedback link and the
  issues link in `CONTRIBUTING.md` aren't reachable by anyone else.

## Open questions

None currently.
