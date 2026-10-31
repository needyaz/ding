# Distribution setup

Ding goes to TestFlight from the **build box only**, with one command:

```sh
make testflight
```

On any other machine that target does not exist (`No rule to make target`): `make/store.mk` is only included when
`make/local.mk` declares `BOX_NAME := prod-build`. The App Store Connect API key must only ever live on the build box.

## What `make testflight` does

1. **Preflight:** `git`, `xcodebuild` and `xcodegen` are on PATH, and `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_FILEPATH` are set.
2. **`pull`:** refuses a dirty working tree, then `git pull --ff-only`. The build number is the commit count, so uncommitted
   work would ship under a number that matches no commit.
3. **Archive:** `xcodebuild archive` in Release, with `CURRENT_PROJECT_VERSION` set to `git rev-list --count HEAD`. The app and its
   bundled MCP helper both read it, so they always agree.
4. **Export with `destination: upload`** (`make/ExportOptions-upload.plist`): the export step is the TestFlight upload. Both steps
   authenticate with the API key, so automatic signing creates and refreshes the distribution certificate and profiles (cloud signing).

The marketing version is `1.0.<build number>`, stamped at archive time like Mylo's, and it is also the App Store version string. (`MARKETING_VERSION` in `project.yml` only labels dev builds.)

## Every release

1. `make test` on a dev box, then commit and **push**. The build box releases what is pushed.
2. On the build box: `make testflight`.
3. A re-run without a new commit re-uploads a build number Apple already has, and Apple answers a duplicate with opaque errors.
   Make a new commit first.
4. Apple processes the build for a few minutes before it appears in TestFlight.

## The App Store listing

Text and screenshots are declared in `listing/` and pushed with the same API key, on the build box only. The targets match Mylo's:

```sh
make listing-dump        make screenshots-dump     # print what the store has (read-only)
make listing-diff        make screenshots-diff     # what differs from listing/ (read-only)
make listing-apply       make screenshots-apply    # write, then read back and verify
```

- `scripts/listing_metadata.ts` handles the name, subtitle, description, keywords, promotional text, URLs and App Review notes.
  `scripts/listing_screenshots.ts` handles the screenshot set (2880 × 1800, in file-name order; any difference replaces the whole set,
  because Apple orders by upload). Fields `metadata.json` doesn't mention are never touched.
- `listing-apply` creates the editable version as `VERSION` (default `1.0.<commit count>`, what `make testflight` just stamped, so run it with no new commits in between) if none exists.
  Description, keywords, review notes and screenshots can only change on an editable version; promotional text can change any time.
- Order: `make testflight`, then `make listing-apply`, then `make screenshots-apply` (the locale must exist first).
- `make listing-check` and `make test-listing` run offline on any machine, with no credentials.
- Category, age rating, privacy label, pricing, the privacy policy URL, copyright and the review contact are set once in the web UI,
  as for the other apps.
- This tooling has been tested offline only, so run the read-only `diff` targets first on the build box.

## One-time setup

### App Store Connect
- An app record for bundle ID `blue.luci.Ding`, platform macOS, must exist. It can only be created in the web UI; the API cannot.
- App group `46XLY7Y9P8.blue.luci.Ding` (the app and its helper share it). Cloud signing should register it; if upload validation
  complains about it, register it under Certificates, Identifiers & Profiles.
- Export compliance is answered in the build (`ITSAppUsesNonExemptEncryption` is false). Privacy: no data collected; the privacy
  manifest (`Ding/PrivacyInfo.xcprivacy`) declares UserDefaults use.

### The build box
```sh
# ~/.zshenv
export ASC_KEY_ID="XXXXXXXXXX"
export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ASC_KEY_FILEPATH="$HOME/.secrets/AuthKey_XXXXXXXXXX.p8"

cp make/local.prod.mk.example make/local.mk     # gitignored, per machine
brew install xcodegen                           # and Xcode, with: sudo xcode-select -s /Applications/Xcode.app
```

## Checked before the first upload (on a dev box, no credentials)
A Release archive builds and its signature verifies. The app and the helper both carry the same version and commit-count build number;
both are sandboxed with the app group; there are no development-only entitlements; the privacy manifest, the 1024px icon and the
required Info.plist keys are present.

## Not verifiable without uploading: what to look at if the first upload fails
- **The bundled helper** (`Contents/Helpers/ding-mcp`) carries the `application-groups` entitlement. On the Mac App Store that
  normally has to be covered by a provisioning profile, and a bare command-line tool can't embed its own. If validation rejects
  the helper, the error names it.
- **The app group ID format** (`46XLY7Y9P8.blue.luci.Ding`) is the team-prefixed form macOS allows; App Store validation may want it registered.
- **App Review** may ask about an app that ships a program for other apps to run.
