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

## One command: `make release`

On the build box, `make release` does everything, in this order (as Mylo's `release-ios`):

1. **`testflight`:** preflight, `pull`, then the duplicate-build check (`scripts/asc_build_check.ts`: a build already on App Store
   Connect is reused, a burned number stops the run, anything unknown builds as usual), archive and upload.
2. **`store-setup-apply`:** the app's one-time settings from `listing/app.json`: content rights, category, age rating, price, availability.
3. **`listing-apply`:** the listing text, copyright, release type and App Review information from `listing/metadata.json`. It creates
   the editable version as `VERSION` (default `1.0.<commit count>`, what step 1 just stamped, so keep new commits out in between).
4. **`screenshots-apply`:** the screenshots from `listing/screenshots/`. The locale has to exist first, which step 3 ensures.

5. **`submit`:** attaches the build to the version and sends it to App Review. It is also a target on its own (`DRY=1` previews).

Each step is also a target on its own, and every write target has a read-only twin:

```sh
make store-setup-diff    make listing-dump    make listing-diff    make screenshots-dump    make screenshots-diff
make beta                # promote the build to the public TestFlight beta; re-run until Apple finishes processing
```

- Description, keywords, copyright, release type, review notes and screenshots can only change on an editable version; promotional text
  can change any time. `apply` refuses rather than guess.
- Screenshots are rendered anywhere with `make screenshots` and committed; a different set replaces the whole one (Apple orders by upload).
- `make listing-check` and `make test-listing` run offline on any machine, with no credentials.
- **App Review contact:** set `REVIEW_CONTACT_FIRST_NAME`, `REVIEW_CONTACT_LAST_NAME`, `REVIEW_CONTACT_PHONE` and `REVIEW_CONTACT_EMAIL` in
  the build box's `~/.zshenv`, next to the API key. They are applied with the listing, and never live in the repo, which is public.
- **Only the web UI:** the privacy "nutrition label" (no API), the public TestFlight group named "Public Beta".
- This tooling has been tested offline only, so on the first run use the read-only `-diff` targets before the `-apply` ones.

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
