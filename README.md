# Ding

A tiny, free, open-source macOS menu bar app that counts down to your next meeting and joins it in one click.

Ding reads the calendars already set up on your Mac (iCloud, Google, Exchange) through EventKit. No accounts, no servers, no tracking.

## Features

- Menu bar countdown with the next meeting's title
- Dropdown of upcoming events grouped by day, with calendar colors
- One-click join for Zoom, Google Meet, Microsoft Teams and Webex, plus any other link found in the event
- Choose which app or browser opens each service
- Notification before meetings, with optional edge flash or full-screen alert
- Global hotkeys

## Requirements

macOS 14 Sonoma or later.

## Building

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make menu       # pick a target (or `make` to list them)
make run        # build and launch; look for the bell in the menu bar
make test       # core tests, then app tests
make coverage   # run everything and print line coverage
```

## Project layout

| Path | What's there |
|---|---|
| `Sources/DingCore` | UI-free logic: link detection, opener routing, grouping, countdowns, alert planning. Tested with `swift test`. |
| `Ding/` | The macOS app: EventKit, timers, notifications, alert windows, SwiftUI views. |
| `DingTests/` | App tests, hosted inside the app. |
| `design/` | Icon source art and `make_icon.py`, which builds the asset catalog's icon set. |
| `project.yml` | XcodeGen spec; `Ding.xcodeproj` is generated and not checked in. |

Anything that would touch the real system (notification center, browsers, windows, EventKit, login items) sits behind a small protocol or closure, so tests use fakes and never reach your real data. See [SPEC.md](SPEC.md) for the architecture.

## Status

Feature-complete for v1 and pending a manual test pass. See [SPEC.md](SPEC.md) for the plan.

## Contributing

Issues are welcome; outside code contributions aren't accepted. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

The code is GPLv3. See `LICENSE`.

The Ding name and the app icon artwork (`design/` and `Ding/Assets.xcassets/AppIcon.appiconset`) are not covered by the GPL; all rights
are reserved. If you fork the project, please use your own name and icon.
