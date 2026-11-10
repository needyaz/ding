// The documents and spec rows settled by ding-20261109-1, read as a user or reviewer would read them.

function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}
const assertFalse = (condition: unknown, message = "expected false") => assert(!condition, message);

const read = (path: string) => Deno.readTextFile(new URL(`../${path}`, import.meta.url).pathname);

/** The body of a `## ` section, up to the next `## ` heading. */
function section(markdown: string, heading: string): string {
  const lines = markdown.split("\n");
  const start = lines.findIndex((line) => line.startsWith("## ") && line.slice(3).trim().startsWith(heading));
  if (start < 0) throw new Error(`no section "${heading}"`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith("## "));
  return (end < 0 ? rest : rest.slice(0, end)).join("\n");
}

const collapse = (text: string) => text.replace(/\s+/g, " ");
const sentences = (text: string) => collapse(text).split(/(?<=[.!?])\s+/);

type Row = { id: string; status: string; src: string; statement: string; evidence: string };

async function requirement(id: string): Promise<Row> {
  const lines = (await read("spec/requirements.tsv")).split("\n");
  const line = lines.find((l) => l.split("\t")[0] === id);
  assert(line, `spec/requirements.tsv has a row for ${id}`);
  const [, status, src, statement, evidence] = line.split("\t");
  return { id, status, src, statement, evidence };
}

Deno.test("DING-NOTIF-013: SPEC.md's default-setup sentence describes a 5-minute notification and style None", async () => {
  const spec = await read("SPEC.md");
  const match = sentences(spec).filter((s) => /\bdefault\b/i.test(s) && /\b5[- ]minutes?\b/i.test(s) && /\bNone\b/.test(s));
  assert(match.length > 0, "a sentence states the default setup: a 5-minute notification and screen reminder style None");
  assertFalse(/followed by a full-screen reminder/i.test(collapse(spec)), "no sentence makes a full-screen reminder part of the default");
});

Deno.test("DING-NOTIF-028: SPEC.md no longer requires the UI to say \"screen reminder\" instead of \"alert\"", async () => {
  const spec = collapse(await read("SPEC.md"));
  assertFalse(/the UI says ["“]screen reminder["”]/i.test(spec), "SPEC.md still says the UI says \"screen reminder\"");
});

Deno.test("DING-NOTIF-016: the requirement row describes the one linkless-events switch with its new label and is no longer unspecced", async () => {
  const row = await requirement("DING-NOTIF-016");
  assert(["C", "IU"].includes(row.status), `DING-NOTIF-016 status is ${row.status}`);
  assert(row.statement.includes("Remind me about events without a meeting link"), row.statement);
});

Deno.test("DING-MCP-019: the requirement row is settled, no longer a conflict", async () => {
  const row = await requirement("DING-MCP-019");
  assert(["C", "IU"].includes(row.status), `DING-MCP-019 status is ${row.status}`);
  assert(/\bopened\b/.test(row.statement), row.statement);
});

Deno.test("DING-TEST-001: the requirement row is settled and is about the real AppModel and notification center", async () => {
  const row = await requirement("DING-TEST-001");
  assert(["C", "IU"].includes(row.status), `DING-TEST-001 status is ${row.status}`);
  assert(/AppModel/.test(row.statement), row.statement);
});

Deno.test("DING-REL-002: DISTRIBUTION.md's preflight step names deno along with git, xcodebuild and xcodegen", async () => {
  const doc = await read("DISTRIBUTION.md");
  const step = doc.split("\n").find((line) => line.includes("**Preflight:**"));
  assert(step, "the preflight step is still listed");
  for (const tool of ["git", "xcodebuild", "xcodegen", "deno"]) {
    assert(step.includes(`\`${tool}\``), `the preflight step names ${tool}`);
  }
});

Deno.test("DING-REL-019: SPEC.md's Milestones no longer lists signing, notarization or App Store submission as remaining", async () => {
  const spec = await read("SPEC.md");
  const status = collapse(section(spec, "Milestones").split(/\n1\. /)[0]);
  assertFalse(/Remaining:[^.]*(signing and notarization|App Store submission)/i.test(status), status);
  const distribution = collapse(section(spec, "Distribution"));
  assert(/GitHub Releases?/.test(distribution), "Distribution & License describes the GitHub Releases download");
});

Deno.test("DING-PROC-005: SPEC.md's Decisions say the needyaz/ding repository is public", async () => {
  const decisions = sentences(section(await read("SPEC.md"), "Decisions"));
  const repo = decisions.filter((s) => s.includes("needyaz/ding"));
  assert(repo.length > 0, "the Decisions entry still names the repository");
  for (const s of repo) {
    assert(/\bpublic\b/i.test(s), s);
    assertFalse(/\bprivate\b/i.test(s), s);
  }
});

Deno.test("DING-REL-020: README.md sends users to the Mac App Store listing", async () => {
  const readme = await read("README.md");
  assert(readme.includes("https://apps.apple.com/app/id6829270522?mt=12"), "README links the listing");
  assertFalse(/coming to the Mac App Store/i.test(collapse(readme)), "README no longer calls the App Store future");
});

Deno.test("DING-REL-010: listing/README.md no longer claims the check rejects trademarked keywords", async () => {
  const text = collapse(section(await read("listing/README.md"), "Text"));
  assertFalse(/trademark/i.test(text), text);
});

Deno.test("DING-REL-010: (keeps) listing/README.md still says keywords carry no spaces after commas", async () => {
  const text = collapse(section(await read("listing/README.md"), "Text"));
  assert(/no spaces after commas/i.test(text), text);
});
