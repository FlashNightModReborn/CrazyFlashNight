#!/usr/bin/env node
"use strict";

const assert = require("assert");
const path = require("path");
const { coreEnvironment, detectDotnetRuntime } = require("./lib/arena-worker-dotnet");

const projectRoot = path.resolve(__dirname, "../..");
const selectedRoot = path.join(projectRoot, "tmp", "fixture-dotnet");
const environment = { Path: "fixture-path", DOTNET_ROOT: "stale-root", DOTNET_ROOT_X64: "stale-x64" };
const override = { DOTNET_ROOT: selectedRoot, DOTNET_ROOT_X64: selectedRoot };
let calls = 0;
function runProbe(value, resultChanges = {}) {
  return detectDotnetRuntime(projectRoot, { platform: "win32", environment,
    spawnSync: (command, args, options) => {
      calls++;
      assert.strictEqual(command, "powershell.exe");
      assert(args.includes("-NonInteractive"));
      const script = Buffer.from(args[args.indexOf("-EncodedCommand") + 1], "base64").toString("utf16le");
      assert(script.includes(". $env:CF7_ARENA_DOTNET_HELPER"));
      assert(script.includes("Set-DotnetRootForCore -Quiet"));
      assert.strictEqual(options.windowsHide, true);
      assert.strictEqual(options.env.DOTNET_ROOT, undefined);
      assert.strictEqual(options.env.DOTNET_ROOT_X64, undefined);
      assert.strictEqual(options.env.CF7_ARENA_DOTNET_HELPER, path.join(projectRoot, "tools", "dotnet-runtime-detect.ps1"));
      return { status: 0, stdout: JSON.stringify(value), ...resultChanges };
    } });
}

const successful = { available: true, selectedRoot, desktopVersions: ["10.0.8"], environment: override };
const detection = runProbe(successful);
assert.strictEqual(detection.source, "tools/dotnet-runtime-detect.ps1");
assert.strictEqual(detection.desktopVersions[0], "10.0.8");
assert.match(detection.helperSha256, /^sha256:[a-f0-9]{64}$/);
assert.deepStrictEqual(coreEnvironment(environment, detection), { Path: "fixture-path", ...override });
assert.deepStrictEqual(environment, { Path: "fixture-path", DOTNET_ROOT: "stale-root", DOTNET_ROOT_X64: "stale-x64" });
const system = runProbe({ ...successful, environment: { DOTNET_ROOT: null, DOTNET_ROOT_X64: null } });
assert.deepStrictEqual(coreEnvironment(environment, system), { Path: "fixture-path" });
assert.throws(() => runProbe({ available: false, selectedRoot: null, desktopVersions: [], environment: {} }), /unavailable according to/);
assert.throws(() => runProbe(successful, { status: 1 }), /probe failed/);
assert.throws(() => runProbe(successful, { status: null, error: new Error("fixture timeout") }), /fixture timeout/);
assert.throws(() => runProbe(successful, { stdout: "not-json" }), /invalid evidence/);
assert.throws(() => runProbe({ ...successful, environment: { DOTNET_ROOT: selectedRoot } }), /inconsistent root/);
assert.throws(() => runProbe({ ...successful, selectedRoot: path.dirname(selectedRoot) }), /different environment root/);
assert.throws(() => runProbe({ ...successful, desktopVersions: [] }), /incomplete evidence/);
const beforeNonWindows = calls;
assert.throws(() => detectDotnetRuntime(projectRoot, { platform: "linux", spawnSync: () => { calls++; } }), /requires Windows/);
assert.strictEqual(calls, beforeNonWindows, "non-Windows fixtures must not launch PowerShell");
console.log(JSON.stringify({ ok: true, evidenceKind: "isolated_fixture", canonicalHelperReused: true,
  childEnvironmentOnly: true, actualProcessQueries: 0, actualHostStarts: 0 }));
