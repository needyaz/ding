# Generates grouped `make help` output from the Makefile's
# `## [Category] description` lines (each directly above its target).
# Same annotations the `menu` picker reads — single source of truth.
#
# Invoked by the help target with:
#   awk -f makefile_help.awk $(MAKEFILE_LIST)

BEGIN {
  np = split("Run,Build,Tests,Utilities", pref, ",")
}

function add(cat, name, desc) {
  if (!(cat in seen)) { seen[cat] = 1; order[++n] = cat }
  items[cat] = items[cat] sprintf("  %-27s %s\n", name, desc)
}

/^## \[/ {
  cat = $0; sub(/^## \[/, "", cat); sub(/\].*/, "", cat)
  desc = $0; sub(/^## \[[^]]*\] */, "", desc)
  if (getline target <= 0) next
  name = target; sub(/:.*/, "", name)
  add(cat, name, desc)
}

END {
  print "Usage: make <target>   (or: make menu)\n"
  for (i = 1; i <= np; i++) {
    c = pref[i]
    if (c in items) { printf "%s\n%s\n", c, items[c]; done[c] = 1 }
  }
  for (i = 1; i <= n; i++) {
    c = order[i]
    if (!(c in done)) printf "%s\n%s\n", c, items[c]
  }
}
