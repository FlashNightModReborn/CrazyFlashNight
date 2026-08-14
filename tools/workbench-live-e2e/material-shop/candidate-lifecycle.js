"use strict";

const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const RuntimeGuard = require("../lib/runtime-guard");
const { loadSharedAdapter } = require("../npc/shared-adapter");
const Applicability = require("./applicability");
const Common = require("./common");

const INTERNAL_OWNED_BASE = path.join("tmp", "workbench-live-e2e", "material-shop");
const LIFECYCLE_SCHEMA = "workbench-live-e2e.material-shop.lifecycle-preparation.v2";
const LEGACY_SAVE_STATE_SCHEMA = "workbench-live-e2e.material-shop.sealed-save-state.v1";
const SAVE_STATE_SCHEMA = "workbench-live-e2e.material-shop.sealed-save-state.v2";
const SAVE_STAGES = Object.freeze(["baseline", "archive", "restart"]);
const ORDER_INSENSITIVE_SOURCE_CACHE_KEYS = Object.freeze(new Set([
  "completedChallengeQuests",
  "discoveredEnemies",
  "discoveredQuests",
  "discoveredStages",
]));

function validSave(data) {
  const player = data && data["0"];
  return !!data && data.version === "3.0" && Array.isArray(player)
    && player.length >= 14 && player[0] != null && player[0] !== ""
    && Array.isArray(data["1"]) && !!data.inventory && !!data.collection;
}

function noRuntime() {
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  return true;
}

function ensureDirectory(directory) {
  if (!fs.existsSync(directory)) fs.mkdirSync(directory, { recursive: true });
  return Evidence.assertExactDirectory(directory, "clone_prepare");
}

function evidenceDirectory(evidenceRoot, evidenceRunDir, runId) {
  const root = path.resolve(evidenceRoot || "");
  const runDir = path.resolve(evidenceRunDir || "");
  const expected = path.resolve(root, Common.OWNED_BASE_RELATIVE, "runs", String(runId || ""));
  if (runDir.toLowerCase() !== expected.toLowerCase()) {
    Common.fail("material_shop_save_evidence_directory_invalid", "save_state",
      "sealed save bytes must stay inside the exact canonical A5 run directory");
  }
  return Evidence.assertExactDirectory(runDir, "save_state");
}

function saveProjection(save, itemName) {
  const money = Number(save && save["0"] && save["0"][2]);
  const owned = Applicability.materialOwnedFromSave(save, itemName);
  if (!Number.isFinite(money) || Math.floor(money) !== money || money < 0) {
    Common.fail("material_shop_save_money_invalid", "save_state",
      "sealed save has no valid non-negative integer balance");
  }
  return { money, owned };
}

function semanticSaveProjection(value, trail) {
  const pathTrail = trail || [];
  if (Array.isArray(value)) {
    const projected = value.map((entry, index) =>
      semanticSaveProjection(entry, pathTrail.concat(String(index))));
    const key = pathTrail.length > 0 ? pathTrail[pathTrail.length - 1] : "";
    if (pathTrail.length === 3 && pathTrail[0] === "others"
        && pathTrail[1] === "物品来源缓存"
        && ORDER_INSENSITIVE_SOURCE_CACHE_KEYS.has(key)) {
      if (projected.some((entry) => typeof entry !== "string")) {
        Common.fail("material_shop_save_semantic_source_cache_invalid", "save_state",
          "registered order-insensitive source-cache values must be strings");
      }
      projected.sort((left, right) => left < right ? -1 : left > right ? 1 : 0);
    }
    return projected;
  }
  if (value && typeof value === "object") {
    const projected = {};
    Object.keys(value).forEach((key) => {
      if (pathTrail.length === 0 && key === "lastSaved") return;
      const child = value[key];
      if (pathTrail.length === 2 && pathTrail[0] === "others"
          && pathTrail[1] === "物品来源缓存"
          && ORDER_INSENSITIVE_SOURCE_CACHE_KEYS.has(key) && !Array.isArray(child)) {
        Common.fail("material_shop_save_semantic_source_cache_invalid", "save_state",
          "registered order-insensitive source-cache values must be arrays");
      }
      projected[key] = semanticSaveProjection(child, pathTrail.concat(key));
    });
    return projected;
  }
  return value;
}

function saveSemanticSha256(save) {
  return Evidence.sha256Text(Evidence.canonicalJson(semanticSaveProjection(save, [])));
}

