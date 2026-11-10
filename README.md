# Ding

A tiny, free, open-source macOS menu bar app that counts down to your next meeting and joins it in one click.

Ding reads the calendars already set up on your Mac (iCloud, Google, Exchange) through EventKit. No accounts, no servers, no tracking.

## Features

- Menu bar countdown with the next meeting's title
- Dropdown of upcoming events grouped by day, with calendar colors
- One-click join for Zoom, Google Meet, Microsoft Teams and Webex, plus any other link found in the event
- Choose which app or browser opens each service
- Notification before meetings, with an optional edge flash or full-screen reminder
- Global hotkeys
- Optional AI assistant integration (MCP): let Claude, or any app that supports MCP, check your next meeting or open it. Off until you turn it on

## Requirements

macOS 14 Sonoma or later.

Ding is on the [Mac App Store](https://apps.apple.com/app/id6829270522?mt=12), free, which is the way to install it and keep it up to date. You can also build it yourself (below). Notarized builds for download are attached to the [GitHub Releases](../../releases) and don't update themselves.

## Building

Requires Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and, for `make test`, [Deno](https://deno.com) (`brew install deno`), which runs the App Store listing tool tests.

```sh
make menu       # pick a target (or `make` to list them)
make run        # build and launch; look for the bell in the menu bar
make test       # core tests, app tests, then the listing tool tests
make coverage   # run everything and print line coverage
```

### Building your own copy

The project is signed with the author's team and bundle ID, which only the author can build under. To build a copy, use your own, from an Apple
developer account that is signed in to Xcode (Settings > Accounts), so automatic signing can create the app ID and the app group Ding and its
helper share:

```sh
make run TEAM=ABCDE12345 BUNDLE_ID=com.example.MyDing
```

`TEAM` is your 10-character team ID and `BUNDLE_ID` is any ID you own. Everything else derives from them: the helper is `<BUNDLE_ID>.mcp`, the app
group is `<TEAM>.<BUNDLE_ID>`, and Ding only talks to a helper with that identifier signed by your team. Give the same `TEAM` and `BUNDLE_ID` to
every `make` target you use (or set them in `make/local.mk`, which is gitignored). The first launch asks for Calendar access. The Mac App Store
build and release tooling in `DISTRIBUTION.md` are the author's and not needed to run Ding.

To use the optional AI assistant integration, open Preferences > AI Access: it shows the helper's path and the text to paste into Claude
Desktop or Claude Code, and Ding must be running for an assistant to reach it.

Releases to TestFlight are built on a separate build box: see [DISTRIBUTION.md](DISTRIBUTION.md). There is no CI; run `make test` before you push. The app tests run inside Ding, which allows one instance, so `make test` quits a running Ding first (`make run` starts it again).

## Project layout

| Path | What's there |
|---|---|
| `Sources/DingCore` | UI-free logic: link detection, opener routing, grouping, countdowns, alert planning, what an assistant may see. Tested with `swift test`. |
| `Sources/DingIPC`, `Sources/DingMCP` | The socket between the app and its helper, and the MCP server. Also tested with `swift test`. |
| `DingMCPHelper/` | `ding-mcp`, the small program that exposes the MCP server over stdio. Embedded in the app. |
| `Ding/` | The macOS app: EventKit, timers, notifications, alert windows, SwiftUI views. |
| `DingTests/` | App tests, hosted inside the app. |
| `design/` | Icon source art and `make_icon.py`, which builds the asset catalog's icon set. |
| `project.yml` | XcodeGen spec; `Ding.xcodeproj` is generated and not checked in. |

Anything that would touch the real system (notification center, browsers, windows, EventKit, login items) sits behind a small protocol or closure, so tests use fakes and never reach your real data. See [SPEC.md](SPEC.md) for the architecture.

## Status

Ding 1.0 is live on the Mac App Store; a manual test pass is still pending. See [SPEC.md](SPEC.md) for the plan.

## Contributing

Issues are welcome; outside code contributions aren't accepted. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

The code is GPLv3. See `LICENSE`.

The Ding name and the app icon artwork (`design/` and `Ding/Assets.xcassets/AppIcon.appiconset`) are not covered by the GPL; all rights
are reserved. If you fork the project, please use your own name and icon.
