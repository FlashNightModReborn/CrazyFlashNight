"use strict";

const {
  AUTHORITY_BINDING_SCHEMA,
  TOKEN_REF_RE,
  deepClone,
  fail,
  verifyRecordChain,
} = require("./common");
const { canonicalJson, isPlainObject, sha256Text } = require("../lib/evidence-artifact");
const IdentityFixture = require("../../equipment-tuning/fixtures/item-identity-triple.json");

const TUNING_FIRST = ["snapshot", "preview", "preview", "commit", "snapshot", "detach"];
const TUNING_RESTART = ["snapshot", "detach"];
const INVENTORY_FIRST = ["snapshot", "snapshot"];
const INVENTORY_RESTART = ["snapshot"];
const CROSS_DOMAIN_FIRST = [
  "equipment_tuning:snapshot", "inventory:snapshot",
  "equipment_tuning:preview", "equipment_tuning:preview",
  "equipment_tuning:commit", "inventory:snapshot",
  "equipment_tuning:snapshot", "equipment_tuning:detach",
];
const CROSS_DOMAIN_RESTART = [
  "equipment_tuning:snapshot", "inventory:snapshot", "equipment_tuning:detach",
];
const ALLOWED_OPERATIONS = new Set(["install_mod"]);
const OPAQUE_RE = /^[A-Za-z0-9._~-]{1,128}$/;
const EQUIPMENT_KEYS = Object.freeze([
  "name", "displayName", "icon", "type", "use", "level", "tier", "mods",
  "lastUpdate", "maxLevel", "hardMaxLevel",
]);
const MOD_CANDIDATE_KEYS = Object.freeze([
  "candidateKey", "itemName", "displayName", "icon", "owned", "installed",
  "available", "availabilityCode", "reason", "replaceableFrom", "grade",
  "gradeLabel", "gradeColor", "scope", "scopeLabel", "role", "roleLabel", "symbol",
]);
const FLASH_ACTIONS = Object.freeze({
  equipment_tuning: Object.freeze({
    snapshot: "equipmentTuningSnapshot",
    preview: "equipmentTuningPreview",
    commit: "equipmentTuningCommit",
    detach: "equipmentTuningDetach",
  }),
  inventory: Object.freeze({ snapshot: "inventorySnapshot" }),
});
const DIAGNOSTIC_KEYS = Object.freeze([
  "type", "scope", "sequence", "event", "cmd", "operation", "capability", "phase",
  "webCallId", "panelInstanceId", "viewSessionId", "sourceKeyRef", "candidateKey",
  "intentKeyRef", "reconcileAfterCallId", "pendingCount", "tokenPresent", "commitReady",
  "confirmationMode", "autoCommitPending", "writeState", "success",
  "transactionIdPresent", "requiresReconcile", "currentLeasePresent", "needsReconcile",
  "reconciled", "noOp", "mismatchFields",
]);
const DIAGNOSTIC_SEQUENCE = Object.freeze([
  "candidate_hit", "preview_issued", "preview_adopted",
  "candidate_hit", "preview_issued", "preview_adopted",
  "commit_issued", "commit_adopted", "inventory_refresh_settled",
]);

function exactKeys(value, required, optional, code, phase) {
  if (!isPlainObject(value)) fail(code, phase, "expected one exact object");
  const actual = Object.keys(value).sort();
  const allowed = new Set((required || []).concat(optional || []));
  if ((required || []).some((key) => !Object.prototype.hasOwnProperty.call(value, key))
      || actual.some((key) => !allowed.has(key))) {
    fail(code, phase, "object keys do not match the closed contract", { actual, required, optional });
  }
  return value;
}

function safeText(value, minimum, maximum) {
  const lower = minimum == null ? 1 : minimum;
  return typeof value === "string" && value.length >= lower
    && value.length <= (maximum || 512) && !/[\u0000-\u001f\u007f]/.test(value);
}

function identityText(value, maximum) {
  return safeText(value, 1, maximum || 256) && value.trim().length > 0
    && value.trim().toLowerCase() !== "undefined";
}

function exactStringArray(value, maximumCount, maximumLength, code, phase, opaque) {
  if (!Array.isArray(value) || value.length > maximumCount
      || value.some((entry) => !(opaque ? OPAQUE_RE.test(entry) : safeText(entry, 1, maximumLength)))
      || new Set(value).size !== value.length) {
    fail(code, phase, "string array is malformed, duplicated, or outside its production bound");
  }
  return value.slice();
}

function identityTriple(value, phase, code) {
  if (!isPlainObject(value) || !identityText(value.itemName || value.name, 256)
      || !identityText(value.displayName, 256) || !identityText(value.icon, 256)) {
    fail(code || "identity_triple_invalid", phase, "item identity triple is missing or malformed", { value });
  }
  return {
    itemName: String(value.itemName || value.name),
    displayName: value.displayName,
    icon: value.icon,
  };
}

function sameIdentity(left, right) {
  return left.itemName === right.itemName && left.displayName === right.displayName
    && left.icon === right.icon;
}

function sourceRef(value, phase) {
  exactKeys(value, ["sourceKind", "containerId", "slot", "expectedLease"], [],
    "source_ref_invalid", phase);
  if (value.sourceKind !== "inventory" || value.containerId !== "背包"
      || !Number.isInteger(value.slot) || value.slot < 0 || value.slot > 49
      || !TOKEN_REF_RE.test(value.expectedLease || "")) {
    fail("inventory_source_required", phase, "Equipment v2 admits one inventory source only", { value });
  }
  return {
    sourceKind: "inventory",
    containerId: value.containerId,
    slot: value.slot,
    expectedLease: value.expectedLease,
  };
}

function sameCoordinate(left, right) {
  return left && right && left.sourceKind === "inventory" && right.sourceKind === "inventory"
    && left.containerId === right.containerId && left.slot === right.slot;
}

function sameSourceAuthority(left, right) {
  return sameCoordinate(left, right) && left.expectedLease === right.expectedLease;
}

function requireBefore(left, right, code, phase, message) {
  if (!left || !right || !(left.sequence < right.sequence)) {
    fail(code, phase, message, {
      left: left && left.sequence,
      right: right && right.sequence,
    });
  }
}

function equipmentLeaf(value, phase) {
  if (!isPlainObject(value)) fail("equipment_leaf_invalid", phase, "equipment leaf is missing");
  exactKeys(value, EQUIPMENT_KEYS, ["modSlotCapacity"], "equipment_leaf_invalid", phase);
  const identity = identityTriple(value, phase, "equipment_identity_invalid");
  const mods = exactStringArray(value.mods, 64, 256, "equipment_leaf_invalid", phase, false);
  if (!["武器", "防具"].includes(value.type) || !safeText(value.use, 1, 128)
      || !safeText(value.tier, 0, 128)
      || !Number.isInteger(value.level) || value.level < 1
      || !Number.isInteger(value.maxLevel) || value.maxLevel < 1
      || !Number.isInteger(value.hardMaxLevel) || value.hardMaxLevel < 1
      || value.maxLevel > value.hardMaxLevel || value.level > value.hardMaxLevel
      || !Number.isFinite(value.lastUpdate) || value.lastUpdate < 0
      || value.lastUpdate > Number.MAX_SAFE_INTEGER
      || (Object.prototype.hasOwnProperty.call(value, "modSlotCapacity")
        && (!Number.isInteger(value.modSlotCapacity) || value.modSlotCapacity < 0
          || value.modSlotCapacity > 64))) {
    fail("equipment_leaf_invalid", phase, "equipment state is malformed", { value });
  }
  return Object.assign(identity, {
    type: value.type,
    use: value.use,
    level: value.level,
    tier: value.tier == null ? "" : String(value.tier),
    mods,
    modSlotCapacity: value.modSlotCapacity == null ? null : Number(value.modSlotCapacity),
    lastUpdate: Number(value.lastUpdate),
    raw: deepClone(value),
  });
}

function candidateLeaf(candidate, isMod, phase) {
  const allowed = isMod ? MOD_CANDIDATE_KEYS
    : ["candidateKey", "itemName", "displayName", "icon", "tierName", "owned",
      "available", "reason"];
  const required = isMod
    ? ["candidateKey", "itemName", "displayName", "icon", "owned", "installed",
      "available", "availabilityCode", "reason", "replaceableFrom", "grade", "scope", "role"]
    : allowed;
  exactKeys(candidate, required, allowed.filter((key) => !required.includes(key)),
    isMod ? "mod_candidate_invalid" : "tier_candidate_invalid", phase);
  const identity = identityTriple(candidate, phase,
    isMod ? "mod_candidate_invalid" : "tier_candidate_invalid");
  if (!OPAQUE_RE.test(candidate.candidateKey || "")
      || !Number.isInteger(candidate.owned) || candidate.owned < 0
      || typeof candidate.available !== "boolean" || !safeText(candidate.reason, 0, 256)) {
    fail(isMod ? "mod_candidate_invalid" : "tier_candidate_invalid", phase,
      "candidate selector, ownership, availability, or reason is malformed");
  }
  if (isMod) {
    exactStringArray(candidate.replaceableFrom, 512, 128,
      "mod_candidate_invalid", phase + ".replaceableFrom", true);
    if (typeof candidate.installed !== "boolean"
        || !Number.isInteger(candidate.availabilityCode)
        || candidate.availabilityCode < -100 || candidate.availabilityCode > 100
        || !safeText(candidate.grade, 1, 64) || !safeText(candidate.scope, 1, 64)
        || !safeText(candidate.role, 1, 64)
        || ["gradeLabel", "gradeColor", "scopeLabel", "roleLabel", "symbol"]
          .some((key) => candidate[key] != null && !safeText(candidate[key], 1, 128))) {
      fail("mod_candidate_invalid", phase, "mod candidate metadata is malformed");
    }
  } else if (!safeText(candidate.tierName, 1, 64)) {
    fail("tier_candidate_invalid", phase, "tier candidate metadata is malformed");
  }
  return Object.assign(identity, {
    candidateKey: candidate.candidateKey,
    available: candidate.available,
    owned: candidate.owned,
    installed: isMod ? candidate.installed : false,
    raw: deepClone(candidate),
  });
}

function projection(value, phase) {
  exactKeys(value, ["source"], [], "projection_invalid", phase);
  exactKeys(value.source, ["source", "equipment"], [], "projection_source_invalid", phase);
  const source = sourceRef(value.source.source, phase);
  const equipment = equipmentLeaf(value.source.equipment, phase);
  return { source, equipment, raw: deepClone(value) };
}

function snapshot(value, phase) {
  exactKeys(value, ["gender", "source", "equipment", "enhance", "tierCandidates",
    "modCandidates", "materials", "materialRevision", "inventoryRevision"], [],
  "tuning_snapshot_invalid", phase);
  if (!["男", "女"].includes(value.gender) || !isPlainObject(value.enhance)
      || !Array.isArray(value.tierCandidates) || !Array.isArray(value.modCandidates)
      || !Array.isArray(value.materials) || !Number.isInteger(value.materialRevision)
      || value.materialRevision < 0 || !Number.isInteger(value.inventoryRevision)
      || value.inventoryRevision < 0) {
    fail("tuning_snapshot_invalid", phase, "tuning snapshot shape is malformed");
  }
  const source = sourceRef(value.source, phase);
  const equipment = equipmentLeaf(value.equipment, phase);
  exactKeys(value.enhance, ["currentLevel", "maxLevel", "availableMaxLevel", "hardMaxLevel"],
    [], "tuning_snapshot_invalid", phase + ".enhance");
  if (![value.enhance.currentLevel, value.enhance.maxLevel, value.enhance.availableMaxLevel,
    value.enhance.hardMaxLevel].every((entry) => Number.isInteger(entry) && entry >= 1)
      || value.enhance.currentLevel !== equipment.level
      || value.enhance.maxLevel !== value.enhance.availableMaxLevel
      || value.enhance.maxLevel !== value.equipment.maxLevel
      || value.enhance.hardMaxLevel !== value.equipment.hardMaxLevel) {
    fail("tuning_snapshot_invalid", phase, "enhance projection does not bind equipment levels");
  }
  const tierCandidates = value.tierCandidates.map((candidate, index) =>
    candidateLeaf(candidate, false, phase + ".tierCandidates[" + index + "]"));
  const candidates = value.modCandidates.map((candidate, index) =>
    candidateLeaf(candidate, true, phase + ".modCandidates[" + index + "]"));
  if (new Set(candidates.map((entry) => entry.candidateKey)).size !== candidates.length
      || new Set(candidates.map((entry) => entry.itemName)).size !== candidates.length) {
    fail("mod_candidate_duplicate", phase, "candidate keys/internal identities must be unique");
  }
  const materialNames = new Set();
  const materials = value.materials.map((material, index) => {
    exactKeys(material, ["itemName", "displayName", "icon", "count"], [],
      "snapshot_material_invalid", phase + ".materials[" + index + "]");
    const identity = identityTriple(material, phase + ".materials[" + index + "]");
    if (!Number.isInteger(material.count) || material.count < 0
        || materialNames.has(identity.itemName)) {
      fail("snapshot_material_invalid", phase, "snapshot material count is malformed", { material });
    }
    materialNames.add(identity.itemName);
    return Object.assign(identity, { count: material.count, raw: deepClone(material) });
  });
  const installed = candidates.filter((candidate) => candidate.installed)
    .map((candidate) => candidate.itemName).sort();
  if (canonicalJson(installed) !== canonicalJson(equipment.mods.slice().sort())) {
    fail("tuning_snapshot_invalid", phase,
      "installed candidate set does not equal the equipment mod set");
  }
  return { source, equipment, tierCandidates, candidates, materials,
    materialRevision: value.materialRevision, inventoryRevision: value.inventoryRevision,
    raw: deepClone(value) };
}

function materialPlan(values, phase) {
  if (!Array.isArray(values) || values.length < 1 || values.length > 512) {
    fail("material_plan_invalid", phase, "material plan must be one bounded non-empty array");
  }
  const names = new Set();
  return values.map((value, index) => {
    exactKeys(value, ["itemName", "displayName", "icon", "before", "delta", "after"], [],
      "material_plan_invalid", phase + "[" + index + "]");
    const identity = identityTriple(value, phase + "[" + index + "]");
    if (!Number.isInteger(value.before) || value.before < 0 || !Number.isInteger(value.delta)
        || value.delta === 0 || !Number.isInteger(value.after) || value.after < 0
        || value.before + value.delta !== value.after || names.has(identity.itemName)) {
      fail("material_plan_invalid", phase, "material arithmetic is not exact", { value });
    }
    names.add(identity.itemName);
    return Object.assign(identity, {
      before: value.before,
      delta: value.delta,
      after: value.after,
      raw: deepClone(value),
    });
  });
}

