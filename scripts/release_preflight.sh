#!/usr/bin/env bash
#
# Fail a release in the first second, not after the build: check that every tool
# the release will shell out to is on PATH, and report ALL missing ones at once.
# Called first by every release entry point in make/store.mk:
#
#   scripts/release_preflight.sh <tool>...
set -uo pipefail

hint() {
  case "$1" in
    xcodegen)   echo "brew install xcodegen" ;;
    xcodebuild) echo "install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" ;;
    *)          echo "install $1 and put it on PATH" ;;
  esac
}

missing=()
for tool in "$@"; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "✗ release preflight: ${#missing[@]} required tool(s) missing; nothing was built or changed:"
  for tool in "${missing[@]}"; do echo "    $tool: $(hint "$tool")"; done
  exit 1
fi
echo "→ release preflight: all ${#} tools present ($*)"
