import { assertEquals } from "jsr:@std/assert@1";
import { imageSize, isMacSize, type LiveShot, type LocalShot, planScreenshotSet, validateSet } from "./listing_screenshots.ts";

const local = (name: string, md5 = name): LocalShot => ({ fileName: name, md5, size: 1, path: `/x/${name}` });
const live = (name: string, md5 = name, state = "COMPLETE"): LiveShot => ({ id: `id-${name}`, fileName: name, md5, state });

Deno.test("an identical, fully processed set matches", () => {
  assertEquals(planScreenshotSet([local("01"), local("02")], [live("01"), live("02")]), { action: "match" });
});

Deno.test("any difference replaces the whole set, because order comes from upload order", () => {
  const plan = planScreenshotSet([local("01"), local("02", "new")], [live("01"), live("02")]);
  assertEquals(plan, { action: "replace", deleteIds: ["id-01", "id-02"], upload: ["01", "02"] });
});

Deno.test("a missing, extra, reordered or still-processing screenshot is a difference", () => {
  assertEquals(planScreenshotSet([local("01")], []).action, "replace");
  assertEquals(planScreenshotSet([local("01")], [live("01"), live("02")]).action, "replace");
  assertEquals(planScreenshotSet([local("01"), local("02")], [live("02"), live("01")]).action, "replace");
  assertEquals(planScreenshotSet([local("01")], [live("01", "01", "UPLOAD_COMPLETE")]).action, "replace");
});

Deno.test("Mac sizes are the four Apple lists", () => {
  for (const [w, h] of [[1280, 800], [1440, 900], [2560, 1600], [2880, 1800]]) assertEquals(isMacSize(w, h), true);
  assertEquals(isMacSize(1290, 2796), false, "an iPhone size");
  assertEquals(isMacSize(2880, 1801), false);
});

Deno.test("validateSet flags wrong sizes, mixed sizes and more than ten", () => {
  const ok = { fileName: "a.png", w: 2880, h: 1800 };
  assertEquals(validateSet("en-US", [ok]), []);
  assertEquals(validateSet("en-US", [{ ...ok, w: 1000, h: 700 }]).length, 1);
  assertEquals(validateSet("en-US", [ok, { fileName: "b.png", w: 1440, h: 900 }]).length, 1);
  assertEquals(validateSet("en-US", Array.from({ length: 11 }, (_, i) => ({ ...ok, fileName: `${i}.png` }))).length, 1);
});

Deno.test("imageSize reads a PNG header", () => {
  const png = new Uint8Array(32);
  png.set([0x89, 0x50, 0x4e, 0x47]);
  new DataView(png.buffer).setUint32(16, 2880);
  new DataView(png.buffer).setUint32(20, 1800);
  assertEquals(imageSize(png), { w: 2880, h: 1800 });
  assertEquals(imageSize(new Uint8Array([1, 2, 3])), null);
});

Deno.test("the committed screenshots are all one valid Mac size", async () => {
  const dir = new URL("../listing/screenshots/en-US/", import.meta.url).pathname;
  const names = [...Deno.readDirSync(dir)].filter((e) => e.name.endsWith(".png")).map((e) => e.name).sort();
  assertEquals(names.length > 0, true);
  const shots = [];
  for (const fileName of names) shots.push({ fileName, ...imageSize(await Deno.readFile(dir + fileName))! });
  assertEquals(validateSet("en-US", shots), []);
});
