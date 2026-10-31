# Ding — build / run / test entry points. Run `make` for the list, `make menu` to pick.
#
# Annotate every public target with `## [Category] description` on the line
# directly above it; `help` and `menu` both read those lines.

APP_NAME  := Ding
BUNDLE_ID := blue.luci.Ding
PROJECT   := $(APP_NAME).xcodeproj
BUILD_DIR := build
APP_PATH  := $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME).app

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(APP_NAME) -configuration Debug -derivedDataPath $(BUILD_DIR) -allowProvisioningUpdates

.DEFAULT_GOAL := help

# Per-machine identity, gitignored (see make/local.*.mk.example and DISTRIBUTION.md). Defaults to a dev box.
-include make/local.mk
BOX_NAME ?= dev

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

.PHONY: run
## [Run] Build, then (re)launch Ding — look for the bell in the menu bar
run: build stop
	open $(APP_PATH)
	@echo "Ding is a menu bar app: no Dock icon. Look for the bell at the top right."

.PHONY: stop
## [Run] Quit a running Ding
stop:
	-@pkill -x $(APP_NAME) && echo "Stopped $(APP_NAME)" || true

.PHONY: mcp-smoke
## [Run] Smoke-test the bundled MCP helper: handshake and tool list (Ding need not be running)
mcp-smoke: build
	@printf '%s\n' \
	  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
	  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
	  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
	  | $(APP_PATH)/Contents/Helpers/ding-mcp \
	  | python3 -c 'import sys, json; r = [json.loads(l) for l in sys.stdin]; i = r[0]["result"]; print("server:", i["serverInfo"]["name"], i["serverInfo"]["version"], "· protocol", i["protocolVersion"]); print("tools: ", ", ".join(t["name"] for t in r[1]["result"]["tools"]))'

.PHONY: logs
## [Run] Stream Ding's logs (Ctrl-C to stop)
logs:
	log stream --style compact --predicate 'process == "$(APP_NAME)"'

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

.PHONY: build
## [Build] Build the debug app into ./build
build: generate
	$(XCODEBUILD) -quiet build

.PHONY: screenshots
## [Build] Render the App Store screenshots from the real views with fixture data (quits a running Ding)
screenshots: build stop
	@mkdir -p listing/screenshots/en-US
	@rm -f "$(HOME)/Library/Containers/$(BUNDLE_ID)/Data/tmp/shots/"*.png
	@sleep 2  # LaunchServices needs a moment after the quit
	@# Launch in screenshot mode, then `open` the running app again: for the regular app it becomes during this run, that
	@# brings it forward. Controls only draw in their live colors (not dimmed) in an active app.
	@open -W $(APP_PATH) --args --screenshots & \
	  sleep 3; open $(APP_PATH); wait
	@rm -f listing/screenshots/en-US/*.png   # so a renamed or removed scene can't leave a stale file behind
	@cp "$(HOME)/Library/Containers/$(BUNDLE_ID)/Data/tmp/shots/"*.png listing/screenshots/en-US/
	@ls -1 listing/screenshots/en-US

# The Xcode project is generated from project.yml and gitignored. build/test depend on this
# (it's fast) so newly added source files are always picked up.
.PHONY: generate
## [Build] Regenerate Ding.xcodeproj from project.yml
generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not installed — run: brew install xcodegen"; exit 1; }
	@xcodegen generate --quiet

.PHONY: xcode
## [Build] Open the project in Xcode
xcode: generate
	open $(PROJECT)

.PHONY: clean
## [Build] Remove build output and the generated Xcode project
clean: stop
	rm -rf $(BUILD_DIR) $(PROJECT) .build

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

.PHONY: test
## [Tests] Run everything: core unit tests, the app tests, then the store-listing tool tests
test: test-core test-app test-listing

.PHONY: test-listing
## [Tests] Store-listing tools (Deno): diff/plan logic, Apple's limits, and a check of listing/ (offline, no credentials)
test-listing: listing-check
	@command -v deno >/dev/null 2>&1 || { echo "deno not installed — run: brew install deno"; exit 1; }
	deno test --allow-read scripts/

.PHONY: listing-check
## [Build] Validate listing/ (metadata.json, app.json, screenshots) against Apple's limits (offline)
listing-check:
	@command -v deno >/dev/null 2>&1 || { echo "deno not installed — run: brew install deno"; exit 1; }
	@deno run --allow-read --allow-env scripts/listing_metadata.ts check
	@deno run --allow-read scripts/listing_screenshots.ts check
	@deno run --allow-read scripts/store_setup.ts check

.PHONY: test-core
## [Tests] DingCore unit tests (link detection, opener routing, grouping, scheduling)
test-core:
	swift test

.PHONY: test-app
## [Tests] App-layer tests hosted in Ding (quits a running Ding first: it allows one instance)
test-app: generate stop
	@rm -rf $(BUILD_DIR)/test.xcresult
	$(XCODEBUILD) -quiet test -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath $(BUILD_DIR)/test.xcresult

.PHONY: coverage
## [Tests] Run all tests and print line coverage for core and app
coverage: stop
	@swift test --enable-code-coverage >/dev/null 2>&1 || { echo "core tests failed — run: make test-core"; exit 1; }
	@echo "── DingCore (swift test) ──"
	@xcrun llvm-cov report .build/arm64-apple-macosx/debug/DingCorePackageTests.xctest/Contents/MacOS/DingCorePackageTests \
	  -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata -ignore-filename-regex='Tests|\.build' \
	  | awk '$$1 ~ /\.swift$$|^TOTAL$$/ {printf "  %-28s %8s\n", $$1, $$10}'
	@$(MAKE) --no-print-directory test-app >/dev/null 2>&1 || { echo "app tests failed — run: make test-app"; exit 1; }
	@echo "── Ding app (xcodebuild test) ──"
	@xcrun xccov view --report --files-for-target Ding.app $(BUILD_DIR)/test.xcresult 2>/dev/null \
	  | awk '$$2 ~ /\.swift$$/ {n=split($$2, p, "/"); printf "  %-28s %8s %s\n", p[n], $$4, $$5}'
	@xcrun xccov view --report --only-targets $(BUILD_DIR)/test.xcresult 2>/dev/null \
	  | awk '$$2 == "Ding.app" || $$1 == "Ding.app" {printf "  %-28s %8s %s\n", "TOTAL", $$(NF-1), $$NF}'

# ---------------------------------------------------------------------------
# Release (build box only)
# ---------------------------------------------------------------------------

# The TestFlight targets touch the live App Store Connect API key, so they only exist as make rules on the box that
# declares BOX_NAME := prod-build. On any other machine `make testflight` fails with "No rule to make target".
ifeq ($(BOX_NAME),prod-build)
-include make/store.mk
endif

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

.PHONY: reset-calendar-permission
## [Utilities] Forget Ding's calendar grant so the permission prompt shows again
reset-calendar-permission: stop
	tccutil reset Calendar $(BUNDLE_ID)

.PHONY: help
## [Utilities] List targets, grouped by category
help:
	@awk -f scripts/makefile_help.awk $(MAKEFILE_LIST)

.PHONY: menu
## [Utilities] Interactive grouped target picker (fzf + preview)
menu:
	@command -v fzf >/dev/null 2>&1 || { echo "fzf not installed — run: brew install fzf"; exit 1; }
	@bash scripts/menu.sh
