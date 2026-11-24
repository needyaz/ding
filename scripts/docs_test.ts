import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";

const read = (path: string) => Deno.readTextFile(new URL(`../${path}`, import.meta.url).pathname);

/** The body of a markdown section: from its heading up to the next heading of the same or a higher level. */
function section(md: string, heading: string): string {
  const lines = md.split("\n");
  const start = lines.findIndex((l) => /^#{1,6}\s/.test(l) && l.replace(/^#+\s*/, "").trim() === heading);
  assert(start >= 0, `heading "${heading}" not found`);
  const level = lines[start].match(/^#+/)![0].length;
  const out: string[] = [];
  for (const l of lines.slice(start + 1)) {
    const m = l.match(/^(#+)\s/);
    if (m && m[1].length <= level) break;
    out.push(l);
  }
  return out.join("\n");
}

/** Collapses runs of whitespace (including line wraps) to single spaces. */
const collapse = (s: string) => s.replace(/\s+/g, " ").trim();

Deno.test("the release preflight names git, xcodebuild, xcodegen and deno", async () => {
  const line = collapse(await read("DISTRIBUTION.md")).match(/\*\*Preflight:\*\*[^]*?(?= \d+\. |$)/)?.[0] ?? "";
  assert(line, "no Preflight step found");
  for (const tool of ["git", "xcodebuild", "xcodegen", "deno"]) assert(line.includes(`\`${tool}\``), `preflight must name ${tool}`);
});

Deno.test("the README links the Mac App Store listing and no longer says it is coming", async () => {
  const readme = collapse(await read("README.md"));
  assert(readme.includes("https://apps.apple.com/app/id6829270522?mt=12"));
  assertFalse(/coming to the Mac App Store/i.test(readme));
});

Deno.test("the listing text section makes no trademark claim", async () => {
  const text = section(await read("listing/README.md"), "Text");
  assertFalse(/trademark|™|®/i.test(text));
});

Deno.test("the listing text section says keywords carry no spaces after commas", async () => {
  const text = collapse(section(await read("listing/README.md"), "Text"));
  assert(text.includes("Keywords carry no spaces after commas"));
  assertEquals(text.includes("100 for keywords"), true);
});

Deno.test("targets reachable from `test` never quit, reset or delete the installed Ding", async () => {
  const out = await new Deno.Command("make", { args: ["-n", "--no-print-directory", "test"], stdout: "piped", stderr: "piped" }).output();
  const text = new TextDecoder().decode(out.stdout);
  assert(out.success, new TextDecoder().decode(out.stderr));
  const risky = /\b(pkill|killall|tccutil|rm)\b/;
  const touchesReal = /blue\.luci\.Ding(?!\.dev)|\b(pkill|killall)\b[^\n]*[ "']Ding(?![ \w.-]*Dev)|\/Ding\.app/;
  const offenders = text.split("\n").filter((l) => risky.test(l) && touchesReal.test(l));
  assertEquals(offenders, []);
  assert(text.includes("blue.luci.Ding.dev"), "the test build must use the dev bundle id");
});

Deno.test("the Makefile keeps the real bundle id for release builds and `test` does not depend on stop", async () => {
  const mk = await read("Makefile");
  assert(/^BUNDLE_ID \?= blue\.luci\.Ding$/m.test(mk));
  assertFalse(/^test:.*\bstop\b(?!-)/m.test(mk));
  assertFalse(/^test-app:.*\bstop\b(?!-)/m.test(mk));
});
