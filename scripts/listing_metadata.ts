/**
 * App Store listing text: name, subtitle, description, keywords, promotional text, URLs and App Review notes.
 * The desired state is listing/metadata.json; this tool shows what the store has, what differs, and applies it.
 *
 *   deno run scripts/listing_metadata.ts check                     offline: validate the file against Apple's limits
 *   deno run --allow-net --allow-env --allow-read scripts/listing_metadata.ts dump
 *   deno run --allow-net --allow-env --allow-read scripts/listing_metadata.ts diff
 *   deno run --allow-net --allow-env --allow-read scripts/listing_metadata.ts apply [--create-version 1.0]
 *
 * Only the fields present in the file are managed; a field that isn't mentioned is never touched. Description, keywords,
 * URLs and review notes belong to an app store *version* and can only change while one is editable (`apply` refuses
 * otherwise, or creates one with --create-version). Promotional text may change on any version. Name, subtitle and the
 * privacy policy URL belong to the app's info record and follow the same editable rule.
 *
 * Needs ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_FILEPATH (build box only).
 */

import { asc, ascJwt, createVersion, fail, findApp, type Json, macVersions, pass, pickTarget, step, EDITABLE_STATES } from "./lib/asc.ts";

const DESIRED_PATH = new URL("../listing/metadata.json", import.meta.url).pathname;

// ---------------------------------------------------------------------------
// Pure logic (tested in listing_metadata_test.ts)
// ---------------------------------------------------------------------------

export type Section = "version" | "info";

/** Field → [store resource, Apple's character limit]. */
export const FIELDS = {
  description: { section: "version", limit: 4000 },
  keywords: { section: "version", limit: 100 },
  promotionalText: { section: "version", limit: 170 },
  whatsNew: { section: "version", limit: 4000 },
  supportUrl: { section: "version", limit: 255 },
  marketingUrl: { section: "version", limit: 255 },
  name: { section: "info", limit: 30 },
  subtitle: { section: "info", limit: 30 },
  privacyPolicyUrl: { section: "info", limit: 255 },
} as const satisfies Record<string, { section: Section; limit: number }>;
export type Field = keyof typeof FIELDS;
export type Localization = Partial<Record<Field, string>>;

export const REVIEW_FIELDS = [
  "notes", "contactFirstName", "contactLastName", "contactPhone", "contactEmail",
] as const;
export type ReviewField = typeof REVIEW_FIELDS[number];
export type Review = Partial<Record<ReviewField, string>>;

export interface Desired {
  localizations: Record<string, Localization>;
  review?: Review;
}

export interface Change {
  section: Section | "review";
  locale?: string;
  field: string;
  from: string;
  to: string;
}

/** Everything wrong with a desired-state file, as readable lines. Empty means it is fine to apply. */
export function validate(desired: Desired): string[] {
  const problems: string[] = [];
  const locales = Object.entries(desired.localizations ?? {});
  if (locales.length === 0) problems.push("no localizations");
  for (const [locale, loc] of locales) {
    for (const [field, value] of Object.entries(loc)) {
      const spec = FIELDS[field as Field];
      if (!spec) { problems.push(`[${locale}] unknown field "${field}"`); continue; }
      if (typeof value !== "string" || value.length === 0) { problems.push(`[${locale}] ${field} must be a non-empty string`); continue; }
      if ([...value].length > spec.limit) problems.push(`[${locale}] ${field} is ${[...value].length} characters; Apple allows ${spec.limit}`);
      if (field.endsWith("Url") && !/^https:\/\/\S+$/.test(value)) problems.push(`[${locale}] ${field} must be an https URL`);
    }
    if (loc.keywords && /,\s|\s,/.test(loc.keywords)) problems.push(`[${locale}] keywords: no spaces around commas (they waste the 100 characters)`);
  }
  for (const [field, value] of Object.entries(desired.review ?? {})) {
    if (!(REVIEW_FIELDS as readonly string[]).includes(field)) problems.push(`review: unknown field "${field}"`);
    else if (typeof value !== "string" || value.length === 0) problems.push(`review: ${field} must be a non-empty string`);
    else if (field === "notes" && value.length > 4000) problems.push(`review: notes is ${value.length} characters; Apple allows 4000`);
  }
  return problems;
}

/** What differs between the store and the desired file, over the fields the file mentions. */
export function computeDiff(live: Desired, desired: Desired): Change[] {
  const changes: Change[] = [];
  for (const [locale, want] of Object.entries(desired.localizations)) {
    const have = live.localizations[locale] ?? {};
    for (const field of Object.keys(want) as Field[]) {
      const to = want[field] ?? "";
      const from = have[field] ?? "";
      if (from !== to) changes.push({ section: FIELDS[field].section, locale, field, from, to });
    }
  }
  for (const field of Object.keys(desired.review ?? {}) as ReviewField[]) {
    const to = desired.review![field] ?? "";
    const from = live.review?.[field] ?? "";
    if (from !== to) changes.push({ section: "review", field, from, to });
  }
  return changes;
}

