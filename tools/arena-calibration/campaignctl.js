#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  readJsonFile,
} = require("./lib/arena-calibration-core");
const {
  createIdleGrant,
  createProducerRegistry,
} = require("./lib/campaign-resource-arbiter");
const {
  CampaignSupervisor,
} = require("./lib/campaign-supervisor");
const {
  DurableCampaignJournal,
  writeJsonAtomic,
} = require("./lib/durable-campaign-journal");

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  if (argv.length === 0) return { command: "help" };
  const args = {
    command: argv[0],
    projectRoot: path.resolve(__dirname, "../.."),
    journalRoot: null,
    campaignId: null,
    config: null,
    registry: null,
    grant: null,
    observations: null,
    outputDir: null,
    shardId: null,
    manifest: null,
    result: null,
    runReport: null,
    attention: null,
    allowPartial: false,
    complete: null,
    gateFPlanHash: null,
    battleSemanticsCohortId: null,
    changedPaths: [],
    reason: null,
    shardKind: "unattended",
  };
  for (let index = 1; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--project-root") args.projectRoot = path.resolve(argv[++index]);
    else if (token === "--journal-root") args.journalRoot = path.resolve(argv[++index]);
    else if (token === "--campaign-id") args.campaignId = argv[++index];
    else if (token === "--config") args.config = path.resolve(argv[++index]);
    else if (token === "--registry") args.registry = path.resolve(argv[++index]);
    else if (token === "--grant") args.grant = path.resolve(argv[++index]);
    else if (token === "--observations") args.observations = path.resolve(argv[++index]);
    else if (token === "--output-dir") args.outputDir = path.resolve(argv[++index]);
    else if (token === "--shard-id") args.shardId = argv[++index];
    else if (token === "--shard-kind") args.shardKind = argv[++index];
    else if (token === "--manifest") args.manifest = argv[++index];
    else if (token === "--result") args.result = argv[++index];
    else if (token === "--run-report") args.runReport = argv[++index];
    else if (token === "--attention") args.attention = argv[++index];
    else if (token === "--allow-partial") args.allowPartial = true;
    else if (token === "--complete") args.complete = true;
    else if (token === "--gate-f-plan-hash") args.gateFPlanHash = argv[++index];
    else if (token === "--battle-semantics-cohort") args.battleSemanticsCohortId = argv[++index];
    else if (token === "--changed-paths") args.changedPaths = String(argv[++index] || "").split(",").map((value) => value.trim()).filter(Boolean);
    else if (token === "--reason") args.reason = argv[++index];
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/campaignctl.js <command> [options]

Commands:
  issue-grant  Create a hash-bound producer registry and short-lived local idleGrant.
  init         Create/resume a provisional campaign under a valid idleGrant.
  schedule     Durably schedule one shard.
  import       Validate and durably commit one completed shard exactly once.
  pause        Pause the campaign, close the segment, and release the writer lease.
  status       Rebuild state from the journal without trusting checkpoint.json.

Shared options:
  --campaign-id <id>
  --journal-root <path>
  --registry <json> --grant <json>

issue-grant:
  --observations <json-array> --output-dir <dir>

init:
  --config <json>

schedule:
  --shard-id <id> --manifest <project-relative path>

import:
  --shard-id <id> --manifest <path> --result <path> --run-report <path>
  --attention <json> --battle-semantics-cohort <id> [--changed-paths <a,b>]
  [--allow-partial] [--complete] [--gate-f-plan-hash <sha256>]
`);
}

function requireValue(args, field) {
  if (!args[field]) fail(`--${field.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)} is required`);
  return args[field];
}

function supervisorFor(args) {
  requireValue(args, "campaignId");
  return new CampaignSupervisor({
    projectRoot: args.projectRoot,
    journalRoot: args.journalRoot || path.join(args.projectRoot, "logs/arena-calibration/campaigns"),
    campaignId: args.campaignId,
  });
}

function readGrantInputs(args) {
  return {
    registry: readJsonFile(requireValue(args, "registry")),
    grant: readJsonFile(requireValue(args, "grant")),
  };
}

function issueGrant(args) {
  const observations = readJsonFile(requireValue(args, "observations"));
  if (!Array.isArray(observations)) fail("--observations must contain a JSON array");
  const outputDir = requireValue(args, "outputDir");
  fs.mkdirSync(outputDir, { recursive: true });
  const now = new Date().toISOString();
  const registry = createProducerRegistry(observations, {
    registryId: `registry-${now.replace(/[^0-9]/g, "").slice(0, 17)}`,
    generatedAt: now,
    observationTtlSeconds: 60,
  });
  const grant = createIdleGrant(registry, {
    grantId: `grant-${now.replace(/[^0-9]/g, "").slice(0, 17)}`,
    issuedAt: now,
    ttlSeconds: 120,
  });
  const registryPath = path.join(outputDir, "producer-registry.json");
  const grantPath = path.join(outputDir, "idle-grant.json");
  writeJsonAtomic(registryPath, registry);
  writeJsonAtomic(grantPath, grant);
  return { registryPath, grantPath, registryHash: registry.registryHash, grantHash: grant.grantHash, expiresAt: grant.expiresAt };
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.command === "help" || args.command === "--help" || args.command === "-h") return printHelp();
  if (args.command === "issue-grant") return console.log(JSON.stringify({ ok: true, ...issueGrant(args) }, null, 2));

  if (args.command === "status") {
    requireValue(args, "campaignId");
    const journal = new DurableCampaignJournal({
      root: args.journalRoot || path.join(args.projectRoot, "logs/arena-calibration/campaigns"),
      campaignId: args.campaignId,
    });
    journal.recover({ repairTail: false });
    return console.log(JSON.stringify({ ok: true, ...journal.snapshot() }, null, 2));
  }

  const supervisor = supervisorFor(args);
  if (args.command === "pause") {
    const result = supervisor.pause(args.reason || "operator_requested_process_boundary", { resourcesReleased: true });
    return console.log(JSON.stringify({ ok: true, ...result.snapshot }, null, 2));
  }

  const { registry, grant } = readGrantInputs(args);
  if (args.command === "init") {
    const config = readJsonFile(requireValue(args, "config"));
    const result = supervisor.initialize(config, registry, grant);
    supervisor.release("command_complete");
    return console.log(JSON.stringify({ ok: true, ...result }, null, 2));
  }

  supervisor.acquire({ allowStaleRecovery: true });
  supervisor.resume(registry, grant, args.command);
  if (args.command === "schedule") {
    const manifest = supervisor.scheduleShard({
      shardId: requireValue(args, "shardId"),
      shardKind: args.shardKind,
      manifestPath: requireValue(args, "manifest"),
    });
    const result = { ok: true, campaignId: args.campaignId, shardId: args.shardId, manifestHash: manifest.manifestHash };
    supervisor.release("command_complete");
    return console.log(JSON.stringify(result, null, 2));
  }
  if (args.command === "import") {
    const result = supervisor.importShard({
      shardId: requireValue(args, "shardId"),
      shardKind: args.shardKind,
      manifestPath: requireValue(args, "manifest"),
      resultPath: requireValue(args, "result"),
      runReportPath: requireValue(args, "runReport"),
      attentionMeasurement: readJsonFile(requireValue(args, "attention")),
      allowPartial: args.allowPartial,
      complete: args.complete,
      gateFPlanHash: args.gateFPlanHash,
      battleSemanticsCohortId: requireValue(args, "battleSemanticsCohortId"),
      changedPaths: args.changedPaths,
      compatible: true,
    });
    supervisor.release("command_complete");
    return console.log(JSON.stringify({
      ok: true,
      artifactId: result.artifact.artifactId,
      artifactHash: result.artifact.artifactHash,
      accepted: result.disposition.accepted,
      acceptedRows: result.disposition.acceptedCount,
      duplicateRowsExcluded: result.disposition.duplicateCount,
      attentionEventId: result.attention.event.eventId,
      attentionMeasurementId: result.attention.measurement.measurementId,
    }, null, 2));
  }
  supervisor.release("unknown_command");
  fail(`unknown command: ${args.command}`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exit(error.isUsageError ? 2 : 1);
}
