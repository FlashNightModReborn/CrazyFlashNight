#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const ArenaCustomMatchCode = require("../../launcher/web/modules/arena-custom-match-code");
const { createPvePacket } = require("./lib/campaign-evaluation");
const { readJsonFile, sha256OfValue } = require("./lib/arena-calibration-core");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");
const { isValidSaveData } = require("../workbench-live-e2e/kshop/generic-opener");

const DEFAULT_TARGET_SLOT = "cf7_agent_arena_pve_review";

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    snapshot: null,
    completionReceipt: null,
    runtimeArtifact: null,
    candidateId: null,
    seedSave: null,
    seedSlot: null,
    targetSlot: DEFAULT_TARGET_SLOT,
    outputDir: null,
    targetActiveMinutes: 8,
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--snapshot") options.snapshot = path.resolve(argv[++index]);
    else if (token === "--completion-receipt") options.completionReceipt = path.resolve(argv[++index]);
    else if (token === "--runtime-artifact") options.runtimeArtifact = path.resolve(argv[++index]);
    else if (token === "--candidate-id") options.candidateId = String(argv[++index]);
    else if (token === "--seed-save") options.seedSave = path.resolve(argv[++index]);
    else if (token === "--seed-slot") options.seedSlot = String(argv[++index]);
    else if (token === "--target-slot") options.targetSlot = String(argv[++index]);
    else if (token === "--output-dir") options.outputDir = path.resolve(argv[++index]);
    else if (token === "--target-active-minutes") options.targetActiveMinutes = Number(argv[++index]);
    else if (token === "--check") options.check = true;
    else if (token === "--help" || token === "-h") options.help = true;
    else fail(`unknown argument: ${token}`);
  }
  if (!Number.isInteger(options.targetActiveMinutes) || options.targetActiveMinutes < 5 || options.targetActiveMinutes > 10) {
    fail("--target-active-minutes must be an integer from 5 to 10");
  }
  if (!/^cf7_agent_[A-Za-z0-9_-]+$/.test(options.targetSlot)) fail("--target-slot must be a dedicated cf7_agent_* slot");
  if (options.seedSlot && !/^[A-Za-z0-9_-]+$/.test(options.seedSlot)) fail("--seed-slot is invalid");
  return options;
}

function usage() {
  return [
    "Usage: node tools/arena-calibration/build-pve-readiness.js --snapshot <json> --completion-receipt <json> --runtime-artifact <json>",
    "  --candidate-id <id> --seed-save <json> --seed-slot <slot> --output-dir <dir>",
    "  [--target-slot cf7_agent_arena_pve_review] [--target-active-minutes 8]",
    "  --check  Validate the packet/code builder without writing artifacts",
  ].join("\n");
}

