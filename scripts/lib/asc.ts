/**
 * App Store Connect plumbing shared by the listing tools: API-key auth and a thin fetch.
 *
 * Needs ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_FILEPATH, which only exist on the build box (see DISTRIBUTION.md).
 * The offline `check` commands never reach this file's network code.
 */

export const BUNDLE_ID = "blue.luci.Ding";
export const PLATFORM = "MAC_OS";
export const ASC_BASE = "https://api.appstoreconnect.apple.com/v1";

/** States in which a version's text and screenshots can still be edited. */
export const EDITABLE_STATES = new Set([
  "PREPARE_FOR_SUBMISSION",
  "DEVELOPER_REJECTED",
  "REJECTED",
  "METADATA_REJECTED",
  "INVALID_BINARY",
]);

// deno-lint-ignore no-explicit-any
export type Json = any;

export const step = (message: string) => console.log(`\n  → ${message}`);
export const pass = (message: string) => console.log(`  ✓ ${message}`);
export const fail = (message: string) => console.error(`  ✗ ${message}`);

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    console.error(`\n  Missing required env var: ${name} (App Store Connect credentials live on the build box only)`);
    Deno.exit(1);
  }
  return value;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}
const base64urlJson = (value: object) => base64url(new TextEncoder().encode(JSON.stringify(value)));

/** A 15-minute App Store Connect token signed with the team's API key. */
export async function ascJwt(): Promise<string> {
  const pem = await Deno.readTextFile(env("ASC_KEY_FILEPATH"));
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der.buffer, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = base64urlJson({ alg: "ES256", kid: env("ASC_KEY_ID"), typ: "JWT" });
  const payload = base64urlJson({ iss: env("ASC_ISSUER_ID"), iat: now, exp: now + 900, aud: "appstoreconnect-v1" });
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${base64url(new Uint8Array(signature))}`;
}

export async function asc(jwt: string, path: string, init?: RequestInit): Promise<Json> {
  const response = await fetch(path.startsWith("http") ? path : `${ASC_BASE}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json", ...(init?.headers ?? {}) },
  });
  if (!response.ok) throw new Error(`ASC ${init?.method ?? "GET"} ${path} → ${response.status}: ${await response.text()}`);
  return response.status === 204 ? null : await response.json();
}

export async function findApp(jwt: string): Promise<string> {
  const apps = await asc(jwt, `/apps?filter[bundleId]=${BUNDLE_ID}`);
  const id = apps.data[0]?.id;
  if (!id) throw new Error(`No App Store Connect app has bundle ID ${BUNDLE_ID}. Create the app record first.`);
  return id;
}

export interface AscVersion { id: string; versionString: string; state: string }

/** The app's macOS versions, newest first. */
export async function macVersions(jwt: string, appId: string): Promise<AscVersion[]> {
  const versions = await asc(jwt, `/apps/${appId}/appStoreVersions?filter[platform]=${PLATFORM}&limit=10`);
  return versions.data.map((v: Json) => ({ id: v.id, versionString: v.attributes.versionString, state: v.attributes.appStoreState }));
}

/** The version to edit if there is one, otherwise the newest (read-only). */
export function pickTarget(versions: AscVersion[]): { target: AscVersion; editable: boolean } | null {
  const editable = versions.find((v) => EDITABLE_STATES.has(v.state));
  if (editable) return { target: editable, editable: true };
  return versions[0] ? { target: versions[0], editable: false } : null;
}

export async function createVersion(jwt: string, appId: string, versionString: string): Promise<void> {
  await asc(jwt, `/appStoreVersions`, {
    method: "POST",
    body: JSON.stringify({
      data: {
        type: "appStoreVersions",
        attributes: { platform: PLATFORM, versionString },
        relationships: { app: { data: { type: "apps", id: appId } } },
      },
    }),
  });
}
