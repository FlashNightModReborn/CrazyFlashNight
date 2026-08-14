#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { test } = require("node:test");
const VerifyRun = require("./verify-run");

function withTemporaryDirectory(callback) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "a5-raw-candidate-reader-"));
  const exactRoot = fs.realpathSync.native(root);
  try { return callback(exactRoot); }
  finally { fs.rmSync(root, { recursive: true, force: true }); }
}

function assertExactFileFailure(filePath, code, phase) {
  assert.throws(() => VerifyRun.readRawCandidateJourney(filePath, phase), (error) => {
    assert.strictEqual(error.code, code);
    assert.strictEqual(error.phase, phase);
    assert.strictEqual(error.details.filePath, path.resolve(filePath));
    return true;
  });
}

test("large raw reader accepts ordinary UTF-8 JSON", () => withTemporaryDirectory((root) => {
  const filePath = path.join(root, "raw.json");
  const expected = { schema: "raw-candidate.test.v1", count: 2, nested: { ok: true } };
  fs.writeFileSync(filePath, JSON.stringify(expected), "utf8");
  assert.deepStrictEqual(VerifyRun.readRawCandidateJourney(filePath, "raw_reader_test"), expected);
}));

test("large raw reader accepts one UTF-8 BOM", () => withTemporaryDirectory((root) => {
  const filePath = path.join(root, "raw-bom.json");
  const expected = { schema: "raw-candidate.test.v1", bom: true };
  fs.writeFileSync(filePath, Buffer.concat([
    Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(JSON.stringify(expected), "utf8"),
  ]));
  assert.deepStrictEqual(VerifyRun.readRawCandidateJourney(filePath, "raw_reader_bom"), expected);
}));

test("malformed JSON preserves the caller phase and normalized error", () =>
  withTemporaryDirectory((root) => {
    const filePath = path.join(root, "malformed.json");
    fs.writeFileSync(filePath, "{", "utf8");
    assertExactFileFailure(filePath, "material_shop_json_invalid", "raw_reader_malformed");
  }));

test("empty files and directories remain outside the exact-file contract", () =>
  withTemporaryDirectory((root) => {
    const emptyPath = path.join(root, "empty.json");
    const directoryPath = path.join(root, "directory.json");
    fs.writeFileSync(emptyPath, "", "utf8");
    fs.mkdirSync(directoryPath);
    assertExactFileFailure(emptyPath, "exact_file_invalid", "raw_reader_empty");
    assertExactFileFailure(directoryPath, "exact_file_invalid", "raw_reader_directory");
  }));

test("symbolic links remain outside the exact-file contract when Windows permits creation",
  (context) => withTemporaryDirectory((root) => {
    const targetPath = path.join(root, "target.json");
    const linkPath = path.join(root, "link.json");
    fs.writeFileSync(targetPath, "{}", "utf8");
    try { fs.symlinkSync(targetPath, linkPath, "file"); }
    catch (error) {
      if (["EACCES", "EPERM", "UNKNOWN"].includes(error.code)) {
        context.skip("Windows symbolic-link privilege is unavailable");
        return;
      }
      throw error;
    }
    assertExactFileFailure(linkPath, "exact_file_invalid", "raw_reader_symlink");
  }));

test("reader exposes and applies the frozen 512 MiB ceiling", () => {
  const source = fs.readFileSync(path.join(__dirname, "verify-run.js"), "utf8");
  assert.strictEqual(VerifyRun.MAXIMUM_RAW_JOURNEY_BYTES, 512 * 1024 * 1024);
  assert.match(source,
    /const MAXIMUM_RAW_JOURNEY_BYTES = 512 \* 1024 \* 1024;/);
  assert.match(source,
    /maximumBytes: MAXIMUM_RAW_JOURNEY_BYTES,/);
});

test("verify, finalizer, and acceptance consume raw through the bounded reader", () => {
  const verify = fs.readFileSync(path.join(__dirname, "verify-run.js"), "utf8");
  const finalize = fs.readFileSync(path.join(__dirname, "finalize-clone-release.js"), "utf8");
  const accept = fs.readFileSync(path.join(__dirname, "accept-run.js"), "utf8");
  assert.match(verify,
    /const raw = readRawCandidateJourney\(options\.raw, "verify_run"\);/);
  assert.match(finalize,
    /const raw = VerifyRun\.readRawCandidateJourney\(path\.resolve\(args\.raw\), "clone_release"\);/);
  assert.match(accept,
    /const raw = VerifyRun\.readRawCandidateJourney\(options\.raw, "acceptance"\);/);
  assert.doesNotMatch(finalize, /Prepare\.readJson\([^\n]*args\.raw/);
  assert.doesNotMatch(accept, /readJson\([^\n]*options\.raw/);
});

test("verify captures optional protected-scope bootstrap before Build and raw replay", () => {
  const source = fs.readFileSync(path.join(__dirname, "verify-run.js"), "utf8");
  const capture = source.indexOf("PostReleaseAdapter.captureProtectedScopeBootstrap(");
  const optional = source.indexOf("preparation, { optional: true });", capture);
  const build = source.indexOf("Build.loadBuildReceipt(", optional);
  const raw = source.indexOf(
    "readRawCandidateJourney(options.raw, \"verify_run\")", build);
  assert(capture >= 0);
  assert(optional > capture);
  assert(build > optional);
  assert(raw > build);
});