function requestEnvelope(message, phase) {
  if (!isPlainObject(message) || message.type !== "panel" || message.panel !== "workbench"
      || !safeText(message.domain, 1, 80) || !safeText(message.cmd, 1, 80)
      || !safeText(message.callId, 1, 160) || !safeText(message.panelInstanceId, 1, 160)
      || !isPlainObject(message.payload)) {
    fail("request_envelope_invalid", phase, "panel request envelope is malformed", { message });
  }
  exactKeys(message, ["type", "panel", "domain", "cmd", "callId", "panelInstanceId", "payload"],
    [], "request_envelope_invalid", phase);
  if (message.domain === "equipment_tuning" && !safeText(message.payload.viewSessionId, 1, 160)) {
    fail("request_view_session_invalid", phase, "tuning request lacks exact viewSessionId");
  }
  if (message.domain === "equipment_tuning") {
    const keys = message.cmd === "snapshot" ? ["v", "viewSessionId", "source"]
      : message.cmd === "preview" ? ["v", "viewSessionId", "operation", "source", "candidateKey"]
        : message.cmd === "commit" ? ["v", "viewSessionId", "expectedTuningToken"]
          : message.cmd === "detach" ? ["v", "viewSessionId"] : [];
    if (!keys.length || message.payload.v !== 1) {
      fail("request_payload_invalid", phase, "unexpected Equipment command payload");
    }
    exactKeys(message.payload, keys, [], "request_payload_invalid", phase);
  } else if (message.domain !== "inventory" || message.cmd !== "snapshot"
      || message.payload.v !== 1 || !Array.isArray(message.payload.requests)) {
    fail("request_payload_invalid", phase, "unexpected Inventory command payload");
  } else {
    exactKeys(message.payload, ["v", "requests"], [], "request_payload_invalid", phase);
    if (message.payload.requests.length < 1 || message.payload.requests.length > 4) {
      fail("request_payload_invalid", phase,
        "Inventory snapshot must request one bounded production window set");
    }
    const containers = new Set();
    message.payload.requests.forEach((window, index) => {
      exactKeys(window, ["containerId", "offset", "limit", "filterKey"],
        ["scope", "filterSpec"], "request_payload_invalid", phase + ".requests[" + index + "]");
      const scope = window.scope == null ? "all" : window.scope;
      if (!["背包", "仓库", "战备箱"].includes(window.containerId)
          || containers.has(window.containerId)
          || !Number.isInteger(window.offset) || window.offset < 0
          || !Number.isInteger(window.limit) || window.limit < 1 || window.limit > 100
          || !["all", "weapon", "armor", "consumable", "material", "other"]
            .includes(window.filterKey)
          || !["all", "equipment"].includes(scope)
          || (scope === "equipment" && window.containerId !== "背包")
          || (window.filterSpec != null && !isPlainObject(window.filterSpec))) {
        fail("request_payload_invalid", phase,
          "Inventory snapshot window is not one production-valid projection", { index });
      }
      containers.add(window.containerId);
    });
  }
  return message;
}

function responseEnvelope(message, request, phase) {
  if (!isPlainObject(message) || message.type !== "panel_resp" || message.panel !== "workbench"
      || message.domain !== request.domain || message.cmd !== request.cmd
      || message.callId !== request.callId || message.panelInstanceId !== request.panelInstanceId
      || message.success !== true) {
    fail("response_envelope_invalid", phase, "response does not exactly bind its request", {
      request, message,
    });
  }
  if (request.domain === "equipment_tuning"
      && message.viewSessionId !== request.payload.viewSessionId) {
    fail("response_view_session_invalid", phase, "response crossed tuning view session");
  }
  const base = ["type", "panel", "domain", "cmd", "callId", "panelInstanceId", "success"];
  if (request.domain === "equipment_tuning") {
    const fields = request.cmd === "snapshot" ? ["v", "viewSessionId", "writeEpoch", "snapshot"]
      : request.cmd === "preview" ? ["v", "viewSessionId", "writeEpoch", "operation",
        "tuningToken", "noOp", "canCommit", "before", "after", "materials", "removedMods"]
        : request.cmd === "commit" ? ["v", "viewSessionId", "writeEpoch", "operation",
          "tuningToken", "transactionId", "noOp", "canCommit", "before", "after",
          "materials", "removedMods", "snapshot", "inventorySnapshots"]
          : request.cmd === "detach" ? ["v", "viewSessionId", "writeEpoch"] : [];
    if (!fields.length || message.v !== 1 || !Number.isInteger(message.writeEpoch)
        || message.writeEpoch < 0) {
      fail("response_fields_invalid", phase,
        "successful Equipment response lacks its exact production generation fields");
    }
    exactKeys(message, base.concat(fields), [], "response_fields_invalid", phase);
  } else {
    if (request.domain !== "inventory" || request.cmd !== "snapshot" || message.v !== 1
        || !safeText(message.sessionNonce, 1, 128) || !Array.isArray(message.snapshots)) {
      fail("response_fields_invalid", phase,
        "successful Inventory response lacks its exact production snapshot fields");
    }
    exactKeys(message, base.concat(["v", "sessionNonce", "snapshots"]), [],
      "response_fields_invalid", phase);
  }
  return message;
}

function previewResponse(message, request, phase) {
  responseEnvelope(message, request, phase);
  if (!ALLOWED_OPERATIONS.has(message.operation) || message.operation !== request.payload.operation
      || !TOKEN_REF_RE.test(message.tuningToken || "") || message.noOp !== false
      || message.canCommit !== true || !Array.isArray(message.removedMods)) {
    fail("preview_response_invalid", phase, "preview authority is incomplete or not committable", { message });
  }
  const removedMods = exactStringArray(message.removedMods, 64, 256,
    "preview_response_invalid", phase + ".removedMods", false);
  const before = projection(message.before, phase + ".before");
  const after = projection(message.after, phase + ".after");
  const materials = materialPlan(message.materials, phase + ".materials");
  return {
    operation: message.operation,
    tokenRef: message.tuningToken,
    candidateKey: request.payload.candidateKey,
    before,
    after,
    materials,
    removedMods,
    raw: deepClone(message),
  };
}

function commitResponse(message, request, phase) {
  responseEnvelope(message, request, phase);
  if (!ALLOWED_OPERATIONS.has(message.operation) || !TOKEN_REF_RE.test(message.tuningToken || "")
      || !TOKEN_REF_RE.test(message.transactionId || "") || message.noOp !== false
      || message.canCommit !== false || !isPlainObject(message.snapshot)) {
    fail("commit_response_invalid", phase, "commit authority/poststate is incomplete", { message });
  }
  const removedMods = exactStringArray(message.removedMods, 64, 256,
    "commit_response_invalid", phase + ".removedMods", false);
  return {
    operation: message.operation,
    tokenRef: message.tuningToken,
    transactionRef: message.transactionId,
    before: projection(message.before, phase + ".before"),
    after: projection(message.after, phase + ".after"),
    materials: materialPlan(message.materials, phase + ".materials"),
    removedMods,
    snapshot: snapshot(message.snapshot, phase + ".snapshot"),
    raw: deepClone(message),
  };
}

function snapshotResponse(message, request, phase) {
  responseEnvelope(message, request, phase);
  if (!isPlainObject(message.snapshot)) fail("snapshot_response_invalid", phase, "snapshot response lacks authority");
  return snapshot(message.snapshot, phase + ".snapshot");
}

function messageEvents(transcript, kind, domain) {
  return transcript.events.filter((event) => event.kind === kind && isPlainObject(event.message)
    && event.message.domain === domain).map((event) => ({ event, message: event.message }));
}

function exactCommandList(records, expected, phase, domain) {
  const commands = records.map((entry) => entry.message.cmd);
  if (canonicalJson(commands) !== canonicalJson(expected)) {
    fail("command_sequence_invalid", phase, "domain command sequence is not exact", {
      domain, expected, actual: commands,
    });
  }
}

function pairRequests(transcript, phaseName) {
  verifyRecordChain(transcript);
  const tuningRequests = messageEvents(transcript, "bridge_send", "equipment_tuning");
  const inventoryRequests = messageEvents(transcript, "bridge_send", "inventory");
  const expectedTuning = phaseName === "first" ? TUNING_FIRST : TUNING_RESTART;
  const expectedInventory = phaseName === "first" ? INVENTORY_FIRST : INVENTORY_RESTART;
  exactCommandList(tuningRequests, expectedTuning, phaseName, "equipment_tuning");
  exactCommandList(inventoryRequests, expectedInventory, phaseName, "inventory");
  const allRequests = tuningRequests.concat(inventoryRequests);
  const chronologicalRequests = allRequests.slice().sort((left, right) =>
    left.event.sequence - right.event.sequence);
  const expectedCrossDomain = phaseName === "first" ? CROSS_DOMAIN_FIRST : CROSS_DOMAIN_RESTART;
  const actualCrossDomain = chronologicalRequests.map((entry) =>
    entry.message.domain + ":" + entry.message.cmd);
  if (canonicalJson(actualCrossDomain) !== canonicalJson(expectedCrossDomain)) {
    fail("cross_domain_request_order_invalid", phaseName,
      "cross-domain request sequence is not the frozen Equipment journey", {
        expected: expectedCrossDomain, actual: actualCrossDomain,
      });
  }
  allRequests.forEach((entry) => requestEnvelope(entry.message, phaseName));
  if (new Set(allRequests.map((entry) => entry.message.callId)).size !== allRequests.length) {
    fail("request_call_id_duplicate", phaseName, "Web callId is not one-to-one");
  }
  const inbound = messageEvents(transcript, "webview_message", "equipment_tuning")
    .concat(messageEvents(transcript, "webview_message", "inventory"));
  const pairs = allRequests.map((entry) => {
    const matches = inbound.filter((candidate) => candidate.message.callId === entry.message.callId
      && candidate.message.domain === entry.message.domain && candidate.message.cmd === entry.message.cmd);
    if (matches.length !== 1 || matches[0].event.sequence <= entry.event.sequence) {
      fail("request_response_pair_invalid", phaseName, "request does not have one later exact response", {
        callId: entry.message.callId, matches: matches.length,
      });
    }
    responseEnvelope(matches[0].message, entry.message, phaseName);
    return { requestEvent: entry.event, request: entry.message,
      responseEvent: matches[0].event, response: matches[0].message };
  });
  const usedResponses = new Set(pairs.map((pair) => pair.responseEvent.sequence));
  if (usedResponses.size !== inbound.length) {
    fail("response_set_not_exact", phaseName, "extra or duplicate authority responses were observed");
  }
  const panelIds = new Set(allRequests.map((entry) => entry.message.panelInstanceId));
  if (panelIds.size !== 1) fail("panel_owner_not_exact", phaseName, "phase crossed panel owner instance");
  const viewIds = new Set(tuningRequests.map((entry) => entry.message.payload.viewSessionId));
  if (viewIds.size !== 1) fail("view_session_not_exact", phaseName, "phase crossed tuning view session");
  return {
    transcript,
    panelInstanceId: tuningRequests[0].message.panelInstanceId,
    viewSessionId: tuningRequests[0].message.payload.viewSessionId,
    tuning: pairs.filter((pair) => pair.request.domain === "equipment_tuning"),
    inventory: pairs.filter((pair) => pair.request.domain === "inventory"),
    all: pairs,
  };
}

function requireCandidate(snapshotValue, candidateKey, phase) {
  const matches = snapshotValue.candidates.filter((candidate) => candidate.candidateKey === candidateKey);
  if (matches.length !== 1 || !matches[0].available || matches[0].installed
      || matches[0].owned < 1) {
    fail("selected_candidate_not_authoritative", phase,
      "selected candidate is absent, duplicated, installed, unavailable, or unowned",
      { candidateKey });
  }
  return matches[0];
}

function sameRaw(left, right, code, phase, message) {
  if (canonicalJson(left) !== canonicalJson(right)) fail(code, phase, message);
}

function equipmentBusiness(value) {
  const result = deepClone(value);
  delete result.lastUpdate;
  return result;
}

function verifyInstallPreview(before, after, candidate, materials, removedMods, phase) {
  sameRaw(equipmentBusiness(after.equipment.raw), Object.assign(
    equipmentBusiness(before.equipment.raw),
    { mods: before.equipment.mods.concat([candidate.itemName]) }),
  "install_mod_postcondition_invalid", phase,
  "install-mod preview changed fields outside the exact appended mod");
  if (after.equipment.lastUpdate !== before.equipment.lastUpdate
      || before.equipment.mods.includes(candidate.itemName)
      || materials.length !== 1 || !sameIdentity(materials[0], candidate)
      || materials[0].delta !== -1 || removedMods.length !== 0) {
    fail("install_mod_postcondition_invalid", phase,
      "install-mod preview does not preserve timestamp or consume one exact candidate");
  }
}

function exactInputTarget(event, expected, phase) {
  const target = event && event.target;
  const attributes = target && target.attributes;
  const rect = target && target.rect;
  const point = target && target.clientPoint;
  const viewport = target && target.viewport;
  const targetKeys = ["attributes", "clientPoint", "enabled", "hitTargetMatches",
    "mutationCapable", "rect", "selector", "tagName", "text", "viewport", "visible"];
  if (!event || event.kind !== "dom_input" || event.eventType !== "click"
      || event.isTrusted !== true || event.button !== 0 || !isPlainObject(target)
      || !isPlainObject(attributes) || !Number.isSafeInteger(event.pageTime)
      || event.pageTime <= 0 || canonicalJson(Object.keys(target).sort())
        !== canonicalJson(targetKeys)
      || target.tagName !== "BUTTON" || target.selector !== expected.selector
      || target.visible !== true || target.enabled !== true || target.hitTargetMatches !== true
      || !isPlainObject(rect) || canonicalJson(Object.keys(rect).sort())
        !== canonicalJson(["bottom", "height", "left", "right", "top", "width"])
      || !isPlainObject(point) || canonicalJson(Object.keys(point).sort())
        !== canonicalJson(["x", "y"])
      || !isPlainObject(viewport) || canonicalJson(Object.keys(viewport).sort())
        !== canonicalJson(["height", "width"])
      || ![rect.left, rect.top, rect.right, rect.bottom, rect.width, rect.height,
        point.x, point.y, viewport.width, viewport.height].every(Number.isFinite)
      || rect.width <= 0 || rect.height <= 0 || viewport.width <= 0 || viewport.height <= 0
      || Math.abs(rect.right - rect.left - rect.width) > 0.01
      || Math.abs(rect.bottom - rect.top - rect.height) > 0.01
      || point.x < rect.left || point.x > rect.right || point.y < rect.top || point.y > rect.bottom
      || point.x < 0 || point.x >= viewport.width || point.y < 0 || point.y >= viewport.height) {
    fail("trusted_input_contract_invalid", phase,
      "journey input is not one visible enabled BUTTON hit by an exact trusted primary click");
  }
  Object.keys(expected.attributes || {}).forEach((key) => {
    if (attributes[key] !== String(expected.attributes[key])) {
      fail("trusted_input_target_invalid", phase,
        "trusted input target does not match the frozen production selector", {
          key, expected: expected.attributes[key], actual: attributes[key],
        });
    }
  });
  if (target.mutationCapable !== expected.mutationCapable) {
    fail("trusted_input_target_invalid", phase,
      "trusted input mutation capability does not match its journey step");
  }
  return event;
}

function observerDetachEvent(transcript, phase) {
  const values = transcript.events.filter((event) => ["observer_detached",
    "observer_detach_transport_lost"].includes(event.kind));
  if (values.length !== 1) {
    fail("observer_lifecycle_invalid", phase, "observer detach event is not exact");
  }
  return values[0];
}

