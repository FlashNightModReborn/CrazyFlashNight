"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const cp = require("child_process");
const { ROOT, bindSources, create } = require("./elite-arena-plan");
const { resolveExpectedRuntimeIdentity, assertRuntimeIdentity } = require("../lib/runtime-process-identity");

function read(file) {
  return JSON.parse(fs.readFileSync(path.toNamespacedPath(file), "utf8").replace(/^\uFEFF/, ""));
}
function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(path.toNamespacedPath(file), `${JSON.stringify(value, null, 2)}\n`, { flag: "wx" });
}
function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(path.toNamespacedPath(file))).digest("hex");
}
function opponent(protocol, id) {
  const result = protocol.matchRules.primaryOpponents.find((entry) => entry.unitId === id);
  if (!result) throw Error(`Unregistered opponent ${id}`);
  return result;
}
function buildCampaign(protocol, revision) {
  if (protocol.schema !== "cf6-soldier.elite-arena-protocol.v1") throw Error("Unexpected elite protocol");
  if (!/^[a-z][a-z0-9-]{0,15}$/.test(revision || "")) throw Error("A fresh bounded revision is required");
  const counts = Object.fromEntries(protocol.phases.map((entry) => [entry.phase, entry.runsPerArmPerOpponent]));
  const batches = [];
  function add(phase, includeInSummary, target, side, variants) {
    if (!variants.length || variants.some((entry) => entry.count !== variants[0].count)) throw Error("Balanced arms required");
    const size = Math.max(1, Math.floor(10 / variants.length));
    for (let repeat = 1; repeat <= variants[0].count; repeat += size) {
      const rows = variants.map(({ variant, count, ...options }) => ({
        ...options,
        id: `${variant}-${target.unitId}-${side}-${batches.length}`,
        pairKey: `${target.unitId}|${side}|${batches.length}`,
        variant,
        opponentId: target.unitId,
        opponentWeapon: target.opponentWeapon,
        opponentLevel: 60,
        level: 60,
        weapon: "M4A1战术版",
        side,
        distance: 650,
        timeoutFrames: 1800,
        repeat: Math.min(size, count - repeat + 1),
      }));
      const index = batches.filter((batch) => batch.phase === phase && batch.opponentId === target.unitId).length;
      const expectedRows = rows.reduce((sum, row) => sum + row.repeat, 0);
      if (expectedRows > 10) throw Error("A manifest exceeds the bounded batch size");
      batches.push({ id: `elite-${revision}-${phase}-${target.unitId}-${index}`, phase,
        includeInSummary, opponentId: target.unitId, comparisons: rows, expectedRows,
        worstCaseMs: expectedRows * 60000 });
    }
  }
  for (const target of protocol.matchRules.primaryOpponents) {
    add("smoke", false, target, "red", [{ variant: "ordinary", count: counts.smoke }, { variant: "elite", count: counts.smoke }]);
    add("exploration", false, target, "red", [{ variant: "ordinary", count: counts.exploration }, { variant: "elite", count: counts.exploration }]);
    add("confirmation", true, target, "red", [{ variant: "ordinary", count: counts.confirmation }, { variant: "elite", count: counts.confirmation }]);
  }
  for (const ablation of protocol.ablations) {
    if (ablation.comparison === "same toughness") {
      add("same-toughness", true, opponent(protocol, 449), "red", [
        { variant: "ordinary", count: ablation.runsPerArm, sidearm: "FR506", sidearm2: "FR506", toughnessCoefficient: 50 },
        { variant: "elite", count: ablation.runsPerArm },
      ]);
    } else if (ablation.comparison === "sidearm") {
      add("sidearm", true, opponent(protocol, 449), "red", [
        { variant: "elite", count: ablation.runsPerArm }, { variant: "noSidearm", count: ablation.runsPerArm },
      ]);
    } else if (ablation.comparison === "mobility and brain") {
      add("mobility", true, opponent(protocol, 465), "red", [
        { variant: "elite", count: ablation.runsPerArmPerVariant },
        { variant: "stationary", count: ablation.runsPerArmPerVariant },
        { variant: "ordinaryBrain", count: ablation.runsPerArmPerVariant },
      ]);
    } else if (ablation.comparison === "shield boundary") {
      add("shield", true, opponent(protocol, 465), "red", [
        { variant: "shieldOrdinary", count: ablation.runsPerArm }, { variant: "shieldElite", count: ablation.runsPerArm },
      ]);
    } else if (ablation.comparison === "side swap") {
      for (const target of protocol.matchRules.primaryOpponents) {
        add("side-swap", true, target, "blue", [
          { variant: "ordinary", count: ablation.runsPerArmPerOpponent }, { variant: "elite", count: ablation.runsPerArmPerOpponent },
        ]);
      }
    } else throw Error(`Unregistered ablation ${ablation.comparison}`);
  }
  return batches;
}
function generate(protocolPath, revision, candidateRoot, outputRoot) {
  const protocol = read(protocolPath);
  const batches = buildCampaign(protocol, revision);
  const identity = resolveExpectedRuntimeIdentity(ROOT, candidateRoot);
  if (identity.runtimeMode !== "isolated_candidate") throw Error("An exact isolated candidate is required");
  if (fs.existsSync(outputRoot)) throw Error(`Preserve the prior campaign: ${outputRoot}`);
  const sourceBindings = bindSources();
  const queue = {
    schema: "cf6-soldier.elite-arena-campaign.v1",
    revision,
    protocolPath: path.resolve(protocolPath),
    protocolSha256: sha256(protocolPath),
    seedSlot: protocol.execution.seedSlot,
    candidateRoot,
    runtimeIdentity: identity,
    executionLog: path.join(outputRoot, "execution.jsonl"),
    batches: [],
  };
  for (const batch of batches) {
    const directory = path.join(outputRoot, batch.id);
    const result = create({ candidateRoot, outputDirectory: directory, batchId: batch.id,
      comparisons: batch.comparisons }, { sourceBindings });
    queue.batches.push({ ...batch, directory, slot: result.slot,
      manifestPath: result.manifestPath,
      evidenceConfigPath: path.join(directory, "evidence-config.json"),
      beforePath: path.join(directory, "before.json"),
      afterPath: path.join(directory, "before-after.json") });
  }
  const planPath = path.join(outputRoot, "campaign.json");
  write(planPath, queue);
  return { planPath, batches: queue.batches.length,
    rows: queue.batches.reduce((sum, batch) => sum + batch.expectedRows, 0),
    candidateRoot, candidateExecuted: false };
}
function execute(command, args, logPath, spawnSync = cp.spawnSync) {
  const result = spawnSync(command, args, { cwd: ROOT, encoding: "utf8", windowsHide: false,
    maxBuffer: 32 * 1024 * 1024, env: { ...process.env, NODE_PATH: path.join(ROOT, "tools/arena-calibration/node_modules") } });
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  fs.writeFileSync(logPath, output);
  if (result.error) throw result.error;
  return { status: result.status, output };
}
function reportOutput(output) {
  for (let start = output.lastIndexOf("{"); start >= 0; start = output.lastIndexOf("{", start - 1)) {
    for (let end = output.indexOf("}", start); end >= 0; end = output.indexOf("}", end + 1)) {
      try {
        const report = JSON.parse(output.slice(start, end + 1));
        if (typeof report.report === "string" && report.resultPath !== undefined) {
          return { reportPath: path.resolve(ROOT, report.report), report };
        }
      } catch (_) {}
    }
  }
  throw Error("The foreground runner did not emit a report path");
}
function runCampaign(planPath, only) {
  const queue = read(planPath);
  if (queue.protocolSha256 !== sha256(queue.protocolPath)) throw Error("Protocol changed after plan generation");
  assertRuntimeIdentity(queue.runtimeIdentity, resolveExpectedRuntimeIdentity(ROOT, queue.candidateRoot));
  const selected = only ? new Set(only.split(",")) : null;
  const batches = queue.batches.filter((batch) => !selected || selected.has(batch.id) || selected.has(batch.phase));
  if (!batches.length) throw Error("No batches selected");
  const previous = fs.existsSync(queue.executionLog)
    ? fs.readFileSync(queue.executionLog, "utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse) : [];
  for (const batch of batches) {
    if (previous.some((entry) => entry.batchId === batch.id)) throw Error(`Batch was already executed: ${batch.id}`);
    let record = { batchId: batch.id, phase: batch.phase, includeInSummary: batch.includeInSummary, qualified: false };
    try {
      const beforeArgs = [path.join(ROOT, "tools/cf6-soldier-assets/foreground-evidence.js"), "before", batch.evidenceConfigPath, batch.beforePath];
      if (execute(process.execPath, beforeArgs, path.join(batch.directory, "before.log")).status !== 0) throw Error("Before evidence failed");
      const runArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(ROOT, "tools/cf6-bladebot-assets/run-foreground.ps1"),
        "-ResourceRoot", ROOT, "-CandidateRoot", queue.candidateRoot, "-Manifest", batch.manifestPath,
        "-Slot", batch.slot, "-SeedSlot", queue.seedSlot, "-BatchTimeoutMs", "900000"];
      const output = execute("powershell.exe", runArgs, path.join(batch.directory, "run.log"));
      const parsed = reportOutput(output.output);
      const afterArgs = [path.join(ROOT, "tools/cf6-soldier-assets/foreground-evidence.js"), "after", batch.beforePath, parsed.reportPath];
      const afterExecution = execute(process.execPath, afterArgs, path.join(batch.directory, "after.log"));
      const after = read(batch.afterPath);
      record = { ...record, runReportPath: parsed.reportPath, resultPath: after.resultPath,
        afterPath: batch.afterPath, status: parsed.report.status, exitCode: output.status,
        qualified: after.qualified === true, allNatural: after.allNatural, naturalTimeoutCount: after.naturalTimeoutCount };
      if (output.status !== 0 || afterExecution.status !== 0 || !record.qualified) throw Error("Unqualified combat cohort");
    } catch (error) {
      record.error = error.message;
      fs.appendFileSync(queue.executionLog, `${JSON.stringify(record)}\n`);
      throw error;
    }
    fs.appendFileSync(queue.executionLog, `${JSON.stringify(record)}\n`);
    console.log(JSON.stringify(record));
  }
}
function summaryConfig(planPath) {
  const queue = read(planPath);
  const entries = fs.readFileSync(queue.executionLog, "utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse);
  const expected = new Set(queue.batches.filter((batch) => batch.includeInSummary).map((batch) => batch.id));
  const cohorts = entries.filter((entry) => entry.qualified && entry.includeInSummary).map((entry) => ({
    cohortId: entry.batchId, manifestPath: queue.batches.find((batch) => batch.id === entry.batchId).manifestPath,
    resultPath: entry.resultPath,
  }));
  if (cohorts.length !== expected.size || new Set(cohorts.map((entry) => entry.cohortId)).size !== expected.size) {
    throw Error("Incomplete or unqualified confirmation cohorts");
  }
  const output = path.join(path.dirname(planPath), "summary-config.json");
  write(output, { cohorts, bootstrap: { iterations: 10000, seed: 20261017 }, minimumPairsPerLayer: 30 });
  return output;
}
if (require.main === module) {
  const [mode, ...args] = process.argv.slice(2);
  try {
    if (mode === "--check") {
      const batches = buildCampaign(read(args[0]), args[1] || "r04");
      console.log(JSON.stringify({ ok: true, batches: batches.length,
        rows: batches.reduce((sum, batch) => sum + batch.expectedRows, 0), candidateExecuted: false }, null, 2));
    } else if (mode === "--generate") {
      console.log(JSON.stringify(generate(path.resolve(args[0]), args[1], path.resolve(args[2]), path.resolve(args[3])), null, 2));
    } else if (mode === "--run") {
      runCampaign(path.resolve(args[0]), args[1]);
    } else if (mode === "--summary") {
      console.log(summaryConfig(path.resolve(args[0])));
    } else {
      throw Error("Usage: --check protocol.json [revision] | --generate protocol.json revision candidateRoot outputRoot | --run campaign.json [phase|batchId,...] | --summary campaign.json");
    }
  } catch (error) {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  }
}
module.exports = { buildCampaign, reportOutput, execute };
