# TestFlight release targets. Build box only: the root Makefile includes this
# file only when make/local.mk declares `BOX_NAME := prod-build`, so on every
# other machine these targets don't exist as make rules. The real boundary is
# still that the App Store Connect API key must only ever be on the build box;
# this file makes the intended restriction structural.
#
# Ding is a pure Xcode project with automatic signing, so `xcodebuild archive`
# plus `-exportArchive` with the API key (-authenticationKey*) manages the
# distribution certificate and profiles (cloud signing) and does the TestFlight
# upload itself (`destination: upload` in make/ExportOptions-upload.plist).
#
# Required environment (build box ~/.zshenv, see DISTRIBUTION.md):
#   ASC_KEY_ID        App Store Connect API key ID
#   ASC_ISSUER_ID     App Store Connect issuer ID
#   ASC_KEY_FILEPATH  absolute path to the AuthKey_<KEY_ID>.p8 file
#
# Like Mylo, the build number is `git rev-list --count HEAD` and the marketing
# version is 1.0.<that number>; both are passed to xcodebuild as
# CURRENT_PROJECT_VERSION / MARKETING_VERSION so the app and its bundled MCP
# helper always agree.

RELEASE_TOOLS := git xcodebuild xcodegen deno

ASC_AUTH := -authenticationKeyPath $(ASC_KEY_FILEPATH) \
            -authenticationKeyID $(ASC_KEY_ID) \
            -authenticationKeyIssuerID $(ASC_ISSUER_ID)

ARCHIVE_PATH := $(BUILD_DIR)/archives/$(APP_NAME).xcarchive

.PHONY: _preflight
_preflight:
	@./scripts/release_preflight.sh $(RELEASE_TOOLS)
	@test -n "$(ASC_KEY_ID)" && test -n "$(ASC_ISSUER_ID)" && test -n "$(ASC_KEY_FILEPATH)" || \
	  (echo "✗ ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_FILEPATH must be set: see DISTRIBUTION.md" && exit 1)
	@test -f "$(ASC_KEY_FILEPATH)" || (echo "✗ ASC key file not found: $(ASC_KEY_FILEPATH)" && exit 1)

# Release what's pushed: refuse a dirty tree (the build number is the commit
# count, so uncommitted work would ship under a number that matches no commit),
# then fast-forward to origin.
.PHONY: pull
pull:
	@git diff --quiet && git diff --cached --quiet || \
	  (echo "✗ working tree dirty: commit or stash before releasing" && exit 1)
	git pull --ff-only

# ---------------------------------------------------------------------------
# App Store listing: text (scripts/listing_metadata.ts, desired state in
# listing/metadata.json) and screenshots (scripts/listing_screenshots.ts,
# desired state = listing/screenshots/<locale>/, rendered by `make screenshots`).
# Same targets as Mylo. dump/diff only read; apply writes and then reads back.
#
# Description, keywords and review notes need an EDITABLE appStoreVersion; if
# none exists, listing-apply creates one as VERSION, which defaults to the
# 1.0.<git commit count>, the exact string `make testflight` stamps into the
# binary, so run it right after testflight with no new commits in between (same
# caveat as Mylo). Screenshots need that version and the locale to exist, so they
# run right after listing-apply. promotionalText patches the live version anytime.
# ---------------------------------------------------------------------------

VERSION ?= 1.0.$(shell git rev-list --count HEAD)
LISTING_DENO := deno run --allow-net --allow-env --allow-read

.PHONY: store-setup-diff store-setup-apply
## [Release|box:prod-build] Diff the app's one-time store settings (category, age rating, price, ...) vs listing/app.json (read-only)
store-setup-diff: _preflight-listing
	$(LISTING_DENO) scripts/store_setup.ts diff
## [Release|box:prod-build] Apply category, age rating, content rights, price and availability, then read back and verify
store-setup-apply: _preflight-listing
	$(LISTING_DENO) scripts/store_setup.ts apply

.PHONY: listing-dump listing-diff listing-apply
## [Release|box:prod-build] Print live store listing metadata (read-only)
listing-dump: _preflight-listing
	$(LISTING_DENO) scripts/listing_metadata.ts dump
## [Release|box:prod-build] Diff live store listing vs listing/metadata.json (read-only)
listing-diff: _preflight-listing
	$(LISTING_DENO) scripts/listing_metadata.ts diff
## [Release|box:prod-build] Apply differing listing metadata, then read back and verify (creates editable version VERSION, default 1.0.<commit count>)
listing-apply: _preflight-listing
	$(LISTING_DENO) scripts/listing_metadata.ts apply --create-version $(VERSION)

