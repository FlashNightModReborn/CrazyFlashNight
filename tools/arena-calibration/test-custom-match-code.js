#!/usr/bin/env node
"use strict";

const assert = require("assert");
const path = require("path");

const ArenaCustomMatchCode = require("../../launcher/web/modules/arena-custom-match-code");
const units = require("../../data/units/units.json");
const { normalizeManifest } = require("./lib/arena-calibration-core");

function expectRejected(label, fn) {
  let rejected = false;
  try {
    fn();
  } catch (_error) {
    rejected = true;
  }
  if (!rejected) {
    throw new Error(`${label} was not rejected`);
  }
}

function parse(code) {
  return ArenaCustomMatchCode.parseMatchCode(code, { unitCatalog: units, caseId: "custom-case" });
}

function checkCanonicalRoundTrip() {
  const parsed = parse("CF7ARENA:v1;mode=mvm;seed=90210;blue=u44@30x2,u48@30x1;red=u164@60x1,u11@30x1");
  assert.strictEqual(parsed.mode, "mvm");
  assert.strictEqual(parsed.seed, 90210);
  assert.strictEqual(parsed.blueRoster.length, 2);
  assert.strictEqual(parsed.blueRoster[0].type, "兵种44");
  assert.strictEqual(parsed.blueRoster[0].count, 2);
  assert.strictEqual(parsed.redRoster[0].type, "兵种164");
  assert.strictEqual(
    parsed.canonical,
    "CF7ARENA:v1;mode=mvm;seed=90210;blue=u44@30x2,u48@30x1;red=u164@60x1,u11@30x1"
  );

  assert.strictEqual(parsed.calibrationCase.blueRoster.length, 3);
  assert.strictEqual(parsed.calibrationCase.redRoster.length, 2);
  assert.deepStrictEqual(parsed.calibrationCase.blueRoster[0], { type: "兵种44", level: 30 });
}

function checkChineseTypeAlias() {
  const parsed = parse("CF7ARENA:v1;mode=mvm;seed=1;blue=兵种164@60x1;red=兵种11@30x1");
  assert.strictEqual(parsed.blueRoster[0].id, 164);
  assert.strictEqual(parsed.canonical, "CF7ARENA:v1;mode=mvm;seed=1;blue=u164@60x1;red=u11@30x1");
}

function checkManifestAdapter() {
  const parsed = parse("CF7ARENA:v1;mode=mvm;seed=7;blue=u164@60x1;red=u11@30x1");
  const manifest = ArenaCustomMatchCode.buildCalibrationManifest(parsed, {
    batchId: "custom-p1-contract",
    caseId: "custom-p1-case",
    createdAt: "2026-07-03T00:00:00.000Z",
    buildCommit: "fixture",
  });
  const normalized = normalizeManifest(manifest);
  assert.strictEqual(normalized.schema, "arena-calibration.case-manifest.v1");
  assert.strictEqual(normalized.arenaMode, "calibration");
  assert.strictEqual(normalized.cases.length, 1);
  assert.strictEqual(normalized.cases[0].blueRoster[0].type, "兵种164");
  assert.ok(normalized.cases[0].caseHash.startsWith("sha256:"));
}

function checkPvePayload() {
  const parsed = parse("CF7ARENA:v1;mode=pve;seed=3307;enemy=u164@60x1,u11@10x2;player=current");
  assert.strictEqual(parsed.mode, "pve");
  assert.strictEqual(parsed.seed, 3307);
  assert.strictEqual(parsed.player, "current");
  assert.strictEqual(parsed.enemyRoster.length, 2);
  assert.strictEqual(parsed.enemyRoster[1].type, "兵种11");
  assert.strictEqual(parsed.enemyRoster[1].count, 2);
  assert.strictEqual(parsed.calibrationCase, undefined);
  assert.strictEqual(parsed.venueFeeEstimate, 0);
  assert.strictEqual(
    parsed.canonical,
    "CF7ARENA:v1;mode=pve;seed=3307;enemy=u164@60x1,u11@10x2;player=current"
  );
  assert.deepStrictEqual(parsed.enterPayload.roster, [
    { type: "兵种164", level: 60 },
    { type: "兵种11", level: 10 },
    { type: "兵种11", level: 10 },
  ]);
  assert.strictEqual(parsed.enterPayload.cmd, "enter");
  assert.strictEqual(parsed.enterPayload.mode, "custom_pve");
  assert.strictEqual(parsed.enterPayload.deposit, 0);
  assert.strictEqual(parsed.enterPayload.reward, 0);
}

function checkRejections() {
  expectRejected("unknown unit", () =>
    parse("CF7ARENA:v1;mode=mvm;seed=1;blue=u99999@1x1;red=u11@30x1")
  );
  expectRejected("economy field", () =>
    parse("CF7ARENA:v1;mode=mvm;seed=1;blue=u164@60x1;red=u11@30x1;reward=999")
  );
  expectRejected("pve wrong player", () =>
    parse("CF7ARENA:v1;mode=pve;seed=1;enemy=u11@30x1;player=saved")
  );
  expectRejected("pve blue field", () =>
    parse("CF7ARENA:v1;mode=pve;seed=1;blue=u44@30x1;enemy=u11@30x1;player=current")
  );
  expectRejected("mvm enemy field", () =>
    parse("CF7ARENA:v1;mode=mvm;seed=1;blue=u164@60x1;red=u11@30x1;enemy=u44@30x1")
  );
  expectRejected("duplicate field", () =>
    parse("CF7ARENA:v1;mode=mvm;mode=mvm;seed=1;blue=u164@60x1;red=u11@30x1")
  );
  expectRejected("zero count", () =>
    parse("CF7ARENA:v1;mode=mvm;seed=1;blue=u164@60x0;red=u11@30x1")
  );
}

function main() {
  checkCanonicalRoundTrip();
  checkChineseTypeAlias();
  checkManifestAdapter();
  checkPvePayload();
  checkRejections();
  console.log(JSON.stringify({ ok: true, test: path.basename(__filename) }, null, 2));
}

main();
