import { assertEquals } from "jsr:@std/assert@1";
import { type AppDesired, differences, validate } from "./store_setup.ts";

const want: AppDesired = {
  contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT",
  primaryCategory: "PRODUCTIVITY",
  ageRating: { gambling: false, violenceRealistic: "NONE" },
  free: true,
  allTerritories: true,
};

Deno.test("the committed app settings are valid", async () => {
  const file = JSON.parse(await Deno.readTextFile(new URL("../listing/app.json", import.meta.url).pathname));
  assertEquals(validate(file), []);
});

Deno.test("validate rejects unknown rights, categories and rating levels", () => {
  assertEquals(validate({ ...want, contentRightsDeclaration: "MAYBE" }).length, 1);
  assertEquals(validate({ ...want, primaryCategory: "productivity" }).length, 1);
  assertEquals(validate({ ...want, ageRating: { violenceRealistic: "SOME" } }).length, 1);
  assertEquals(validate({ ...want, ageRating: {} }).length, 1);
});

Deno.test("nothing differs when the store already matches", () => {
  assertEquals(differences({ ...want }, want), []);
});

Deno.test("an empty store differs in every setting", () => {
  const out = differences({}, want);
  assertEquals(out.length, 6);
  assertEquals(out.some((line) => line.startsWith("price")), true);
});

Deno.test("only the settings that differ are reported", () => {
  const live = { ...want, primaryCategory: "UTILITIES", ageRating: { gambling: false, violenceRealistic: "NONE" } };
  assertEquals(differences(live, want), ["primaryCategory: UTILITIES → PRODUCTIVITY"]);
});