.PHONY: screenshots-dump screenshots-diff screenshots-apply
## [Release|box:prod-build] Print the App Store screenshot sets per locale (read-only)
screenshots-dump: _preflight-listing
	$(LISTING_DENO) scripts/listing_screenshots.ts dump
## [Release|box:prod-build] Diff live App Store screenshots vs listing/screenshots (read-only)
screenshots-diff: _preflight-listing
	$(LISTING_DENO) scripts/listing_screenshots.ts diff
## [Release|box:prod-build] Upload differing per-locale App Store screenshots, then read back and verify
screenshots-apply: _preflight-listing
	$(LISTING_DENO) scripts/listing_screenshots.ts apply

.PHONY: _preflight-listing
_preflight-listing: listing-check
	@./scripts/release_preflight.sh git deno
	@test -n "$(ASC_KEY_ID)" && test -n "$(ASC_ISSUER_ID)" && test -f "$(ASC_KEY_FILEPATH)" || \
	  (echo "✗ ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_FILEPATH must be set: see DISTRIBUTION.md" && exit 1)

.PHONY: testflight
## [Release] Archive and upload Ding to TestFlight (build number = commit count)
testflight:
	@$(MAKE) --no-print-directory _preflight
	@$(MAKE) --no-print-directory pull
	@$(MAKE) --no-print-directory _testflight

# Has App Store Connect already got this build number? (scripts/asc_build_check.ts, as in Mylo and Mimir.)
#   REUSE  -> already up (valid or processing): skip the build and upload
#   BURNED -> the number belongs to a failed/invalid/expired build: stop, a new commit is needed
#   ABSENT, or any error -> build as usual; the check never blocks a release
.PHONY: _testflight
_testflight:
	@n=$$(git rev-list --count HEAD); \
	 verdict=$$(deno run --allow-net --allow-env --allow-read scripts/asc_build_check.ts $$n 2>/dev/null || true); \
	 case "$$verdict" in \
	   REUSE)  echo "✓ build $$n is already on App Store Connect (valid or processing): skipping build and upload";; \
	   BURNED) echo "✗ build number $$n is used by a FAILED/INVALID/expired build on App Store Connect."; \
	           echo "  Re-uploading cannot succeed. Make a new commit (the build number is the commit count) and re-run."; \
	           exit 1;; \
	   *)      $(MAKE) --no-print-directory _build-upload;; \
	 esac

.PHONY: beta
## [Release] Promote the current build to the public TestFlight beta (re-run until Apple finishes processing)
beta: _preflight-listing
	deno run --allow-net --allow-env --allow-read scripts/asc_promote_beta.ts $$(git rev-list --count HEAD)

# One command, as Mylo's release-ios: build and upload, then everything the store needs, then submit for review, in
# this order. Each step is also its own target.
.PHONY: release
## [Release] Full release: TestFlight upload, app settings, listing, screenshots, submit for App Review
release:
	@$(MAKE) --no-print-directory _preflight
	@$(MAKE) --no-print-directory pull
	@$(MAKE) --no-print-directory _testflight
	@$(MAKE) --no-print-directory store-setup-apply
	@$(MAKE) --no-print-directory listing-apply
	@$(MAKE) --no-print-directory screenshots-apply
	@$(MAKE) --no-print-directory submit
	@echo "✓ release $(VERSION) built, uploaded, listed and submitted for App Review"

.PHONY: submit
## [Release] Attach the build to version VERSION and submit it to App Review (also the last step of `release`; DRY=1 to preview)
submit: _preflight-listing
	deno run --allow-net --allow-env --allow-read scripts/submit.ts --version $(VERSION) $(if $(DRY),--dry-run)

# Archive, then export with destination=upload: the export step IS the upload.
# A re-run without a new commit re-uploads a build number Apple already has, and
# Apple answers a duplicate with opaque errors, so make a new commit first.
.PHONY: _build-upload
_build-upload: generate
	@n=$$(git rev-list --count HEAD); echo "→ archiving $(APP_NAME) build $$n"; \
	 xcodebuild archive -quiet \
	  -project $(PROJECT) -scheme $(APP_NAME) -configuration Release \
	  -destination 'generic/platform=macOS' \
	  -archivePath $(ARCHIVE_PATH) \
	  CURRENT_PROJECT_VERSION=$$n MARKETING_VERSION=1.0.$$n \
	  -allowProvisioningUpdates $(ASC_AUTH) && \
	 xcodebuild -exportArchive \
	  -archivePath $(ARCHIVE_PATH) \
	  -exportOptionsPlist make/ExportOptions-upload.plist \
	  -allowProvisioningUpdates $(ASC_AUTH) && \
	 echo "✓ build $$n uploaded to TestFlight (processing happens on Apple's side)"
