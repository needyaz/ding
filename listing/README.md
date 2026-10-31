# App Store listing assets

## Screenshots

`listing/screenshots/en-US/` holds the Mac App Store screenshots: 2880 × 1800 PNGs (16:10, one of the sizes the Mac App Store
accepts), in file-name order. They are **generated, not drawn**:

```sh
make screenshots
```

That builds a debug Ding and runs it with `--screenshots`. The screenshot mode (`Ding/Screenshots/`, compiled in debug builds only,
never in a release) renders the **real views** against made-up fixture data and a frozen clock (Tuesday 9:48 AM, Team standup
in 12 minutes). It never reads a calendar and never touches your real preferences. Each scene is laid out at 1280 × 800 points
and drawn at 2.25x, with a caption on a cream-to-blue background that matches luci.blue.

| File | Shows |
|---|---|
| `01_menu-bar` | The menu bar countdown and the dropdown with the Next meeting card |
| `02_meetings` | Per-service open settings |
| `03_full-screen` | The full-screen reminder |
| `04_notifications` | Notification and screen-reminder settings |
| `05_calendars` | Calendars grouped by account |
| `06_ai-access` | The opt-in AI Access tab |

To change a screenshot, edit the scene in `ScreenshotScenes.swift` (or the fixtures in `ScreenshotFixtures.swift`) and run
`make screenshots`; to add one, add a scene. Check the PNGs by eye before committing.

Notes on how it works, because they were hard won:
- **The app has to be the active app.** Controls (toggles, the selected tab, default buttons) only draw in their live blue in an
  active app, otherwise they are gray. macOS won't activate an app started from a background session, so while rendering Ding
  makes itself a regular app and `make screenshots` brings it forward with a second `open`. It writes `status.txt` next to the
  images (`active=true` is what you want).
- **Windows are drawn, not captured.** The real window frame can't be captured off-screen, so the scenes draw a faithful title bar
  around the real content.
- Output is written to the sandbox container (`~/Library/Containers/blue.luci.Ding/Data/tmp/shots/`) and copied here by the make target.
