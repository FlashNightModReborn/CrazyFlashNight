#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  DATA_SCHEMA,
  DECISION_SCHEMA,
  ROOT,
  buildDataset,
  renderReview,
  run,
} = require("./build-review");

function main() {
  const first = buildDataset();
  const second = buildDataset();
  assert.equal(first.schema, DATA_SCHEMA);
  assert.equal(first.decisionSchema, DECISION_SCHEMA);
  assert.equal(first.productionWrites, false);
  assert.equal(first.sourceDigest, second.sourceDigest, "相同源闭包必须得到稳定 digest");
  assert.equal(first.counts.exactNameCollisions, 6);
  assert.equal(first.items.length, 6);
  assert.deepEqual(first.items.map((item) => item.name), ["宝石线人", "丽丽丝", "格格巫", "迷之盔甲君", "酒保", "小F"]);
  assert.equal(first.items.every((item) => item.flashCurrentSource === "external-swf"), true);
  assert.equal(first.items.every((item) => item.webCurrentSource === "external-swf"), true);
  assert.equal(first.items.every((item) => item.policyCurrentSource === "external-swf"), true);
  assert.equal(first.items.every((item) => !item.diverged), true);
  assert.equal(first.counts.currentWebDivergences, 0);
  assert.equal(first.items.every((item) => item.sources.length === 2), true);
  assert.equal(first.items.every((item) => new Set(item.sources.map((source) => source.id)).size === 2), true);
  assert.equal(first.items.every((item) => item.sources.find((source) => source.id === "external-swf").image.assetPath.startsWith("launcher/web/assets/dialogue-portraits/external/")), true);
  assert.equal(first.items.every((item) => item.sources.find((source) => source.id === "dialogue-ui-sprite").image.assetPath.startsWith("tmp/dialogue-portrait-source-review/candidates/internal/")), true);
  assert.equal(first.items.every((item) => item.sources.every((source) => source.image.dataUri.startsWith("data:image/png;base64,"))), true);
  assert.equal(first.items.every((item) => item.sources.every((source) => /^[0-9a-f]{64}$/.test(source.image.assetSha256))), true);

  const html = renderReview(first);
  assert.match(html, /<title>CF7 对话立绘 · 同名双源裁决<\/title>/);
  assert.match(html, new RegExp(`<meta name="cf7-review-source-digest" content="${first.sourceDigest}">`));
  assert.doesNotMatch(html, /__CF7_(?:REVIEW_DATA|SOURCE_DIGEST)__/);
  assert.equal(first.items.every((item) => html.includes(item.name)), true);
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 2);
  assert.doesNotThrow(() => new Function(scripts.at(-1)[1]), "页面交互脚本必须可解析");

  const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-dialogue-source-review-"));
  const output = path.join(tempDirectory, "review.html");
  try {
    const generated = run(["--output", output]);
    assert.equal(fs.existsSync(output), true);
    assert.equal(generated.dataset.sourceDigest, first.sourceDigest);
    const checked = run(["--output", output, "--check"]);
    assert.equal(checked.dataset.sourceDigest, first.sourceDigest);
  } finally {
    fs.rmSync(tempDirectory, { recursive: true, force: true });
  }

  process.stdout.write(`${JSON.stringify({
    status: "dialogue_portrait_source_review_verified",
    externalListEntries: first.counts.externalListEntries,
    internalNamedFrames: first.counts.internalNamedFrames,
    collisions: first.counts.exactNameCollisions,
    currentWebDivergences: first.counts.currentWebDivergences,
    sourceDigestStable: true,
    selfContainedHtml: true,
    productionWrites: false,
    root: path.relative(ROOT, ROOT) || ".",
  })}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
  process.exitCode = 1;
}
