#!/usr/bin/env bash
# Grouped, fuzzy, preview-pane make-target picker (fzf).
#
# Reads the same '## [Category] description' lines (each directly above its
# target) that `make help` uses — single source of truth. The preview pane
# dry-runs the target (`make -n`) so you see what it does before running it.
set -euo pipefail
cd "$(dirname "$0")/.."

rows="$(
  awk '
    function pri(c) { return c=="Run"?1 : c=="Build"?2 : c=="Tests"?3 : c=="Release"?4 : c=="Utilities"?5 : 6 }
    /^## \[/ {
      cat=$0; sub(/^## \[/, "", cat); sub(/\].*/, "", cat)
      desc=$0; sub(/^## \[[^]]*\] */, "", desc)
      if (getline t <= 0) next
      name=t; sub(/:.*/, "", name)
      printf "%d\t%s\t%s\t%s\n", pri(cat), name, cat, desc
    }
  ' Makefile $( [ -f make/store.mk ] && grep -q 'BOX_NAME := prod-build' make/local.mk 2>/dev/null && echo make/store.mk ) \
  | sort -k1,1n -s \
  | awk -F'\t' '{ printf "%s\t%-10s %-27s %s\n", $2, $3, $2, $4 }'
)"

[ -n "$rows" ] || { echo "No annotated targets found in Makefile." >&2; exit 1; }

sel="$(
  printf '%s\n' "$rows" | fzf \
    --delimiter=$'\t' --with-nth=2 \
    --height=90% --layout=reverse --border --info=inline \
    --prompt="make ▸ " \
    --header="Enter: run · type to filter · Esc: cancel" \
    --preview 'make -n {1} 2>&1 | head -40' \
    --preview-window='down,40%,wrap,border-top'
)" || exit 0

[ -n "$sel" ] || exit 0
target="${sel%%$'\t'*}"
echo "→ make $target"
exec make "$target"
