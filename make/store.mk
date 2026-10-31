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
# The build number is `git rev-list --count HEAD`, passed to xcodebuild as
# CURRENT_PROJECT_VERSION so the app and its bundled MCP helper always agree.

RELEASE_TOOLS := git xcodebuild xcodegen

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

.PHONY: testflight
## [Release] Archive and upload Ding to TestFlight (build number = commit count)
testflight:
	@$(MAKE) --no-print-directory _preflight
	@$(MAKE) --no-print-directory pull
	@$(MAKE) --no-print-directory _build-upload

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
	  CURRENT_PROJECT_VERSION=$$n \
	  -allowProvisioningUpdates $(ASC_AUTH) && \
	 xcodebuild -exportArchive \
	  -archivePath $(ARCHIVE_PATH) \
	  -exportOptionsPlist make/ExportOptions-upload.plist \
	  -allowProvisioningUpdates $(ASC_AUTH) && \
	 echo "✓ build $$n uploaded to TestFlight (processing happens on Apple's side)"