function captureSaveStateArtifact(options) {
  const settings = options || {};
  const stage = String(settings.stage || "");
  if (!SAVE_STAGES.includes(stage) || !Common.ID_RE.test(String(settings.slot || ""))
      || typeof settings.itemName !== "string" || settings.itemName.length < 1) {
    Common.fail("material_shop_save_state_arguments_invalid", "save_state",
      "save-state capture requires one frozen stage, slot, and material identity");
  }
  const runDir = evidenceDirectory(settings.evidenceRoot, settings.evidenceRunDir,
    settings.runId);
  const set = CloneGuard.captureSlotArtifactSet({ root: settings.resourcesRoot,
    appData: settings.appData, slot: settings.slot, requireJson: true });
  const sourcePath = CloneGuard.saveJsonPath(settings.resourcesRoot, settings.slot);
  const source = Evidence.readExactRegularFile(sourcePath, {
    phase: "save_state", maximumBytes: 128 * 1024 * 1024,
  });
  const jsonArtifact = set.artifacts.find((entry) => entry.kind === "json");
  if (!jsonArtifact || jsonArtifact.sha256 !== source.sha256
      || jsonArtifact.bytes !== source.length) {
    Common.fail("material_shop_save_state_set_drift", "save_state",
      "JSON bytes differ from the exact JSON/SOL target artifact set");
  }
  let parsed;
  try { parsed = JSON.parse(source.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_save_state_json_invalid", "save_state", error.message); }
  if (!validSave(parsed)) Common.fail("material_shop_save_state_json_invalid", "save_state",
    "sealed target save is not a valid CF7 save");
  const projection = saveProjection(parsed, settings.itemName);
  const directory = ensureDirectory(path.join(runDir, "save-state-artifacts"));
  const destination = path.join(directory, "target-" + stage + ".json");
  fs.writeFileSync(destination, source.bytes, { flag: "wx", mode: 0o600 });
  const sealed = Evidence.readExactRegularFile(destination, {
    phase: "save_state", maximumBytes: 128 * 1024 * 1024,
  });
  if (sealed.sha256 !== source.sha256 || sealed.length !== source.length) {
    Common.fail("material_shop_save_state_copy_drift", "save_state",
      "run evidence did not preserve the exact save JSON bytes");
  }
  const value = { schema: SAVE_STATE_SCHEMA, capturedAt: new Date().toISOString(),
    stage, slot: settings.slot, itemName: settings.itemName,
    relativePath: path.relative(runDir, sealed.path).replace(/\\/g, "/"),
    bytes: sealed.length, sha256: sealed.sha256, artifactSetSha256: set.setSha256,
    money: projection.money, owned: projection.owned };
  value.stateSha256 = Evidence.sha256Text(Evidence.canonicalJson({ slot: value.slot,
    itemName: value.itemName, money: value.money, owned: value.owned }));
  value.semanticSha256 = saveSemanticSha256(parsed);
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function verifySaveStateArtifact(runDirInput, value, expectedStage, expectedSlot,
  expectedItemName) {
  const legacy = value && value.schema === LEGACY_SAVE_STATE_SCHEMA;
  const keys = ["schema", "capturedAt", "stage", "slot", "itemName", "relativePath",
    "bytes", "sha256", "artifactSetSha256", "money", "owned", "stateSha256"];
  if (!legacy) keys.push("semanticSha256");
  keys.push("evidenceSha256");
  Common.exactKeys(value, keys, "material_shop_save_state_invalid", "save_state");
  const unsigned = Object.assign({}, value);
  delete unsigned.evidenceSha256;
  const runDir = path.resolve(runDirInput);
  const expectedPath = path.join(runDir, "save-state-artifacts",
    "target-" + expectedStage + ".json");
  const actualPath = path.resolve(runDir, String(value.relativePath || "").replace(/\//g, path.sep));
  if (![LEGACY_SAVE_STATE_SCHEMA, SAVE_STATE_SCHEMA].includes(value.schema)
      || value.stage !== expectedStage
      || value.slot !== expectedSlot || value.itemName !== expectedItemName
      || !Number.isFinite(Date.parse(value.capturedAt))
      || actualPath.toLowerCase() !== expectedPath.toLowerCase()
      || !Evidence.pathInside(runDir, actualPath)
      || !Number.isInteger(value.bytes) || value.bytes < 1
      || !Common.SHA256_RE.test(String(value.sha256 || ""))
      || !Common.SHA256_RE.test(String(value.artifactSetSha256 || ""))
      || value.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_save_state_invalid", "save_state",
      "sealed save-state receipt is malformed or detached");
  }
  const file = Evidence.readExactRegularFile(actualPath, {
    phase: "save_state", maximumBytes: 128 * 1024 * 1024,
  });
  if (file.sha256 !== value.sha256 || file.length !== value.bytes) {
    Common.fail("material_shop_save_state_byte_drift", "save_state",
      "sealed save JSON bytes changed after live capture");
  }
  let parsed;
  try { parsed = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_save_state_json_invalid", "save_state", error.message); }
  if (!validSave(parsed)) Common.fail("material_shop_save_state_json_invalid", "save_state",
    "sealed evidence is not a valid CF7 save");
  const projection = saveProjection(parsed, expectedItemName);
  const stateSha256 = Evidence.sha256Text(Evidence.canonicalJson({ slot: expectedSlot,
    itemName: expectedItemName, money: projection.money, owned: projection.owned }));
  const semanticSha256 = saveSemanticSha256(parsed);
  if (projection.money !== value.money || projection.owned !== value.owned
      || value.stateSha256 !== stateSha256
      || (!legacy && (value.semanticSha256 !== semanticSha256
        || !Common.SHA256_RE.test(String(value.semanticSha256 || ""))))) {
    Common.fail("material_shop_save_state_projection_drift", "save_state",
      "self-reported projection or semantic digest differs from exact JSON bytes");
  }
  return { receipt: value, parsed, projection, semanticSha256 };
}

function importSeed(canonicalRoot, resourcesRoot, sourceFixtureSlot, seedSlot,
  expectedSourceSha256) {
  if (sourceFixtureSlot !== Common.SOURCE_FIXTURE_SLOT
      || !Common.SEED_SLOT_RE.test(String(seedSlot || ""))) {
    Common.fail("material_shop_seed_mapping_invalid", "clone_prepare",
      "only the frozen b4 source may be copied into one dedicated A5 seed slot");
  }
  const source = CloneGuard.saveJsonPath(canonicalRoot, sourceFixtureSlot);
  const sourceFile = Evidence.readExactRegularFile(source, {
    phase: "clone_prepare", maximumBytes: 128 * 1024 * 1024,
  });
  let parsed;
  try { parsed = JSON.parse(sourceFile.bytes.toString("utf8")); }
  catch (error) { Common.fail("material_shop_seed_json_invalid", "clone_prepare", error.message); }
  if (!validSave(parsed)) Common.fail("material_shop_seed_contract_invalid", "clone_prepare", "seed save is not valid");
  if (expectedSourceSha256 && sourceFile.sha256 !== expectedSourceSha256) {
    Common.fail("material_shop_seed_source_drift", "clone_prepare",
      "source fixture JSON changed after applicability capture");
  }
  const saves = ensureDirectory(path.join(resourcesRoot, "saves"));
  const destination = path.join(saves, seedSlot + ".json");
  if (fs.existsSync(destination)) Common.fail("material_shop_seed_destination_exists", "clone_prepare", "materialized seed already exists");
  fs.copyFileSync(sourceFile.path, destination, fs.constants.COPYFILE_EXCL);
  const copied = Evidence.readExactRegularFile(destination, {
    phase: "clone_prepare", maximumBytes: 128 * 1024 * 1024,
  });
  if (copied.sha256 !== sourceFile.sha256 || copied.length !== sourceFile.length) {
    Common.fail("material_shop_seed_copy_mismatch", "clone_prepare", "isolated seed bytes changed");
  }
  return { sourceFixtureSlot, dedicatedSeedSlot: seedSlot,
    transformId: "exact-byte-copy", sourcePath: sourceFile.path, destination: copied.path,
    sourceSha256: sourceFile.sha256, destinationSha256: copied.sha256,
    bytes: copied.length };
}

function prepareRecovery(resourcesRoot, runDir, seedSlot, recoverySlot, appData) {
  const lock = CloneGuard.acquireCloneLock({ root: resourcesRoot, slot: recoverySlot,
    runDir, ownedBaseRelative: INTERNAL_OWNED_BASE });
  let preparation;
  try {
    preparation = CloneGuard.prepareDedicatedClone({
      root: resourcesRoot, appData, runDir, ownedBaseRelative: INTERNAL_OWNED_BASE,
      seedSlot, targetSlot: recoverySlot, lock, validateSeed: validSave,
      validateTarget: validSave, transformId: "exact-byte-copy",
    });
    const released = CloneGuard.releaseDedicatedClone({ preparation, lock, appData });
    return { preparation, released,
      artifactSet: CloneGuard.captureSlotArtifactSet({
        root: resourcesRoot, appData, slot: recoverySlot, requireJson: true,
      }) };
  } catch (error) {
    try { CloneGuard.releaseCloneLock(lock); } catch (_releaseError) {}
    throw error;
  }
}

async function prepare(options) {
  const settings = options || {};
  const productionRoot = Common.assertCanonicalRoot(
    settings.canonicalRoot || Common.CANONICAL_ROOT);
  const resourcesRoot = path.resolve(settings.resourcesRoot);
  Evidence.assertExactDirectory(resourcesRoot, "clone_prepare");
  if (resourcesRoot.toLowerCase() !== productionRoot.toLowerCase()) {
    Common.fail("material_shop_lifecycle_production_root_invalid", "clone_prepare",
      "materialized lifecycle production and mutation roots must be the same exact worktree");
  }
  const slots = Common.assertDedicatedSlots(settings.seedSlot,
    settings.targetSlot, settings.recoverySlot);
  if (!process.env.APPDATA) Common.fail("appdata_root_missing", "clone_prepare", "APPDATA is required");
  const appData = Evidence.assertExactDirectory(path.resolve(process.env.APPDATA), "clone_prepare");
  const applicability = Applicability.validateApplicability(settings.applicability);
  const fixtureAuthority = Applicability.replayFixtureAuthorityBinding(
    settings.fixtureAuthorityBinding, applicability, { resourcesRoot, appData });
  const sourceFixtureRoot = fixtureAuthority.root;
  const sourceJson = applicability.sourceFixture.artifacts.find((entry) => entry.kind === "json");
  if (!sourceJson) Common.fail("material_shop_source_fixture_incomplete", "clone_prepare",
    "applicability artifact lacks the source fixture JSON");
  const internalBase = ensureDirectory(path.join(resourcesRoot, INTERNAL_OWNED_BASE));
  const lifecycleRun = ensureDirectory(path.join(internalBase, String(settings.runId)));
  const recoveryRun = ensureDirectory(path.join(lifecycleRun, "recovery"));
  const targetRun = ensureDirectory(path.join(lifecycleRun, "target"));
  let seedImport;
  let recovery;
  const resolved = RuntimeGuard.resolveCandidateIdentityBeforeMutation({
    root: resourcesRoot, candidateRoot: path.resolve(settings.candidateRoot),
    assertNoRuntime: noRuntime,
    prepareClone() {
      seedImport = importSeed(sourceFixtureRoot, resourcesRoot, Common.SOURCE_FIXTURE_SLOT,
        slots.seedSlot, sourceJson.sha256);
      recovery = prepareRecovery(resourcesRoot, recoveryRun,
        slots.seedSlot, slots.recoverySlot, appData);
      return { seedSha256: seedImport.destinationSha256,
        recoverySetSha256: recovery.artifactSet.setSha256 };
    },
  });
  const adapter = loadSharedAdapter(resourcesRoot, {
    ownedBaseRelative: INTERNAL_OWNED_BASE,
    returnFullArchiveEvidence: true,
  });
  const journey = await adapter.prepare({
    candidateRoot: settings.candidateRoot,
    slot: slots.targetSlot,
    seedSlot: slots.seedSlot,
    runDir: targetRun,
  });
  const evidenceRunDir = evidenceDirectory(settings.evidenceRoot,
    settings.evidenceRunDir, settings.runId);
  const targetItemName = applicability.selectedUnlockedTarget.itemName;
  const baselineSaveState = captureSaveStateArtifact({ resourcesRoot, appData,
    evidenceRoot: settings.evidenceRoot, evidenceRunDir, runId: settings.runId,
    slot: slots.targetSlot, itemName: targetItemName, stage: "baseline" });
  const value = {
    schema: LIFECYCLE_SCHEMA,
    preparedAt: new Date().toISOString(),
    resourcesRoot,
    fixtureAuthorityBinding: JSON.parse(JSON.stringify(fixtureAuthority.binding)),
    candidateIdentity: RuntimeGuard.publicCandidateIdentity(resolved.identity),
    slots,
    seedImport,
    recoveryBaseline: recovery.artifactSet,
    recoveryLockReleased: recovery.released.lockRelease.lockFileAbsent === true,
    targetClone: JSON.parse(JSON.stringify(journey.clone)),
    baselineSaveState,
  };
  value.preparationSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return {
    evidence: value,
    journey,
    async captureRecoveryInvariant() {
      const current = CloneGuard.captureSlotArtifactSet({
        root: resourcesRoot, appData, slot: slots.recoverySlot, requireJson: true,
      });
      CloneGuard.assertArtifactSetInvariant(recovery.artifactSet, current,
        "material_shop_recovery_changed");
      return current;
    },
    async captureTargetSaveState(stage) {
      return captureSaveStateArtifact({ resourcesRoot, appData,
        evidenceRoot: settings.evidenceRoot, evidenceRunDir, runId: settings.runId,
        slot: slots.targetSlot, itemName: targetItemName, stage });
    },
  };
}

module.exports = {
  INTERNAL_OWNED_BASE,
  LEGACY_SAVE_STATE_SCHEMA,
  LIFECYCLE_SCHEMA,
  SAVE_STATE_SCHEMA,
  SAVE_STAGES,
  captureSaveStateArtifact,
  evidenceDirectory,
  importSeed,
  noRuntime,
  prepare,
  prepareRecovery,
  saveSemanticSha256,
  saveProjection,
  semanticSaveProjection,
  validSave,
  verifySaveStateArtifact,
};
