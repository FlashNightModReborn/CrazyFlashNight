#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const Transcript = require("./verify-receipt");
const { validateSourceFingerprint } = require("./source-contract");
const InventoryRuntime = require("../../../launcher/web/modules/inventory-runtime");

const SESSION_SCHEMA = "crafting.production-session-evidence.v2";
const RAW_ROLES = Object.freeze([
  "firstTranscript",
  "firstLogs",
  "restartTranscript",
  "restartLogs",
  "runtime",
  "persistence",
  "sourceFingerprints",
  "seedInvariant",
  "control"
]);
const STABLE_IDENTITY_FIELDS = Object.freeze([
  "runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure"
]);
const SOURCE_PHASES = Object.freeze([
  "initial",
  "after_clone_seed",
  "before_first_shutdown",
  "before_restart",
  "before_final_shutdown",
  "final"
]);
const HEX64 = /^[A-F0-9]{64}$/;
const SAFE_TOKEN = /^[A-Za-z0-9._~-]{1,160}$/;
const INVENTORY_ACTION = "inventorySnapshot";

function fail(code, phase, message, details) {
  throw new Transcript.GateError(code, phase, message, details);
}

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return Transcript.exactKeys(value, keys);
}

function requireExact(value, keys, code, phase) {
  if (!exactKeys(value, keys)) {
    fail(code, phase, "exact key contract failed", {
      expected: keys.slice().sort(),
      actual: isObject(value) ? Object.keys(value).sort() : null
    });
  }
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function stableIdentity(value) {
  if (!isObject(value)) fail("runtime_identity_invalid", "runtime", "runtime identity is missing");
  const result = {};
  STABLE_IDENTITY_FIELDS.forEach((field) => {
    const candidate = value[field];
    if (typeof candidate !== "string" || candidate.length === 0) {
      fail("runtime_identity_invalid", "runtime", "stable runtime identity field is missing", { field });
    }
    result[field] = field === "processPath" ? path.resolve(candidate) : candidate;
  });
  if (result.runtimeMode !== "isolated_candidate"
      || !HEX64.test(result.coreSha256)
      || !HEX64.test(result.buildIdentity)
      || !HEX64.test(result.payloadClosure)) {
    fail("runtime_identity_invalid", "runtime", "stable runtime identity is not an isolated candidate", result);
  }
  return result;
}

function sameStableIdentity(left, right) {
  const a = stableIdentity(left);
  const b = stableIdentity(right);
  return a.runtimeMode === b.runtimeMode
    && a.processPath.toLowerCase() === b.processPath.toLowerCase()
    && a.coreSha256 === b.coreSha256
    && a.buildIdentity === b.buildIdentity
    && a.payloadClosure === b.payloadClosure;
}

function verifyPortEvidence(session, label) {
  if (!isObject(session) || !Number.isInteger(session.pid) || session.pid <= 0
      || !Number.isInteger(session.httpPort) || session.httpPort < 1024 || session.httpPort > 65535
      || !Number.isInteger(session.cdpPort) || session.cdpPort < 1024 || session.cdpPort > 65535
      || !isObject(session.identity) || session.identity.pid !== session.pid
      || session.identity.httpPort !== session.httpPort || !isObject(session.portEvidence)
      || session.portEvidence.launcherPortsBound !== true
      || session.portEvidence.authenticatedHttpEndpoint !== true
      || session.portEvidence.cdpEndpointObserved !== true
      || session.portEvidence.httpPort !== session.httpPort
      || session.portEvidence.cdpPort !== session.cdpPort) {
    fail("runtime_port_evidence_invalid", "runtime",
      label + " PID/port evidence is incomplete or cross-wired", session);
  }
}

function verifyRuntimeEvidence(runtime) {
  if (!isObject(runtime) || !isObject(runtime.expectedStable)
      || !isObject(runtime.first) || !isObject(runtime.restart)) {
    fail("runtime_evidence_missing", "runtime", "runtime evidence is incomplete");
  }
  const expected = stableIdentity(runtime.expectedStable);
  verifyPortEvidence(runtime.first, "first");
  verifyPortEvidence(runtime.restart, "restart");
  if (!sameStableIdentity(expected, runtime.first.identity)
      || !sameStableIdentity(expected, runtime.restart.identity)) {
    fail("runtime_stable_identity_drift", "runtime",
      "stable identity changed between expected/first/restart", runtime);
  }
  if (runtime.first.pid === runtime.restart.pid) {
    fail("runtime_pid_reused", "runtime", "restart must have a fresh PID", {
      firstPid: runtime.first.pid,
      restartPid: runtime.restart.pid
    });
  }
  return {
    stableIdentity: expected,
    firstPid: runtime.first.pid,
    restartPid: runtime.restart.pid,
    firstHttpPort: runtime.first.httpPort,
    restartHttpPort: runtime.restart.httpPort,
    firstCdpPort: runtime.first.cdpPort,
    restartCdpPort: runtime.restart.cdpPort
  };
}

function verifySourceFingerprints(records) {
  if (!Array.isArray(records) || records.length !== SOURCE_PHASES.length) {
    fail("source_fingerprint_phases_invalid", "source", "source fingerprint phase set is incomplete");
  }
  let canonical = null;
  SOURCE_PHASES.forEach((phase, index) => {
    const record = records[index];
    requireExact(record, ["phase", "fingerprint"], "source_fingerprint_record_invalid", "source");
    if (record.phase !== phase || !isObject(record.fingerprint)) {
      fail("source_fingerprint_phase_invalid", "source", "source fingerprint phase order drifted", record);
    }
    if (!validateSourceFingerprint(record.fingerprint)) {
      fail("source_fingerprint_shape_invalid", "source",
        "source fingerprint does not cover the canonical Crafting asset inventory", { phase });
    }
    if (canonical == null) canonical = record.fingerprint;
    else if (!Transcript.deepEqual(canonical, record.fingerprint)) {
      fail("source_fingerprint_drift", "source", "source/candidate inputs changed during session", {
        phase,
        expected: canonical,
        actual: record.fingerprint
      });
    }
  });
  return { phaseCount: records.length, fingerprint: canonical };
}

function validateSlotFileSet(value, label) {
  if (!isObject(value) || !Array.isArray(value.files) || value.files.length < 1
      || typeof value.slot !== "string" || !value.slot.startsWith("crazyflasher7_saves")
      || !HEX64.test(String(value.setSha256 || ""))) {
    fail("seed_file_set_invalid", "seed", label + " seed JSON/SOL set is malformed", value);
  }
  let jsonCount = 0;
  let previous = "";
  value.files.forEach((file) => {
    requireExact(file, ["kind", "path", "bytes", "sha256"],
      "seed_file_record_invalid", "seed");
    if ((file.kind !== "json" && file.kind !== "sol")
        || typeof file.path !== "string" || file.path <= previous
        || !Number.isInteger(file.bytes) || file.bytes < 0 || !HEX64.test(file.sha256)) {
      fail("seed_file_record_invalid", "seed", label + " seed file record is malformed", file);
    }
    if (file.kind === "json") jsonCount += 1;
    previous = file.path;
  });
  if (jsonCount !== 1) fail("seed_json_count_invalid", "seed", "seed set needs exactly one JSON file");
  const computed = sha256(Buffer.from(JSON.stringify(value.files), "utf8"));
  if (computed !== value.setSha256) {
    fail("seed_set_hash_invalid", "seed", label + " seed set digest does not match records");
  }
  return value;
}

function verifySeedInvariant(seed) {
  if (!isObject(seed)) fail("seed_invariant_missing", "seed", "seed invariant evidence is missing");
  const before = validateSlotFileSet(seed.before, "before");
  const after = validateSlotFileSet(seed.after, "after");
  if (!Transcript.deepEqual(before, after)) {
    fail("seed_source_changed", "seed", "read-only seed JSON/SOL set changed", { before, after });
  }
  return {
    slot: before.slot,
    files: before.files,
    setSha256: before.setSha256,
    fileCount: before.files.length,
    unchanged: true
  };
}

function relevantBusinessClicks(events, floors) {
  return events.filter((event) => event.sequence > floors.interactionSequence
    && event.sequence < floors.tailSequence && event.kind === "capture_click")
    .filter((event) => {
      const selector = String(event.detail && event.detail.selector || "");
      return selector.includes("crafting-recipe-card")
        || selector.includes("crafting-commit-btn")
        || selector.includes("data-commit-primary");
    });
}

function verifyTrustedClicks(events, floors, selected, commit) {
  const clicks = relevantBusinessClicks(events, floors);
  const untrusted = clicks.find((event) => !event.detail
    || event.detail.browserEventIsTrusted !== true);
  if (untrusted) {
    fail("untrusted_business_click", "input_trust",
      "browser event trust is absent for a Crafting business click", untrusted);
  }
  const recipeClicks = clicks.filter((event) => {
    const selector = String(event.detail.selector || "");
    return selector.includes("crafting-recipe-card")
      && String(event.detail.workbenchKey) === String(selected.response.recipeIndex);
  });
  if (recipeClicks.length !== 1
      || recipeClicks[0].sequence >= selected.event.sequence) {
    fail("trusted_recipe_click_invalid", "input_trust",
      "selected preview needs exactly one preceding trusted recipe click", recipeClicks);
  }
  const commitClicks = clicks.filter((event) => {
    const selector = String(event.detail.selector || "");
    return selector.includes("crafting-commit-btn")
      || selector.includes("data-commit-primary");
  });
  if (commit) {
    if (commitClicks.length !== 1
        || commitClicks[0].sequence <= selected.responseEvent.sequence
        || commitClicks[0].sequence >= commit.event.sequence) {
      fail("trusted_commit_click_invalid", "input_trust",
        "commit needs exactly one trusted click after selected preview", commitClicks);
    }
  } else if (commitClicks.length !== 0) {
    fail("restart_commit_click_detected", "input_trust",
      "restart readback must not contain a commit click", commitClicks);
  }
  return {
    recipeSequence: recipeClicks[0].sequence,
    commitSequence: commit ? commitClicks[0].sequence : null
  };
}

function checkpoint(events, sequence, label) {
  const event = events.find((entry) => entry.sequence === sequence);
  if (!event || event.kind !== "observer_checkpoint" || !event.detail
      || event.detail.label !== label || !isObject(event.detail.data)) {
    fail("journey_floor_checkpoint_invalid", "journey", "checkpoint is absent or mislabeled", {
      sequence,
      label,
      event
    });
  }
  return event;
}

function validateLogWindow(records, floors) {
  if (!Array.isArray(records) || records.length === 0
      || !isObject(floors) || !Number.isInteger(floors.ingressLogFloor)
      || !Number.isInteger(floors.interactionLogFloor)
      || !Number.isInteger(floors.tailLogEnd)
      || floors.ingressLogFloor < 0
      || floors.interactionLogFloor <= floors.ingressLogFloor
      || floors.tailLogEnd < floors.interactionLogFloor) {
    fail("journey_log_floor_invalid", "journey", "log floors are malformed", floors);
  }
  let previous = floors.ingressLogFloor;
  records.forEach((record) => {
    if (!isObject(record) || !Number.isInteger(record.lineNumber)
        || record.lineNumber !== previous + 1 || typeof record.line !== "string") {
      fail("journey_log_window_truncated", "journey",
        "raw Host log window is missing, duplicated, or reordered", { previous, record });
    }
    previous = record.lineNumber;
  });
  if (previous !== floors.tailLogEnd) {
    fail("journey_log_tail_mismatch", "journey", "raw Host log window does not reach tail seal", {
      expected: floors.tailLogEnd,
      actual: previous
    });
  }
}

function validatePreFloorLogWindow(records, floors, label) {
  if (!Array.isArray(records) || !Number.isInteger(floors.startLogFloor)
      || floors.startLogFloor < 0 || floors.startLogFloor > floors.ingressLogFloor) {
    fail("journey_pre_floor_log_invalid", "journey",
      label + " pre-ingress Host log window is malformed");
  }
  let previous = floors.startLogFloor;
  records.forEach((record) => {
    if (!isObject(record) || !Number.isInteger(record.lineNumber)
        || record.lineNumber !== previous + 1 || typeof record.line !== "string") {
      fail("journey_pre_floor_log_truncated", "journey",
        label + " pre-ingress Host log window is incomplete", { previous, record });
    }
    const line = record.line;
    if (line.includes("[CraftingTask] -> Flash:")
        || line.includes("[InventoryTask] -> Flash:")
        || (line.includes("[XmlSocket:JSON]")
          && (/\"panel\"\s*:\s*\"crafting\"/.test(line)
            || /\"domain\"\s*:\s*\"(?:crafting|inventory)\"/.test(line)))) {
      fail("business_before_ingress_log_floor", "journey",
        label + " business traffic existed before the Host ingress floor", record);
    }
    previous = record.lineNumber;
  });
  if (previous !== floors.ingressLogFloor) {
    fail("journey_pre_floor_log_tail_mismatch", "journey",
      label + " pre-ingress Host window does not reach ingress floor", {
        expected: floors.ingressLogFloor,
        actual: previous
      });
  }
}

function validateJourneyFloors(transcript, preFloorRecords, logRecords, floors, label) {
  const events = Transcript.assertTranscript(transcript);
  if (!isObject(floors) || !Number.isInteger(floors.ingressSequence)
      || !Number.isInteger(floors.interactionSequence)
      || !Number.isInteger(floors.tailSequence)
      || floors.ingressSequence <= 0 || floors.interactionSequence <= floors.ingressSequence
      || floors.tailSequence <= floors.interactionSequence
      || floors.tailSequence !== transcript.sequence) {
    fail("journey_sequence_floor_invalid", "journey", label + " sequence floors are malformed", floors);
  }
  const ingress = checkpoint(events, floors.ingressSequence, label + "_ingress_floor");
  const interaction = checkpoint(events, floors.interactionSequence, label + "_interaction_floor");
  const tail = checkpoint(events, floors.tailSequence, label + "_tail_seal");
  if (ingress.detail.data.logFloor !== floors.ingressLogFloor
      || interaction.detail.data.logFloor !== floors.interactionLogFloor
      || tail.detail.data.logEnd !== floors.tailLogEnd) {
    fail("journey_floor_binding_invalid", "journey", "Web checkpoints do not bind Host log floors", {
      ingress: ingress.detail.data,
      interaction: interaction.detail.data,
      tail: tail.detail.data,
      floors
    });
  }
  validatePreFloorLogWindow(preFloorRecords, floors, label);
  validateLogWindow(logRecords, floors);
  const preFloorBusiness = events.find((event) => event.sequence <= floors.ingressSequence && (() => {
    const message = Transcript.bridgeMessage(event);
    return message && message.type === "panel"
      && (message.domain === "crafting" || message.domain === "inventory");
  })());
  if (preFloorBusiness) {
    fail("business_before_ingress_floor", "journey",
      "business traffic existed before the production ingress floor", preFloorBusiness);
  }
  return events;
}

function inventoryRequest(message, owner) {
  requireExact(message,
    ["type", "domain", "panel", "cmd", "panelInstanceId", "callId", "payload"],
    "inventory_request_keys_invalid", "journey");
  if (message.type !== "panel" || message.domain !== "inventory" || message.panel !== "crafting"
      || message.cmd !== "snapshot" || message.panelInstanceId !== owner
      || !SAFE_TOKEN.test(String(message.callId || "")) || !isObject(message.payload)) {
    fail("inventory_request_invalid", "journey", "Inventory authority request is malformed", message);
  }
  requireExact(message.payload, ["v", "requests"], "inventory_payload_keys_invalid", "journey");
  if (message.payload.v !== 1 || !Array.isArray(message.payload.requests)
      || message.payload.requests.length !== 2) {
    fail("inventory_payload_invalid", "journey", "Inventory snapshot does not cover exact storage pair");
  }
  const expected = [
    { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
    { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" }
  ];
  if (!Transcript.deepEqual(message.payload.requests, expected)) {
    fail("inventory_windows_invalid", "journey", "Inventory snapshot windows drifted", message.payload.requests);
  }
}

function inventoryResponse(message, request, owner) {
  requireExact(message,
    ["type", "domain", "panel", "panelInstanceId", "cmd", "callId", "success",
      "v", "sessionNonce", "snapshots"],
    "inventory_response_keys_invalid", "journey");
  if (message.type !== "panel_resp" || message.domain !== "inventory"
      || message.panel !== "crafting" || message.panelInstanceId !== owner
      || message.cmd !== "snapshot" || message.callId !== request.callId
      || message.success !== true || message.v !== 1 || message.clientSynthetic === true
      || !SAFE_TOKEN.test(String(message.sessionNonce || ""))
      || !Array.isArray(message.snapshots)) {
    fail("inventory_response_invalid", "journey", "Inventory authority response is malformed", message);
  }
  const ids = message.snapshots.map((snapshot) => snapshot && snapshot.containerId);
  if (ids.length !== 2 || ids[0] !== "背包" || ids[1] !== "战备箱") {
    fail("inventory_snapshot_coverage_invalid", "journey", "Inventory response missed storage pair", ids);
  }
  message.snapshots.forEach((snapshot, index) => {
    const expected = request.payload.requests[index];
    if (!InventoryRuntime.isValidSnapshot(snapshot)) {
      fail("inventory_snapshot_projection_invalid", "journey",
        "Inventory response is not a valid production projection", {
          containerId: snapshot && snapshot.containerId,
          index
        });
    }
    const expectedLimit = Math.min(expected.limit,
      Math.max(0, Number(snapshot.viewCapacity) - expected.offset));
    if (snapshot.containerId !== expected.containerId
        || snapshot.filterKey !== expected.filterKey
        || snapshot.offset !== expected.offset
        || snapshot.limit !== expectedLimit
        || snapshot.pageSizeHint !== expected.limit
        || Object.prototype.hasOwnProperty.call(snapshot, "filterSpec")
        || Object.prototype.hasOwnProperty.call(snapshot, "scope")) {
      fail("inventory_snapshot_window_mismatch", "journey",
        "Inventory production projection does not bind to the exact requested window", {
          expected,
          actual: {
            containerId: snapshot.containerId,
            filterKey: snapshot.filterKey,
            offset: snapshot.offset,
            limit: snapshot.limit,
            pageSizeHint: snapshot.pageSizeHint,
            filterSpec: snapshot.filterSpec,
            scope: snapshot.scope
          }
        });
    }
  });
}

function isBusinessRequest(message) {
  return isObject(message) && message.type === "panel"
    && (message.domain === "crafting" || message.domain === "inventory");
}

function isBusinessResponse(message) {
  return isObject(message) && message.type === "panel_resp"
    && (message.domain === "crafting" || message.domain === "inventory");
}

function collectJourneyCalls(events, floors, owner) {
  const calls = [];
  const outstanding = { crafting: null, inventory: null };
  const callIds = new Set();
  for (const event of events) {
    if (event.sequence <= floors.ingressSequence || event.sequence > floors.tailSequence) continue;
    const outbound = Transcript.bridgeMessage(event);
    if (isBusinessRequest(outbound)) {
      if (outbound.domain === "crafting") Transcript.validateRequestMessage(outbound, owner);
      else inventoryRequest(outbound, owner);
      if (!event.detail || event.detail.completed !== true || event.detail.returned !== true
          || event.detail.threw) {
        fail("business_send_not_accepted", "journey", "Bridge.send did not synchronously accept request", event);
      }
      if (outstanding[outbound.domain]) {
        fail("domain_not_single_flight", "journey", "domain issued a request before prior response", {
          pending: outstanding[outbound.domain].message.callId,
          next: outbound.callId
        });
      }
      const globalKey = outbound.domain + ":" + outbound.callId;
      if (callIds.has(globalKey)) fail("duplicate_web_call_id", "journey", "Web callId was reused", outbound);
      callIds.add(globalKey);
      const call = { event, message: outbound, responseEvent: null, response: null };
      calls.push(call);
      outstanding[outbound.domain] = call;
      continue;
    }
    const inbound = Transcript.hostMessage(event);
    if (isBusinessResponse(inbound)) {
      const call = outstanding[inbound.domain];
      if (!call || call.message.callId !== inbound.callId) {
        fail("business_response_out_of_order", "journey", "response did not match domain single-flight", inbound);
      }
      if (inbound.domain === "crafting") {
        Transcript.validateResponseMessage(inbound, call.message, owner);
      } else inventoryResponse(inbound, call.message, owner);
      call.responseEvent = event;
      call.response = inbound;
      outstanding[inbound.domain] = null;
    }
  }
  Object.keys(outstanding).forEach((domain) => {
    if (outstanding[domain]) {
      fail("unresolved_business_call", "journey", "tail seal contains unresolved request", {
        domain,
        callId: outstanding[domain].message.callId
      });
    }
  });
  return calls;
}

function parseInventoryFlash(record) {
  const marker = "[InventoryTask] -> Flash: ";
  const line = record && typeof record.line === "string" ? record.line : "";
  const index = line.indexOf(marker);
  if (index < 0) return null;
  try { return { record, message: JSON.parse(line.slice(index + marker.length).trim()) }; }
  catch (_error) { return { record, message: null }; }
}

function hostBusinessRecords(logRecords) {
  return logRecords.map((record) => {
    const crafting = Transcript.parseHostFlash(record);
    if (crafting) return { domain: "crafting", record, message: crafting.message };
    const inventory = parseInventoryFlash(record);
    return inventory ? { domain: "inventory", record, message: inventory.message } : null;
  }).filter(Boolean);
}

function isHostWrite(entry) {
  if (!entry.message) return false;
  if (entry.domain === "crafting") return entry.message.action === "craftingCommit";
  return entry.domain === "inventory" && entry.message.action !== INVENTORY_ACTION
    && entry.message.action !== "inventoryTooltip";
}

function isWebWrite(call) {
  return call.message.domain === "crafting" ? call.message.cmd === "commit"
    : call.message.cmd !== "snapshot" && call.message.cmd !== "tooltip";
}

function correlateAllCalls(calls, logRecords, floors, mode) {
  const host = hostBusinessRecords(logRecords);
  const hostWrites = host.filter(isHostWrite);
  const webWrites = calls.filter(isWebWrite);
  const expectedWrites = mode === "commit" ? 1 : 0;
  if (hostWrites.length !== expectedWrites || webWrites.length !== expectedWrites) {
    fail("tail_write_detected", "tail",
      mode + " process has a missing, extra, or Host-only write at terminal seal", {
        hostWrites,
        webWrites: webWrites.map((entry) => entry.message)
      });
  }
  if (host.length !== calls.length || host.some((entry) => !entry.message)) {
    fail("host_fid_count_invalid", "host_correlation",
      "every Web business call needs exactly one parseable Host fid", {
        webCalls: calls.length,
        hostRecords: host.length,
        malformed: host.filter((entry) => !entry.message).length
      });
  }
  const fids = { crafting: new Set(), inventory: new Set() };
  return calls.map((call, index) => {
    const entry = host[index];
    if (entry.domain !== call.message.domain) {
      fail("host_fid_order_invalid", "host_correlation", "Host domain order drifted", {
        web: call.message,
        host: entry
      });
    }
    const expectedAction = call.message.domain === "crafting"
      ? Transcript.ACTION_BY_CMD[call.message.cmd] : INVENTORY_ACTION;
    const expectedKeys = ["task", "action", "callId"].concat(Object.keys(call.message.payload));
    requireExact(entry.message, expectedKeys, "host_payload_keys_invalid", "host_correlation");
    if (entry.message.task !== "cmd" || entry.message.action !== expectedAction
        || !Number.isInteger(entry.message.callId) || entry.message.callId <= 0
        || fids[entry.domain].has(entry.message.callId)) {
      fail("host_fid_invalid", "host_correlation", "Host fid/action is malformed or reused", entry);
    }
    fids[entry.domain].add(entry.message.callId);
    const payload = Object.assign({}, entry.message);
    delete payload.task; delete payload.action; delete payload.callId;
    if (!Transcript.deepEqual(payload, call.message.payload)) {
      fail("host_payload_mismatch", "host_correlation", "Host payload differs from Web request", {
        web: call.message.payload,
        host: payload
      });
    }
    const inInteractionPhase = call.event.sequence > floors.interactionSequence;
    if (inInteractionPhase !== (entry.record.lineNumber > floors.interactionLogFloor)) {
      fail("web_host_floor_mismatch", "host_correlation",
        "Web sequence and Host line crossed different interaction floors", { call, entry, floors });
    }
    return {
      domain: entry.domain,
      cmd: call.message.cmd,
      webCallId: call.message.callId,
      as2CallId: entry.message.callId,
      hostLogLine: entry.record.lineNumber,
      requestSequence: call.event.sequence,
      responseSequence: call.responseEvent.sequence
    };
  });
}

function successful(calls, domain, cmd) {
  return calls.filter((call) => call.message.domain === domain && call.message.cmd === cmd
    && call.response && call.response.success === true);
}

function verifyInitialCraftingOrder(calls, floors, label) {
  const before = calls.filter((call) => call.message.domain === "crafting"
    && call.response && call.response.success === true
    && call.responseEvent.sequence < floors.interactionSequence
    && call.message.cmd !== "tooltip");
  if (before.length < 2 || before[0].message.cmd !== "snapshot"
      || before[1].message.cmd !== "preview") {
    fail("initial_authority_order_invalid", "journey",
      label + " must begin with authoritative snapshot then preview", before.map((call) => ({
        cmd: call.message.cmd,
        callId: call.message.callId,
        requestSequence: call.event.sequence,
        responseSequence: call.responseEvent.sequence
      })));
  }
  return { snapshot: before[0], preview: before[1] };
}

function stripEnvelope(message) {
  const body = Object.assign({}, message);
  ["type", "domain", "panel", "panelInstanceId", "cmd", "callId", "success", "craftToken"]
    .forEach((field) => { delete body[field]; });
  return body;
}

function inventoryCount(response, identity) {
  let count = 0;
  let matchingSlots = 0;
  (response.snapshots || []).forEach((snapshot) => {
    if (!snapshot || snapshot.containerId !== "背包" || !Array.isArray(snapshot.slots)) return;
    snapshot.slots.forEach((slot) => {
      const item = slot && slot.occupied === true ? slot.item : null;
      if (!item || item.name !== identity.name) return;
      matchingSlots += 1;
      if (item.displayName !== identity.displayName || item.icon !== identity.icon) {
        fail("inventory_output_identity_mismatch", "inventory",
          "Inventory item reused internal name with wrong display/icon", item);
      }
      const quantity = Number(item.quantity);
      if (!Number.isFinite(quantity) || quantity <= 0) {
        fail("inventory_output_quantity_invalid", "inventory", "Inventory quantity is invalid", item);
      }
      count += quantity;
    });
  });
  return { count, matchingSlots };
}

function verifyCommitTrace(evidence) {
  const events = validateJourneyFloors(
    evidence.transcript, evidence.preFloorRecords,
    evidence.logRecords, evidence.floors, "first");
  const ingress = Transcript.validateIngress(evidence.transcript, evidence.logRecords, {
    entryFloorSequence: evidence.floors.ingressSequence
  });
  if (ingress.openSequence >= evidence.floors.interactionSequence
      || ingress.as2PanelRequestLine <= evidence.floors.ingressLogFloor
      || ingress.as2PanelRequestLine > evidence.floors.interactionLogFloor) {
    fail("ingress_floor_order_invalid", "journey",
      "production ingress did not occur strictly between double floors", ingress);
  }
  const calls = collectJourneyCalls(events, evidence.floors, ingress.panelInstanceId);
  const mapping = correlateAllCalls(calls, evidence.logRecords, evidence.floors, "commit");
  const initial = verifyInitialCraftingOrder(calls, evidence.floors, "first");
  if (initial.snapshot.message.payload.category !== ingress.category
      || initial.preview.message.payload.category !== ingress.category) {
    fail("initial_category_drift", "journey",
      "initial Crafting authority escaped the production ingress category", {
        ingress: ingress.category,
        snapshot: initial.snapshot.message.payload.category,
        preview: initial.preview.message.payload.category
      });
  }
  const snapshots = successful(calls, "crafting", "snapshot");
  const previews = successful(calls, "crafting", "preview");
  const commits = successful(calls, "crafting", "commit");
  if (!snapshots.some((call) => call.event.sequence < evidence.floors.interactionSequence)) {
    fail("initial_snapshot_missing", "journey", "initial snapshot is absent before interaction floor");
  }
  if (commits.length !== 1) fail("commit_count_invalid", "journey", "exactly one commit is required");
  const commit = commits[0];
  const postInteractionCrafting = calls.filter((call) => call.message.domain === "crafting"
    && call.response && call.response.success === true
    && call.event.sequence > evidence.floors.interactionSequence
    && call.message.cmd !== "tooltip");
  const requiredOrder = ["preview", "commit", "snapshot", "preview"];
  if (postInteractionCrafting.length < requiredOrder.length
      || requiredOrder.some((cmd, index) =>
        postInteractionCrafting[index].message.cmd !== cmd)) {
    fail("commit_authority_order_invalid", "journey",
      "selected preview/commit/fresh snapshot/fresh preview order drifted",
      postInteractionCrafting.map((call) => call.message.cmd));
  }
  const selected = previews.filter((call) => call.event.sequence > evidence.floors.interactionSequence
    && call.responseEvent.sequence < commit.event.sequence).pop();
  if (!selected) fail("selected_preview_missing", "journey", "selected preview is absent after interaction floor");
  const trustedClicks = verifyTrustedClicks(events, evidence.floors, selected, commit);
  if (commit.message.payload.expectedCraftToken !== selected.response.craftToken
      || commit.response.recipeIndex !== selected.response.recipeIndex
      || commit.response.craftCount !== selected.response.craftCount
      || !Transcript.deepEqual(commit.response.crafted, selected.response.output)) {
    fail("commit_preview_binding_invalid", "journey", "commit did not consume exact selected preview");
  }
  const freshSnapshot = snapshots.find((call) => call.event.sequence > commit.responseEvent.sequence);
  const freshPreview = previews.find((call) => freshSnapshot
    && call.event.sequence > freshSnapshot.responseEvent.sequence);
  if (!freshSnapshot || !freshPreview) {
    fail("fresh_authority_missing", "journey", "commit lacks fresh snapshot/preview");
  }
  const deepPoststate = Transcript.verifyCommitJourney({
    transcript: evidence.transcript,
    interactionFloorSequence: evidence.floors.interactionSequence,
    ingress,
    logRecords: evidence.logRecords.filter((record) =>
      record.lineNumber > evidence.floors.interactionLogFloor)
  });
  const inventories = successful(calls, "inventory", "snapshot");
  const beforeInventory = inventories.filter((call) =>
    call.responseEvent.sequence < evidence.floors.interactionSequence).pop();
  const afterInventory = inventories.find((call) =>
    call.event.sequence > freshPreview.responseEvent.sequence);
  if (!beforeInventory || !afterInventory) {
    fail("inventory_authority_missing", "inventory",
      "initial and post-commit Inventory snapshots are both required");
  }
  if (beforeInventory.response.sessionNonce !== afterInventory.response.sessionNonce) {
    fail("inventory_session_nonce_drift", "inventory",
      "one live process must keep one authoritative Inventory session nonce", {
        before: beforeInventory.response.sessionNonce,
        after: afterInventory.response.sessionNonce
      });
  }
  ["背包", "战备箱"].forEach((containerId) => {
    const beforeSnapshot = beforeInventory.response.snapshots.find((snapshot) =>
      snapshot.containerId === containerId);
    const afterSnapshot = afterInventory.response.snapshots.find((snapshot) =>
      snapshot.containerId === containerId);
    if (!beforeSnapshot || !afterSnapshot
        || afterSnapshot.snapshotSeq <= beforeSnapshot.snapshotSeq
        || afterSnapshot.containerEpoch !== beforeSnapshot.containerEpoch
        || afterSnapshot.containerVersion < beforeSnapshot.containerVersion
        || (containerId === "背包"
          && afterSnapshot.containerVersion <= beforeSnapshot.containerVersion)) {
      fail("inventory_freshness_invalid", "inventory",
        "post-commit Inventory proof is stale or crossed authority epochs", {
          containerId,
          before: beforeSnapshot && {
            snapshotSeq: beforeSnapshot.snapshotSeq,
            containerEpoch: beforeSnapshot.containerEpoch,
            containerVersion: beforeSnapshot.containerVersion
          },
          after: afterSnapshot && {
            snapshotSeq: afterSnapshot.snapshotSeq,
            containerEpoch: afterSnapshot.containerEpoch,
            containerVersion: afterSnapshot.containerVersion
          }
        });
    }
  });
  const identity = {
    name: commit.response.crafted.name,
    displayName: commit.response.crafted.displayName,
    icon: commit.response.crafted.icon
  };
  const before = inventoryCount(beforeInventory.response, identity);
  const after = inventoryCount(afterInventory.response, identity);
  const expectedDelta = Number(commit.response.crafted.quantity);
  if (!Number.isFinite(expectedDelta) || expectedDelta <= 0
      || after.count - before.count !== expectedDelta || after.count === before.count) {
    fail("inventory_output_delta_invalid", "inventory",
      "crafted output has no exact observable Inventory quantity delta", {
        identity,
        before,
        after,
        expectedDelta
      });
  }
  return {
    ingress,
    mapping,
    owner: ingress.panelInstanceId,
    initialSnapshot: initial.snapshot.response,
    selectedPreview: selected.response,
    commit: commit.response,
    freshSnapshot: freshSnapshot.response,
    freshPreview: freshPreview.response,
    beforeInventory: beforeInventory.response,
    afterInventory: afterInventory.response,
    inventoryCounts: { before: before.count, after: after.count, delta: expectedDelta },
    identity,
    trustedClicks,
    deepPoststate
  };
}

function verifyRestartTrace(evidence, committed) {
  const events = validateJourneyFloors(
    evidence.transcript, evidence.preFloorRecords,
    evidence.logRecords, evidence.floors, "restart");
  const ingress = Transcript.validateIngress(evidence.transcript, evidence.logRecords, {
    entryFloorSequence: evidence.floors.ingressSequence,
    expectedCategory: committed.ingress.category
  });
  if (ingress.openSequence >= evidence.floors.interactionSequence
      || ingress.as2PanelRequestLine <= evidence.floors.ingressLogFloor
      || ingress.as2PanelRequestLine > evidence.floors.interactionLogFloor) {
    fail("ingress_floor_order_invalid", "journey",
      "restart production ingress did not occur strictly between double floors", ingress);
  }
  const calls = collectJourneyCalls(events, evidence.floors, ingress.panelInstanceId);
  const mapping = correlateAllCalls(calls, evidence.logRecords, evidence.floors, "readback");
  const initialOrder = verifyInitialCraftingOrder(calls, evidence.floors, "restart");
  if (initialOrder.snapshot.message.payload.category !== ingress.category
      || initialOrder.preview.message.payload.category !== ingress.category) {
    fail("initial_category_drift", "readback",
      "restart initial authority escaped the production ingress category", {
        ingress: ingress.category,
        snapshot: initialOrder.snapshot.message.payload.category,
        preview: initialOrder.preview.message.payload.category
      });
  }
  const snapshots = successful(calls, "crafting", "snapshot");
  const previews = successful(calls, "crafting", "preview");
  const initialSnapshot = initialOrder.snapshot;
  const selected = previews.find((call) =>
    call.event.sequence > evidence.floors.interactionSequence
      && call.response.recipeIndex === committed.selectedPreview.recipeIndex
      && call.response.craftCount === committed.selectedPreview.craftCount);
  if (!initialSnapshot || !selected) {
    fail("restart_authority_missing", "readback", "restart snapshot/selected preview is absent");
  }
  const trustedClicks = verifyTrustedClicks(events, evidence.floors, selected, null);
  if (!Transcript.deepEqual(stripEnvelope(initialSnapshot.response),
    stripEnvelope(committed.freshSnapshot))
      || !Transcript.deepEqual(stripEnvelope(selected.response),
        stripEnvelope(committed.freshPreview))) {
    fail("restart_crafting_readback_mismatch", "readback",
      "restart Crafting authority differs from committed fresh poststate");
  }
  const inventory = successful(calls, "inventory", "snapshot")
    .find((call) => call.event.sequence > selected.responseEvent.sequence);
  if (!inventory) fail("restart_inventory_missing", "inventory", "restart Inventory snapshot is absent");
  if (ingress.panelInstanceId === committed.owner) {
    fail("restart_owner_reused", "readback",
      "restart must bind a fresh production panel instance", ingress.panelInstanceId);
  }
  if (inventory.response.sessionNonce === committed.beforeInventory.sessionNonce) {
    fail("restart_inventory_nonce_reused", "inventory",
      "restart must bind a fresh Inventory authority session nonce",
      inventory.response.sessionNonce);
  }
  const count = inventoryCount(inventory.response, committed.identity);
  if (count.count !== committed.inventoryCounts.after) {
    fail("restart_inventory_mismatch", "inventory",
      "restart Inventory quantity does not preserve crafted output", {
        expected: committed.inventoryCounts.after,
        actual: count.count
      });
  }
  return {
    ingress,
    mapping,
    owner: ingress.panelInstanceId,
    snapshot: initialSnapshot.response,
    preview: selected.response,
    inventory: inventory.response,
    inventoryCount: count.count,
    trustedClicks
  };
}

function parseArchiveReceipt(record, slot, targetPath) {
  if (!record || typeof record.line !== "string" || typeof targetPath !== "string") return null;
  const body = record.line.replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
  const match = body.match(
    /^\[ArchiveTask\] Shadow saved: ([A-Za-z0-9_-]+) \((\d+) chars\) path=(.+)$/);
  if (!match || match[1] !== slot
      || path.resolve(match[3]).toLowerCase() !== path.resolve(targetPath).toLowerCase()) return null;
  const archiveChars = Number(match[2]);
  return Number.isSafeInteger(archiveChars) && archiveChars > 0
    ? { archiveChars, targetPath: path.resolve(match[3]) } : null;
}

function verifyPersistence(persistence, committed, runtime, seed, firstLogs) {
  if (!isObject(persistence) || !isObject(persistence.lock)
      || persistence.lock.targetSlot !== "cf7_agent_a3_crafting"
      || persistence.lock.ownerRunId !== persistence.runId
      || persistence.lock.exclusive !== true || persistence.lock.acquired !== true
      || persistence.lock.acquireMode !== "create_new"
      || persistence.lock.contentionProbeRejected !== true
      || typeof persistence.lock.path !== "string"
      || !persistence.lock.path.endsWith("cf7_agent_a3_crafting.live-e2e.lock")
      || persistence.lock.released !== true || persistence.lock.heldThroughFinalShutdown !== true
      || !isObject(persistence.clonePreparation) || !isObject(persistence.initialBaseline)
      || !isObject(persistence.archive) || !isObject(persistence.persisted)
      || !isObject(persistence.restartBaseline) || !isObject(persistence.firstShutdown)
      || !isObject(persistence.finalShutdown)) {
    fail("persistence_evidence_invalid", "persistence", "clone/lock/archive evidence is incomplete");
  }
  const commitLine = committed.mapping.find((entry) => entry.cmd === "commit").hostLogLine;
  const archiveRecord = firstLogs.records.find((record) =>
    record.lineNumber === persistence.archive.lineNumber);
  const seedJson = seed.files.find((file) => file.kind === "json");
  const parsedArchive = parseArchiveReceipt(
    archiveRecord, persistence.lock.targetSlot, persistence.archive.targetPath);
  if (persistence.clonePreparation.seedSlot !== seed.slot
      || persistence.clonePreparation.targetSlot !== persistence.lock.targetSlot
      || persistence.clonePreparation.seedSetSha256 !== seed.setSha256
      || persistence.clonePreparation.seedJsonSha256 !== seedJson.sha256
      || !HEX64.test(String(persistence.clonePreparation.seedSemanticSha256 || ""))
      || !HEX64.test(String(persistence.clonePreparation.seededTargetSha256 || ""))
      || !HEX64.test(String(persistence.initialBaseline.sha256 || ""))
      || !HEX64.test(String(persistence.initialBaseline.semanticSha256 || ""))
      || !HEX64.test(String(persistence.persisted.sha256 || ""))
      || !HEX64.test(String(persistence.persisted.semanticSha256 || ""))
      || !HEX64.test(String(persistence.restartBaseline.sha256 || ""))
      || !HEX64.test(String(persistence.restartBaseline.semanticSha256 || ""))
      || persistence.clonePreparation.seedSemanticSha256
        !== persistence.initialBaseline.semanticSha256
      || persistence.clonePreparation.seededTargetSha256
        !== persistence.initialBaseline.sha256
      || persistence.initialBaseline.semanticSha256 === persistence.persisted.semanticSha256
      || persistence.persisted.semanticSha256 !== persistence.restartBaseline.semanticSha256
      || persistence.persisted.sha256 !== persistence.restartBaseline.sha256
      || String(persistence.initialBaseline.role) !== String(persistence.persisted.role)
      || String(persistence.persisted.role) !== String(persistence.restartBaseline.role)
      || String(persistence.initialBaseline.level) !== String(persistence.persisted.level)
      || String(persistence.persisted.level) !== String(persistence.restartBaseline.level)
      || typeof persistence.initialBaseline.role !== "string"
      || persistence.initialBaseline.role.length === 0
      || !Number.isInteger(persistence.initialBaseline.level)
      || typeof persistence.persisted.role !== "string"
      || persistence.persisted.role.length === 0
      || !Number.isInteger(persistence.persisted.level)
      || typeof persistence.restartBaseline.role !== "string"
      || persistence.restartBaseline.role.length === 0
      || !Number.isInteger(persistence.restartBaseline.level)
      || !Number.isInteger(persistence.persisted.textChars)
      || persistence.persisted.textChars <= 0
      || persistence.archive.slot !== persistence.lock.targetSlot
      || persistence.archive.status !== "archived"
      || persistence.archive.lineNumber <= commitLine
      || persistence.archive.lineNumber >= firstLogs.floors.tailLogEnd
      || !archiveRecord
      || !parsedArchive
      || parsedArchive.archiveChars !== persistence.archive.archiveChars
      || persistence.persisted.textChars !== persistence.archive.archiveChars
      || persistence.archive.lineSha256 !== sha256(Buffer.from(archiveRecord.line, "utf8"))) {
    fail("clone_archive_readback_invalid", "persistence",
      "clone archive/restart baseline does not bind verified commit", persistence);
  }
  [
    [persistence.firstShutdown, runtime.firstPid],
    [persistence.finalShutdown, runtime.restartPid]
  ].forEach(([shutdown, pid]) => {
    if (shutdown.supportedShutdown !== true || shutdown.oldPid !== pid
        || shutdown.processExited !== true || shutdown.launcherPortsFileAbsent !== true
        || shutdown.credentialAbsent !== true || shutdown.cdpPortClosed !== true
        || !Array.isArray(shutdown.projectProcesses) || shutdown.projectProcesses.length !== 0) {
      fail("shutdown_residue_invalid", "residue", "shutdown/residue evidence is incomplete", shutdown);
    }
  });
  return {
    cloneSlot: persistence.lock.targetSlot,
    archiveLine: persistence.archive.lineNumber,
    restartSemanticSha256: persistence.restartBaseline.semanticSha256,
    lockReleased: true,
    zeroResidue: true
  };
}

function readArtifact(entry, baseDirectory, options) {
  if (path.isAbsolute(entry.path) || entry.path.split(/[\\/]+/).includes("..")) {
    fail("artifact_path_invalid", "artifacts", "artifact path escaped session directory", entry);
  }
  if (options && isObject(options.artifacts)
      && Object.prototype.hasOwnProperty.call(options.artifacts, entry.role)) {
    return Buffer.from(JSON.stringify(options.artifacts[entry.role]), "utf8");
  }
  if (!baseDirectory) fail("artifact_base_missing", "artifacts", "artifact base directory is required");
  const absolute = path.resolve(baseDirectory, entry.path);
  const relative = path.relative(baseDirectory, absolute);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("artifact_path_invalid", "artifacts", "artifact path escaped session directory", entry);
  }
  let stat;
  try { stat = fs.lstatSync(absolute); }
  catch (error) {
    fail("artifact_file_missing", "artifacts", "raw artifact is absent or inaccessible", {
      entry,
      error: error.message
    });
  }
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("artifact_file_invalid", "artifacts", "artifact is not a regular file", entry);
  }
  return fs.readFileSync(absolute);
}

function loadArtifacts(bundle, baseDirectory, options) {
  if (!Array.isArray(bundle.artifactManifest) || bundle.artifactManifest.length !== RAW_ROLES.length) {
    fail("artifact_manifest_invalid", "artifacts", "raw artifact manifest is incomplete");
  }
  const result = {};
  const seen = new Set();
  const seenPaths = new Set();
  bundle.artifactManifest.forEach((entry) => {
    requireExact(entry, ["role", "path", "bytes", "sha256"],
      "artifact_manifest_entry_invalid", "artifacts");
    if (!RAW_ROLES.includes(entry.role) || seen.has(entry.role)
        || typeof entry.path !== "string" || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || !HEX64.test(entry.sha256)) {
      fail("artifact_manifest_entry_invalid", "artifacts", "artifact manifest entry is malformed", entry);
    }
    const normalizedPath = entry.path.replace(/\\/g, "/").toLowerCase();
    if (seenPaths.has(normalizedPath)) {
      fail("artifact_manifest_path_reused", "artifacts",
        "raw artifact roles must not alias one path", entry);
    }
    seen.add(entry.role);
    seenPaths.add(normalizedPath);
    const bytes = readArtifact(entry, baseDirectory, options);
    if (bytes.length !== entry.bytes || sha256(bytes) !== entry.sha256) {
      fail("artifact_digest_mismatch", "artifacts", "raw artifact bytes/hash mismatched manifest", entry);
    }
    try { result[entry.role] = JSON.parse(bytes.toString("utf8")); }
    catch (error) { fail("artifact_json_invalid", "artifacts", error.message, entry); }
  });
  return result;
}

function verifyArtifactBindings(bundle, artifacts) {
  const boundRoles = [
    "firstTranscript", "firstLogs", "restartTranscript", "restartLogs", "runtime",
    "persistence", "sourceFingerprints", "seedInvariant", "control"
  ];
  const drifted = boundRoles.filter((role) => !isObject(artifacts[role])
    || artifacts[role].runId !== bundle.runId
    || artifacts[role].cloneSlot !== bundle.cloneSlot);
  if (drifted.length !== 0) {
    fail("session_cross_binding_invalid", "bundle",
      "run/clone binding drifted across raw artifacts", { drifted });
  }
  if (!isObject(artifacts.runtime.first) || !isObject(artifacts.runtime.restart)
      || artifacts.firstTranscript.processPid !== artifacts.runtime.first.pid
      || artifacts.firstLogs.processPid !== artifacts.runtime.first.pid
      || artifacts.restartTranscript.processPid !== artifacts.runtime.restart.pid
      || artifacts.restartLogs.processPid !== artifacts.runtime.restart.pid
      || !isObject(artifacts.firstLogs.floors) || !isObject(artifacts.restartLogs.floors)
      || artifacts.firstLogs.floors.startLogFloor !== artifacts.runtime.first.startLogFloor
      || artifacts.restartLogs.floors.startLogFloor !== artifacts.runtime.restart.startLogFloor) {
    fail("session_process_binding_invalid", "bundle",
      "transcript/log artifacts are not bound to the verified process sessions");
  }
}

function verifyControlWithIndependentVerifier(control, context, options) {
  const verifier = options && options.controlVerifier;
  if (typeof verifier !== "function") {
    fail("control_verifier_unavailable", "control",
      "an independent shared computer-use evidence verifier is required");
  }
  let result;
  try { result = verifier(control, context); }
  catch (error) {
    fail(error && error.code || "control_evidence_unverified", "control",
      error && error.message || "shared control verifier rejected evidence",
      error && error.details || null);
  }
  if (!isObject(result) || result.verified !== true
      || result.browserEventAcksVerified !== true
      || result.safeExitAcksVerified !== true
      || result.transportProvenanceVerified !== true
      || result.captureDigestsVerified !== true
      || result.ttlVerified !== true
      || result.fallbackPolicyVerified !== true) {
    fail("control_evidence_unverified", "control",
      "shared verifier did not close every computer-use control gate", result);
  }
  return result;
}

function verifySessionEvidence(bundle, options) {
  if (!isObject(bundle) || bundle.schema !== SESSION_SCHEMA
      || typeof bundle.runId !== "string" || bundle.runId.length < 8
      || bundle.cloneSlot !== "cf7_agent_a3_crafting"
      || bundle.deploymentStatus !== "NOT_DEPLOYED") {
    fail("session_bundle_invalid", "bundle", "session bundle envelope is malformed", bundle);
  }
  if (options && isObject(options.artifacts)
      && options.testOnlyAllowInjectedArtifacts !== true) {
    fail("artifact_injection_forbidden", "artifacts",
      "raw artifacts may only be injected by the explicit offline fixture harness");
  }
  const artifacts = loadArtifacts(bundle, options && options.baseDirectory, options);
  verifyArtifactBindings(bundle, artifacts);
  const runtime = verifyRuntimeEvidence(artifacts.runtime);
  const source = verifySourceFingerprints(artifacts.sourceFingerprints.records);
  const seed = verifySeedInvariant(artifacts.seedInvariant);
  const first = verifyCommitTrace({
    transcript: artifacts.firstTranscript,
    preFloorRecords: artifacts.firstLogs.preFloorRecords,
    logRecords: artifacts.firstLogs.records,
    floors: artifacts.firstLogs.floors
  });
  const restart = verifyRestartTrace({
    transcript: artifacts.restartTranscript,
    preFloorRecords: artifacts.restartLogs.preFloorRecords,
    logRecords: artifacts.restartLogs.records,
    floors: artifacts.restartLogs.floors
  }, first);
  const persistence = verifyPersistence(
    artifacts.persistence, first, runtime, seed, artifacts.firstLogs);
  const control = verifyControlWithIndependentVerifier(artifacts.control, {
    runId: bundle.runId,
    cloneSlot: bundle.cloneSlot,
    firstPid: runtime.firstPid,
    restartPid: runtime.restartPid,
    firstOwner: first.owner,
    restartOwner: restart.owner,
    firstIngressLogLine: first.ingress.as2PanelRequestLine,
    restartIngressLogLine: restart.ingress.as2PanelRequestLine,
    firstRecipeClickSequence: first.trustedClicks.recipeSequence,
    firstCommitClickSequence: first.trustedClicks.commitSequence,
    restartRecipeClickSequence: restart.trustedClicks.recipeSequence,
    firstSelectedPreview: first.mapping.find((entry) => entry.domain === "crafting"
      && entry.cmd === "preview"
      && entry.requestSequence > artifacts.firstLogs.floors.interactionSequence),
    firstCommit: first.mapping.find((entry) => entry.domain === "crafting"
      && entry.cmd === "commit"),
    firstInventoryBefore: first.mapping.find((entry) => entry.domain === "inventory"
      && entry.webCallId === first.beforeInventory.callId),
    firstInventoryAfter: first.mapping.find((entry) => entry.domain === "inventory"
      && entry.webCallId === first.afterInventory.callId),
    restartSelectedPreview: restart.mapping.find((entry) => entry.domain === "crafting"
      && entry.cmd === "preview"
      && entry.requestSequence > artifacts.restartLogs.floors.interactionSequence),
    restartInventory: restart.mapping.find((entry) => entry.domain === "inventory"
      && entry.webCallId === restart.inventory.callId),
    archiveLine: persistence.archiveLine
  }, options);
  return {
    schema: "crafting.production-session-verification.v2",
    runId: bundle.runId,
    cloneSlot: bundle.cloneSlot,
    runtime,
    source,
    seed,
    first: {
      owner: first.owner,
      commitCallId: first.mapping.find((entry) => entry.cmd === "commit").webCallId,
      identity: first.identity,
      inventoryCounts: first.inventoryCounts,
      exactCallMappings: first.mapping.length
    },
    restart: {
      owner: restart.owner,
      previewCallId: restart.mapping.find((entry) => entry.cmd === "preview"
        && entry.requestSequence > artifacts.restartLogs.floors.interactionSequence).webCallId,
      inventoryCount: restart.inventoryCount,
      exactCallMappings: restart.mapping.length
    },
    persistence,
    control: {
      provider: control.provider || null,
      ackCount: control.ackCount,
      controlEvidenceVerified: true
    },
    outputInventoryCountReadbackVerified: true,
    completeTailSealsVerified: true,
    status: "e2e_verified",
    deploymentStatus: "NOT_DEPLOYED"
  };
}

function main(argv) {
  if (argv.length !== 2 || argv[0] !== "--input") {
    process.stderr.write("Usage: node verify-session-evidence.js --input <session-evidence.json>\n");
    process.exitCode = 2;
    return;
  }
  const inputPath = path.resolve(argv[1]);
  const bundle = JSON.parse(fs.readFileSync(inputPath, "utf8"));
  const result = verifySessionEvidence(bundle, { baseDirectory: path.dirname(inputPath) });
  process.stdout.write(JSON.stringify({ ok: true, result }, null, 2) + "\n");
}

function supersededEntry() {
  const error = new Error("SUPERSEDED / NOT_ADMITTED: use bootstrap.js --verify-bundle");
  error.code = "superseded_not_admitted";
  throw error;
}

module.exports = {
  RAW_ROLES,
  SESSION_SCHEMA,
  SOURCE_PHASES,
  STABLE_IDENTITY_FIELDS,
  inventoryCount,
  sameStableIdentity,
  stableIdentity,
  verifyCommitTrace: supersededEntry,
  verifyRestartTrace: supersededEntry,
  verifyRuntimeEvidence: supersededEntry,
  verifySessionEvidence: supersededEntry,
  verifySourceFingerprints: supersededEntry
};

if (require.main === module) {
  process.stderr.write("SUPERSEDED / NOT_ADMITTED: use bootstrap.js --verify-bundle <path>.\n");
  process.exitCode = 2;
}
