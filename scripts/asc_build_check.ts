/**
 * Has App Store Connect already got a build with this build number?
 *
 *   deno run --allow-net --allow-env --allow-read scripts/asc_build_check.ts <buildNumber>
 *
 * Prints exactly one word, ABSENT | REUSE | BURNED, and exits 0. Any error (no credentials, network, a 5xx) prints the
 * reason on stderr and exits non-zero; the release recipe treats that as "unknown" and builds as usual, so this check
 * can never be the thing that stops a release.
 *
 * Why (from Mylo and Mimir): the build number is `git rev-list --count HEAD`, so re-running a release without a new
 * commit re-uploads the same number, and Apple answers a duplicate with opaque 500s that look like an outage. REUSE
 * lets the recipe skip the build and upload and carry on. BURNED means the number belongs to a failed, invalid or
 * expired build, which only a new commit can get past.
 */

import { asc, ascJwt, findApp, type Json, PLATFORM } from "./lib/asc.ts";

export interface AscBuild {
  version: string; // CFBundleVersion, the build number
  processingState: string; // PROCESSING | FAILED | INVALID | VALID
  expired: boolean;
}

export function classifyBuild(builds: AscBuild[], buildNumber: string): "ABSENT" | "REUSE" | "BURNED" {
  const mine = builds.filter((b) => b.version === buildNumber);
  if (mine.length === 0) return "ABSENT";
  const usable = mine.some((b) => !b.expired && (b.processingState === "VALID" || b.processingState === "PROCESSING"));
  return usable ? "REUSE" : "BURNED";
}

if (import.meta.main) {
  try {
    const [buildNumber] = Deno.args;
    if (!/^\d+$/.test(buildNumber ?? "")) throw new Error("usage: asc_build_check.ts <buildNumber>");
    const jwt = await ascJwt();
    const appId = await findApp(jwt);
    const response = await asc(
      jwt,
      `/builds?filter[app]=${appId}&filter[version]=${buildNumber}&filter[preReleaseVersion.platform]=${PLATFORM}` +
        `&fields[builds]=version,processingState,expired&limit=20`,
    );
    const builds: AscBuild[] = response.data.map((b: Json) => ({
      version: b.attributes.version,
      processingState: b.attributes.processingState,
      expired: !!b.attributes.expired,
    }));
    console.log(classifyBuild(builds, buildNumber));
  } catch (e) {
    console.error(`asc_build_check: ${e instanceof Error ? e.message : e}`);
    Deno.exit(2);
  }
}