/** Whether a change can be written without an editable version (promotional text on an existing locale can). */
export function needsEditableVersion(change: Change, localeExistsOnStore: boolean): boolean {
  if (change.section === "info") return true;
  return !(change.field === "promotionalText" && localeExistsOnStore);
}

const clip = (text: string) => JSON.stringify(text.length > 70 ? `${text.slice(0, 67)}…` : text);

// ---------------------------------------------------------------------------
// Store access
// ---------------------------------------------------------------------------

interface Live {
  appId: string;
  desired: Desired;
  versionId: string;
  versionString: string;
  versionState: string;
  versionEditable: boolean;
  /** Version localization ids by locale. */
  versionLocIds: Record<string, string>;
  /** The app info record that name/subtitle go to, when it is editable. */
  editableInfoId?: string;
  infoLocIds: Record<string, string>;
  reviewDetailId?: string;
}

async function read(jwt: string): Promise<Live | null> {
  const appId = await findApp(jwt);
  const picked = pickTarget(await macVersions(jwt, appId));
  if (!picked) return null;
  const { target, editable } = picked;
  const live: Live = {
    appId,
    desired: { localizations: {}, review: {} },
    versionId: target.id,
    versionString: target.versionString,
    versionState: target.state,
    versionEditable: editable,
    versionLocIds: {},
    infoLocIds: {},
  };

  const versionLocs = await asc(jwt, `/appStoreVersions/${target.id}/appStoreVersionLocalizations`);
  for (const l of versionLocs.data) {
    const loc = live.desired.localizations[l.attributes.locale] ??= {};
    for (const field of Object.keys(FIELDS) as Field[]) {
      if (FIELDS[field].section === "version") loc[field] = l.attributes[field] ?? "";
    }
    live.versionLocIds[l.attributes.locale] = l.id;
  }

  // An app has one info record per state; the editable one exists next to an editable version.
  const infos = await asc(jwt, `/apps/${appId}/appInfos`);
  const stateOf = (i: Json) => i.attributes.state ?? i.attributes.appStoreState;
  const editableInfo = infos.data.find((i: Json) => EDITABLE_STATES.has(stateOf(i)));
  const info = editableInfo ?? infos.data[0];
  live.editableInfoId = editableInfo?.id;
  if (info) {
    const infoLocs = await asc(jwt, `/appInfos/${info.id}/appInfoLocalizations`);
    for (const l of infoLocs.data) {
      const loc = live.desired.localizations[l.attributes.locale] ??= {};
      for (const field of Object.keys(FIELDS) as Field[]) {
        if (FIELDS[field].section === "info") loc[field] = l.attributes[field] ?? "";
      }
      live.infoLocIds[l.attributes.locale] = l.id;
    }
  }

  try {
    const detail = await asc(jwt, `/appStoreVersions/${target.id}/appStoreReviewDetail`);
    live.reviewDetailId = detail?.data?.id;
    for (const field of REVIEW_FIELDS) live.desired.review![field] = detail?.data?.attributes?.[field] ?? "";
  } catch { /* a fresh version has no review detail yet */ }
  return live;
}

function attributesFor(section: Section, loc: Localization): Record<string, string> {
  return Object.fromEntries(Object.entries(loc).filter(([field]) => FIELDS[field as Field].section === section));
}

