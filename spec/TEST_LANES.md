# Test lanes for Ding

These come from reading `Makefile`, `make/store.mk`, `Package.swift`, `project.yml` and the test sources. Nothing that needs a Mac,
the network or a secret was run during this recovery. The timings are estimates from the test code (explicit waits and timeouts), not
measurements.

| Lane | Command | Plain Linux container? |
|---|---|---|
| Core package tests | `make test-core` (`swift test`) | No |
| App-hosted tests | `make test-app` | No |
| Listing tool tests | `make test-listing` | Yes, with Deno and JSR access |
| MCP smoke | `make mcp-smoke` | No |
| Coverage | `make coverage` | No |
| Manual matrix | by hand | No |
| Release dry runs | `make *-diff`, `make submit DRY=1`, `make withdraw DRY=1` | No (build box only) |

## 1. Core package tests (DingCore, DingIPC, DingMCP)

- **Command:** `make test-core`, which is `swift test` at the repository root. The suites are `Tests/DingCoreTests`, `Tests/DingIPCTests`
  and `Tests/DingMCPTests`.
- **Needs:** macOS 14+ with a Swift 5.9+ toolchain (Xcode). The package has no external dependencies, so no network is needed. No
  secrets, no device, no database.
- **Time:** about 1 to 2 minutes, including the build. The socket and end-to-end suites deliberately wait on timeouts of 0.05 to 2 s.
- **Linux container: no.** `Sources/DingIPC` imports `Darwin` and `Security` (`SecCodeCopyGuestWithAttributes`, `LOCAL_PEERTOKEN`,
  `SO_NOSIGPIPE`), and `Tests/DingIPCTests/SocketTests.swift` uses `SecCodeCopySelf`. All three test targets are in one package, so
  `swift test` can't build there. `DingCore` and `DingCoreTests` use only Foundation and XCTest and might build on Linux in a separate
  package, but that has not been tried, and `DateFormatter`/`ISO8601DateFormatter`/time-zone behavior may differ in swift-corelibs-foundation.

## 2. App-hosted tests (DingTests)

- **Command:** `make test-app`, which runs `xcodegen generate`, quits a running Ding (`pkill -x Ding`, because the app allows one instance),
  then `xcodebuild -project Ding.xcodeproj -scheme Ding -configuration Debug -derivedDataPath build -allowProvisioningUpdates DING_BUNDLE_ID=… test -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath build/test.xcresult`.
- **Needs:**
  - macOS with Xcode 26 and XcodeGen (`brew install xcodegen`).
  - Network on the first run, for SwiftPM to fetch KeyboardShortcuts 3.1.0 and MenuBarExtraAccess 1.3.1 from GitHub.
  - A logged-in GUI session: tests build `NSWindow`s and `NSHostingView`s and read `NSScreen.screens`.
  - Code signing: the project signs with team `46XLY7Y9P8` and an app-group entitlement, so either an Xcode account in that team or
    `make test-app TEAM=<your team> BUNDLE_ID=<your id>`.
  - Safari installed (`InstalledBrowsersTests`).
  - The results also depend on the machine's calendar grant (`CalendarStoreTests` branches on it).
  - No secrets in the repo sense.
- **Time:** about 3 to 6 minutes. The build takes several minutes the first time. `AppModelLifecycleTests` and `SchedulerTests` contain about
  40 s of real-timer waits between them.
- **Linux container: no** (AppKit, SwiftUI, EventKit, UserNotifications, ServiceManagement).
- **Caution:** this lane runs inside the real Ding bundle, and one test builds a real `AppModel()` that touches the real notification
  center (DRIFT_REPORT.md, DING-TEST-001).

## 3. Listing tool tests (Deno)

- **Command:** `make test-listing`. It first runs `make listing-check`:
  - `deno run --allow-read --allow-env scripts/listing_metadata.ts check`
  - `deno run --allow-read scripts/listing_screenshots.ts check`
  - `deno run --allow-read scripts/store_setup.ts check`

  then `deno test --allow-read scripts/`.
- **Needs:** Deno. Network on the first run to fetch `jsr:@std/assert@1` from JSR, or a pre-filled `DENO_DIR`. No App Store Connect
  credentials, no Mac. The tests read `listing/metadata.json`, `listing/app.json` and the committed PNGs.
- **Time:** about 10 to 30 seconds.
- **Linux container: yes**, given Deno and either JSR access or a cached `DENO_DIR`. This is the only lane that runs today
  without macOS.

## 4. MCP smoke test

- **Command:** `make mcp-smoke`. It builds the debug app, pipes `initialize`, `notifications/initialized` and `tools/list` into
  `build/Build/Products/Debug/Ding.app/Contents/Helpers/ding-mcp`, and summarizes with `python3`.
- **Needs:** everything lane 2 needs to build (macOS, Xcode, XcodeGen, signing, network for packages on the first run), plus `python3`.
  Ding need not be running.
- **Time:** about 1 minute after a cached build.
- **Linux container: no.**

## 5. Coverage

- **Command:** `make coverage`. It runs `swift test --enable-code-coverage`, reports through `xcrun llvm-cov` on the hard-coded
  `.build/arm64-apple-macosx/...` path, then runs `make test-app` and `xcrun xccov`.
- **Needs:** everything lanes 1 and 2 need, on an Apple silicon Mac (the path is hard-coded for arm64).
- **Time:** about 5 to 8 minutes.
- **Linux container: no.**

## 6. Manual matrix (not automated)

- A real Mac with iCloud, Google and Exchange accounts, sleep and wake, time zone and DST changes, several displays, notifications and
  hotkeys (SPEC.md Testing, DING-TEST-003). Still pending according to SPEC.md and README.md.

## 7. Release dry runs (build box only; do not run in the factory)

- **Commands:** `make store-setup-diff`, `make listing-diff`, `make screenshots-diff`, `make submit DRY=1`, `make withdraw DRY=1`.
- **Needs:**
  - `make/local.mk` with `BOX_NAME := prod-build`.
  - `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_FILEPATH` (App Store Connect API key, a secret).
  - Network to api.appstoreconnect.apple.com.
  - Deno and git.
- **Time:** seconds to a minute each.
- **Linux container: no.** These are secrets-bearing, network-bound operations. Their pure logic is already covered by lane 3.

## Not test lanes

`make screenshots` (a GUI render on macOS that writes `listing/screenshots/en-US`), `make testflight`, `make release`, `make github-release`
and `make beta` change external state (App Store Connect, GitHub Releases) and must never run in a gate.
