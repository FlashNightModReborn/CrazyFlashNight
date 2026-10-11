"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const { assertNoReparse, samePath } = require("./arena-worker-client");
const { sha256Bytes } = require("./immutable-evidence");

function withoutDotnetRoot(environment) {
  const result = { ...environment };
  for (const key of Object.keys(result)) {
    if (/^DOTNET_ROOT(?:_X64)?$/i.test(key)) delete result[key];
  }
  return result;
}

function coreEnvironment(environment, detection) {
  if (!detection || detection.available !== true || !detection.environment
      || Object.keys(detection.environment).some((key) => !["DOTNET_ROOT", "DOTNET_ROOT_X64"].includes(key))) {
    throw new Error("Worker .NET runtime detection did not produce a valid child environment");
  }
  const roots = Object.values(detection.environment);
  if (roots.some((root) => typeof root !== "string" || !path.isAbsolute(root))
      || (roots.length > 0 && (roots.length !== 2 || !samePath(roots[0], roots[1])))) {
    throw new Error("Worker .NET runtime detection returned inconsistent root overrides");
  }
  return { ...withoutDotnetRoot(environment), ...detection.environment };
}

function detectDotnetRuntime(projectRoot, options = {}) {
  if ((options.platform || process.platform) !== "win32") throw new Error("Worker .NET runtime detection requires Windows");
  const helperPath = assertNoReparse(path.join(projectRoot, "tools", "dotnet-runtime-detect.ps1"));
  if (!fs.existsSync(helperPath) || !fs.statSync(helperPath).isFile()) throw new Error("Worker canonical .NET runtime detection helper is missing");
  const helperSha256 = sha256Bytes(fs.readFileSync(helperPath));
  // The repository helper owns the system/user-scope selection. The subprocess
  // changes only its own environment; Core remains the directly spawned child.
  const script = "chcp.com 65001 | Out-Null; $ErrorActionPreference='Stop'; "
    + "$OutputEncoding=[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false); "
    + ". $env:CF7_ARENA_DOTNET_HELPER; $available=Set-DotnetRootForCore -Quiet; "
    + "$selectedRoot=$null; $versions=@(); "
    + "if ($available) { $selectedRoot=if ($env:DOTNET_ROOT_X64) {$env:DOTNET_ROOT_X64} else {Join-Path $env:ProgramFiles 'dotnet'}; "
    + "$versions=@(Get-ChildItem -LiteralPath (Join-Path $selectedRoot 'shared\\Microsoft.WindowsDesktop.App') -Directory -Filter '10.*' "
    + "| Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'Microsoft.WindowsDesktop.App.deps.json')} | ForEach-Object {$_.Name}) }; "
    + "[ordered]@{available=[bool]$available; selectedRoot=$selectedRoot; desktopVersions=$versions; "
    + "environment=[ordered]@{DOTNET_ROOT=$env:DOTNET_ROOT;DOTNET_ROOT_X64=$env:DOTNET_ROOT_X64}} | ConvertTo-Json -Compress";
  const result = (options.spawnSync || childProcess.spawnSync)("powershell.exe",
    ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")],
    { encoding: "utf8", windowsHide: true, timeout: 30000, maxBuffer: 1024 * 1024,
      env: { ...withoutDotnetRoot(options.environment || process.env), CF7_ARENA_DOTNET_HELPER: helperPath } });
  if (result.error || result.status !== 0) {
    throw new Error(`Worker canonical .NET runtime probe failed${result.error ? `: ${result.error.message}` : ` (exit ${result.status})`}`);
  }
  let value;
  try { value = JSON.parse(String(result.stdout || "").trim().replace(/^\uFEFF/, "")); }
  catch (_error) { throw new Error("Worker canonical .NET runtime probe returned invalid evidence"); }
  if (!value || value.available !== true) throw new Error("Worker .NET 10 Desktop runtime is unavailable according to tools/dotnet-runtime-detect.ps1");
  if (typeof value.selectedRoot !== "string" || !path.isAbsolute(value.selectedRoot)
      || !Array.isArray(value.desktopVersions) || value.desktopVersions.length === 0
      || value.desktopVersions.some((version) => typeof version !== "string" || !/^10\./.test(version))
      || !value.environment || typeof value.environment !== "object" || Array.isArray(value.environment)) {
    throw new Error("Worker canonical .NET runtime probe returned incomplete evidence");
  }
  const detection = { source: "tools/dotnet-runtime-detect.ps1", available: true, helperPath, helperSha256,
    selectedRoot: value.selectedRoot, desktopVersions: value.desktopVersions,
    environment: Object.fromEntries(Object.entries(value.environment).filter(([_key, entry]) => entry !== null && entry !== "")) };
  coreEnvironment({}, detection);
  if (Object.values(detection.environment).some((root) => !samePath(root, detection.selectedRoot))) {
    throw new Error("Worker canonical .NET runtime probe selected a different environment root");
  }
  return detection;
}

module.exports = { coreEnvironment, detectDotnetRuntime };
