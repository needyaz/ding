/**
 * The App Store Connect settings that belong to the app, not to a version: content rights, category, age rating,
 * price and availability. Desired state is listing/app.json. Idempotent: `diff` reads, `apply` writes only what
 * differs and then reads back. (Copyright, release type and the review contact live with the version, in
 * listing_metadata.ts. The privacy "nutrition label" has no API and is answered once in the web UI.)
 *
 *   deno run --allow-read scripts/store_setup.ts check
 *   deno run --allow-net --allow-env --allow-read scripts/store_setup.ts diff
 *   deno run --allow-net --allow-env --allow-read scripts/store_setup.ts apply
 */

import { asc, ascJwt, fail, findApp, type Json, pass, step } from "./lib/asc.ts";

const DESIRED_PATH = new URL("../listing/app.json", import.meta.url).pathname;
const ROOT = "https://api.appstoreconnect.apple.com";

export interface AppDesired {
  contentRightsDeclaration: string;
  primaryCategory: string;
  /** Every age rating question: "NONE" / true / false. */
  ageRating: Record<string, string | boolean>;
  free: boolean;
  allTerritories: boolean;
}

export const CONTENT_RIGHTS = ["DOES_NOT_USE_THIRD_PARTY_CONTENT", "USES_THIRD_PARTY_CONTENT"];

export function validate(desired: AppDesired): string[] {
  const problems: string[] = [];
  if (!CONTENT_RIGHTS.includes(desired.contentRightsDeclaration)) problems.push(`contentRightsDeclaration must be one of ${CONTENT_RIGHTS.join(", ")}`);
  if (!/^[A-Z_]+$/.test(desired.primaryCategory ?? "")) problems.push("primaryCategory must be an App Store category id such as PRODUCTIVITY");
  if (Object.keys(desired.ageRating ?? {}).length === 0) problems.push("ageRating is empty");
  for (const [key, value] of Object.entries(desired.ageRating ?? {})) {
    if (typeof value === "string" && !["NONE", "INFREQUENT_OR_MILD", "FREQUENT_OR_INTENSE"].includes(value)) problems.push(`ageRating.${key}: "${value}" is not a rating level`);
  }
  return problems;
}

/** The settings whose live value differs from the desired one, as `name: have → want`. */
export function differences(live: Partial<AppDesired>, want: AppDesired): string[] {
  const out: string[] = [];
  if (live.contentRightsDeclaration !== want.contentRightsDeclaration) out.push(`contentRightsDeclaration: ${live.contentRightsDeclaration ?? "unset"} → ${want.contentRightsDeclaration}`);
  if (live.primaryCategory !== want.primaryCategory) out.push(`primaryCategory: ${live.primaryCategory ?? "unset"} → ${want.primaryCategory}`);
  for (const [key, value] of Object.entries(want.ageRating)) {
    if (live.ageRating?.[key] !== value) out.push(`ageRating.${key}: ${live.ageRating?.[key] ?? "unset"} → ${value}`);
  }
  if (want.free && live.free !== true) out.push(`price: ${live.free === undefined ? "unset" : "not free"} → free`);
  if (want.allTerritories && live.allTerritories !== true) out.push("availability: not set → all territories");
  return out;
}

async function read(jwt: string, appId: string, want: AppDesired): Promise<{ live: Partial<AppDesired>; infoId: string; ageId: string }> {
  const app = (await asc(jwt, `/apps/${appId}`)).data;
  const info = (await asc(jwt, `/apps/${appId}/appInfos`)).data[0];
  const category = await asc(jwt, `/appInfos/${info.id}/primaryCategory`).catch(() => null);
  const age = (await asc(jwt, `/appInfos/${info.id}/ageRatingDeclaration`)).data;

  let free: boolean | undefined;
  try {
    const manual = await asc(jwt, `/appPriceSchedules/${appId}/manualPrices?include=appPricePoint&limit=50`);
    const points: Json[] = manual.included ?? [];
    free = (manual.data ?? []).length > 0 && points.length > 0 && points.every((p) => p.attributes?.customerPrice === "0.0");
  } catch { /* no schedule yet */ }

  let allTerritories: boolean | undefined;
  try {
    await asc(jwt, `/apps/${appId}/appAvailabilityV2`);
    allTerritories = true;
  } catch { /* not set yet */ }

  return {
    infoId: info.id,
    ageId: age.id,
    live: {
      contentRightsDeclaration: app.attributes.contentRightsDeclaration ?? undefined,
      primaryCategory: category?.data?.id,
      ageRating: Object.fromEntries(Object.keys(want.ageRating).map((k) => [k, age.attributes[k]])),
      free,
      allTerritories,
    },
  };
}

