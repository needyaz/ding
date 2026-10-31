import { assertEquals } from "jsr:@std/assert@1";
import { actionFor, buildNumberFromVersion } from "./submit.ts";

Deno.test("the build number is the last part of 1.0.<n>", () => {
  assertEquals(buildNumberFromVersion("1.0.77"), "77");
  assertEquals(buildNumberFromVersion("1.0"), null);
  assertEquals(buildNumberFromVersion("1.0.x"), null);
});

Deno.test("only an editable version is submitted; a waiting one is left alone", () => {
  assertEquals(actionFor("PREPARE_FOR_SUBMISSION"), "submit");
  assertEquals(actionFor("REJECTED"), "submit");
  assertEquals(actionFor("WAITING_FOR_REVIEW"), "already-submitted");
  assertEquals(actionFor("IN_REVIEW"), "already-submitted");
  assertEquals(actionFor("READY_FOR_SALE"), "approved-or-live");
});
