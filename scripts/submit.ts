/**
 * Attach the uploaded build to the editable App Store version and submit it for App Review. Idempotent: it converges
 * on "this version has its build and is submitted", whatever state it starts in.
 *
 *   deno run --allow-net --allow-env --allow-read scripts/submit.ts --version 1.0.77 [--dry-run]
 *
 * The build number is the last part of the version (1.0.77 is build 77): `make testflight` stamps both from the commit
 * count. The version's text, screenshots and review information must already be applied (`make listing-apply`,
 * `make screenshots-apply`), and `submit` waits for the build to finish processing (up to `--wait-minutes`, default 45).
 */

import { asc, ascJwt, EDITABLE_STATES, fail, findApp, type Json, macVersions, PLATFORM, pass, step } from "./lib/asc.ts";

const SUBMITTED_STATES = new Set(["WAITING_FOR_REVIEW", "IN_REVIEW"]);

export function buildNumberFromVersion(version: string): string | null {
  return /^\d+\.\d+\.(\d+)$/.exec(version)?.[1] ?? null;
}

export type Readiness = "missing" | "processing" | "ready" | "unusable";

/** Where a build stands: not visible yet (just uploaded), still processing, ready to attach, or beyond help. */
export function readiness(build: { processingState: string; expired: boolean } | undefined): Readiness {
  if (!build) return "missing";
  if (build.expired || ["FAILED", "INVALID"].includes(build.processingState)) return "unusable";
  return build.processingState === "VALID" ? "ready" : "processing";
}

export type Action = "already-submitted" | "approved-or-live" | "submit";

/** What to do for a version in `state`. */
export function actionFor(state: string): Action {
  if (SUBMITTED_STATES.has(state)) return "already-submitted";
  if (EDITABLE_STATES.has(state)) return "submit";
  return "approved-or-live";
}

if (import.meta.main) {
  const args = Deno.args;
  const version = args[args.indexOf("--version") + 1];
  const dry = args.includes("--dry-run");
  const buildNumber = buildNumberFromVersion(version ?? "");
  if (!buildNumber) { console.error("usage: submit.ts --version 1.0.<build number> [--dry-run]"); Deno.exit(1); }

  const jwt = await ascJwt();
  const appId = await findApp(jwt);
  const target = (await macVersions(jwt, appId)).find((v) => v.versionString === version);
  if (!target) {
    const found = (await macVersions(jwt, appId)).map((v) => `${v.versionString} (${v.state})`).join(", ") || "none";
    fail(`No macOS version named exactly ${version} on the store. Found: ${found}. listing-apply makes the editable version carry that name.`);
    Deno.exit(1);
  }

  const action = actionFor(target.state);
  if (action === "already-submitted") { pass(`${version} is already ${target.state}.`); Deno.exit(0); }
  if (action === "approved-or-live") { fail(`${version} is ${target.state}; nothing to submit.`); Deno.exit(1); }

  // A build uploaded a moment ago isn't listed until Apple has started processing it, and can't be attached until it
  // finishes, which takes several minutes. Wait for it (the upload step already succeeded), up to --wait-minutes.
  step(`Waiting for build ${buildNumber} to finish processing…`);
  const waitMinutes = Number(args[args.indexOf("--wait-minutes") + 1]) || 45;
  const deadline = Date.now() + waitMinutes * 60_000;
  let build: Json | undefined;
  let last = "";
  while (true) {
    const builds = await asc(jwt, `/builds?filter[app]=${appId}&filter[version]=${buildNumber}&filter[preReleaseVersion.platform]=${PLATFORM}&fields[builds]=version,processingState,expired&limit=1`);
    build = builds.data[0];
    const state = readiness(build ? { processingState: build.attributes.processingState, expired: !!build.attributes.expired } : undefined);
    if (state === "ready") break;
    if (dry) { pass(`dry run: build ${buildNumber} is ${state}; once ready it would be attached to ${version} and submitted.`); Deno.exit(0); }
    if (state === "unusable") { fail(`Build ${buildNumber} is ${build.attributes.expired ? "expired" : build.attributes.processingState} and can't be submitted. Make a new commit and release again.`); Deno.exit(1); }
    if (Date.now() > deadline) { fail(`Build ${buildNumber} still isn't ready after ${waitMinutes} minutes (${state}). Re-run make submit later.`); Deno.exit(1); }
    if (state !== last) { console.log(`  ${state === "missing" ? "not listed by Apple yet" : "processing"}…`); last = state; }
    await new Promise((resolve) => setTimeout(resolve, 30_000));
  }
  pass(`build ${buildNumber} is processed.`);

  if (dry) { pass(`dry run: would attach build ${buildNumber} to ${version} and submit it for review.`); Deno.exit(0); }

  step(`Attaching build ${buildNumber} to ${version}…`);
  await asc(jwt, `/appStoreVersions/${target.id}/relationships/build`, { method: "PATCH", body: JSON.stringify({ data: { type: "builds", id: build.id } }) });

  // Reuse an open draft submission if there is one; a second would be refused.
  const open = (await asc(jwt, `/apps/${appId}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&filter[platform]=${PLATFORM}`)).data as Json[];
  let submissionId = open[0]?.id as string | undefined;
  if (!submissionId) {
    step("Creating the review submission…");
    submissionId = (await asc(jwt, `/reviewSubmissions`, {
      method: "POST",
      body: JSON.stringify({ data: { type: "reviewSubmissions", attributes: { platform: PLATFORM }, relationships: { app: { data: { type: "apps", id: appId } } } } }),
    })).data.id;
  }
  const items = (await asc(jwt, `/reviewSubmissions/${submissionId}/items`)).data as Json[];
  if (items.length === 0) {
    step("Adding the version to the submission…");
    await asc(jwt, `/reviewSubmissionItems`, {
      method: "POST",
      body: JSON.stringify({ data: { type: "reviewSubmissionItems", relationships: {
        reviewSubmission: { data: { type: "reviewSubmissions", id: submissionId } },
        appStoreVersion: { data: { type: "appStoreVersions", id: target.id } },
      } } }),
    });
  }
  step("Submitting for review…");
  await asc(jwt, `/reviewSubmissions/${submissionId}`, { method: "PATCH", body: JSON.stringify({ data: { type: "reviewSubmissions", id: submissionId, attributes: { submitted: true } } }) });

  const after = (await macVersions(jwt, appId)).find((v) => v.versionString === version);
  if (after && SUBMITTED_STATES.has(after.state)) { pass(`${version} is ${after.state}.`); Deno.exit(0); }
  fail(`Submitted, but ${version} reads back as ${after?.state}. Check App Store Connect.`);
  Deno.exit(1);
}
