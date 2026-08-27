#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const CloneSaveGuard = require("../workbench-live-e2e/lib/clone-save-guard");
const LauncherObservation = require("../workbench-live-e2e/lib/launcher-observation");
const SharedEvidence = require("../workbench-live-e2e/lib/evidence-artifact");
const { assertSchemaInstance } = require("./lib/schema-registry");
const { sha256OfValue } = require("./lib/arena-calibration-core");
const {
  atomicWriteJson,
  canonicalJson,
  readJson,
  sha256Bytes,
} = require("../workbench-live-e2e/kshop/common");

const ROOT = path.resolve(__dirname, "..", "..");
const OWNED_RELATIVE = path.join("tmp", "workbench-live-e2e", "arena-pve");

function fail(message) { throw new Error(message); }

function parseArgs(argv) {
  const options = { packet: null, plan: null, reportOne: null, reportTwo: null,
    quarantineDir: null, outputDir: null, countOne: null, levelOne: null,
    countTwo: null, levelTwo: null, statementOne: null, statementTwo: null, submittedAt: null,
    check: false, help: false };
  function take(index, flag) {
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${flag} requires a value`);
    return value;
  }
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--packet") options.packet = path.resolve(take(index++, token));
    else if (token === "--plan") options.plan = path.resolve(take(index++, token));
    else if (token === "--report-one") options.reportOne = path.resolve(take(index++, token));
    else if (token === "--report-two") options.reportTwo = path.resolve(take(index++, token));
    else if (token === "--quarantine-dir") options.quarantineDir = path.resolve(take(index++, token));
    else if (token === "--output-dir") options.outputDir = path.resolve(take(index++, token));
    else if (token === "--count-one") options.countOne = Number(take(index++, token));
    else if (token === "--level-one") options.levelOne = Number(take(index++, token));
    else if (token === "--count-two") options.countTwo = Number(take(index++, token));
    else if (token === "--level-two") options.levelTwo = Number(take(index++, token));
    else if (token === "--statement-one") options.statementOne = take(index++, token);
    else if (token === "--statement-two") options.statementTwo = take(index++, token);
    else if (token === "--submitted-at") options.submittedAt = take(index++, token);
    else if (token === "--check") options.check = true;
    else if (token === "--help" || token === "-h") options.help = true;
    else fail(`unknown argument: ${token}`);
  }
  return options;
}

function usage() {
  return "Usage: node tools/arena-calibration/finalize-human-pve.js --packet <pve-packet.json> --plan <private-plan.json> --report-one <report.json> --report-two <report.json> --quarantine-dir <dir> --output-dir <dir> --count-one <n> --level-one <n> --count-two <n> --level-two <n> --statement-one <text> --statement-two <text> [--submitted-at <ISO-8601>]";
}

function hashFile(filePath) {
  const bytes = fs.readFileSync(filePath);
  return { bytes: bytes.length, sha256: `sha256:${sha256Bytes(bytes)}` };
}

function sameRuntime(required, actual) {
  const fields = ["runtimeMode", "coreSha256", "buildIdentity", "payloadClosure"];
  return fields.every((field) => String(required[field] || "").toUpperCase()
    === String(actual[field] || "").toUpperCase());
}

function assertReport(report, reportPath, plan, order) {
  const encounter = report.controlledEncounters && report.controlledEncounters[0];
  const planned = plan.encounters[order - 1];
  if (!report || report.schema !== "arena-calibration.human-pve-live-session.v1"
      || report.packetId !== plan.packetId || report.targetSlot !== plan.targetSlot
      || !sameRuntime(plan.runtimeIdentityRequired, report.runtimeIdentity)
      || !encounter || encounter.order !== order
      || encounter.encounterId !== planned.encounterId
      || encounter.matchCodeSha256 !== planned.matchCodeSha256
      || !encounter.finalConfirmation || encounter.finalConfirmation.automaticStartClick !== false
      || !encounter.screenshot || !/^([a-f0-9]{64})$/.test(encounter.screenshot.sha256)
      || !report.seedInvariant || report.seedInvariant.unchanged !== true
      || `sha256:${report.seedInvariant.sha256}` !== plan.playerBuild.saveSha256
      || !report.shutdown || report.shutdown.responseSucceeded !== true
      || !report.cloneLifecycle || !report.cloneLifecycle.collateral
      || report.cloneLifecycle.collateral.setSha256
        !== report.cloneLifecycle.collateralBefore.setSha256
      || report.cloneLifecycle.collateral.setSha256
        !== report.cloneLifecycle.collateralEnd.setSha256) {
    fail(`human PVE report ${order} is incomplete or detached: ${reportPath}`);
  }
  if (order === 1 && report.status !== "aborted_cleaned") {
    fail("encounter 1 report must preserve the observed post-encounter PTY-abort cleanup status");
  }
  if (order === 2 && (report.status !== "human_run_finished_cleanup"
      || report.operatorCommand !== "finish")) {
    fail("encounter 2 report lacks the explicit finish cleanup receipt");
  }
  return encounter;
}

function validateLabel(count, level, statement, label) {
  if (!Number.isInteger(count) || count < 1 || count > 20
      || !Number.isInteger(level) || level < 1 || level > 100
      || typeof statement !== "string" || !statement.trim()) {
    fail(`${label} equivalence label is invalid`);
  }
  return { count, level, statement: statement.trim() };
}

function finalize(options) {
  const required = ["packet", "plan", "reportOne", "reportTwo", "quarantineDir",
    "outputDir", "statementOne", "statementTwo"];
  required.forEach((field) => { if (!options[field]) fail(`--${field.replace(/[A-Z]/g,
    (char) => `-${char.toLowerCase()}`)} is required`); });
  const labelOne = validateLabel(options.countOne, options.levelOne,
    options.statementOne, "encounter 1");
  const labelTwo = validateLabel(options.countTwo, options.levelTwo,
    options.statementTwo, "encounter 2");
  const packet = readJson(options.packet, "PVE packet");
  const plan = readJson(options.plan, "PVE runtime plan");
  const reportOne = readJson(options.reportOne, "PVE report one");
  const reportTwo = readJson(options.reportTwo, "PVE report two");
  if (packet.schema !== "arena-calibration.pve-packet.v1"
      || packet.packetId !== plan.packetId || packet.packetHash !== plan.packetHash
      || packet.encounters.length !== 2 || plan.encounters.length !== 2) {
    fail("PVE packet and runtime plan are not one exact two-encounter packet");
  }
  const encounterOne = assertReport(reportOne, options.reportOne, plan, 1);
  const encounterTwo = assertReport(reportTwo, options.reportTwo, plan, 2);
  const reportHashes = [hashFile(options.reportOne), hashFile(options.reportTwo)];
  const sourceBytes = fs.readFileSync(plan.sourceSavePath);
  const sourceHash = `sha256:${sha256Bytes(sourceBytes)}`;
  if (sourceHash !== plan.playerBuild.saveSha256) fail("source player save changed before PVE finalization");
  const runtimeProcesses = LauncherObservation.queryLauncherCoreProcesses();
  if (runtimeProcesses.length !== 0) fail("PVE finalization requires zero Launcher Core processes");
  const lock = CloneSaveGuard.inspectCloneLock({ root: ROOT, slot: plan.targetSlot });
  if (lock.lockPresent || lock.recoveryPresent) fail("PVE finalization found a clone lock or recovery record");
  const activeTarget = CloneSaveGuard.captureSlotArtifactSet({ root: ROOT,
    appData: process.env.APPDATA, slot: plan.targetSlot, requireJson: false });
  if (activeTarget.artifacts.length !== 0) fail("PVE dedicated slot still has active artifacts");
  const quarantine = SharedEvidence.assertExactDirectory(options.quarantineDir,
    "pve_final_quarantine");
  const expectedQuarantine = path.join(path.dirname(options.reportTwo), "purged-dedicated-clone");
  if (path.resolve(quarantine).toLowerCase() !== path.resolve(expectedQuarantine).toLowerCase()) {
    fail("PVE quarantine is outside the exact second-session run directory");
  }
  const quarantineFiles = fs.readdirSync(quarantine).sort();
  if (canonicalJson(quarantineFiles) !== canonicalJson([
    `${plan.targetSlot}.json`, `${plan.targetSlot}.sol`].sort())) {
    fail("PVE quarantine does not contain the exact dedicated JSON/SOL pair");
  }
  const quarantineHashes = quarantineFiles.map((name) => hashFile(path.join(quarantine, name)));
  const expectedTargetHashes = new Set(reportTwo.cloneLifecycle.release.targetEnd.artifacts
    .map((entry) => `sha256:${entry.sha256}`));
  if (quarantineHashes.some((entry) => !expectedTargetHashes.has(entry.sha256))) {
    fail("quarantined dedicated clone differs from the released target evidence");
  }
  const labels = [labelOne, labelTwo].map((label, index) => ({
    encounterId: packet.encounters[index].encounterId,
    equivalentHumanoidCount: label.count,
    equivalentHumanoidLevel: label.level,
    humanStatement: label.statement,
    pressureTags: [],
    confidence: null,
    abnormalReported: null,
  }));
  const submittedAt = options.submittedAt || new Date().toISOString();
  if (Number.isNaN(Date.parse(submittedAt)) || new Date(submittedAt).toISOString() !== submittedAt) {
    fail("--submitted-at must be a canonical ISO-8601 timestamp");
  }
  const response = {
    schema: "arena-calibration.pve-equivalence-response.v1",
    packetId: packet.packetId,
    packetHash: packet.packetHash,
    calibrationObjective: "monster_group_to_humanoid_mercenary_equivalence",
    evidenceStatus: "human_equivalence_labels_complete",
    telemetryCompleteness: "equivalence_only",
    labels,
    evidenceRefs: [reportHashes[0].sha256, reportHashes[1].sha256,
      `sha256:${encounterOne.screenshot.sha256}`, `sha256:${encounterTwo.screenshot.sha256}`],
    cleanup: {
      sourceSaveSha256: sourceHash,
      sourceSaveUnchanged: true,
      nonTargetSaveUniverseUnchanged: true,
      activeDedicatedSlotArtifacts: 0,
      runtimeProcessCount: 0,
      cloneLockPresent: false,
      recoveryRecordPresent: false,
      quarantinedDedicatedArtifactHashes: quarantineHashes.map((entry) => entry.sha256),
    },
    submittedAt,
    responseHash: "",
  };
  response.responseHash = sha256OfValue(Object.fromEntries(
    Object.entries(response).filter(([key]) => key !== "responseHash")));
  assertSchemaInstance(response.schema, response, "human PVE equivalence response");
  fs.mkdirSync(options.outputDir, { recursive: true });
  atomicWriteJson(path.join(options.outputDir, "pve-equivalence-response.json"), response);
  return { response, reportHashes, quarantineHashes, activeTarget, lock };
}

function checkContract() {
  const parsed = parseArgs(["--count-one", "1", "--level-one", "10",
    "--count-two", "2", "--level-two", "20", "--statement-one", "one",
    "--statement-two", "two", "--submitted-at", "2026-08-27T12:03:54.458Z"]);
  validateLabel(parsed.countOne, parsed.levelOne, parsed.statementOne, "fixture one");
  validateLabel(parsed.countTwo, parsed.levelTwo, parsed.statementTwo, "fixture two");
  if (new Date(parsed.submittedAt).toISOString() !== parsed.submittedAt) {
    fail("submittedAt parser contract failed");
  }
  process.stdout.write(`${JSON.stringify({ ok: true, check: "finalize-human-pve-contract",
    calibrationObjective: "monster_group_to_humanoid_mercenary_equivalence" })}\n`);
}

function main(argv) {
  const options = parseArgs(argv);
  if (options.help) return process.stdout.write(`${usage()}\n`);
  if (options.check) return checkContract();
  const result = finalize(options);
  process.stdout.write(`${JSON.stringify({ ok: true,
    responseHash: result.response.responseHash,
    evidenceStatus: result.response.evidenceStatus,
    telemetryCompleteness: result.response.telemetryCompleteness,
    labels: result.response.labels.map((entry) => ({ encounterId: entry.encounterId,
      equivalentHumanoidCount: entry.equivalentHumanoidCount,
      equivalentHumanoidLevel: entry.equivalentHumanoidLevel })),
    cleanup: result.response.cleanup,
  }, null, 2)}\n`);
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
}

module.exports = { finalize, parseArgs, validateLabel };
