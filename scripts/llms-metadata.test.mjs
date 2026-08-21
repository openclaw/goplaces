import assert from "node:assert/strict";
import test from "node:test";

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
