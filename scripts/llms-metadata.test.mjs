import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

import { metadataText } from "./llms-metadata.mjs";

test("rejects markup instead of trying to sanitize it", () => {
  assert.throws(
    () => metadataText("<scrip<script>t>alert(1)</script>", "title"),
    /title must be plain text/,
  );
});

test("decodes supported entities exactly once", () => {
  assert.equal(metadataText("&amp;quot; &quot; &mdash;", "title"), '&quot; " -');
});

test("the generated index preserves descriptions in valid HTML attributes", (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "goplaces-llms-metadata-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, "scripts"));
  fs.mkdirSync(path.join(root, "docs"));
  for (const script of ["generate-llms.mjs", "llms-metadata.mjs"]) {
    fs.copyFileSync(new URL(script, import.meta.url), path.join(root, "scripts", script));
  }
  fs.writeFileSync(path.join(root, "docs", "CNAME"), "docs.example.test\n");
  const cases = [
    ['<meta name="description" content="A place\'s full details">', "A place's full details"],
    ["<meta name='description' content='Search for a \"coffee shop\" nearby'>", 'Search for a "coffee shop" nearby'],
    ['<meta content="Reordered description" name="description">', "Reordered description"],
    ['<META data-name="ignored" content="Case and spacing" NAME = "DESCRIPTION">', "Case and spacing"],
    ['<meta name=description content="Unquoted name">', "Unquoted name"],
    ['<meta name="other" content="Ignore this"><meta name="description" content="Select description">', "Select description"],
    ['<meta name="description" content="Decode &amp;quot; &quot; once">', 'Decode &quot; " once'],
  ];
  for (const [meta, expected] of cases) {
    fs.writeFileSync(path.join(root, "docs", "index.html"), `<title>Fixture</title>${meta}`);
    const result = spawnSync(process.execPath, [path.join(root, "scripts", "generate-llms.mjs")], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    const index = fs.readFileSync(path.join(root, "docs", "llms.txt"), "utf8");
    assert.ok(index.includes(`- Fixture: https://docs.example.test/ - ${expected}\n`), index);
  }
  fs.writeFileSync(path.join(root, "docs", "llms.txt"), "last valid index\n");
  fs.writeFileSync(path.join(root, "docs", "index.html"), '<title>Fixture</title><meta content="<script>bad</script>" name="description">');
  const rejected = spawnSync(process.execPath, [path.join(root, "scripts", "generate-llms.mjs")], { encoding: "utf8" });
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /description must be plain text/);
  assert.equal(fs.readFileSync(path.join(root, "docs", "llms.txt"), "utf8"), "last valid index\n");
});