function verifyFirstJourneyOrder(phaseResult, diagnostics, first, options) {
  const inputs = phaseResult.transcript.events.filter((event) => event.kind === "dom_input");
  if (inputs.length !== 6) {
    fail("trusted_input_multiset_invalid", "first",
      "first journey must contain exactly source/A/B/commit/reselect/close inputs", {
        count: inputs.length,
      });
  }
  const source = String(first.initial.source.slot);
  const sourceInitial = exactInputTarget(inputs[0], {
    selector: "button[data-physical-slot=\"" + source + "\"]",
    attributes: { "data-physical-slot": source }, mutationCapable: false,
  }, "first.select_source");
  const candidateA = exactInputTarget(inputs[1], {
    selector: "button[data-candidate-key=\"" + first.candidateA.candidateKey + "\"]",
    attributes: { "data-candidate-key": first.candidateA.candidateKey }, mutationCapable: true,
  }, "first.preview_a");
  const candidateB = exactInputTarget(inputs[2], {
    selector: "button[data-candidate-key=\"" + first.candidateB.candidateKey + "\"]",
    attributes: { "data-candidate-key": first.candidateB.candidateKey }, mutationCapable: true,
  }, "first.preview_b");
  const commit = exactInputTarget(inputs[3], {
    selector: ".equipment-tuning-commit[data-tuning-focus-key=\"commit\"]",
    attributes: { "data-tuning-focus-key": "commit" }, mutationCapable: true,
  }, "first.commit");
  const sourceFresh = exactInputTarget(inputs[4], {
    selector: "button[data-physical-slot=\"" + source + "\"]",
    attributes: { "data-physical-slot": source }, mutationCapable: false,
  }, "first.reselect_source");
  const close = exactInputTarget(inputs[5], {
    selector: "button[data-header-action=\"close\"]",
    attributes: { "data-header-action": "close" }, mutationCapable: false,
  }, "first.close");
  const tuning = phaseResult.tuning;
  const inventory = phaseResult.inventory;
  requireBefore(sourceInitial, tuning[0].requestEvent, "journey_order_invalid", "first",
    "source selection must precede initial tuning request");
  requireBefore(tuning[0].responseEvent, candidateA, "journey_order_invalid", "first",
    "initial tuning response must settle before candidate A input");
  requireBefore(tuning[0].responseEvent, inventory[0].requestEvent,
    "journey_order_invalid", "first",
    "initial tuning response must settle before the Inventory request");
  requireBefore(inventory[0].requestEvent, inventory[0].responseEvent,
    "journey_order_invalid", "first", "initial Inventory response must follow its request");
  requireBefore(inventory[0].responseEvent, candidateA, "journey_order_invalid", "first",
    "initial Inventory authority must settle before candidate A input");

  requireBefore(candidateA, diagnostics.candidateAHit, "journey_order_invalid", "first",
    "candidate A hit diagnostic must follow its trusted click");
  requireBefore(diagnostics.candidateAHit, diagnostics.previewAIssued,
    "journey_order_invalid", "first", "candidate A issued diagnostic is out of order");
  requireBefore(diagnostics.previewAIssued, tuning[1].requestEvent,
    "journey_order_invalid", "first", "candidate A issued must precede business dispatch");
  requireBefore(tuning[1].requestEvent, tuning[1].responseEvent,
    "journey_order_invalid", "first", "candidate A response must follow request");
  requireBefore(tuning[1].requestEvent, diagnostics.previewAAdopted,
    "journey_order_invalid", "first", "candidate A adopted must follow request");
  requireBefore(tuning[1].responseEvent, candidateB, "journey_order_invalid", "first",
    "candidate A response must settle before candidate B input");
  requireBefore(diagnostics.previewAAdopted, candidateB,
    "journey_order_invalid", "first", "candidate A adoption must settle before candidate B input");

  requireBefore(candidateB, diagnostics.candidateBHit, "journey_order_invalid", "first",
    "candidate B hit diagnostic must follow its trusted click");
  requireBefore(diagnostics.candidateBHit, diagnostics.previewBIssued,
    "journey_order_invalid", "first", "candidate B issued diagnostic is out of order");
  requireBefore(diagnostics.previewBIssued, tuning[2].requestEvent,
    "journey_order_invalid", "first", "candidate B issued must precede business dispatch");
  requireBefore(tuning[2].requestEvent, tuning[2].responseEvent,
    "journey_order_invalid", "first", "candidate B response must follow request");
  requireBefore(tuning[2].requestEvent, diagnostics.previewBAdopted,
    "journey_order_invalid", "first", "candidate B adopted must follow request");
  requireBefore(tuning[2].responseEvent, commit, "journey_order_invalid", "first",
    "candidate B response must settle before commit input");
  requireBefore(diagnostics.previewBAdopted, commit, "journey_order_invalid", "first",
    "candidate B adoption must settle before commit input");

  requireBefore(commit, diagnostics.commitIssued, "journey_order_invalid", "first",
    "commit issued must follow trusted commit input");
  requireBefore(diagnostics.commitIssued, tuning[3].requestEvent,
    "journey_order_invalid", "first", "commit issued must precede business dispatch");
  requireBefore(tuning[3].requestEvent, tuning[3].responseEvent,
    "journey_order_invalid", "first", "commit response must follow request");
  requireBefore(tuning[3].requestEvent, diagnostics.commitAdopted,
    "journey_order_invalid", "first", "commit adopted must follow request");
  requireBefore(diagnostics.commitAdopted, inventory[1].requestEvent,
    "journey_order_invalid", "first", "successful commit adoption must trigger Inventory refresh");
  requireBefore(inventory[1].requestEvent, inventory[1].responseEvent,
    "journey_order_invalid", "first", "Inventory refresh response must follow request");
  requireBefore(inventory[1].requestEvent, diagnostics.refreshSettled,
    "journey_order_invalid", "first", "Inventory refresh diagnostic must follow request");
  [tuning[3].responseEvent, diagnostics.commitAdopted, inventory[1].responseEvent,
    diagnostics.refreshSettled].forEach((event) => requireBefore(event, sourceFresh,
    "journey_order_invalid", "first",
    "commit and refresh authorities must settle before source reselection"));

  requireBefore(sourceFresh, tuning[4].requestEvent, "journey_order_invalid", "first",
    "source reselection must precede fresh tuning snapshot");
  requireBefore(tuning[4].requestEvent, tuning[4].responseEvent,
    "journey_order_invalid", "first", "fresh tuning response must follow request");
  requireBefore(tuning[4].responseEvent, close, "journey_order_invalid", "first",
    "fresh tuning authority must settle before close");
  requireBefore(close, tuning[5].requestEvent, "journey_order_invalid", "first",
    "trusted close must precede detach request");
  requireBefore(tuning[5].requestEvent, tuning[5].responseEvent,
    "journey_order_invalid", "first", "detach response must follow request");
  if (!options || options.requireObserverDetached !== false) {
    requireBefore(tuning[5].responseEvent, observerDetachEvent(phaseResult.transcript, "first"),
      "journey_order_invalid", "first", "observer detached before exact detach settled");
  }
  return { sourceInitial, candidateA, candidateB, commit, sourceFresh, close };
}

function verifyRestartJourneyOrder(phaseResult, restart, options) {
  const inputs = phaseResult.transcript.events.filter((event) => event.kind === "dom_input");
  if (inputs.length !== 2) {
    fail("restart_input_multiset_invalid", "restart",
      "restart journey must contain exactly source and close trusted inputs", { count: inputs.length });
  }
  const source = exactInputTarget(inputs[0], {
    selector: "button[data-physical-slot=\"" + String(restart.readback.source.slot) + "\"]",
    attributes: { "data-physical-slot": String(restart.readback.source.slot) },
    mutationCapable: false,
  }, "restart.select_source");
  const close = exactInputTarget(inputs[1], {
    selector: "button[data-header-action=\"close\"]",
    attributes: { "data-header-action": "close" }, mutationCapable: false,
  }, "restart.close");
  const tuning = phaseResult.tuning;
  const inventory = phaseResult.inventory;
  requireBefore(source, tuning[0].requestEvent, "restart_journey_order_invalid", "restart",
    "restart source selection must precede tuning readback");
  requireBefore(tuning[0].requestEvent, tuning[0].responseEvent,
    "restart_journey_order_invalid", "restart", "restart tuning response must follow request");
  requireBefore(tuning[0].responseEvent, inventory[0].requestEvent,
    "restart_journey_order_invalid", "restart",
    "restart tuning response must settle before the Inventory request");
  requireBefore(inventory[0].requestEvent, inventory[0].responseEvent,
    "restart_journey_order_invalid", "restart", "restart Inventory response must follow request");
  requireBefore(tuning[0].responseEvent, close, "restart_journey_order_invalid", "restart",
    "restart tuning readback must settle before close");
  requireBefore(inventory[0].responseEvent, close, "restart_journey_order_invalid", "restart",
    "restart Inventory readback must settle before close");
  requireBefore(close, tuning[1].requestEvent, "restart_journey_order_invalid", "restart",
    "restart trusted close must precede detach");
  requireBefore(tuning[1].requestEvent, tuning[1].responseEvent,
    "restart_journey_order_invalid", "restart", "restart detach response must follow request");
  if (!options || options.requireObserverDetached !== false) {
    requireBefore(tuning[1].responseEvent, observerDetachEvent(phaseResult.transcript, "restart"),
      "restart_journey_order_invalid", "restart", "restart observer detached before detach settled");
  }
  return { source, close };
}

function verifyFirstTranscript(transcript, options) {
  const pairs = pairRequests(transcript, "first");
  const tuning = pairs.tuning;
  const initial = snapshotResponse(tuning[0].response, tuning[0].request, "first.initial");
  const previewA = previewResponse(tuning[1].response, tuning[1].request, "first.previewA");
  const previewB = previewResponse(tuning[2].response, tuning[2].request, "first.previewB");
  const commit = commitResponse(tuning[3].response, tuning[3].request, "first.commit");
  const fresh = snapshotResponse(tuning[4].response, tuning[4].request, "first.fresh");
  responseEnvelope(tuning[5].response, tuning[5].request, "first.detach");
  const sourceA = sourceRef(tuning[1].request.payload.source, "first.previewA.source");
  const sourceB = sourceRef(tuning[2].request.payload.source, "first.previewB.source");
  const sourceFresh = sourceRef(tuning[4].request.payload.source, "first.fresh.source");
  const sourceInitialRequest = sourceRef(tuning[0].request.payload.source,
    "first.initial.request.source");
  const beforeSources = [sourceInitialRequest, sourceA, sourceB, previewA.before.source,
    previewA.after.source, previewB.before.source, previewB.after.source,
    commit.before.source];
  const afterSources = [commit.after.source, commit.snapshot.source, sourceFresh, fresh.source];
  if (!beforeSources.every((source) => sameSourceAuthority(initial.source, source))
      || !afterSources.every((source) => sameSourceAuthority(commit.snapshot.source, source))
      || !sameCoordinate(initial.source, commit.snapshot.source)
      || initial.source.expectedLease === commit.snapshot.source.expectedLease) {
    fail("source_authority_drift", "first",
      "before/after source coordinate and lease generations are not exact");
  }
  if (previewA.candidateKey === previewB.candidateKey || previewA.tokenRef === previewB.tokenRef) {
    fail("preview_replacement_not_proven", "first", "two distinct preview authorities are required");
  }
  const candidateA = requireCandidate(initial, previewA.candidateKey, "first.previewA");
  const candidateB = requireCandidate(initial, previewB.candidateKey, "first.previewB");
  if (candidateB.itemName === candidateB.displayName || candidateB.itemName === candidateB.icon
      || candidateB.displayName === candidateB.icon) {
    fail("final_candidate_not_all_distinct", "first", "final selected mod must exercise all three identity fields");
  }
  if (!IdentityFixture.allDistinct.some((entry) => entry.itemName === candidateB.itemName
      && entry.displayName === candidateB.displayName
      && entry.icon === candidateB.icon)) {
    fail("final_candidate_not_canonical_fixture", "first",
      "final selected mod is not one frozen all-distinct identity fixture");
  }
  if (!sameIdentity(candidateA, previewA.materials[0])
      || !sameIdentity(candidateB, previewB.materials[0])) {
    fail("candidate_material_identity_mismatch", "first", "preview material identity does not bind candidate triple");
  }
  sameRaw(initial.equipment.raw, previewA.before.equipment.raw,
    "initial_preview_before_mismatch", "first",
    "first preview before does not equal the initial authoritative equipment");
  verifyInstallPreview(previewA.before, previewA.after, candidateA,
    previewA.materials, previewA.removedMods, "first.previewA");
  sameRaw(previewA.before.raw, previewB.before.raw, "preview_before_drift", "first",
    "second preview is not based on the same canonical before projection");
  verifyInstallPreview(previewB.before, previewB.after, candidateB,
    previewB.materials, previewB.removedMods, "first.previewB");
  sameRaw(previewB.before.raw, commit.before.raw, "commit_before_mismatch", "first",
    "commit before does not equal accepted preview before");
  sameRaw(equipmentBusiness(previewB.after.equipment.raw),
    equipmentBusiness(commit.after.equipment.raw), "commit_after_mismatch", "first",
    "commit after business state does not equal accepted preview after");
  if (commit.after.equipment.lastUpdate <= previewB.after.equipment.lastUpdate) {
    fail("commit_after_mismatch", "first",
      "committed after timestamp did not advance beyond the accepted preview");
  }
  sameRaw(previewB.materials.map((entry) => entry.raw), commit.materials.map((entry) => entry.raw),
    "commit_materials_mismatch", "first", "commit material plan does not equal accepted preview");
  sameRaw(previewB.removedMods, commit.removedMods, "commit_removed_mods_mismatch", "first",
    "commit removed-mod set does not equal accepted preview");
  if (tuning[3].request.payload.expectedTuningToken !== previewB.tokenRef
      || commit.tokenRef !== previewB.tokenRef || commit.operation !== previewB.operation
      || commit.transactionRef === commit.tokenRef) {
    fail("commit_token_binding_invalid", "first", "commit did not consume final preview authority exactly once");
  }
  sameRaw(commit.after.equipment.raw, commit.snapshot.equipment.raw,
    "commit_snapshot_after_mismatch", "first", "commit snapshot does not adopt expected-after equipment");
  sameRaw(commit.after.equipment.raw, fresh.equipment.raw,
    "fresh_snapshot_after_mismatch", "first", "fresh snapshot does not re-prove accepted after equipment");
  if (commit.snapshot.materialRevision <= initial.materialRevision
      || commit.snapshot.inventoryRevision <= initial.inventoryRevision
      || fresh.materialRevision !== commit.snapshot.materialRevision
      || fresh.inventoryRevision !== commit.snapshot.inventoryRevision) {
    fail("fresh_revision_postcondition_invalid", "first",
      "commit/fresh snapshots do not prove one advanced material/inventory revision");
  }
  commit.materials.forEach((planned) => {
    const committed = commit.snapshot.materials.filter((entry) => entry.itemName === planned.itemName);
    const refreshed = fresh.materials.filter((entry) => entry.itemName === planned.itemName);
    if (committed.length !== 1 || refreshed.length !== 1 || committed[0].count !== planned.after
        || refreshed[0].count !== planned.after || !sameIdentity(committed[0], planned)
        || !sameIdentity(refreshed[0], planned)) {
      fail("fresh_material_postcondition_invalid", "first",
        "material totals/identity do not equal accepted plan after", { itemName: planned.itemName });
    }
  });
  const result = { pairs, initial, previewA, previewB, commit, fresh, candidateA, candidateB };
  const diagnostics = verifyDiagnostics(pairs, result, "first");
  result.diagnostics = diagnostics;
  result.inputs = verifyFirstJourneyOrder(pairs, diagnostics, result, options);
  return result;
}