function sha256Bytes(bytes) {
  return `sha256:${crypto.createHash("sha256").update(bytes).digest("hex")}`;
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function stableKey(value) {
  return ArenaCustomMatchCode.stableStringify(value || null);
}

function compressRoster(roster) {
  const grouped = new Map();
  (roster || []).forEach((unit) => {
    const id = ArenaCustomMatchCode.normalizeUnitId(unit.type);
    if (!Number.isInteger(id) || id < 0 || !Number.isInteger(unit.level) || unit.level < 1) {
      throw new Error("candidate roster contains an invalid unit");
    }
    const parameters = unit.parameters && Object.keys(unit.parameters).length > 0
      ? JSON.parse(JSON.stringify(unit.parameters)) : null;
    const key = `${id}\u0000${unit.level}\u0000${stableKey(parameters)}`;
    if (!grouped.has(key)) grouped.set(key, { id, type: `兵种${id}`, level: unit.level, count: 0, parameters });
    grouped.get(key).count += 1;
  });
  return Array.from(grouped.values()).map((entry) => {
    if (!entry.parameters) delete entry.parameters;
    return entry;
  });
}

function buildEncounterCode(roster, sourceCase, seed) {
  const compressed = compressRoster(roster);
  const value = {
    mode: "pve",
    seed,
    enemyRoster: compressed,
    player: "current",
    timeoutFrames: ArenaCustomMatchCode.DEFAULT_TIMEOUT_FRAMES,
    spawnDistance: sourceCase.spawnDistance,
    blueFormation: sourceCase.blueFormation,
    redFormation: sourceCase.redFormation,
    formationSpacing: sourceCase.formationSpacing,
  };
  const matchCode = ArenaCustomMatchCode.serializeMatchCode(value);
  const parsed = ArenaCustomMatchCode.parseMatchCode(matchCode);
  if (parsed.canonical !== matchCode || parsed.mode !== "pve" || parsed.player !== "current") {
    throw new Error("PVE match code did not round-trip canonically");
  }
  ["deposit", "reward", "money", "exp", "drop"].forEach((field) => {
    if (Object.prototype.hasOwnProperty.call(parsed.enterPayload, field)) {
      throw new Error(`PVE enter payload unexpectedly contains economy field ${field}`);
    }
  });
  return {
    matchCode,
    matchCodeSha256: sha256Bytes(Buffer.from(matchCode, "utf8")),
    roster: compressed,
    enterPayload: parsed.enterPayload,
  };
}

function buildPlayerProfile(seedBytes, seedData, seedSlot, targetSlot) {
  if (!isValidSaveData(seedData)) throw new Error("selected player build save does not satisfy the runtime clone contract");
  const player = seedData["0"];
  const equipment = seedData.inventory && seedData.inventory["装备栏"];
  if (!Array.isArray(player) || !equipment) throw new Error("selected player build lacks player/equipment projection");
  const saveSha256 = sha256Bytes(seedBytes);
  const buildProjection = {
    role: player[0],
    level: Number(player[3]),
    maxHp: Number(player[8]),
    equipment,
  };
  const buildProjectionSha256 = sha256OfValue(buildProjection);
  return {
    profileId: `approved-human-pve-${String(player[0]).replace(/[^A-Za-z0-9_-]/g, "role")}-lv${Number(player[3])}-${saveSha256.slice(7, 19)}`,
    approvalBasis: "operator requested advancement to one 5-10 minute human PVE review",
    seedSlot,
    targetSlot,
    clonePolicy: "exact-byte-copy; source remains read-only; target is isolated and disposable",
    saveSha256,
    saveBytes: seedBytes.length,
    role: player[0],
    level: Number(player[3]),
    maxHp: Number(player[8]),
    equipmentSlotCount: Object.keys(equipment).length,
    buildProjectionSha256,
  };
}

function buildArtifacts(options, snapshot, completionReceipt, runtimeArtifact, seedBytes, seedData, createdAt) {
  const catalog = (snapshot.caseCatalog || []).find((entry) => entry.candidateId === options.candidateId);
  const evidence = (snapshot.candidateEvidence || []).find((entry) => entry.candidateId === options.candidateId);
  if (!catalog || !evidence) throw new Error("selected candidate is absent from the frozen snapshot");
  if (!completionReceipt || completionReceipt.outcome !== "accepted"
      || completionReceipt.decisionSnapshotId !== snapshot.decisionSnapshotId
      || !completionReceipt.acceptedActionIds.includes(`complete-${options.candidateId}`)) {
    throw new Error("accepted completion receipt is not bound to the selected candidate/snapshot");
  }
  const runtimeIdentity = runtimeArtifact && runtimeArtifact.runtimeIdentity;
  if (!runtimeIdentity || runtimeIdentity.verified !== true || runtimeIdentity.runtimeMode !== "formal_runtime"
      || runtimeArtifact.protectedSaveUnchanged !== true
      || runtimeArtifact.battleSemanticsCohortId !== snapshot.runtimeCohort.battleSemanticsCohortId) {
    throw new Error("runtime artifact is not a protected, verified formal-runtime member of the frozen cohort");
  }
  const playerProfile = buildPlayerProfile(seedBytes, seedData, options.seedSlot, options.targetSlot);
  const sourceCase = catalog.caseTemplate;
  const candidateIds = {
    blue: `${options.candidateId}-roster-blue`,
    red: `${options.candidateId}-roster-red`,
  };
  const candidates = [
    { candidateId: candidateIds.blue, evidenceRef: evidence.completionGateRef },
    { candidateId: candidateIds.red, evidenceRef: evidence.completionGateRef },
  ];
  const packetId = `pve-${options.candidateId}-20260827-a`;
  const generated = createPvePacket({
    packetId,
    campaignId: snapshot.campaignId,
    candidatePairId: `${options.candidateId}-two-rosters`,
    candidates,
    holdoutCandidateId: candidateIds.red,
    playerBuildProfiles: [playerProfile.profileId],
    targetActiveMinutes: options.targetActiveMinutes,
    createdAt,
  });
  const codeByCandidate = new Map([
    [candidateIds.blue, buildEncounterCode(sourceCase.blueRoster, sourceCase, 27082701)],
    [candidateIds.red, buildEncounterCode(sourceCase.redRoster, sourceCase, 27082702)],
  ]);
  const mappingByEncounter = new Map(generated.secretMapping.mappings.map((entry) => [entry.encounterId, entry]));
  const privateEncounters = generated.packet.encounters.map((encounter) => {
    const mapping = mappingByEncounter.get(encounter.encounterId);
    const code = codeByCandidate.get(mapping.candidateId);
    return { ...encounter, candidateId: mapping.candidateId, evidenceRef: mapping.evidenceRef, ...code };
  });
  const publicCard = {
    schema: "arena-calibration.human-pve-card.v1",
    packetId: generated.packet.packetId,
    packetHash: generated.packet.packetHash,
    playerBuildProfile: playerProfile.profileId,
    targetActiveMinutes: generated.packet.targetActiveMinutes,
    hardLimitMinutes: generated.packet.hardLimitMinutes,
    runtimeIdentity: {
      runtimeMode: runtimeIdentity.runtimeMode,
      coreSha256: runtimeIdentity.coreSha256,
      buildIdentity: runtimeIdentity.buildIdentity,
      payloadClosure: runtimeIdentity.payloadClosure,
    },
    encounterOrder: privateEncounters.map((entry) => ({
      encounterId: entry.encounterId,
      candidateAlias: entry.candidateAlias,
      matchCode: entry.matchCode,
      matchCodeSha256: entry.matchCodeSha256,
    })),
    operatorInstructions: [
      "使用已准备的隔离存档，不要改装备或使用消耗品。",
      "按 encounterOrder 顺序各完成一场；两场合计目标 5-10 分钟，15 分钟硬停止。",
      "每场结束记录该怪物组合约等效于几名、多少级的人形佣兵；最多补两个压力标签和可选信心。",
      "玩家 build 只是保持固定量程的测量工具；不要把是否能击败当前玩家直接当作怪物档位。",
      "任何进场失败、明显卡死、掉落/经验/金钱变化都标记 abnormal 并停止。",
    ],
    telemetryBoundary: "runtime session timing is automatic; combat totals and subjective labels require the human checkpoint until production PVE telemetry exists",
    status: "ready_for_runtime_preflight",
    createdAt,
    cardHash: "",
  };
  publicCard.cardHash = sha256OfValue(withoutHash(publicCard, "cardHash"));
  const privatePlan = {
    schema: "arena-calibration.pve-runtime-plan.v1",
    packetId: generated.packet.packetId,
    packetHash: generated.packet.packetHash,
    candidateId: options.candidateId,
    candidateCaseHash: evidence.caseHash,
    completionGateRef: evidence.completionGateRef,
    completionReceiptId: completionReceipt.receiptId,
    playerBuild: playerProfile,
    encounters: privateEncounters,
    targetSlot: options.targetSlot,
    seedSlot: options.seedSlot,
    sourceSavePath: options.seedSave,
    runtimeIdentityRequired: {
      ...runtimeIdentity,
      executionArtifactIdentity: snapshot.runtimeCohort.executionArtifactIdentity,
      battleSemanticsCohortId: snapshot.runtimeCohort.battleSemanticsCohortId,
      sourceExecutionArtifactHash: runtimeArtifact.artifactHash,
    },
    createdAt,
    planHash: "",
  };
  privatePlan.planHash = sha256OfValue(withoutHash(privatePlan, "planHash"));
  return { packet: generated.packet, mapping: generated.secretMapping, publicCard, privatePlan };
}

function checkContract() {
  const sourceCase = {
    blueRoster: [{ type: "兵种13", level: 10 }, { type: "兵种13", level: 10 }],
    redRoster: [{ type: "兵种7", level: 25, parameters: { threatThreshold: 15 } }],
    spawnDistance: 650,
    blueFormation: "line",
    redFormation: "line",
    formationSpacing: 54,
  };
  const blue = buildEncounterCode(sourceCase.blueRoster, sourceCase, 1);
  const red = buildEncounterCode(sourceCase.redRoster, sourceCase, 2);
  if (blue.roster[0].count !== 2 || red.enterPayload.roster[0].parameters.threatThreshold !== 15) {
    throw new Error("PVE readiness fixture did not preserve count/parameter payload");
  }
  process.stdout.write(`${JSON.stringify({ ok: true, check: "pve-readiness-contract", encounterCodes: 2,
    calibrationObjective: "monster_group_to_humanoid_mercenary_equivalence" })}\n`);
}

function main(argv) {
  const options = parseArgs(argv);
  if (options.help) return process.stdout.write(`${usage()}\n`);
  if (options.check) return checkContract();
  ["snapshot", "completionReceipt", "runtimeArtifact", "candidateId", "seedSave", "seedSlot", "outputDir"].forEach((field) => {
    if (!options[field]) fail(`--${field.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)} is required`);
  });
  const snapshot = readJsonFile(options.snapshot);
  const completionReceipt = readJsonFile(options.completionReceipt);
  const runtimeArtifact = readJsonFile(options.runtimeArtifact);
  const seedBytes = fs.readFileSync(options.seedSave);
  const seedData = JSON.parse(seedBytes.toString("utf8"));
  const createdAt = new Date().toISOString();
  const artifacts = buildArtifacts(options, snapshot, completionReceipt, runtimeArtifact, seedBytes, seedData, createdAt);
  fs.mkdirSync(path.join(options.outputDir, "private"), { recursive: true });
  writeJsonAtomic(path.join(options.outputDir, "pve-packet.json"), artifacts.packet);
  writeJsonAtomic(path.join(options.outputDir, "human-pve-card.json"), artifacts.publicCard);
  writeJsonAtomic(path.join(options.outputDir, "private", "pve-mapping.json"), artifacts.mapping);
  writeJsonAtomic(path.join(options.outputDir, "private", "pve-runtime-plan.json"), artifacts.privatePlan);
  process.stdout.write(`${JSON.stringify({
    ok: true,
    packetHash: artifacts.packet.packetHash,
    cardHash: artifacts.publicCard.cardHash,
    planHash: artifacts.privatePlan.planHash,
    playerBuild: artifacts.privatePlan.playerBuild,
    encounterCount: artifacts.packet.encounters.length,
    targetActiveMinutes: artifacts.packet.targetActiveMinutes,
    hardLimitMinutes: artifacts.packet.hardLimitMinutes,
  }, null, 2)}\n`);
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = error.isUsageError ? 2 : 1;
  }
}

module.exports = { buildArtifacts, buildEncounterCode, buildPlayerProfile, compressRoster, parseArgs };
