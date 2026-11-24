import { assert, assertFalse } from "jsr:@std/assert@1";

const text = await Deno.readTextFile(new URL("../Makefile", import.meta.url).pathname);

type Rule = { deps: string[]; recipe: string[] };

/** Targets with their prerequisites and recipe lines (enough Makefile syntax for this project's rules). */
function parse(src: string): Map<string, Rule> {
  const rules = new Map<string, Rule>();
  let current: Rule[] = [];
  for (const line of src.split("\n")) {
    if (line.startsWith("\t")) {
      for (const r of current) r.recipe.push(line.trim());
      continue;
    }
    const m = line.match(/^([A-Za-z0-9_.-]+(?:\s+[A-Za-z0-9_.-]+)*)\s*:(?!=)\s*([^#]*)/);
    if (!m || /^[A-Z_]+\s*[:?+]?=/.test(line)) {
      current = [];
      continue;
    }
    const deps = m[2].trim().split(/\s+/).filter(Boolean);
    current = m[1].split(/\s+/).map((name) => {
      const rule = rules.get(name) ?? { deps: [], recipe: [] };
      rule.deps.push(...deps);
      rules.set(name, rule);
      return rule;
    });
  }
  return rules;
}

/** Every target `test` runs: itself and all its prerequisites, transitively. */
function reachable(rules: Map<string, Rule>, from: string): string[] {
  const seen = new Set<string>();
  const queue = [from];
  while (queue.length) {
    const t = queue.pop()!;
    if (seen.has(t)) continue;
    seen.add(t);
    queue.push(...(rules.get(t)?.deps ?? []));
  }
  return [...seen];
}

const rules = parse(text);

Deno.test("make test never depends on the target that quits the installed app", () => {
  const targets = reachable(rules, "test");
  assert(targets.includes("test-app"), "test should reach test-app");
  assertFalse(targets.includes("stop"));
});

Deno.test("no target reachable from test quits, resets or deletes the real app", () => {
  const destructive = /\b(pkill|killall|tccutil|rm)\b/;
  const realApp = /\$\((APP_NAME|BUNDLE_ID)\)|blue\.luci\.Ding(?!\.dev)|\bDing\b(?!\s*Dev)/;
  for (const target of reachable(rules, "test")) {
    for (const line of rules.get(target)?.recipe ?? []) {
      if (!destructive.test(line)) continue;
      assertFalse(realApp.test(line.replace(/\$\(BUILD_DIR\)[^\s]*/g, "")), `${target} touches the real app: ${line}`);
    }
  }
});

Deno.test("test builds use the dev identity and release builds keep the real one", () => {
  assert(/DEV_BUNDLE_ID\s*:=\s*blue\.luci\.Ding\.dev\s*$/m.test(text));
  assert(/DEV_APP_NAME\s*:=\s*Ding Dev\s*$/m.test(text));
  assert(/BUNDLE_ID\s*\?=\s*blue\.luci\.Ding\s*$/m.test(text));
  assert(/^test-app:.*\n(?:.*\n)*?.*XCODEBUILD_DEV/m.test(text));
});