function verifyRestartTranscript(transcript, first, options) {
  const pairs = pairRequests(transcript, "restart");
  if (pairs.panelInstanceId === first.pairs.panelInstanceId
      || pairs.viewSessionId === first.pairs.viewSessionId) {
    fail("restart_instance_not_fresh", "restart", "restart reused panel/view session identity");
  }
  const readback = snapshotResponse(pairs.tuning[0].response, pairs.tuning[0].request, "restart.snapshot");
  responseEnvelope(pairs.tuning[1].response, pairs.tuning[1].request, "restart.detach");
  const restartRequestSource = sourceRef(pairs.tuning[0].request.payload.source,
    "restart.snapshot.request.source");
  if (!sameCoordinate(readback.source, first.fresh.source)
      || sameSourceAuthority(readback.source, first.fresh.source)
      || !sameSourceAuthority(restartRequestSource, readback.source)) {
    fail("restart_detach_or_source_invalid", "restart",
      "restart must reselect the same coordinate under one fresh process-local lease");
  }
  sameRaw(readback.equipment.raw, first.commit.after.equipment.raw,
    "restart_equipment_readback_mismatch", "restart", "restart did not read accepted after equipment");
  first.commit.materials.forEach((planned) => {
    const current = readback.materials.filter((entry) => entry.itemName === planned.itemName);
    if (current.length !== 1 || current[0].count !== planned.after || !sameIdentity(current[0], planned)) {
      fail("restart_material_readback_mismatch", "restart", "restart material total/identity drifted");
    }
  });
  if (transcript.events.some((event) => event.kind === "dom_input"
      && event.target && event.target.mutationCapable === true)) {
    fail("restart_write_input_observed", "restart", "restart readback phase contains a mutation-capable input");
  }
  const result = { pairs, readback };
  result.inputs = verifyRestartJourneyOrder(pairs, result, options);
  return result;
}

function inventoryContainers(message) {
  const values = Array.isArray(message.snapshots) ? message.snapshots
    : Array.isArray(message.inventorySnapshots) ? message.inventorySnapshots
      : isPlainObject(message.snapshot) ? [message.snapshot] : [];
  if (!values.length) fail("inventory_snapshot_missing", "inventory", "inventory response lacks snapshots");
  return values;
}

const INVENTORY_SNAPSHOT_KEYS = Object.freeze([
  "containerId", "capacity", "accessibleCapacity", "viewCapacity", "filterKey",
  "pageSizeHint", "locked", "snapshotSeq", "containerEpoch", "containerVersion",
  "offset", "limit", "slots", "filterFacets", "filterItemCount", "setFacets",
  "setFilterItemCount",
]);
const INVENTORY_ITEM_KEYS = Object.freeze([
  "name", "displayName", "icon", "majorType", "use", "actionType", "weaponType",
  "setId", "setName", "setOrder", "itemKind", "quantity", "enhancementLevel",
  "maxEnhancementLevel", "isMaxEnhancement", "tierSlotAvailable", "tierSlotUsed",
  "modSlotCapacity", "modSlotUsed", "modSlots", "modMeta", "rarity",
]);
const INVENTORY_MOD_KEYS = Object.freeze([
  "name", "displayName", "icon", "grade", "gradeLabel", "gradeColor", "role",
  "roleLabel", "symbol", "scope",
]);

