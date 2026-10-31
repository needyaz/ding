/**
 * Promote one build to the public TestFlight beta.
 *
 *   deno run --allow-net --allow-env --allow-read scripts/asc_promote_beta.ts <buildNumber>
 *
 *   1. answers export compliance (usesNonExemptEncryption=false) if the build still asks
 *   2. attaches the build to the "Public Beta" external group (the one behind the public link)
 *   3. submits it for Beta App Review when App Store Connect says one is owed
 *
 * Every step is idempotent. A build still PROCESSING can't be promoted yet: the script says so and exits non-zero, so
 * `make beta` reads as "re-run in a few minutes", not success.
 */

import { asc, ascJwt, findApp, PLATFORM } from "./lib/asc.ts";

const GROUP_NAME = "Public Beta";

/** true = done; false = not promotable yet (re-run later). */
async function promote(jwt: string, appId: string, groupId: string, buildNumber: string): Promise<boolean> {
  const response = await asc(
    jwt,
    `/builds?filter[app]=${appId}&filter[version]=${buildNumber}&filter[preReleaseVersion.platform]=${PLATFORM}` +
      `&fields[builds]=version,processingState,expired,usesNonExemptEncryption&limit=1`,
  );
  const build = response.data[0];
  if (!build) {
    console.log(`build ${buildNumber} is not on App Store Connect: upload it first (make testflight)`);
    return false;
  }
  const a = build.attributes;
  if (a.processingState === "PROCESSING") {
    console.log(`build ${buildNumber} is still processing on Apple's side: re-run in a few minutes`);
    return false;
  }
  if (a.expired || a.processingState !== "VALID") {
    console.log(`build ${buildNumber} is ${a.expired ? "expired" : a.processingState} and can't be promoted`);
    return false;
  }

  if (a.usesNonExemptEncryption === null) {
    await asc(jwt, `/builds/${build.id}`, {
      method: "PATCH",
      body: JSON.stringify({ data: { type: "builds", id: build.id, attributes: { usesNonExemptEncryption: false } } }),
    });
    console.log(`build ${buildNumber}: export compliance answered`);
  }

  try {
    await asc(jwt, `/betaGroups/${groupId}/relationships/builds`, {
      method: "POST",
      body: JSON.stringify({ data: [{ type: "builds", id: build.id }] }),
    });
  } catch (e) {
    // Adding an attached build answers 409, which is the idempotent case.
    if (!String(e).includes("409")) throw e;
  }

  const detail = await asc(jwt, `/builds/${build.id}/buildBetaDetail?fields[buildBetaDetails]=externalBuildState`);
  const state = detail.data?.attributes?.externalBuildState ?? "UNKNOWN";
  if (state === "READY_FOR_BETA_SUBMISSION") {
    await asc(jwt, `/betaAppReviewSubmissions`, {
      method: "POST",
      body: JSON.stringify({ data: { type: "betaAppReviewSubmissions", relationships: { build: { data: { type: "builds", id: build.id } } } } }),
    });
    console.log(`build ${buildNumber} attached to "${GROUP_NAME}" and submitted for Beta App Review`);
  } else {
    console.log(`build ${buildNumber} attached to "${GROUP_NAME}" (${state}: no review submission needed)`);
  }
  return true;
}

if (import.meta.main) {
  try {
    const [buildNumber] = Deno.args;
    if (!/^\d+$/.test(buildNumber ?? "")) throw new Error("usage: asc_promote_beta.ts <buildNumber>");
    const jwt = await ascJwt();
    const appId = await findApp(jwt);
    const group = (await asc(jwt, `/betaGroups?filter[app]=${appId}&filter[name]=${encodeURIComponent(GROUP_NAME)}`)).data[0];
    if (!group) throw new Error(`no beta group named "${GROUP_NAME}" on the app: create it once in TestFlight`);
    if (!(await promote(jwt, appId, group.id, buildNumber))) Deno.exit(1);
  } catch (e) {
    console.error(`asc_promote_beta: ${e instanceof Error ? e.message : e}`);
    Deno.exit(2);
  }
}
