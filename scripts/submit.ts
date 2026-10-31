/**
 * Attach the uploaded build to the editable App Store version and submit it for App Review. Idempotent: it converges
 * on "this version has its build and is submitted", whatever state it starts in.
 *
 *   deno run --allow-net --allow-env --allow-read scripts/submit.ts --version 1.0.77 [--dry-run]
 *
 * The build number is the last part of the version (1.0.77 is build 77): `make testflight` stamps both from the commit
 * count. The version's text, screenshots and review information must already be applied (`make listing-apply`,
 * `make screenshots-apply`), and the build must have finished processing.
 */

import { asc, ascJwt, EDITABLE_STATES, fail, findApp, type Json, macVersions, PLATFORM, pass, step } from "./lib/asc.ts";

const SUBMITTED_STATES = new Set(["WAITING_FOR_REVIEW", "IN_REVIEW"]);

export function buildNumberFromVersion(version: string): string | null {
  return /^\d+\.\d+\.(\d+)$/.exec(version)?.[1] ?? null;
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
  if (!target) { fail(`No macOS version ${version} on the store. Run make listing-apply first.`); Deno.exit(1); }

  const action = actionFor(target.state);
  if (action === "already-submitted") { pass(`${version} is already ${target.state}.`); Deno.exit(0); }
  if (action === "approved-or-live") { fail(`${version} is ${target.state}; nothing to submit.`); Deno.exit(1); }

  step(`Finding build ${buildNumber}…`);
  const builds = await asc(jwt, `/builds?filter[app]=${appId}&filter[version]=${buildNumber}&filter[preReleaseVersion.platform]=${PLATFORM}&fields[builds]=version,processingState,expired&limit=1`);
  const build = builds.data[0];
  if (!build) { fail(`Build ${buildNumber} is not on App Store Connect. Run make testflight.`); Deno.exit(1); }
  if (build.attributes.expired || build.attributes.processingState !== "VALID") {
    fail(`Build ${buildNumber} is ${build.attributes.expired ? "expired" : build.attributes.processingState}; wait for it to finish processing.`);
    Deno.exit(1);
  }

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