function boundedInteger(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function validateInventoryMod(value, phase) {
  exactKeys(value, INVENTORY_MOD_KEYS, [], "inventory_mod_invalid", phase);
  identityTriple(value, phase, "inventory_mod_invalid");
  ["grade", "gradeLabel", "gradeColor", "role", "roleLabel", "symbol", "scope"]
    .forEach((key) => {
      if (!safeText(value[key], 0, 128)) {
        fail("inventory_mod_invalid", phase, "Inventory mod metadata is malformed", { key });
      }
    });
  return value;
}

function validateInventoryItem(value, phase) {
  exactKeys(value, INVENTORY_ITEM_KEYS, ["balanceSummary"], "inventory_item_invalid", phase);
  identityTriple(value, phase, "inventory_item_invalid");
  ["majorType", "use", "actionType", "weaponType", "setId", "setName", "rarity"]
    .forEach((key) => {
      if (!safeText(value[key], 0, key === "use" ? 64 : 256)) {
        fail("inventory_item_invalid", phase, "Inventory item text projection is malformed", { key });
      }
    });
  if (!["equipment", "stack"].includes(value.itemKind)
      || !boundedInteger(value.setOrder, 0, 0x7fffffff)
      || !Number.isSafeInteger(value.quantity) || value.quantity < 0
      || !boundedInteger(value.enhancementLevel, 0, 0x7fffffff)
      || !boundedInteger(value.maxEnhancementLevel, 0, 0x7fffffff)
      || typeof value.isMaxEnhancement !== "boolean"
      || typeof value.tierSlotAvailable !== "boolean"
      || typeof value.tierSlotUsed !== "boolean"
      || !boundedInteger(value.modSlotCapacity, 0, 0x7fffffff)
      || !boundedInteger(value.modSlotUsed, 0, 0x7fffffff)
      || value.tierSlotUsed && !value.tierSlotAvailable
      || !Array.isArray(value.modSlots) || value.modSlots.length > 3
      || value.modSlots.length > value.modSlotUsed) {
    fail("inventory_item_invalid", phase, "Inventory item numeric/capability projection is malformed");
  }
  value.modSlots.forEach((entry, index) =>
    validateInventoryMod(entry, phase + ".modSlots[" + index + "]"));
  if (value.modMeta != null) validateInventoryMod(value.modMeta, phase + ".modMeta");
  if (value.itemKind === "equipment") {
    if (value.quantity !== 1
        || value.isMaxEnhancement !== (value.enhancementLevel >= value.maxEnhancementLevel)) {
      fail("inventory_item_invalid", phase, "equipment quantity/max-level projection is inconsistent");
    }
  } else if (value.quantity < 1 || value.enhancementLevel !== 0 || value.isMaxEnhancement
      || value.tierSlotAvailable || value.tierSlotUsed || value.modSlotCapacity !== 0
      || value.modSlotUsed !== 0 || value.modSlots.length !== 0) {
    fail("inventory_item_invalid", phase, "stack projection carries equipment-only state");
  }
  if (value.balanceSummary != null) {
    exactKeys(value.balanceSummary, ["state", "weightLayers", "formula", "level"], [],
      "inventory_item_invalid", phase + ".balanceSummary");
    if (value.balanceSummary.state !== "confirmed"
        || !boundedInteger(value.balanceSummary.weightLayers, -100000, 100000)
        || value.balanceSummary.formula !== 1
        || !boundedInteger(value.balanceSummary.level, 0, 0x7fffffff)) {
      fail("inventory_item_invalid", phase, "balance summary is malformed");
    }
  }
  return value;
}

function validateInventoryConfirm(value, item, phase) {
  exactKeys(value, ["itemKind", "name", "displayName", "quantity", "enhancementLevel",
    "rarity", "tier", "modSignature", "lastUpdate"], [], "inventory_confirm_invalid", phase);
  if (value.itemKind !== item.itemKind || value.name !== item.name
      || value.displayName !== item.displayName || value.rarity !== item.rarity
      || value.quantity !== item.quantity || value.enhancementLevel !== item.enhancementLevel
      || !safeText(value.tier, 0, 256) || !safeText(value.modSignature, 0, 2048)
      || !Number.isSafeInteger(value.lastUpdate) || value.lastUpdate < 0) {
    fail("inventory_confirm_invalid", phase,
      "Inventory confirmation projection does not exactly bind its item");
  }
  return value;
}

function validateFacetArray(values, sets, depth, maximumCount, phase) {
  if (!Array.isArray(values) || values.length > 64 || depth > 2) {
    fail("inventory_facets_invalid", phase, "Inventory facet array is malformed");
  }
  const ids = new Set();
  let total = 0;
  values.forEach((value, index) => {
    exactKeys(value, ["id", "label", "order", "count", "children"], [],
      "inventory_facets_invalid", phase + "[" + index + "]");
    if (!safeText(value.id, 1, 128) || !safeText(value.label, 1, 128)
        || ids.has(value.id) || !boundedInteger(value.order, -1000000, 1000000)
        || !boundedInteger(value.count, 0, maximumCount) || !Array.isArray(value.children)
        || (sets && value.children.length !== 0)) {
      fail("inventory_facets_invalid", phase, "Inventory facet node is malformed");
    }
    ids.add(value.id);
    const childTotal = sets || value.children.length === 0 ? 0
      : validateFacetArray(value.children, false, depth + 1, maximumCount,
        phase + "[" + index + "].children");
    if (childTotal > value.count || total + value.count > maximumCount) {
      fail("inventory_facets_invalid", phase, "Inventory facet totals exceed their authority bound");
    }
    total += value.count;
  });
  return total;
}

function validateInventorySnapshot(snapshot, phase, requestWindow, requireFullBackpack) {
  exactKeys(snapshot, INVENTORY_SNAPSHOT_KEYS, ["filterSpec", "scope"],
    "inventory_snapshot_shape_invalid", phase);
  const hasScope = Object.prototype.hasOwnProperty.call(snapshot, "scope");
  const hasFilterSpec = Object.prototype.hasOwnProperty.call(snapshot, "filterSpec");
  const scope = snapshot.scope == null ? "all" : snapshot.scope;
  if (!["背包", "仓库", "战备箱"].includes(snapshot.containerId)
      || !["all", "weapon", "armor", "consumable", "material", "other"]
        .includes(snapshot.filterKey)
      || !["all", "equipment"].includes(scope)
      || hasScope && scope !== "equipment"
      || hasFilterSpec && snapshot.filterSpec == null
      || scope === "equipment" && snapshot.containerId !== "背包"
      || !boundedInteger(snapshot.capacity, 1, 1200)
      || !boundedInteger(snapshot.accessibleCapacity, 0, snapshot.capacity)
      || !boundedInteger(snapshot.viewCapacity, 0, snapshot.accessibleCapacity)
      || !boundedInteger(snapshot.pageSizeHint, 1, 100)
      || typeof snapshot.locked !== "boolean"
      || snapshot.locked !== (snapshot.accessibleCapacity <= 0)
      || !boundedInteger(snapshot.snapshotSeq, 1, 0x7fffffff)
      || !boundedInteger(snapshot.containerEpoch, 1, 0x7fffffff)
      || !boundedInteger(snapshot.containerVersion, 0, 0x7fffffff)
      || !boundedInteger(snapshot.offset, 0, Math.max(0, snapshot.viewCapacity - 1))
      || !boundedInteger(snapshot.limit, 0, 100)
      || snapshot.limit > Math.max(0, snapshot.viewCapacity - snapshot.offset)
      || !boundedInteger(snapshot.filterItemCount, 0, snapshot.accessibleCapacity)
      || !boundedInteger(snapshot.setFilterItemCount, 0, snapshot.accessibleCapacity)
      || snapshot.setFilterItemCount > snapshot.filterItemCount
      || !Array.isArray(snapshot.slots) || snapshot.slots.length !== snapshot.limit) {
    fail("inventory_snapshot_shape_invalid", phase,
      "Inventory snapshot numeric/window projection is malformed");
  }
  if (snapshot.viewCapacity <= 0 && snapshot.offset !== 0) {
    fail("inventory_snapshot_shape_invalid", phase, "empty Inventory view must start at offset zero");
  }
  if (requestWindow) {
    const requestScope = requestWindow.scope == null ? "all" : requestWindow.scope;
    const requestHasSpec = requestWindow.filterSpec != null;
    const responseHasSpec = snapshot.filterSpec != null;
    const expectedOffset = snapshot.viewCapacity <= 0 ? 0
      : requestWindow.offset >= snapshot.viewCapacity
        ? Math.floor((snapshot.viewCapacity - 1) / requestWindow.limit) * requestWindow.limit
        : requestWindow.offset;
    const expectedLimit = Math.min(requestWindow.limit,
      Math.max(0, snapshot.viewCapacity - expectedOffset));
    if (snapshot.containerId !== requestWindow.containerId
        || snapshot.filterKey !== requestWindow.filterKey || scope !== requestScope
        || requestHasSpec !== responseHasSpec
        || requestHasSpec && canonicalJson(snapshot.filterSpec) !== canonicalJson(requestWindow.filterSpec)
        || snapshot.offset !== expectedOffset || snapshot.limit !== expectedLimit) {
      fail("inventory_snapshot_request_mismatch", phase,
        "Inventory snapshot does not exactly answer its requested window");
    }
  }
  const seen = new Set();
  let previous = -1;
  let occupiedCount = 0;
  const direct = scope === "all" && snapshot.filterKey === "all" && snapshot.filterSpec == null;
  snapshot.slots.forEach((slot, index) => {
    const required = slot && slot.occupied === true
      ? ["physicalSlot", "occupied", "slotLease", "item", "confirmProjection"]
      : ["physicalSlot", "occupied", "slotLease"];
    exactKeys(slot, required, [], "inventory_slot_invalid", phase + ".slots[" + index + "]");
    if (!boundedInteger(slot.physicalSlot, 0, Math.max(0, snapshot.accessibleCapacity - 1))
        || seen.has(slot.physicalSlot) || slot.physicalSlot <= previous
        || direct && slot.physicalSlot !== snapshot.offset + index
        || typeof slot.occupied !== "boolean" || !TOKEN_REF_RE.test(slot.slotLease || "")) {
      fail("inventory_slot_invalid", phase, "Inventory slot coordinate/lease is malformed");
    }
    seen.add(slot.physicalSlot);
    previous = slot.physicalSlot;
    if (slot.occupied) {
      occupiedCount += 1;
      const item = validateInventoryItem(slot.item, phase + ".slots[" + index + "].item");
      validateInventoryConfirm(slot.confirmProjection, item,
        phase + ".slots[" + index + "].confirmProjection");
      if (scope === "equipment" && item.itemKind !== "equipment") {
        fail("inventory_slot_invalid", phase, "equipment scope contains a non-equipment item");
      }
    }
  });
  const facetTotal = validateFacetArray(snapshot.filterFacets, false, 0,
    snapshot.accessibleCapacity, phase + ".filterFacets");
  const setFacetTotal = validateFacetArray(snapshot.setFacets, true, 0,
    snapshot.accessibleCapacity, phase + ".setFacets");
  if (facetTotal !== snapshot.filterItemCount || setFacetTotal !== snapshot.setFilterItemCount) {
    fail("inventory_facets_invalid", phase, "Inventory facet totals do not equal declared counts");
  }
  if (requireFullBackpack && (snapshot.containerId !== "背包" || scope !== "all"
      || snapshot.filterKey !== "all" || snapshot.filterSpec != null
      || snapshot.capacity !== 50 || snapshot.accessibleCapacity !== 50
      || snapshot.viewCapacity !== 50 || snapshot.pageSizeHint !== 50 || snapshot.locked
      || snapshot.offset !== 0 || snapshot.limit !== 50 || occupiedCount !== snapshot.filterItemCount)) {
    fail("inventory_full_backpack_invalid", phase,
      "commit embedded Inventory projection is not one canonical full backpack");
  }
  return snapshot;
}

function validateInventoryResponse(pair, phase) {
  if (pair.request.payload.requests.length !== 1 || pair.response.snapshots.length !== 1) {
    fail("inventory_request_scope_invalid", phase,
      "Equipment journey requires one exact full-backpack window");
  }
  const window = pair.request.payload.requests[0];
  if (window.containerId !== "背包" || window.offset !== 0 || window.limit !== 50
      || window.filterKey !== "all" || window.scope !== "all"
      || Object.prototype.hasOwnProperty.call(window, "filterSpec")) {
    fail("inventory_request_scope_invalid", phase,
      "Equipment Inventory request is not the frozen scope=all 50-slot window");
  }
  return validateInventorySnapshot(pair.response.snapshots[0], phase, window, true);
}

function findInventorySlot(message, source, phase) {
  const containers = inventoryContainers(message).filter((entry) => entry.containerId === source.containerId);
  if (containers.length !== 1 || !Array.isArray(containers[0].slots)) {
    fail("inventory_container_invalid", phase, "source container snapshot is absent/duplicated");
  }
  const slots = containers[0].slots.filter((entry) => Number(entry.physicalSlot) === source.slot);
  if (slots.length !== 1 || slots[0].occupied !== true || !isPlainObject(slots[0].item)
      || !isPlainObject(slots[0].confirmProjection)
      || !TOKEN_REF_RE.test(slots[0].slotLease || "")) {
    fail("inventory_source_slot_invalid", phase, "source slot projection is absent or malformed");
  }
  return { container: containers[0], slot: slots[0], slotLease: slots[0].slotLease,
    identity: identityTriple(slots[0].item, phase), raw: deepClone(slots[0].item),
    confirm: deepClone(slots[0].confirmProjection) };
}

function verifyInventoryRequestScope(pair, source, phase) {
  const windows = pair.request.payload.requests.filter((entry) =>
    entry.containerId === source.containerId && entry.offset <= source.slot
      && source.slot < entry.offset + entry.limit);
  if (windows.length !== 1) {
    fail("inventory_request_scope_invalid", phase,
      "Inventory snapshot request does not cover the authoritative physical source slot");
  }
  return windows[0];
}

function inventoryEquipmentComparable(item, confirm) {
  if (!isPlainObject(item) || !isPlainObject(confirm)) return null;
  return {
    name: item.name,
    displayName: item.displayName,
    icon: item.icon,
    type: item.majorType,
    use: item.use,
    level: Number(item.enhancementLevel != null ? item.enhancementLevel : item.level),
    tier: confirm.tier == null ? "" : String(confirm.tier),
    mods: Array.isArray(item.modSlots) ? item.modSlots.map((entry) => entry.name) : [],
    modSignature: confirm.modSignature,
    modSlotCapacity: item.modSlotCapacity == null ? null : Number(item.modSlotCapacity),
    hardMaxLevel: Number(item.maxEnhancementLevel),
    lastUpdate: Number(confirm.lastUpdate),
  };
}

function equipmentComparable(equipment) {
  const mods = equipment.mods.slice();
  return {
    name: equipment.itemName,
    displayName: equipment.displayName,
    icon: equipment.icon,
    type: equipment.type,
    use: equipment.use,
    level: equipment.level,
    tier: equipment.tier,
    mods,
    modSignature: mods.map((name) => String(name).length + ":" + name + ";").join(""),
    modSlotCapacity: equipment.modSlotCapacity,
    hardMaxLevel: equipment.raw.hardMaxLevel,
    lastUpdate: equipment.lastUpdate,
  };
}

function stableInventorySlotProjection(slot) {
  const value = { physicalSlot: slot.physicalSlot, occupied: slot.occupied };
  if (slot.occupied) {
    value.item = deepClone(slot.item);
    value.confirmProjection = deepClone(slot.confirmProjection);
  }
  return value;
}

function stableInventorySnapshotProjection(snapshot) {
  return {
    containerId: snapshot.containerId,
    capacity: snapshot.capacity,
    accessibleCapacity: snapshot.accessibleCapacity,
    viewCapacity: snapshot.viewCapacity,
    filterKey: snapshot.filterKey,
    pageSizeHint: snapshot.pageSizeHint,
    locked: snapshot.locked,
    containerEpoch: snapshot.containerEpoch,
    offset: snapshot.offset,
    limit: snapshot.limit,
    filterFacets: deepClone(snapshot.filterFacets),
    filterItemCount: snapshot.filterItemCount,
    setFacets: deepClone(snapshot.setFacets),
    setFilterItemCount: snapshot.setFilterItemCount,
  };
}

function verifyFullBackpackInvariance(snapshots, targetSlot) {
  const labels = ["initial", "commit", "refreshed", "restart"];
  const values = [snapshots.initial, snapshots.commit, snapshots.refreshed, snapshots.restart];
  values.forEach((snapshot, index) => {
    if (!snapshot || snapshot.slots.length !== 50
        || snapshot.slots.some((slot, slotIndex) => slot.physicalSlot !== slotIndex)) {
      fail("inventory_full_backpack_invalid", "inventory." + labels[index],
        "full-backpack evidence is not one exact ordered 0..49 physical-slot set");
    }
  });
  const baselineHeader = stableInventorySnapshotProjection(values[0]);
  values.slice(1).forEach((snapshot, index) => {
    sameRaw(stableInventorySnapshotProjection(snapshot), baselineHeader,
      "inventory_non_target_drift", "inventory." + labels[index + 1],
      "full-backpack non-version metadata drifted across the journey");
  });
  for (let physicalSlot = 0; physicalSlot < 50; physicalSlot += 1) {
    const slots = values.map((snapshot) => snapshot.slots[physicalSlot]);
    const projections = slots.map(stableInventorySlotProjection);
    if (physicalSlot !== targetSlot) {
      projections.slice(1).forEach((projection, index) => {
        sameRaw(projection, projections[0], "inventory_non_target_drift",
          "inventory." + labels[index + 1] + ".slots[" + physicalSlot + "]",
          "a non-target physical slot changed during single-slot tuning");
      });
    } else {
      sameRaw(projections[1], projections[2], "inventory_target_settlement_mismatch",
        "inventory.target", "commit and refreshed target projections differ");
      sameRaw(projections[2], projections[3], "inventory_target_restart_mismatch",
        "inventory.target", "refreshed and restart target projections differ");
      if (canonicalJson(projections[0]) === canonicalJson(projections[1])) {
        fail("inventory_target_not_changed", "inventory.target",
          "the one authorized target physical slot did not change");
      }
    }
    if (slots[0].slotLease === slots[1].slotLease
        || slots[1].slotLease !== slots[2].slotLease
        || slots[2].slotLease === slots[3].slotLease) {
      fail("inventory_slot_lease_lifecycle_invalid", "inventory.slots[" + physicalSlot + "]",
        "slotLease must rotate with the first mutation, settle in-process, and rotate on restart");
    }
  }
}

function verifyInventory(firstTranscript, restartTranscript, first, restart) {
  const initialPair = first.pairs.inventory[0];
  const refreshedPair = first.pairs.inventory[1];
  const restartPair = restart.pairs.inventory[0];
  const initialSnapshot = validateInventoryResponse(initialPair, "inventory.initial_response");
  const refreshedSnapshot = validateInventoryResponse(refreshedPair, "inventory.refresh_response");
  const restartSnapshot = validateInventoryResponse(restartPair, "inventory.restart_response");
  verifyInventoryRequestScope(initialPair, first.initial.source, "inventory.initial_request");
  verifyInventoryRequestScope(refreshedPair, first.commit.snapshot.source,
    "inventory.refresh_request");
  verifyInventoryRequestScope(restartPair, restart.readback.source, "inventory.restart_request");
  if (!Array.isArray(first.commit.raw.inventorySnapshots)
      || first.commit.raw.inventorySnapshots.length !== 1) {
    fail("inventory_full_backpack_invalid", "inventory.commit_embedded",
      "commit lacks one canonical full-backpack projection");
  }
  const commitSnapshot = validateInventorySnapshot(first.commit.raw.inventorySnapshots[0],
    "inventory.commit_embedded", null, true);
  const initial = findInventorySlot(initialPair.response, first.initial.source, "inventory.initial");
  const committed = findInventorySlot({ snapshots: first.commit.raw.inventorySnapshots },
    first.commit.snapshot.source, "inventory.commit_embedded");
  const refreshed = findInventorySlot(refreshedPair.response, first.initial.source, "inventory.refreshed");
  const reloaded = findInventorySlot(restartPair.response, first.initial.source, "inventory.restart");
  if (initial.slotLease !== first.initial.source.expectedLease
      || committed.slotLease !== first.commit.snapshot.source.expectedLease
      || refreshed.slotLease !== first.commit.snapshot.source.expectedLease
      || refreshed.slotLease !== first.fresh.source.expectedLease
      || reloaded.slotLease !== restart.readback.source.expectedLease
      || reloaded.slotLease === first.fresh.source.expectedLease) {
    fail("inventory_source_lease_mismatch", "inventory",
      "Inventory slotLease does not close the before/after and fresh-restart lease chains");
  }
  if (initialPair.response.sessionNonce !== refreshedPair.response.sessionNonce
      || restartPair.response.sessionNonce === initialPair.response.sessionNonce) {
    fail("inventory_session_nonce_invalid", "inventory",
      "Inventory nonce must remain stable in-process and rotate on restart");
  }
  if (!(initial.container.containerVersion < committed.container.containerVersion)
      || committed.container.containerVersion !== refreshed.container.containerVersion) {
    fail("inventory_container_version_invalid", "inventory",
      "first-process Inventory container version did not advance and settle");
  }
  if (!(initial.container.snapshotSeq < committed.container.snapshotSeq
      && committed.container.snapshotSeq < refreshed.container.snapshotSeq)) {
    fail("inventory_snapshot_sequence_invalid", "inventory",
      "Inventory snapshots are not strictly ordered across read, commit, and refresh");
  }
  if (initial.container.containerEpoch !== committed.container.containerEpoch
      || committed.container.containerEpoch !== refreshed.container.containerEpoch) {
    fail("inventory_container_epoch_invalid", "inventory",
      "single-slot tuning unexpectedly rebuilt the first-process Inventory container");
  }
  if (initial.container.containerVersion !== first.initial.inventoryRevision
      || committed.container.containerVersion !== first.commit.snapshot.inventoryRevision
      || refreshed.container.containerVersion !== first.fresh.inventoryRevision
      || reloaded.container.containerVersion !== restart.readback.inventoryRevision) {
    fail("inventory_revision_binding_invalid", "inventory",
      "Inventory containerVersion does not bind the corresponding tuning inventoryRevision");
  }
  sameRaw(inventoryEquipmentComparable(initial.raw, initial.confirm),
    equipmentComparable(first.previewB.before.equipment),
    "inventory_initial_before_mismatch", "inventory", "Inventory initial state != tuning canonical before");
  sameRaw(inventoryEquipmentComparable(committed.raw, committed.confirm),
    equipmentComparable(first.commit.after.equipment),
    "inventory_commit_after_mismatch", "inventory",
    "commit embedded Inventory snapshot != accepted tuning after");
  sameRaw(inventoryEquipmentComparable(refreshed.raw, refreshed.confirm),
    equipmentComparable(first.commit.after.equipment),
    "inventory_refresh_after_mismatch", "inventory", "Inventory refresh != accepted tuning after");
  sameRaw(inventoryEquipmentComparable(reloaded.raw, reloaded.confirm),
    equipmentComparable(first.commit.after.equipment),
    "inventory_restart_after_mismatch", "inventory", "restart Inventory != accepted tuning after");
  verifyFullBackpackInvariance({ initial: initialSnapshot, commit: commitSnapshot,
    refreshed: refreshedSnapshot, restart: restartSnapshot }, first.initial.source.slot);
  return { initial, committed, refreshed, reloaded };
}

function parseField(line, name) {
  const match = new RegExp("(?:^|\\s)" + name + "=([^\\s]+)").exec(String(line || ""));
  if (!match) return null;
  try { return decodeURIComponent(match[1]); } catch (_error) { return match[1]; }
}

const HOST_TIMESTAMP_PREFIX_RE = /^(\d{2}):(\d{2}):(\d{2})\.(\d{3}) /;
const HOST_RELEVANT_MARKERS = Object.freeze([
  "[Panel] HandlePanelMessage: ",
  "[Panel] Routing ",
  "event=authority_flash_call_bound ",
  "[EquipmentTuningTask] -> Flash: ",
  "[InventoryTask] -> Flash: ",
  "[XmlSocket:JSON] task=equipment_tuning_response ",
  "[XmlSocket:JSON] task=inventory_response ",
  "event=equipment_tuning_preview_settled ",
  "event=equipment_tuning_commit_settled ",
  "event=equipment_tuning_snapshot_confirmed ",
  "event=panel_exact_close_completed ",
]);

function normalizeHostRecord(record, phaseName) {
  const raw = String(record && record.line || "");
  const timestamp = HOST_TIMESTAMP_PREFIX_RE.exec(raw);
  const hour = timestamp ? Number(timestamp[1]) : null;
  const minute = timestamp ? Number(timestamp[2]) : null;
  const second = timestamp ? Number(timestamp[3]) : null;
  const millisecond = timestamp ? Number(timestamp[4]) : null;
  if (timestamp && (hour > 23 || minute > 59 || second > 59)) {
    fail("host_timestamp_invalid", phaseName, "Host log timestamp is outside clock bounds", {
      lineNumber: record && record.lineNumber,
    });
  }
  const body = timestamp ? raw.slice(timestamp[0].length) : raw;
  const occurrences = [];
  HOST_RELEVANT_MARKERS.forEach((marker) => {
    let offset = body.indexOf(marker);
    while (offset >= 0) {
      occurrences.push({ marker, offset });
      offset = body.indexOf(marker, offset + marker.length);
    }
  });
  if (occurrences.length
      && (HOST_TIMESTAMP_PREFIX_RE.test(body) || occurrences.length !== 1
        || occurrences[0].offset !== 0)) {
    fail("host_relevant_record_invalid", phaseName,
      "Host relevant record has an extra prefix, embedded marker, or multiple markers", {
        lineNumber: record && record.lineNumber,
      });
  }
  return Object.assign({}, record, { line: body,
    hostTimeOfDayMs: timestamp
      ? (((hour * 60 + minute) * 60 + second) * 1000 + millisecond) : null,
    observedAt: null });
}

function resolveHostTimeline(logSnapshot, phaseName) {
  if (!isPlainObject(logSnapshot) || !Array.isArray(logSnapshot.records)
      || !Number.isFinite(Date.parse(logSnapshot.capturedAt))) {
    fail("host_log_snapshot_invalid", phaseName,
      "terminal Host log snapshot lacks records or a finite capture time");
  }
  const capturedAt = new Date(logSnapshot.capturedAt);
  const records = logSnapshot.records.map((record) => normalizeHostRecord(record, phaseName));
  if (records.some((record) => record.hostTimeOfDayMs == null)) {
    fail("host_timestamp_missing", phaseName,
      "every Host timeline record must preserve its production timestamp prefix");
  }
  if (!records.length) return records;
  const firstValue = records[0].hostTimeOfDayMs;
  let currentDate = new Date(capturedAt.getFullYear(), capturedAt.getMonth(), capturedAt.getDate(),
    Math.floor(firstValue / 3600000), Math.floor(firstValue / 60000) % 60,
    Math.floor(firstValue / 1000) % 60, firstValue % 1000);
  if (currentDate.getTime() > capturedAt.getTime()) currentDate.setDate(currentDate.getDate() - 1);
  let previousTimeOfDay = firstValue;
  let rolloverCount = 0;
  records.forEach((record, index) => {
    const value = record.hostTimeOfDayMs;
    if (index > 0 && value < previousTimeOfDay) {
      const previousHour = Math.floor(previousTimeOfDay / 3600000);
      const currentHour = Math.floor(value / 3600000);
      if (previousHour !== 23 || currentHour !== 0 || rolloverCount !== 0) {
        fail("host_timeline_regression", phaseName,
          "Host records regress outside one exact 23:xx to 00:xx rollover", {
            previousLineNumber: records[index - 1].lineNumber,
            lineNumber: record.lineNumber, previousTimeOfDay, currentTimeOfDay: value,
            rolloverCount,
          });
      }
      rolloverCount += 1;
      currentDate.setDate(currentDate.getDate() + 1);
    }
    const candidate = new Date(currentDate.getFullYear(), currentDate.getMonth(),
      currentDate.getDate(), Math.floor(value / 3600000), Math.floor(value / 60000) % 60,
      Math.floor(value / 1000) % 60, value % 1000);
    const previousObserved = index > 0 ? Date.parse(records[index - 1].observedAt) : null;
    if (previousObserved !== null && candidate.getTime() < previousObserved) {
      fail("host_timestamp_invalid", phaseName,
        "Host record timeline is non-monotonic after calendar reconstruction", {
          lineNumber: record.lineNumber, rolloverCount,
        });
    }
    record.observedAt = candidate.toISOString();
    previousTimeOfDay = value;
  });
  const firstObserved = Date.parse(records[0].observedAt);
  const lastObserved = Date.parse(records[records.length - 1].observedAt);
  if (lastObserved > capturedAt.getTime()
      || capturedAt.getTime() - firstObserved > 36 * 60 * 60 * 1000) {
    fail("host_timestamp_invalid", phaseName,
      "Host record timeline is future-dated or older than the bounded capture window", {
        firstLineNumber: records[0].lineNumber,
        lastLineNumber: records[records.length - 1].lineNumber,
        rolloverCount,
      });
  }
  return records;
}

function parseKeyValueFields(line, marker, code, phaseName) {
  const source = String(line || "");
  if (!source.startsWith(marker)) return null;
  const fields = {};
  const tokens = source.slice(marker.endsWith(" ") ? marker.length : 0)
    .trim().split(/\s+/);
  tokens.forEach((token) => {
    const separator = token.indexOf("=");
    if (separator < 1) {
      fail(code, phaseName, "structured Host record contains a malformed field", { marker, token });
    }
    const key = token.slice(0, separator);
    if (Object.prototype.hasOwnProperty.call(fields, key)) {
      fail(code, phaseName, "structured Host record contains a duplicate field", { marker, key });
    }
    const raw = token.slice(separator + 1);
    try { fields[key] = decodeURIComponent(raw); } catch (_error) { fields[key] = raw; }
  });
  return fields;
}

function assertExactFieldNames(fields, expectedKeys, code, phaseName, marker) {
  const actual = Object.keys(fields || {}).sort();
  const expected = expectedKeys.slice().sort();
  if (canonicalJson(actual) !== canonicalJson(expected)) {
    fail(code, phaseName, "structured Host record fields are not exact", {
      marker, actual, expected,
    });
  }
  return fields;
}

function parseStructuredReceipt(line, eventName, expectedKeys, phaseName, code) {
  const marker = "event=" + eventName;
  const errorCode = code || "host_call_bound_receipt_invalid";
  const fields = parseKeyValueFields(line, marker, errorCode, phaseName);
  if (!fields) return null;
  assertExactFieldNames(fields, expectedKeys, errorCode, phaseName, marker);
  if (fields.event !== eventName) {
    fail(errorCode, phaseName, "structured Host event name drifted", { eventName });
  }
  return fields;
}

function parseJsonWithoutDuplicateKeys(text, code, phaseName) {
  const source = String(text || "");
  let index = 0;
  function whitespace() { while (/\s/.test(source[index] || "")) index += 1; }
  function stringToken() {
    whitespace();
    const start = index;
    if (source[index] !== "\"") fail(code, phaseName, "expected JSON string token");
    index += 1;
    while (index < source.length) {
      if (source[index] === "\\") { index += 2; continue; }
      if (source[index] === "\"") {
        index += 1;
        try { return JSON.parse(source.slice(start, index)); }
        catch (_error) { fail(code, phaseName, "malformed JSON string token"); }
      }
      index += 1;
    }
    fail(code, phaseName, "unterminated JSON string token");
  }
  function valueToken() {
    whitespace();
    if (source[index] === "{") return objectToken();
    if (source[index] === "[") return arrayToken();
    if (source[index] === "\"") { stringToken(); return; }
    const match = /^(?:-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)/
      .exec(source.slice(index));
    if (!match) fail(code, phaseName, "malformed JSON value token");
    index += match[0].length;
  }
  function objectToken() {
    index += 1;
    whitespace();
    const keys = new Set();
    if (source[index] === "}") { index += 1; return; }
    while (index < source.length) {
      const key = stringToken();
      if (keys.has(key)) fail(code, phaseName, "JSON object contains a duplicate field", { key });
      keys.add(key);
      whitespace();
      if (source[index] !== ":") fail(code, phaseName, "JSON object lacks key separator");
      index += 1;
      valueToken();
      whitespace();
      if (source[index] === "}") { index += 1; return; }
      if (source[index] !== ",") fail(code, phaseName, "JSON object lacks field separator");
      index += 1;
      whitespace();
    }
    fail(code, phaseName, "unterminated JSON object");
  }
  function arrayToken() {
    index += 1;
    whitespace();
    if (source[index] === "]") { index += 1; return; }
    while (index < source.length) {
      valueToken();
      whitespace();
      if (source[index] === "]") { index += 1; return; }
      if (source[index] !== ",") fail(code, phaseName, "JSON array lacks item separator");
      index += 1;
    }
    fail(code, phaseName, "unterminated JSON array");
  }
  valueToken();
  whitespace();
  if (index !== source.length) fail(code, phaseName, "JSON command contains trailing data");
  try { return JSON.parse(source); }
  catch (_error) { fail(code, phaseName, "Host Flash command summary contains malformed JSON"); }
}

const SENSITIVE_AUTHORITY_KEYS = Object.freeze([
  "expectedTuningToken", "tuningToken", "expectedCheckoutToken", "checkoutToken",
  "expectedPurchasedToken", "purchasedToken", "expectedCraftToken", "craftToken",
  "expectedBatchToken", "batchToken", "expectedTradeToken", "tradeToken",
  "expectedLearnToken", "learnToken", "expectedLease", "slotLease", "closeLease",
  "transactionId",
]);

function authorityEvidenceFields(value) {
  let count = 0;
  const refs = {};
  function visit(current) {
    if (Array.isArray(current)) return current.forEach(visit);
    if (!isPlainObject(current)) return;
    Object.keys(current).forEach((key) => {
      if (SENSITIVE_AUTHORITY_KEYS.includes(key)) {
        count += 1;
        if (!TOKEN_REF_RE.test(String(current[key] || ""))) {
          fail("authority_reference_invalid", "host_log",
            "redacted response authority value is not one digest reference", { key });
        }
        if (!refs[key]) refs[key] = new Set();
        refs[key].add(current[key]);
      } else {
        visit(current[key]);
      }
    });
  }
  visit(value);
  const fields = {};
  if (count > 0) fields.authorityFieldCount = String(count);
  SENSITIVE_AUTHORITY_KEYS.forEach((key) => {
    if (!refs[key]) return;
    const values = Array.from(refs[key]).sort();
    fields[key + (values.length === 1 ? "Ref" : "Refs")] = values.slice(0, 4).join(",");
    if (values.length > 4) fields[key + "RefCount"] = String(values.length);
  });
  return fields;
}

function sanitizeAuthorityProjection(value) {
  if (Array.isArray(value)) return value.map(sanitizeAuthorityProjection);
  if (!isPlainObject(value)) return deepClone(value);
  const output = {};
  Object.keys(value).forEach((key) => {
    if (SENSITIVE_AUTHORITY_KEYS.includes(key)) output[key + "Ref"] = value[key];
    else output[key] = sanitizeAuthorityProjection(value[key]);
  });
  return output;
}

function parseFlashCommand(record, domain, phaseName) {
  const marker = domain === "equipment_tuning"
    ? "[EquipmentTuningTask] -> Flash: " : "[InventoryTask] -> Flash: ";
  const line = String(record.line || "");
  if (!line.startsWith(marker)) return null;
  const tail = line.slice(marker.length);
  if (tail.trim().startsWith("{")) {
    const value = parseJsonWithoutDuplicateKeys(tail.trim(), "host_flash_command_invalid", phaseName);
    return { record, task: value.task, action: value.action,
      callId: Number(value.callId), value };
  }
  const fields = parseKeyValueFields(tail, "", "host_flash_command_invalid", phaseName);
  return { record, task: fields.task, action: fields.cmd,
    callId: Number(fields.callId), fields };
}

function snapshotStateRef(value) {
  const stable = {
    gender: value.gender,
    equipment: value.equipment,
    enhance: value.enhance,
    tierCandidates: value.tierCandidates,
    modCandidates: value.modCandidates,
    materials: value.materials,
  };
  return "sha256_" + sha256Text(canonicalJson(stable)).slice(0, 24);
}

function exactAuthorityBinding(binding, basis, expected, phaseName) {
  if (!isPlainObject(binding) || binding.schema !== AUTHORITY_BINDING_SCHEMA
      || binding.basis !== basis || binding.operation !== expected.operation
      || binding.candidateKey !== expected.candidateKey
      || !TOKEN_REF_RE.test(String(binding.sourceKeyRef || ""))
      || !TOKEN_REF_RE.test(String(binding.intentKeyRef || ""))) {
    fail("authority_binding_invalid", phaseName,
      "observer authority binding is missing or not tied to the exact business intent", {
        basis, expected, binding,
      });
  }
  if (basis === "web_diagnostic"
      && (binding.event !== expected.event || binding.webCallId !== expected.webCallId)) {
    fail("authority_binding_invalid", phaseName,
      "Web diagnostic authority binding crossed event/call identity", { expected, binding });
  }
  return binding;
}

function exactSourceBinding(pair, phaseName) {
  const binding = pair && pair.requestEvent && pair.requestEvent.authorityBinding;
  if (!isPlainObject(binding) || binding.schema !== AUTHORITY_BINDING_SCHEMA
      || binding.basis !== "request_source"
      || !TOKEN_REF_RE.test(String(binding.sourceKeyRef || ""))
      || Object.keys(binding).sort().join("|") !== ["basis", "schema", "sourceKeyRef"].sort().join("|")) {
    fail("source_authority_binding_invalid", phaseName,
      "snapshot request lacks one observer-computed source authority reference");
  }
  return binding;
}

function diagnosticEvents(phaseResult) {
  return phaseResult.transcript.events.filter((event) => event.kind === "bridge_send"
    && isPlainObject(event.message) && event.message.type === "debug"
    && event.message.scope === "equipment_tuning");
}

function requireDiagnosticStatus(message, expected, phaseName) {
  Object.keys(expected).forEach((key) => {
    if (canonicalJson(message[key]) !== canonicalJson(expected[key])) {
      fail("authority_diagnostic_status_invalid", phaseName,
        "production diagnostic status does not match the successful journey", {
          event: message.event, key, expected: expected[key], actual: message[key],
        });
    }
  });
}

function verifyDiagnostics(phaseResult, first, phaseName) {
  const diagnostics = diagnosticEvents(phaseResult);
  if (diagnostics.length !== DIAGNOSTIC_SEQUENCE.length
      || canonicalJson(diagnostics.map((event) => event.message.event))
        !== canonicalJson(DIAGNOSTIC_SEQUENCE)) {
    fail("diagnostic_multiset_invalid", phaseName,
      "Equipment diagnostics are not the exact successful install-mod multiset", {
        expected: DIAGNOSTIC_SEQUENCE,
        actual: diagnostics.map((event) => event.message.event),
      });
  }
  const previewA = phaseResult.tuning[1];
  const previewB = phaseResult.tuning[2];
  const commit = phaseResult.tuning[3];
  const refresh = phaseResult.inventory[1];
  const beforeSourceRef = exactAuthorityBinding(previewA.requestEvent.authorityBinding,
    "request_payload", { operation: "install_mod",
      candidateKey: previewA.request.payload.candidateKey }, phaseName).sourceKeyRef;
  const previewBBinding = exactAuthorityBinding(previewB.requestEvent.authorityBinding,
    "request_payload", { operation: "install_mod",
      candidateKey: previewB.request.payload.candidateKey }, phaseName);
  const freshSourceRef = exactSourceBinding(phaseResult.tuning[4], phaseName).sourceKeyRef;
  if (previewBBinding.sourceKeyRef !== beforeSourceRef) {
    fail("preview_authority_binding_mismatch", phaseName,
      "two previews crossed source authority");
  }
  const descriptors = [
    { pair: previewA, candidate: first.candidateA, event: "candidate_hit",
      sourceKeyRef: beforeSourceRef, status: { capability: "candidate", pendingCount: 0,
        tokenPresent: false, commitReady: false, writeState: "idle" } },
    { pair: previewA, candidate: first.candidateA, event: "preview_issued",
      sourceKeyRef: beforeSourceRef, status: { capability: "", pendingCount: 1,
        tokenPresent: false, commitReady: false, writeState: "read_pending" } },
    { pair: previewA, candidate: first.candidateA, event: "preview_adopted",
      sourceKeyRef: beforeSourceRef, status: { capability: "", pendingCount: 0,
        tokenPresent: true, commitReady: true, writeState: "idle" } },
    { pair: previewB, candidate: first.candidateB, event: "candidate_hit",
      sourceKeyRef: beforeSourceRef, status: { capability: "candidate", pendingCount: 0,
        tokenPresent: true, commitReady: true, writeState: "idle" } },
    { pair: previewB, candidate: first.candidateB, event: "preview_issued",
      sourceKeyRef: beforeSourceRef, status: { capability: "", pendingCount: 1,
        tokenPresent: false, commitReady: false, writeState: "read_pending" } },
    { pair: previewB, candidate: first.candidateB, event: "preview_adopted",
      sourceKeyRef: beforeSourceRef, status: { capability: "", pendingCount: 0,
        tokenPresent: true, commitReady: true, writeState: "idle" } },
    { pair: commit, candidate: first.candidateB, event: "commit_issued",
      sourceKeyRef: beforeSourceRef, status: { capability: "", pendingCount: 1,
        tokenPresent: true, commitReady: false, writeState: "write_pending" } },
    { pair: commit, candidate: first.candidateB, event: "commit_adopted",
      sourceKeyRef: beforeSourceRef, status: { capability: "", pendingCount: 0,
        tokenPresent: true, commitReady: false, writeState: "write_pending",
        success: true, transactionIdPresent: true, requiresReconcile: false,
        currentLeasePresent: null, noOp: false } },
    { pair: refresh, candidate: first.candidateB, event: "inventory_refresh_settled",
      sourceKeyRef: freshSourceRef, status: { capability: "", pendingCount: 0,
        tokenPresent: false, commitReady: false, writeState: "idle",
        success: true, transactionIdPresent: null, requiresReconcile: null,
        currentLeasePresent: true, noOp: null } },
  ];
  descriptors.forEach((descriptor, index) => {
    const event = diagnostics[index];
    const message = event.message;
    exactKeys(message, DIAGNOSTIC_KEYS, [], "authority_diagnostic_fields_invalid", phaseName);
    const expectedWebCallId = descriptor.event === "candidate_hit" ? ""
      : descriptor.event === "inventory_refresh_settled"
        ? commit.request.callId : descriptor.pair.request.callId;
    if (message.sequence !== index + 1 || message.event !== descriptor.event
        || message.cmd !== "" || message.operation !== "install_mod" || message.phase !== ""
        || message.webCallId !== expectedWebCallId
        || message.panelInstanceId !== phaseResult.panelInstanceId
        || message.viewSessionId !== phaseResult.viewSessionId
        || message.sourceKeyRef !== descriptor.sourceKeyRef
        || message.candidateKey !== descriptor.candidate.candidateKey
        || !TOKEN_REF_RE.test(String(message.intentKeyRef || ""))
        || message.reconcileAfterCallId !== "" || message.confirmationMode !== "safe"
        || message.autoCommitPending !== false || message.needsReconcile !== false
        || message.reconciled !== null || !Array.isArray(message.mismatchFields)
        || message.mismatchFields.length !== 0) {
      fail("authority_diagnostic_not_exact", phaseName,
        "Equipment diagnostic is not bound to exact owner/source/candidate state", {
          event: descriptor.event,
        });
    }
    requireDiagnosticStatus(message, Object.assign({
      success: null,
      transactionIdPresent: null,
      requiresReconcile: null,
      currentLeasePresent: null,
      noOp: null,
    }, descriptor.status), phaseName);
    if (["preview_issued", "preview_adopted"].includes(descriptor.event)) {
      const requestBinding = descriptor.pair.requestEvent.authorityBinding;
      if (message.intentKeyRef !== requestBinding.intentKeyRef) {
        fail("authority_diagnostic_not_exact", phaseName,
          "preview diagnostic intent reference crossed request authority");
      }
    } else if (["commit_issued", "commit_adopted", "inventory_refresh_settled"]
      .includes(descriptor.event) && message.intentKeyRef !== previewBBinding.intentKeyRef) {
      fail("authority_diagnostic_not_exact", phaseName,
        "commit/refresh diagnostic intent reference crossed accepted preview");
    }
    const issued = /_issued$/.test(descriptor.event);
    if (!issued && Object.prototype.hasOwnProperty.call(event, "authorityBinding")) {
      fail("authority_diagnostic_binding_unexpected", phaseName,
        "only issued diagnostics may carry observer authority bindings");
    }
  });
  return {
    events: diagnostics,
    candidateAHit: diagnostics[0], previewAIssued: diagnostics[1], previewAAdopted: diagnostics[2],
    candidateBHit: diagnostics[3], previewBIssued: diagnostics[4], previewBAdopted: diagnostics[5],
    commitIssued: diagnostics[6], commitAdopted: diagnostics[7], refreshSettled: diagnostics[8],
  };
}

function issuedDiagnosticBinding(phaseResult, pair, eventName, expected, phaseName) {
  const matches = phaseResult.transcript.events.filter((event) => event.kind === "bridge_send"
    && isPlainObject(event.message) && event.message.type === "debug"
    && event.message.scope === "equipment_tuning" && event.message.event === eventName
    && event.message.webCallId === pair.request.callId);
  if (matches.length !== 1 || matches[0].sequence >= pair.requestEvent.sequence) {
    fail("authority_diagnostic_not_exact", phaseName,
      "business request lacks one issued diagnostic immediately before dispatch", {
        eventName, webCallId: pair.request.callId, count: matches.length,
      });
  }
  const message = matches[0].message;
  const binding = exactAuthorityBinding(matches[0].authorityBinding, "web_diagnostic", {
    event: eventName,
    webCallId: pair.request.callId,
    operation: expected.operation,
    candidateKey: expected.candidateKey,
  }, phaseName);
  if (message.panelInstanceId !== pair.request.panelInstanceId
      || message.viewSessionId !== pair.request.payload.viewSessionId
      || message.operation !== expected.operation || message.candidateKey !== expected.candidateKey
      || message.sourceKeyRef !== binding.sourceKeyRef
      || message.intentKeyRef !== binding.intentKeyRef
      || Object.prototype.hasOwnProperty.call(message, "sourceKey")
      || Object.prototype.hasOwnProperty.call(message, "intentKey")) {
    fail("authority_diagnostic_not_exact", phaseName,
      "issued Web diagnostic is not bound to observer-computed owner/source/intent refs", {
        eventName, webCallId: pair.request.callId,
      });
  }
  return binding;
}

function expectedWriteEpoch(pair, phaseResult, phaseName) {
  if (pair.request.domain !== "equipment_tuning") return null;
  if (phaseName === "restart") return 0;
  const index = phaseResult.tuning.indexOf(pair);
  return index >= 3 ? 1 : 0;
}

function expectedEquipmentCommand(pair, fid, writeEpoch) {
  const payload = deepClone(pair.request.payload);
  payload.panelInstanceId = pair.request.panelInstanceId;
  payload.viewSessionId = pair.request.payload.viewSessionId;
  payload.writeEpoch = writeEpoch;
  payload.requestCallId = pair.request.callId;
  return Object.assign({ task: "cmd",
    action: FLASH_ACTIONS.equipment_tuning[pair.request.cmd], callId: fid },
  sanitizeAuthorityProjection(payload));
}

function exactResponseFields(record, pair, fid, phaseName) {
  const prefix = "[XmlSocket:JSON] ";
  const fields = parseKeyValueFields(record.line, prefix, "as2_response_mapping_invalid", phaseName);
  const evidence = authorityEvidenceFields(pair.response);
  const commandKey = pair.request.domain === "equipment_tuning" ? "command" : "cmd";
  const expected = Object.assign({
    task: pair.request.domain === "equipment_tuning"
      ? "equipment_tuning_response" : "inventory_response",
    [commandKey]: pair.request.domain === "equipment_tuning" ? pair.request.cmd : "other",
    callId: String(fid), success: "true", payload: "redacted",
  }, evidence);
  const expectedKeys = Object.keys(expected).concat(["len"]);
  assertExactFieldNames(fields, expectedKeys, "as2_response_mapping_invalid", phaseName, prefix);
  if (Object.keys(expected).some((key) => fields[key] !== expected[key])
      || !/^\d+$/.test(String(fields.len || "")) || Number(fields.len) < 1) {
    fail("as2_response_mapping_invalid", phaseName,
      "AS2 response summary is not the exact successful authority receipt", { fid });
  }
  return fields;
}

function parsePanelRequestSummary(record, phaseName) {
  const marker = "[Panel] HandlePanelMessage: ";
  const line = String(record && record.line || "");
  if (!line.startsWith(marker)) return null;
  const text = line.slice(marker.length);
  const match = /^task=panel panel=workbench domain=(equipment_tuning|inventory) cmd=([A-Za-z][A-Za-z0-9]*) callId=([A-Za-z0-9._~:-]{1,160}) payload=redacted len=(\d+)(.*)$/.exec(text);
  if (!match || Number(match[4]) < 1 || /\benvelope=(?:near_match|malformed)\b/.test(text)) {
    fail("host_panel_summary_invalid", phaseName,
      "Equipment Host panel summary is not one exact redacted request", {
        lineNumber: record.lineNumber,
      });
  }
  const tail = match[5].trim();
  const authority = tail ? parseKeyValueFields(tail, "", "host_panel_summary_invalid", phaseName) : {};
  return { domain: match[1], cmd: match[2], callId: match[3], authority };
}

function parsePanelRoute(record, phaseName) {
  const marker = "[Panel] Routing ";
  const line = String(record && record.line || "");
  if (!line.startsWith(marker)) return null;
  const text = line.slice(marker.length);
  let match = /^domain=equipment_tuning cmd=([A-Za-z][A-Za-z0-9]*) to EquipmentTuningTask, _equipmentTuningTask=ok$/.exec(text);
  if (match) return { domain: "equipment_tuning", cmd: match[1] };
  match = /^domain=inventory cmd=([A-Za-z][A-Za-z0-9]*) to InventoryTask, _inventoryTask=ok$/.exec(text);
  if (match) return { domain: "inventory", cmd: match[1] };
  if (/equipment_tuning|InventoryTask|EquipmentTuningTask|domain=inventory/.test(text)) {
    fail("host_route_invalid", phaseName,
      "Equipment Host route is not one exact successful production route", {
        lineNumber: record.lineNumber,
      });
  }
  return null;
}

function knownRelevantHostRecord(line) {
  return HOST_RELEVANT_MARKERS.some((marker) => line.startsWith(marker));
}

function assertNoUnknownRelevantHostRecords(records, phaseName) {
  const anomaly = /(?:equipment_tuning|equipmentTuning|EquipmentTuningTask|InventoryTask|authority_flash_call_boun|panel_exact_close|foreign_panel_close|authority_response_family|response_family|envelope=(?:near_match|malformed)|\[Workbench\].*close|close (?:deferred|lost)|rejected|not queued|superseded|ignored after replacement)/i;
  const invalid = records.filter((record) => {
    const line = String(record.line || "");
    if (!anomaly.test(line)) return false;
    if (!knownRelevantHostRecord(line)) return true;
    return /(?:response_family|authority_response_family|envelope=(?:near_match|malformed)|foreign_panel_close|rejected|not queued|superseded|ignored after replacement|close (?:deferred|lost))/i.test(line);
  });
  if (invalid.length) {
    fail("host_relevant_record_invalid", phaseName,
      "terminal Host boundary contains a malformed, near-match, rejected, or unknown Equipment record", {
        lines: invalid.map((entry) => entry.lineNumber),
      });
  }
}

function verifyHostMappings(logSnapshot, phaseResult, phaseName) {
  if (!isPlainObject(logSnapshot) || !Array.isArray(logSnapshot.records)) {
    fail("host_log_snapshot_invalid", phaseName, "terminal Host log snapshot is missing");
  }
  const records = resolveHostTimeline(logSnapshot, phaseName);
  assertNoUnknownRelevantHostRecords(records, phaseName);
  const relevantRequests = phaseResult.all;
  const mappings = relevantRequests.map((pair) => {
    const domain = pair.request.domain;
    const panelEntries = records.map((record) => ({ record,
      summary: parsePanelRequestSummary(record, phaseName) }))
      .filter((entry) => entry.summary && entry.summary.domain === domain
        && entry.summary.cmd === pair.request.cmd
        && entry.summary.callId === pair.request.callId);
    if (panelEntries.length !== 1
        || canonicalJson(panelEntries[0].summary.authority)
          !== canonicalJson(authorityEvidenceFields(pair.request))) {
      fail("host_panel_request_invalid", phaseName,
        "Web request does not bind one exact redacted Host panel summary", {
          domain, callId: pair.request.callId, count: panelEntries.length,
        });
    }
    const nextPanelLine = records.map((record) => ({ record,
      summary: parsePanelRequestSummary(record, phaseName) }))
      .filter((entry) => entry.summary
        && entry.record.lineNumber > panelEntries[0].record.lineNumber)
      .reduce((minimum, entry) => Math.min(minimum, entry.record.lineNumber), Infinity);
    const routes = records.map((record) => ({ record,
      route: parsePanelRoute(record, phaseName) }))
      .filter((entry) => entry.route && entry.route.domain === domain
        && entry.route.cmd === pair.request.cmd
        && entry.record.lineNumber > panelEntries[0].record.lineNumber
        && entry.record.lineNumber < nextPanelLine);
    if (routes.length !== 1) {
      fail("host_route_invalid", phaseName,
        "Web request lacks one exact later successful Host route", {
          domain, callId: pair.request.callId, count: routes.length,
        });
    }
    const eventName = "authority_flash_call_bound";
    const receiptKeys = ["event", "domain", "webCallId", "flashCallId", "panel",
      "panelInstanceId", "cmd", "action"];
    if (domain === "equipment_tuning") receiptKeys.push("viewSessionId");
    const callBindings = records.filter((record) =>
      String(record.line || "").startsWith("event=" + eventName + " ")
        && parseField(record.line, "domain") === domain)
      .map((record) => ({ record,
        fields: parseStructuredReceipt(record.line, eventName, receiptKeys, phaseName) }))
      .filter((entry) => entry.fields && entry.fields.domain === domain
        && entry.fields.webCallId === pair.request.callId);
    const expectedAction = FLASH_ACTIONS[domain] && FLASH_ACTIONS[domain][pair.request.cmd];
    if (callBindings.length !== 1 || !expectedAction
        || !Number.isInteger(Number(callBindings[0].fields.flashCallId))
        || Number(callBindings[0].fields.flashCallId) < 1
        || callBindings[0].fields.panel !== "workbench"
        || callBindings[0].fields.panelInstanceId !== pair.request.panelInstanceId
        || callBindings[0].fields.cmd !== pair.request.cmd
        || callBindings[0].fields.action !== expectedAction
        || (domain === "equipment_tuning"
          && callBindings[0].fields.viewSessionId !== pair.request.payload.viewSessionId)) {
      fail("host_call_bound_receipt_invalid", phaseName,
        "Web request does not bind one exact structured Host call-bound receipt", {
          domain, callId: pair.request.callId, count: callBindings.length,
        });
    }
    if (callBindings[0].record.lineNumber <= routes[0].record.lineNumber) {
      fail("host_request_order_invalid", phaseName,
        "Host call-bound receipt did not follow its exact panel summary and route", {
          callId: pair.request.callId,
        });
    }
    const fid = Number(callBindings[0].fields.flashCallId);
    const writeEpoch = expectedWriteEpoch(pair, phaseResult, phaseName);
    if (domain === "equipment_tuning"
        && (!Number.isInteger(pair.response.writeEpoch) || pair.response.writeEpoch !== writeEpoch)) {
      fail("response_write_epoch_invalid", phaseName,
        "Web response writeEpoch does not match the exact Host command generation", {
          callId: pair.request.callId, expected: writeEpoch, actual: pair.response.writeEpoch,
        });
    }
    const commands = records.map((record) => parseFlashCommand(record, domain, phaseName))
      .filter((entry) => entry && entry.callId === fid);
    if (commands.length !== 1 || commands[0].task !== "cmd"
        || commands[0].action !== expectedAction
        || commands[0].record.lineNumber <= callBindings[0].record.lineNumber) {
      fail("host_flash_command_invalid", phaseName,
        "structured call-bound receipt lacks one matching later Host Flash command summary", {
          domain, callId: pair.request.callId, fid, count: commands.length,
        });
    }
    if (domain === "equipment_tuning") {
      const expectedCommand = expectedEquipmentCommand(pair, fid, writeEpoch);
      if (canonicalJson(commands[0].value) !== canonicalJson(expectedCommand)) {
        fail("host_flash_command_invalid", phaseName,
          "Equipment Flash command is not the exact closed request/owner/epoch projection", {
            callId: pair.request.callId,
          });
      }
    } else {
      const evidence = authorityEvidenceFields(pair.request.payload);
      const expectedFields = Object.assign({ task: "cmd", cmd: expectedAction,
        callId: String(fid), payload: "redacted" }, evidence);
      assertExactFieldNames(commands[0].fields,
        Object.keys(expectedFields).concat(["len"]), "host_flash_command_invalid", phaseName,
        "[InventoryTask] -> Flash: ");
      if (Object.keys(expectedFields).some((key) => commands[0].fields[key] !== expectedFields[key])
          || !/^\d+$/.test(String(commands[0].fields.len || ""))
          || Number(commands[0].fields.len) < 1) {
        fail("host_flash_command_invalid", phaseName,
          "Inventory Flash command summary is not exact", { callId: pair.request.callId });
      }
    }
    const expectedTask = domain === "equipment_tuning"
      ? "equipment_tuning_response" : "inventory_response";
    const responses = records.map((record) => {
      const line = String(record.line || "");
      if (!line.startsWith("[XmlSocket:JSON] task=" + expectedTask + " ")) return null;
      const fields = parseKeyValueFields(line, "[XmlSocket:JSON] ",
        "as2_response_mapping_invalid", phaseName);
      return { record, fields };
    }).filter((entry) => entry && Number(entry.fields.callId) === fid);
    if (responses.length !== 1
        || responses[0].record.lineNumber <= commands[0].record.lineNumber) {
      fail("as2_response_mapping_invalid", phaseName, "AS2 fid lacks one later response summary", { fid });
    }
    exactResponseFields(responses[0].record, pair, fid, phaseName);
    return { webCallId: pair.request.callId, as2CallId: fid,
      requestSequence: pair.requestEvent.sequence,
      panelLineNumber: panelEntries[0].record.lineNumber,
      panelObservedAt: panelEntries[0].record.observedAt,
      routeLineNumber: routes[0].record.lineNumber,
      routeObservedAt: routes[0].record.observedAt,
      commandLineNumber: commands[0].record.lineNumber,
      commandObservedAt: commands[0].record.observedAt,
      callBoundLineNumber: callBindings[0].record.lineNumber,
      callBoundObservedAt: callBindings[0].record.observedAt,
      responseLineNumber: responses[0].record.lineNumber,
      responseObservedAt: responses[0].record.observedAt, writeEpoch };
  });
  if (new Set(mappings.map((entry) => entry.as2CallId)).size !== mappings.length) {
    fail("as2_call_id_reused", phaseName, "AS2 fid mapping is not one-to-one");
  }
  const rawAuthorityFields = records.filter((record) => {
    const line = String(record.line || "");
    return /(?:^|\s)(?:sourceKey|intentKey|expectedTuningToken|tuningToken|transactionId|expectedLease|slotLease)=/.test(line)
      || /"(?:sourceKey|intentKey|expectedTuningToken|tuningToken|transactionId|expectedLease|slotLease)"\s*:/.test(line);
  });
  if (rawAuthorityFields.length) {
    fail("host_raw_authority_field_present", phaseName,
      "Host log persisted raw sourceKey/intentKey instead of digest references");
  }
  const previewPairs = phaseResult.tuning.filter((pair) => pair.request.cmd === "preview");
  const commitPairs = phaseResult.tuning.filter((pair) => pair.request.cmd === "commit");
  const previewReceiptKeys = ["event", "webCallId", "flashCallId", "requestCallId",
    "tokenRef", "panelInstanceId", "viewSessionId", "sourceKeyRef", "operation",
    "candidateKey", "intentKeyRef", "outcome", "remainingPending"];
  const previewReceipts = previewPairs.map((pair) => {
    const requestBinding = exactAuthorityBinding(pair.requestEvent.authorityBinding,
      "request_payload", {
        operation: pair.request.payload.operation,
        candidateKey: pair.request.payload.candidateKey,
      }, phaseName);
    const diagnosticBinding = issuedDiagnosticBinding(phaseResult, pair, "preview_issued", {
      operation: pair.request.payload.operation,
      candidateKey: pair.request.payload.candidateKey,
    }, phaseName);
    if (requestBinding.sourceKeyRef !== diagnosticBinding.sourceKeyRef
        || requestBinding.intentKeyRef !== diagnosticBinding.intentKeyRef) {
      fail("preview_authority_binding_mismatch", phaseName,
        "request-derived and Web-diagnostic source/intent refs disagree", {
          callId: pair.request.callId,
        });
    }
    const mapping = mappings.find((entry) => entry.webCallId === pair.request.callId);
    const matches = records.filter((record) =>
      String(record.line || "").startsWith("event=equipment_tuning_preview_settled "))
      .map((record) => ({ record, fields: parseStructuredReceipt(record.line,
        "equipment_tuning_preview_settled", previewReceiptKeys, phaseName,
        "host_preview_receipt_invalid") }))
      .filter((entry) => entry.fields.webCallId === pair.request.callId);
    if (matches.length !== 1) {
      fail("host_preview_receipt_invalid", phaseName,
        "preview lacks one exact structured settled receipt", { callId: pair.request.callId });
    }
    const fields = matches[0].fields;
    const sourceKeyRef = fields.sourceKeyRef;
    const intentKeyRef = fields.intentKeyRef;
    if (Number(fields.flashCallId) !== mapping.as2CallId
        || fields.requestCallId !== pair.request.callId
        || fields.tokenRef !== pair.response.tuningToken
        || fields.panelInstanceId !== pair.request.panelInstanceId
        || fields.viewSessionId !== pair.request.payload.viewSessionId
        || fields.operation !== pair.request.payload.operation
        || fields.candidateKey !== pair.request.payload.candidateKey
        || fields.outcome !== "success"
        || sourceKeyRef !== requestBinding.sourceKeyRef
        || intentKeyRef !== requestBinding.intentKeyRef
        || Number(fields.remainingPending) !== 0
        || matches[0].record.lineNumber <= mapping.responseLineNumber) {
      fail("host_preview_receipt_invalid", phaseName,
        "preview structured receipt is not bound to Web/AS2/token/owner identity", {
          callId: pair.request.callId,
        });
    }
    return { lineNumber: matches[0].record.lineNumber,
      observedAt: matches[0].record.observedAt, webCallId: pair.request.callId,
      sourceKeyRef, intentKeyRef, tokenRef: pair.response.tuningToken };
  });
  const commitReceiptKeys = ["event", "webCallId", "flashCallId", "requestCallId",
    "previewWebCallId", "tokenRef", "panelInstanceId", "viewSessionId", "sourceKeyRef",
    "operation", "candidateKey", "intentKeyRef", "outcome", "writeEpoch", "writeState",
    "remainingPending", "stateRef", "snapshotPresent", "transactionIdPresent"];
  const commitReceipts = commitPairs.map((pair) => {
    const mapping = mappings.find((entry) => entry.webCallId === pair.request.callId);
    const acceptedPreview = previewPairs[previewPairs.length - 1];
    const acceptedReceipt = previewReceipts[previewReceipts.length - 1];
    const diagnosticBinding = issuedDiagnosticBinding(phaseResult, pair, "commit_issued", {
      operation: acceptedPreview.request.payload.operation,
      candidateKey: acceptedPreview.request.payload.candidateKey,
    }, phaseName);
    const matches = records.filter((record) =>
      String(record.line || "").startsWith("event=equipment_tuning_commit_settled "))
      .map((record) => ({ record, fields: parseStructuredReceipt(record.line,
        "equipment_tuning_commit_settled", commitReceiptKeys, phaseName,
        "host_commit_receipt_invalid") }))
      .filter((entry) => entry.fields.webCallId === pair.request.callId);
    if (matches.length !== 1) {
      fail("host_commit_receipt_invalid", phaseName,
        "commit lacks one exact structured settled receipt", { callId: pair.request.callId });
    }
    const fields = matches[0].fields;
    const sourceKeyRef = fields.sourceKeyRef;
    const intentKeyRef = fields.intentKeyRef;
    const stateRef = fields.stateRef;
    const writeEpoch = Number(fields.writeEpoch);
    const expectedStateRef = snapshotStateRef(pair.response.snapshot);
    if (Number(fields.flashCallId) !== mapping.as2CallId
        || fields.requestCallId !== pair.request.callId
        || fields.previewWebCallId !== acceptedPreview.request.callId
        || fields.tokenRef !== acceptedPreview.response.tuningToken
        || fields.panelInstanceId !== pair.request.panelInstanceId
        || fields.viewSessionId !== pair.request.payload.viewSessionId
        || fields.sourceKeyRef !== acceptedReceipt.sourceKeyRef
        || sourceKeyRef !== diagnosticBinding.sourceKeyRef
        || fields.operation !== acceptedPreview.request.payload.operation
        || fields.candidateKey !== acceptedPreview.request.payload.candidateKey
        || intentKeyRef !== acceptedReceipt.intentKeyRef
        || intentKeyRef !== diagnosticBinding.intentKeyRef
        || fields.outcome !== "success"
        || fields.writeState !== "idle"
        || fields.snapshotPresent !== "true"
        || fields.transactionIdPresent !== "true"
        || stateRef !== expectedStateRef
        || writeEpoch !== mapping.writeEpoch || writeEpoch < 1
        || Number(fields.remainingPending) !== 0
        || matches[0].record.lineNumber <= mapping.responseLineNumber) {
      fail("host_commit_receipt_invalid", phaseName,
        "commit receipt is not bound to accepted preview/Web/AS2/owner/poststate", {
          callId: pair.request.callId,
        });
    }
    return { lineNumber: matches[0].record.lineNumber,
      observedAt: matches[0].record.observedAt, webCallId: pair.request.callId,
      sourceKeyRef, intentKeyRef, stateRef, writeEpoch };
  });
  if (previewReceipts.length === 2
      && (previewReceipts[0].sourceKeyRef !== previewReceipts[1].sourceKeyRef
        || previewReceipts[0].intentKeyRef === previewReceipts[1].intentKeyRef)) {
    fail("host_preview_ref_replacement_invalid", phaseName,
      "two previews must share sourceRef while replacing intentRef");
  }
  const snapshotPairs = phaseResult.tuning.filter((pair) => pair.request.cmd === "snapshot");
  const snapshotReceiptKeys = ["event", "callId", "panelInstanceId", "viewSessionId",
    "sourceKeyRef", "stateRef", "writeEpoch"];
  const snapshotReceipts = snapshotPairs.map((pair) => {
    const mapping = mappings.find((entry) => entry.webCallId === pair.request.callId);
    const sourceBinding = exactSourceBinding(pair, phaseName);
    const matches = records.filter((record) =>
      String(record.line || "").startsWith("event=equipment_tuning_snapshot_confirmed "))
      .map((record) => ({ record, fields: parseStructuredReceipt(record.line,
        "equipment_tuning_snapshot_confirmed", snapshotReceiptKeys, phaseName,
        "host_snapshot_receipt_invalid") }))
      .filter((entry) => entry.fields.callId === pair.request.callId);
    const expectedStateRef = snapshotStateRef(pair.response.snapshot);
    if (matches.length !== 1
        || matches[0].fields.panelInstanceId !== pair.request.panelInstanceId
        || matches[0].fields.viewSessionId !== pair.request.payload.viewSessionId
        || matches[0].fields.sourceKeyRef !== sourceBinding.sourceKeyRef
        || matches[0].fields.stateRef !== expectedStateRef
        || Number(matches[0].fields.writeEpoch) !== mapping.writeEpoch
        || matches[0].record.lineNumber <= mapping.responseLineNumber) {
      fail("host_snapshot_receipt_invalid", phaseName,
        "snapshot confirmation is not bound to exact owner/source/state/epoch", {
          callId: pair.request.callId, count: matches.length,
        });
    }
    return { lineNumber: matches[0].record.lineNumber,
      observedAt: matches[0].record.observedAt,
      webCallId: pair.request.callId, sourceKeyRef: sourceBinding.sourceKeyRef,
      stateRef: expectedStateRef, writeEpoch: mapping.writeEpoch };
  });
  const detachPair = phaseResult.tuning.find((pair) => pair.request.cmd === "detach");
  const detachMapping = detachPair && mappings.find((entry) =>
    entry.webCallId === detachPair.request.callId);
  if (!detachPair || !detachMapping) {
    fail("host_close_receipt_invalid", phaseName,
      "lifecycle lacks the exact tuning detach boundary required by close ownership");
  }
  const closeReceiptKeys = ["event", "panel", "panelInstanceId"];
  const closeReceipts = records.filter((record) =>
    String(record.line || "").startsWith("event=panel_exact_close_completed "))
    .map((record) => ({ record, fields: parseStructuredReceipt(record.line,
      "panel_exact_close_completed", closeReceiptKeys, phaseName,
      "host_close_receipt_invalid") }));
  if (closeReceipts.length !== 1
      || closeReceipts[0].fields.panel !== "workbench"
      || closeReceipts[0].fields.panelInstanceId !== phaseResult.panelInstanceId
      || closeReceipts[0].record.lineNumber <= detachMapping.responseLineNumber) {
    fail("host_close_receipt_invalid", phaseName,
      "lifecycle must contain one exact owner close completion after detach response", {
        count: closeReceipts.length,
        expectedPanelInstanceId: phaseResult.panelInstanceId,
      });
  }
  const ownerCloseReceipt = {
    lineNumber: closeReceipts[0].record.lineNumber,
    observedAt: closeReceipts[0].record.observedAt,
    panel: closeReceipts[0].fields.panel,
    panelInstanceId: closeReceipts[0].fields.panelInstanceId,
  };
  const chronologicalMappings = mappings.slice().sort((left, right) =>
    left.requestSequence - right.requestSequence);
  for (let index = 1; index < chronologicalMappings.length; index += 1) {
    if (chronologicalMappings[index - 1].callBoundLineNumber
        >= chronologicalMappings[index].callBoundLineNumber) {
      fail("host_request_order_invalid", phaseName,
        "Host call-bound order disagrees with the observed Web request order");
    }
  }
  const equipmentCommands = records.filter((record) =>
    String(record.line || "").startsWith("[EquipmentTuningTask] -> Flash: "));
  const inventoryCommands = records.filter((record) =>
    String(record.line || "").startsWith("[InventoryTask] -> Flash: "));
  const equipmentCallBindings = records.filter((record) =>
    String(record.line || "").startsWith(
      "event=authority_flash_call_bound domain=equipment_tuning"));
  const inventoryCallBindings = records.filter((record) =>
    String(record.line || "").startsWith(
      "event=authority_flash_call_bound domain=inventory"));
  const allCallBindings = records.filter((record) =>
    String(record.line || "").startsWith("event=authority_flash_call_bound "));
  const equipmentResponses = records.filter((record) =>
    String(record.line || "").startsWith("[XmlSocket:JSON] task=equipment_tuning_response "));
  const inventoryResponses = records.filter((record) =>
    String(record.line || "").startsWith("[XmlSocket:JSON] task=inventory_response "));
  const previewSettledRecords = records.filter((record) =>
    String(record.line || "").startsWith("event=equipment_tuning_preview_settled "));
  const commitSettledRecords = records.filter((record) =>
    String(record.line || "").startsWith("event=equipment_tuning_commit_settled "));
  const snapshotConfirmedRecords = records.filter((record) =>
    String(record.line || "").startsWith("event=equipment_tuning_snapshot_confirmed "));
  const panelSummaryRecords = records.filter((record) =>
    String(record.line || "").startsWith("[Panel] HandlePanelMessage: "));
  const routeRecords = records.filter((record) =>
    String(record.line || "").startsWith("[Panel] Routing "));
  if (panelSummaryRecords.length !== relevantRequests.length
      || routeRecords.length !== relevantRequests.length
      || closeReceipts.length !== 1
      || equipmentCommands.length !== phaseResult.tuning.length
      || inventoryCommands.length !== phaseResult.inventory.length
      || equipmentCallBindings.length !== phaseResult.tuning.length
      || inventoryCallBindings.length !== phaseResult.inventory.length
      || allCallBindings.length !== relevantRequests.length
      || equipmentResponses.length !== phaseResult.tuning.length
      || inventoryResponses.length !== phaseResult.inventory.length
      || previewSettledRecords.length !== previewPairs.length
      || commitSettledRecords.length !== commitPairs.length
      || snapshotConfirmedRecords.length !== snapshotPairs.length) {
    fail("host_command_multiset_invalid", phaseName,
      "terminal boundary contains extra/missing command/response/settled/snapshot receipts", {
        equipment: equipmentCommands.length, inventory: inventoryCommands.length,
        panelSummaries: panelSummaryRecords.length,
        routes: routeRecords.length,
        closeReceipts: closeReceipts.length,
        equipmentCallBindings: equipmentCallBindings.length,
        inventoryCallBindings: inventoryCallBindings.length,
        allCallBindings: allCallBindings.length,
        equipmentResponses: equipmentResponses.length,
        inventoryResponses: inventoryResponses.length,
        previewSettled: previewSettledRecords.length,
        commitSettled: commitSettledRecords.length,
        snapshotConfirmed: snapshotConfirmedRecords.length,
      });
  }
  return mappings.map((mapping) => Object.assign({}, mapping, {
    snapshotReceipt: snapshotReceipts.find((entry) => entry.webCallId === mapping.webCallId) || null,
    previewReceipt: previewReceipts.find((entry) => entry.webCallId === mapping.webCallId) || null,
    commitReceipt: commitReceipts.find((entry) => entry.webCallId === mapping.webCallId) || null,
    ownerCloseReceipt: mapping.webCallId === detachPair.request.callId
      ? ownerCloseReceipt : null,
  }));
}

module.exports = {
  INVENTORY_FIRST,
  INVENTORY_RESTART,
  TUNING_FIRST,
  TUNING_RESTART,
  equipmentComparable,
  exactKeys,
  findInventorySlot,
  identityTriple,
  inventoryEquipmentComparable,
  pairRequests,
  parseField,
  projection,
  requestEnvelope,
  responseEnvelope,
  sameCoordinate,
  sameIdentity,
  snapshot,
  sourceRef,
  verifyFirstTranscript,
  verifyHostMappings,
  resolveHostTimeline,
  verifyInventory,
  verifyRestartTranscript,
};