async function apply(jwt: string, appId: string, want: AppDesired, state: { live: Partial<AppDesired>; infoId: string; ageId: string }) {
  const { live, infoId, ageId } = state;
  if (live.contentRightsDeclaration !== want.contentRightsDeclaration) {
    step("Content rights…");
    await asc(jwt, `/apps/${appId}`, { method: "PATCH", body: JSON.stringify({ data: { type: "apps", id: appId, attributes: { contentRightsDeclaration: want.contentRightsDeclaration } } }) });
  }
  if (live.primaryCategory !== want.primaryCategory) {
    step("Primary category…");
    await asc(jwt, `/appInfos/${infoId}`, {
      method: "PATCH",
      body: JSON.stringify({ data: { type: "appInfos", id: infoId, relationships: { primaryCategory: { data: { type: "appCategories", id: want.primaryCategory } } } } }),
    });
  }
  if (Object.entries(want.ageRating).some(([k, v]) => live.ageRating?.[k] !== v)) {
    step("Age rating…");
    await asc(jwt, `/ageRatingDeclarations/${ageId}`, { method: "PATCH", body: JSON.stringify({ data: { type: "ageRatingDeclarations", id: ageId, attributes: want.ageRating } }) });
  }
  if (want.free && live.free !== true) {
    step("Price: free…");
    const points = (await asc(jwt, `/apps/${appId}/appPricePoints?filter[territory]=USA&limit=200`)).data;
    const free = points.find((p: Json) => p.attributes.customerPrice === "0.0");
    if (!free) throw new Error("no free price point found for USA");
    await asc(jwt, `/appPriceSchedules`, {
      method: "POST",
      body: JSON.stringify({
        data: { type: "appPriceSchedules", relationships: {
          app: { data: { type: "apps", id: appId } },
          baseTerritory: { data: { type: "territories", id: "USA" } },
          manualPrices: { data: [{ type: "appPrices", id: "${p1}" }] },
        } },
        included: [{ type: "appPrices", id: "${p1}", attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: "appPricePoints", id: free.id } } } }],
      }),
    });
  }
  if (want.allTerritories && live.allTerritories !== true) {
    step("Availability: all territories…");
    const territories: string[] = [];
    let next = "/territories?limit=200";
    while (next) {
      const page = await asc(jwt, next);
      territories.push(...page.data.map((t: Json) => t.id));
      next = page.links?.next?.replace(`${ROOT}/v1`, "") ?? "";
    }
    await asc(jwt, `${ROOT}/v2/appAvailabilities`, {
      method: "POST",
      body: JSON.stringify({
        data: { type: "appAvailabilities", attributes: { availableInNewTerritories: true }, relationships: {
          app: { data: { type: "apps", id: appId } },
          territoryAvailabilities: { data: territories.map((t) => ({ type: "territoryAvailabilities", id: `\${${t}}` })) },
        } },
        included: territories.map((t) => ({ type: "territoryAvailabilities", id: `\${${t}}`, attributes: { available: true }, relationships: { territory: { data: { type: "territories", id: t } } } })),
      }),
    });
  }
}

if (import.meta.main) {
  const command = Deno.args[0];
  if (!["check", "diff", "apply"].includes(command ?? "")) {
    console.error("usage: store_setup.ts <check|diff|apply>");
    Deno.exit(1);
  }
  const want = JSON.parse(await Deno.readTextFile(DESIRED_PATH)) as AppDesired;
  const problems = validate(want);
  if (problems.length > 0) { problems.forEach(fail); Deno.exit(1); }
  if (command === "check") { pass("listing/app.json is valid"); Deno.exit(0); }

  const jwt = await ascJwt();
  const appId = await findApp(jwt);
  step("Reading the app's store settings…");
  const state = await read(jwt, appId, want);
  const diff = differences(state.live, want);
  if (diff.length === 0) { pass("The app's store settings already match listing/app.json."); Deno.exit(0); }
  diff.forEach((d) => console.log(`  ${d}`));
  if (command === "diff") Deno.exit(1);

  await apply(jwt, appId, want, state);
  step("Read-back verification…");
  const after = differences((await read(jwt, appId, want)).live, want);
  if (after.length === 0) { pass("Read-back verified: the store matches listing/app.json."); Deno.exit(0); }
  fail("did not stick:");
  after.forEach((d) => console.log(`  ${d}`));
  Deno.exit(1);
}
