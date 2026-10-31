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
## [Tests] Run everything: core unit tests, then the app tests
test: test-core test-app

.PHONY: test-core
## [Tests] DingCore unit tests (link detection, opener routing, grouping, scheduling)
test-core:
	swift test

.PHONY: test-app
## [Tests] App-layer tests hosted in Ding (preferences, EventKit mapping, model, timers, views)
test-app: generate
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