async function apply(jwt: string, live: Live, desired: Desired, versionToCreate: string | undefined): Promise<void> {
  let state = live;
  let changes = computeDiff(state.desired, desired);
  const blocked = (s: Live) => changes.filter((c) => !s.versionEditable && needsEditableVersion(c, c.locale ? c.locale in s.versionLocIds : false));

  if (blocked(state).length > 0) {
    if (!versionToCreate) {
      fail(`${blocked(state).length} change(s) need an EDITABLE version and ${state.versionString} is ${state.versionState}.`);
      console.error("  Re-run with --create-version <string> to start the next version.");
      Deno.exit(1);
    }
    step(`Creating version ${versionToCreate}…`);
    await createVersion(jwt, state.appId, versionToCreate);
    state = (await read(jwt))!;
    // A new version copies most text forward but never "what's new", so compare again.
    changes = computeDiff(state.desired, desired);
  }

  const locales = Object.keys(desired.localizations);
  for (const locale of locales) {
    const want = desired.localizations[locale];
    const versionAttributes = attributesFor("version", want);
    const infoAttributes = attributesFor("info", want);
    const touched = (section: Section) => changes.some((c) => c.locale === locale && c.section === section);

    if (touched("version")) {
      const id = state.versionLocIds[locale];
      if (id) {
        step(`PATCH version text [${locale}]…`);
        await asc(jwt, `/appStoreVersionLocalizations/${id}`, {
          method: "PATCH",
          body: JSON.stringify({ data: { type: "appStoreVersionLocalizations", id, attributes: versionAttributes } }),
        });
      } else {
        step(`POST version text [${locale}]…`);
        await asc(jwt, `/appStoreVersionLocalizations`, {
          method: "POST",
          body: JSON.stringify({ data: {
            type: "appStoreVersionLocalizations",
            attributes: { locale, ...versionAttributes },
            relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: state.versionId } } },
          } }),
        });
      }
    }

    if (touched("info")) {
      if (!state.editableInfoId) {
        fail(`[${locale}] name/subtitle/privacy URL need an editable app info record and none exists.`);
        Deno.exit(1);
      }
      const id = state.infoLocIds[locale];
      if (id) {
        step(`PATCH name and subtitle [${locale}]…`);
        await asc(jwt, `/appInfoLocalizations/${id}`, {
          method: "PATCH",
          body: JSON.stringify({ data: { type: "appInfoLocalizations", id, attributes: infoAttributes } }),
        });
      } else {
        step(`POST name and subtitle [${locale}]…`);
        await asc(jwt, `/appInfoLocalizations`, {
          method: "POST",
          body: JSON.stringify({ data: {
            type: "appInfoLocalizations",
            attributes: { locale, ...infoAttributes },
            relationships: { appInfo: { data: { type: "appInfos", id: state.editableInfoId } } },
          } }),
        });
      }
    }
  }

  if (changes.some((c) => c.section === "review")) {
    const attributes = desired.review!;
    if (state.reviewDetailId) {
      step("PATCH App Review information…");
      await asc(jwt, `/appStoreReviewDetails/${state.reviewDetailId}`, {
        method: "PATCH",
        body: JSON.stringify({ data: { type: "appStoreReviewDetails", id: state.reviewDetailId, attributes } }),
      });
    } else {
      step("POST App Review information…");
      await asc(jwt, `/appStoreReviewDetails`, {
        method: "POST",
        body: JSON.stringify({ data: {
          type: "appStoreReviewDetails",
          attributes,
          relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: state.versionId } } },
        } }),
      });
    }
  }
}

function printChanges(changes: Change[]) {
  for (const c of changes) console.log(`  ${c.locale ? `[${c.locale}] ` : "[review] "}${c.field}: ${clip(c.from)} → ${clip(c.to)}`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function loadDesired(): Promise<Desired> {
  const desired = JSON.parse(await Deno.readTextFile(DESIRED_PATH)) as Desired;
  const problems = validate(desired);
  if (problems.length > 0) {
    for (const p of problems) fail(p);
    Deno.exit(1);
  }
  return desired;
}

if (import.meta.main) {
  const [command, ...rest] = Deno.args;
  if (!["check", "dump", "diff", "apply"].includes(command ?? "")) {
    console.error("usage: listing_metadata.ts <check|dump|diff|apply> [--create-version <string>]");
    Deno.exit(1);
  }
  const desired = await loadDesired();
  if (command === "check") {
    pass(`listing/metadata.json is valid: ${Object.keys(desired.localizations).join(", ")}`);
    Deno.exit(0);
  }

  const jwt = await ascJwt();
  step("Reading the App Store listing…");
  let live = await read(jwt);
  if (!live) {
    fail("The app has no macOS version yet. Run `apply --create-version <string>` after the first build is uploaded, or add one in App Store Connect.");
    if (command !== "apply" || !rest.includes("--create-version")) Deno.exit(1);
    const appId = await findApp(jwt);
    await createVersion(jwt, appId, rest[rest.indexOf("--create-version") + 1]);
    live = await read(jwt);
    if (!live) Deno.exit(1);
  }
  pass(`version ${live.versionString} (${live.versionEditable ? "editable" : `${live.versionState}, read-only`})`);

  if (command === "dump") {
    console.log(JSON.stringify(live.desired, null, 2));
    Deno.exit(0);
  }

  const changes = computeDiff(live.desired, desired);
  if (changes.length === 0) { pass("The store already matches listing/metadata.json."); Deno.exit(0); }
  printChanges(changes);
  if (command === "diff") Deno.exit(1);

  const flag = rest.indexOf("--create-version");
  await apply(jwt, live, desired, flag >= 0 ? rest[flag + 1] : undefined);

  step("Read-back verification…");
  const after = computeDiff((await read(jwt))!.desired, desired);
  if (after.length === 0) { pass("Read-back verified: the store now matches listing/metadata.json."); Deno.exit(0); }
  fail(`${after.length} field(s) did not stick:`);
  printChanges(after);
  Deno.exit(1);
}
