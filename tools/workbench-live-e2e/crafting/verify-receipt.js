#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { PRODUCTION_HREF, RECORDER_SCHEMA } = require("./passive-recorder");
const CraftingRuntime = require("../../../launcher/web/modules/crafting-runtime");

const OWNER_RE = /^[A-Za-z0-9._~-]{1,128}$/;
const CALL_RE = /^craft\.[A-Za-z0-9._~-]{1,90}$/;
const TOKEN_RE = /^[A-Za-z0-9._-]{1,160}$/;
const CATEGORIES = new Set([
  "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
  "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
]);
const ACTION_BY_CMD = Object.freeze({
  snapshot: "craftingSnapshot",
  preview: "craftingPreview",
  commit: "craftingCommit",
  tooltip: "craftingTooltip"
});

class GateError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "GateError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
  }
}

function fail(code, phase, message, details) {
  throw new GateError(code, phase, message, details);
}

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (isObject(value)) {
    const out = {};
    Object.keys(value).sort().forEach((key) => { out[key] = stable(value[key]); });
    return out;
  }
  return value;
}

function deepEqual(left, right) {
  return JSON.stringify(stable(left)) === JSON.stringify(stable(right));
}

function exactKeys(value, expected) {
  if (!isObject(value)) return false;
  const actual = Object.keys(value).sort();
  const wanted = expected.slice().sort();
  return actual.length === wanted.length
    && actual.every((key, index) => key === wanted[index]);
}

function requireExactKeys(value, expected, code, phase) {
  if (!exactKeys(value, expected)) {
    fail(code, phase, "exact key contract failed", {
      expected: expected.slice().sort(),
      actual: isObject(value) ? Object.keys(value).sort() : null
    });
  }
}

function identityTriple(value) {
  return isObject(value)
    && safeIdentityText(value.name, 256)
    && safeIdentityText(value.displayName, 256)
    && safeIdentityText(value.icon, 256);
}

function finiteNonNegative(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function integerInRange(value, minimum, maximum) {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}

function safeIdentityText(value, maximum) {
  return typeof value === "string" && value.length > 0 && value.length <= maximum
    && value.trim().length > 0 && value.trim().toLowerCase() !== "undefined"
    && !/[\u0000-\u001F\u007F]/.test(value);
}

function validBalance(value) {
  return exactKeys(value, ["money", "kpoints"])
    && finiteNonNegative(value.money) && finiteNonNegative(value.kpoints);
}

function sameTriple(left, right) {
  return identityTriple(left) && identityTriple(right)
    && left.name === right.name
    && left.displayName === right.displayName
    && left.icon === right.icon;
}

function assertTranscript(transcript) {
  if (!isObject(transcript) || transcript.schema !== RECORDER_SCHEMA
      || transcript.domain !== "crafting" || !safeIdentityText(transcript.recorderId, 160)
      || !integerInRange(transcript.bridgePatchCount, 1, 100000)
      || !integerInRange(transcript.exportCount, 1, 1000000)
      || !finiteNonNegative(transcript.startedEpochMs)
      || transcript.href !== PRODUCTION_HREF
      || transcript.origin !== "https://overlay.local"
      || transcript.pathname !== "/overlay.html"
      || !Array.isArray(transcript.events)) {
    fail("transcript_invalid", "transcript", "passive transcript envelope is malformed");
  }
  let previous = 0;
  transcript.events.forEach((event) => {
    if (!isObject(event) || !Number.isInteger(event.sequence)
        || event.sequence <= previous || typeof event.kind !== "string"
        || !isObject(event.detail)) {
      fail("transcript_sequence_invalid", "transcript", "event sequence is not strict", event);
    }
    previous = event.sequence;
  });
  if (transcript.sequence !== previous) {
    fail("transcript_tail_mismatch", "transcript", "exported sequence does not match event tail", {
      exported: transcript.sequence,
      tail: previous
    });
  }
  return transcript.events;
}

function hostMessage(event) {
  return event && event.kind === "host_message" && event.detail
    ? event.detail.message : null;
}

function bridgeMessage(event) {
  return event && event.kind === "bridge_send" && event.detail
    ? event.detail.message : null;
}

function isCraftingRequest(message) {
  return isObject(message) && message.type === "panel" && message.domain === "crafting";
}

function isCraftingResponse(message) {
  return isObject(message) && message.type === "panel_resp" && message.domain === "crafting";
}

function validateOpenMessage(message, expectedCategory) {
  requireExactKeys(message, ["type", "cmd", "panel", "panelInstanceId", "initData"],
    "open_keys_invalid", "ingress");
  if (message.type !== "panel_cmd" || message.cmd !== "open" || message.panel !== "crafting"
      || !OWNER_RE.test(String(message.panelInstanceId || "")) || !isObject(message.initData)) {
    fail("open_envelope_invalid", "ingress", "crafting panel_cmd open is malformed", message);
  }
  requireExactKeys(message.initData,
    ["mode", "category", "source", "debug", "panelInstanceId"],
    "open_init_keys_invalid", "ingress");
  if (message.initData.mode !== "runtime" || message.initData.source !== "world_crafting_entry"
      || message.initData.debug !== false
      || message.initData.panelInstanceId !== message.panelInstanceId
      || !CATEGORIES.has(message.initData.category)
      || (expectedCategory && message.initData.category !== expectedCategory)) {
    fail("open_init_contract_invalid", "ingress", "production crafting initData is not exact", message.initData);
  }
  return {
    panelInstanceId: message.panelInstanceId,
    category: message.initData.category,
    source: message.initData.source
  };
}

function parseXmlSocketJson(record) {
  const marker = "[XmlSocket:JSON] ";
  const line = record && typeof record.line === "string" ? record.line : "";
  const index = line.indexOf(marker);
  if (index < 0) return null;
  const body = line.slice(index + marker.length).trim();
  if (!body.startsWith("{")) return null;
  try { return JSON.parse(body); } catch (_error) { return null; }
}

function validateIngress(transcript, logRecords, options) {
  const events = assertTranscript(transcript);
  const floor = options && Number.isInteger(options.entryFloorSequence)
    ? options.entryFloorSequence : 0;
  const openEvents = events.filter((event) => event.sequence > floor)
    .map((event) => ({ event, message: hostMessage(event) }))
    .filter((entry) => entry.message && entry.message.type === "panel_cmd"
      && entry.message.cmd === "open" && entry.message.panel === "crafting");
  if (openEvents.length !== 1) {
    fail("production_open_count_invalid", "ingress", "expected exactly one fresh crafting open", {
      count: openEvents.length
    });
  }
  const owner = validateOpenMessage(openEvents[0].message, options && options.expectedCategory);

  const panelRequests = (logRecords || []).map((record) => ({
    record,
    message: parseXmlSocketJson(record)
  })).filter((entry) => (entry.message && entry.message.panel === "crafting")
    || (entry.record && typeof entry.record.line === "string"
      && entry.record.line.includes("[XmlSocket:JSON]")
      && /"panel"\s*:\s*"crafting"/.test(entry.record.line)));
  if (panelRequests.length !== 1) {
    fail("as2_panel_request_count_invalid", "ingress",
      "expected exactly one fresh AS2 crafting panel_request", { count: panelRequests.length });
  }
  if (!panelRequests[0].message) {
    fail("as2_panel_request_malformed", "ingress",
      "fresh AS2 crafting panel_request JSON is malformed", panelRequests[0].record);
  }
  const request = panelRequests[0].message;
  if (!Number.isInteger(panelRequests[0].record.lineNumber)
      || panelRequests[0].record.lineNumber <= 0
      || typeof panelRequests[0].record.line !== "string") {
    fail("as2_panel_request_record_invalid", "ingress",
      "AS2 production ingress record lacks a stable log position", panelRequests[0].record);
  }
  requireExactKeys(request, ["task", "panel", "source", "initData"],
    "as2_panel_request_keys_invalid", "ingress");
  requireExactKeys(request.initData, ["category"],
    "as2_panel_request_init_keys_invalid", "ingress");
  if (request.task !== "panel_request" || request.panel !== "crafting"
      || request.source !== "world_crafting_entry"
      || request.initData.category !== owner.category) {
    fail("as2_panel_request_invalid", "ingress", "AS2 production ingress tuple mismatched", request);
  }
  return {
    openSequence: openEvents[0].event.sequence,
    panelInstanceId: owner.panelInstanceId,
    category: owner.category,
    source: owner.source,
    as2PanelRequestLine: panelRequests[0].record.lineNumber,
    as2PanelRequestRecord: {
      lineNumber: panelRequests[0].record.lineNumber,
      line: panelRequests[0].record.line
    },
    as2PanelRequest: request
  };
}

function requestKeys(cmd) {
  if (cmd === "snapshot") return ["v", "category"];
  if (cmd === "preview") return ["v", "category", "recipeIndex", "craftCount"];
  if (cmd === "commit") return ["v", "category", "expectedCraftToken"];
  if (cmd === "tooltip") return ["v", "itemName"];
  return null;
}

function validateRequestMessage(message, owner) {
  requireExactKeys(message,
    ["type", "domain", "panel", "cmd", "panelInstanceId", "callId", "payload"],
    "request_keys_invalid", "web_calls");
  if (!ACTION_BY_CMD[message.cmd] || !CALL_RE.test(String(message.callId || ""))
      || message.type !== "panel" || message.domain !== "crafting"
      || message.panel !== "crafting" || message.panelInstanceId !== owner
      || !isObject(message.payload)) {
    fail("request_envelope_invalid", "web_calls", "crafting request envelope is malformed", message);
  }
  requireExactKeys(message.payload, requestKeys(message.cmd),
    "request_payload_keys_invalid", "web_calls");
  if (message.payload.v !== 1) {
    fail("request_version_invalid", "web_calls", "crafting request must carry v=1", message);
  }
  if (message.cmd === "snapshot") {
    if (!CATEGORIES.has(message.payload.category)) {
      fail("request_selector_invalid", "web_calls", "snapshot category is invalid", message.payload);
    }
  } else if (message.cmd === "preview") {
    if (!CATEGORIES.has(message.payload.category)
        || !integerInRange(message.payload.recipeIndex, 0, 999)
        || !integerInRange(message.payload.craftCount, 1, 99)) {
      fail("request_selector_invalid", "web_calls", "preview selector is invalid", message.payload);
    }
  } else if (message.cmd === "commit") {
    if (!CATEGORIES.has(message.payload.category)
        || !TOKEN_RE.test(String(message.payload.expectedCraftToken || ""))) {
      fail("request_selector_invalid", "web_calls", "commit selector/token is invalid", message.payload);
    }
  } else if (message.cmd === "tooltip"
      && !safeIdentityText(message.payload.itemName, 128)) {
    fail("request_selector_invalid", "web_calls", "tooltip itemName is invalid", message.payload);
  }
}

function responseBodyKeys(cmd, response) {
  if (cmd === "snapshot") {
    return ["v", "category", "gender", "recipes", "balance", "skills", "note"];
  }
  if (cmd === "preview") {
    const keys = ["v", "category", "recipeIndex", "craftCount", "batchEligible",
      "maxCraftCount", "output", "materials", "cost", "balance", "skills",
      "levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints",
      "enoughSpace", "canCommit", "blockingError"];
    if (response.canCommit === true) keys.push("craftToken");
    return keys;
  }
  if (cmd === "commit") {
    return ["v", "operation", "category", "recipeIndex", "craftCount", "crafted", "balance"];
  }
  if (cmd === "tooltip") return ["v", "itemName", "displayName", "descHTML", "introHTML"];
  return [];
}

function validateResponseMessage(response, request, owner) {
  if (!isCraftingResponse(response) || response.panel !== "crafting"
      || response.panelInstanceId !== owner || response.cmd !== request.cmd
      || response.callId !== request.callId || response.clientSynthetic === true) {
    fail("response_envelope_invalid", "web_calls", "response did not mirror the exact request", {
      request,
      response
    });
  }
  if (response.success !== true) {
    fail("authority_response_failed", "web_calls", "journey contains a failed authority response", response);
  }
  if (!CraftingRuntime.validateBusinessResponse(response, {
    cmd: request.cmd,
    metadata: { payload: request.payload }
  })) {
    fail("production_response_rejected", "web_calls",
      "production Crafting runtime would reject the recorded authority response", response);
  }
  const envelope = ["type", "domain", "panel", "panelInstanceId", "cmd", "callId", "success"];
  requireExactKeys(response, envelope.concat(responseBodyKeys(request.cmd, response)),
    "response_keys_invalid", "web_calls");
  if (response.v !== 1) {
    fail("response_version_invalid", "web_calls", "authority response must carry v=1", response);
  }
  if (Object.prototype.hasOwnProperty.call(request.payload, "category")
      && response.category !== request.payload.category) {
    fail("response_selector_invalid", "web_calls", "response category did not match request", {
      request: request.payload,
      response
    });
  }
  if (request.cmd === "snapshot") {
    if (!Array.isArray(response.recipes) || !validBalance(response.balance)) {
      fail("response_body_invalid", "web_calls", "snapshot authority body is malformed", response);
    }
  } else if (request.cmd === "preview") {
    if (response.recipeIndex !== request.payload.recipeIndex
        || response.craftCount !== request.payload.craftCount
        || !identityTriple(response.output) || !Array.isArray(response.materials)
        || !validBalance(response.balance) || !validBalance(response.cost)
        || typeof response.canCommit !== "boolean"
        || (response.canCommit === true
          ? !TOKEN_RE.test(String(response.craftToken || ""))
          : Object.prototype.hasOwnProperty.call(response, "craftToken"))) {
      fail("response_body_invalid", "web_calls", "preview authority body is malformed", response);
    }
  } else if (request.cmd === "commit") {
    if (response.operation !== "commit" || !integerInRange(response.recipeIndex, 0, 999)
        || !integerInRange(response.craftCount, 1, 99)
        || !identityTriple(response.crafted) || !validBalance(response.balance)) {
      fail("response_body_invalid", "web_calls", "commit authority body is malformed", response);
    }
  } else if (request.cmd === "tooltip"
      && response.itemName !== request.payload.itemName) {
    fail("response_selector_invalid", "web_calls", "tooltip response did not bind itemName", response);
  }
}

function collectCalls(events, floor, owner) {
  const requests = [];
  const responses = new Map();
  const outstanding = [];
  for (const event of events) {
    if (event.sequence <= floor) continue;
    const outbound = bridgeMessage(event);
    if (isCraftingRequest(outbound)) {
      validateRequestMessage(outbound, owner);
      if (event.detail.completed !== true || event.detail.returned !== true || event.detail.threw) {
        fail("bridge_send_not_accepted", "web_calls", "Bridge.send did not return true exactly", event);
      }
      if (outstanding.length !== 0) {
        fail("domain_not_single_flight", "web_calls",
          "a crafting request was issued before the prior response", {
            pending: outstanding.map((entry) => entry.message.callId),
            next: outbound.callId
          });
      }
      if (requests.some((entry) => entry.message.callId === outbound.callId)) {
        fail("duplicate_call_id", "web_calls", "Web callId was reused", outbound);
      }
      const entry = { event, message: outbound, responseEvent: null, response: null };
      requests.push(entry);
      outstanding.push(entry);
      continue;
    }
    const inbound = hostMessage(event);
    if (isCraftingResponse(inbound) && inbound.panelInstanceId === owner) {
      if (responses.has(inbound.callId)) {
        fail("duplicate_call_response", "web_calls", "callId received more than one response", inbound);
      }
      const entry = requests.find((candidate) => candidate.message.callId === inbound.callId);
      if (!entry || outstanding.length !== 1 || outstanding[0] !== entry) {
        fail("orphan_or_out_of_order_response", "web_calls", "response was not exact single-flight", inbound);
      }
      validateResponseMessage(inbound, entry.message, owner);
      entry.responseEvent = event;
      entry.response = inbound;
      responses.set(inbound.callId, inbound);
      outstanding.shift();
    }
  }
  if (outstanding.length !== 0) {
    fail("unresolved_call", "web_calls", "crafting request remained unresolved", {
      callIds: outstanding.map((entry) => entry.message.callId)
    });
  }
  return requests;
}

function parseHostFlash(record) {
  const marker = "[CraftingTask] -> Flash: ";
  const line = record && typeof record.line === "string" ? record.line : "";
  const index = line.indexOf(marker);
  if (index < 0) return null;
  try {
    return { record, message: JSON.parse(line.slice(index + marker.length).trim()) };
  } catch (_error) {
    return { record, message: null };
  }
}

function correlateHostCalls(calls, logRecords) {
  const host = (logRecords || []).map(parseHostFlash).filter(Boolean);
  if (host.some((entry) => !entry.message) || host.length !== calls.length) {
    fail("host_call_count_ambiguous", "host_correlation",
      "single-flight Web calls do not have a one-to-one Host fid log", {
        webCalls: calls.length,
        hostCalls: host.length,
        malformed: host.filter((entry) => !entry.message).length
      });
  }
  const fids = new Set();
  let previousLine = 0;
  return calls.map((call, index) => {
    const entry = host[index];
    if (!entry.record || !Number.isInteger(entry.record.lineNumber)
        || entry.record.lineNumber <= previousLine) {
      fail("host_log_order_invalid", "host_correlation",
        "Host fid records are not in strict log order", entry && entry.record);
    }
    previousLine = entry.record.lineNumber;
    const expectedAction = ACTION_BY_CMD[call.message.cmd];
    const expectedKeys = ["task", "action", "callId"].concat(Object.keys(call.message.payload));
    requireExactKeys(entry.message, expectedKeys,
      "host_flash_keys_invalid", "host_correlation");
    if (entry.message.task !== "cmd" || entry.message.action !== expectedAction
        || !Number.isInteger(entry.message.callId) || entry.message.callId <= 0) {
      fail("host_flash_envelope_invalid", "host_correlation", "Host Flash command is malformed", entry);
    }
    if (fids.has(entry.message.callId)) {
      fail("host_fid_reused", "host_correlation", "Host reused an AS2 fid", entry);
    }
    fids.add(entry.message.callId);
    const normalized = Object.assign({}, entry.message);
    delete normalized.task;
    delete normalized.action;
    delete normalized.callId;
    if (!deepEqual(normalized, call.message.payload)) {
      fail("host_payload_mismatch", "host_correlation", "Host normalized payload mismatched Web", {
        web: call.message.payload,
        host: normalized
      });
    }
    return {
      cmd: call.message.cmd,
      webCallId: call.message.callId,
      as2CallId: entry.message.callId,
      hostLogLine: entry.record.lineNumber
    };
  });
}

function findRelevantClicks(events, floor) {
  return events.filter((event) => event.sequence > floor && event.kind === "capture_click")
    .filter((event) => {
      const selector = String(event.detail.selector || "");
      return selector.includes("crafting-recipe-card")
        || selector.includes("crafting-commit-btn")
        || selector.includes("data-commit-primary");
    });
}

function assertNoUntrustedBusinessClick(clicks) {
  const untrusted = clicks.find((event) => event.detail.browserEventIsTrusted !== true);
  if (untrusted) {
    fail("untrusted_business_click", "input_trust",
      "synthetic/untrusted crafting business click cannot close A3", untrusted);
  }
}

function latestSuccessfulPreview(calls, beforeSequence) {
  return calls.filter((call) => call.message.cmd === "preview"
    && call.response && call.response.success === true
    && call.response.canCommit === true
    && call.responseEvent.sequence < beforeSequence).pop() || null;
}

function snapshotRecipe(snapshot, recipeIndex) {
  const recipes = snapshot && Array.isArray(snapshot.recipes) ? snapshot.recipes : [];
  return recipes.find((recipe) => Number(recipe.recipeIndex) === Number(recipeIndex)) || null;
}

function assertNumber(value, code, phase) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(code, phase, "expected a finite number", value);
  }
  return value;
}

function verifyPoststate(preview, commit, freshSnapshot, freshPreview) {
  if (!identityTriple(preview.output) || !deepEqual(preview.output, commit.crafted)
      || !deepEqual(preview.output, freshPreview.output)) {
    fail("crafted_identity_drift", "poststate",
      "preview output, commit crafted output, and fresh preview output differ");
  }
  const freshRecipe = snapshotRecipe(freshSnapshot, preview.recipeIndex);
  if (!freshRecipe || !sameTriple(freshRecipe.output, preview.output)) {
    fail("fresh_recipe_identity_mismatch", "poststate",
      "fresh snapshot did not preserve the committed recipe identity triple");
  }
  ["money", "kpoints"].forEach((field) => {
    const before = assertNumber(preview.balance[field], "preview_balance_invalid", "poststate");
    const cost = assertNumber(preview.cost[field], "preview_cost_invalid", "poststate");
    const expected = before - cost;
    if (commit.balance[field] !== expected || freshSnapshot.balance[field] !== expected
        || freshPreview.balance[field] !== expected) {
      fail("balance_poststate_mismatch", "poststate", "balance delta did not match preview cost", {
        field,
        before,
        cost,
        expected,
        commit: commit.balance[field],
        freshSnapshot: freshSnapshot.balance[field],
        freshPreview: freshPreview.balance[field]
      });
    }
  });
  if (!Array.isArray(preview.materials) || !Array.isArray(freshPreview.materials)
      || preview.materials.length !== freshPreview.materials.length) {
    fail("material_projection_count_mismatch", "poststate",
      "fresh material projection count changed", {
        before: Array.isArray(preview.materials) ? preview.materials.length : null,
        after: Array.isArray(freshPreview.materials) ? freshPreview.materials.length : null
      });
  }
  const materialProof = preview.materials.map((before, index) => {
    const after = freshPreview.materials[index];
    if (!after || !sameTriple(before, after) || before.required !== after.required
        || before.consumed !== after.consumed || before.isQuantity !== after.isQuantity
        || before.itemKind !== after.itemKind || before.tier !== after.tier
        || !finiteNonNegative(before.owned) || !finiteNonNegative(after.owned)
        || !finiteNonNegative(before.maxEnhancement)
        || !finiteNonNegative(after.maxEnhancement)) {
      fail("material_projection_drift", "poststate", "fresh material projection mismatched", {
        index,
        before,
        after
      });
    }
    let mode;
    if (before.consumed === false) {
      mode = "retained_exact";
      if (after.owned !== before.owned) {
        fail("retained_material_changed", "poststate", "non-consumed material changed", { before, after });
      }
    } else if (before.itemKind === "stack" || before.isQuantity === true) {
      mode = "stack_delta_exact";
      if (after.owned !== before.owned - before.required) {
        fail("stack_material_delta_mismatch", "poststate", "stack consumption delta mismatched", {
          before,
          after
        });
      }
    } else {
      mode = "equipment_single_consume_and_authority_refresh";
      if (after.owned !== before.owned - 1
          || after.maxEnhancement > before.maxEnhancement) {
        fail("equipment_material_refresh_invalid", "poststate",
          "equipment material did not consume one item and refresh authority", { before, after });
      }
    }
    return { name: before.name, mode, beforeOwned: before.owned, afterOwned: after.owned };
  });
  return { materialProof, outputInventoryCountReadbackVerified: false };
}

function verifyCommitJourney(input) {
  const events = assertTranscript(input.transcript);
  const floor = input.interactionFloorSequence;
  if (!Number.isInteger(floor) || floor <= 0) {
    fail("interaction_floor_invalid", "transcript", "interaction floor is required");
  }
  const owner = input.ingress && input.ingress.panelInstanceId;
  if (!OWNER_RE.test(String(owner || ""))) fail("owner_invalid", "transcript", "owner is invalid");
  const calls = collectCalls(events, floor, owner);
  if (calls.length < 4) fail("commit_chain_incomplete", "commit", "too few authority calls");
  const commits = calls.filter((call) => call.message.cmd === "commit");
  if (commits.length !== 1) {
    fail("commit_count_invalid", "commit", "journey must contain exactly one commit", {
      count: commits.length
    });
  }
  const commitCall = commits[0];
  const previewCall = latestSuccessfulPreview(calls, commitCall.event.sequence);
  if (!previewCall || !TOKEN_RE.test(String(previewCall.response.craftToken || ""))) {
    fail("accepted_preview_missing", "commit", "commit has no final accepted token preview");
  }
  if (previewCall.response.category !== input.ingress.category) {
    fail("ingress_category_drift", "commit",
      "selected preview escaped the production ingress category");
  }
  if (commitCall.message.payload.expectedCraftToken !== previewCall.response.craftToken
      || commitCall.message.payload.category !== previewCall.response.category) {
    fail("commit_token_mismatch", "commit", "commit did not consume the final accepted token");
  }
  const laterPreview = calls.find((call) => call.message.cmd === "preview"
    && call.event.sequence > previewCall.responseEvent.sequence
    && call.event.sequence < commitCall.event.sequence);
  if (laterPreview) fail("preview_superseded_before_commit", "commit", "preview token was superseded");
  const commit = commitCall.response;
  if (commit.operation !== "commit" || commit.category !== previewCall.response.category
      || commit.recipeIndex !== previewCall.response.recipeIndex
      || commit.craftCount !== previewCall.response.craftCount) {
    fail("commit_response_selector_mismatch", "commit", "commit response selector mismatched preview");
  }

  const freshSnapshotCall = calls.find((call) => call.message.cmd === "snapshot"
    && call.event.sequence > commitCall.responseEvent.sequence);
  if (!freshSnapshotCall) fail("fresh_snapshot_missing", "poststate", "commit was not followed by snapshot");
  const freshPreviewCall = calls.find((call) => call.message.cmd === "preview"
    && call.event.sequence > freshSnapshotCall.responseEvent.sequence);
  if (!freshPreviewCall) fail("fresh_preview_missing", "poststate", "fresh snapshot was not followed by preview");
  if (freshPreviewCall.message.payload.recipeIndex !== previewCall.response.recipeIndex
      || freshPreviewCall.message.payload.craftCount !== previewCall.response.craftCount
      || freshPreviewCall.message.payload.category !== previewCall.response.category) {
    fail("fresh_preview_selector_mismatch", "poststate", "fresh preview selector drifted");
  }
  if (freshPreviewCall.response.canCommit === true
      && freshPreviewCall.response.craftToken === previewCall.response.craftToken) {
    fail("fresh_preview_token_reused", "poststate",
      "fresh authoritative preview reused the consumed commit token");
  }

  const priorSnapshots = events.filter((event) => event.sequence < previewCall.event.sequence)
    .map(hostMessage).filter((message) => isCraftingResponse(message)
      && message.panelInstanceId === owner && message.cmd === "snapshot" && message.success === true);
  const initialSnapshot = priorSnapshots.pop();
  const initialRecipe = snapshotRecipe(initialSnapshot, previewCall.response.recipeIndex);
  if (!initialRecipe || !sameTriple(initialRecipe.output, previewCall.response.output)) {
    fail("selected_recipe_identity_mismatch", "commit", "selected snapshot recipe triple mismatched preview");
  }

  const clicks = findRelevantClicks(events, floor);
  assertNoUntrustedBusinessClick(clicks);
  const allRecipeClicks = clicks.filter((event) =>
    String(event.detail.selector).includes("crafting-recipe-card"));
  const recipeClicks = allRecipeClicks.filter((event) =>
    String(event.detail.workbenchKey) === String(previewCall.response.recipeIndex)
      && event.sequence < previewCall.event.sequence);
  if (allRecipeClicks.length !== 1 || recipeClicks.length !== 1
      || recipeClicks[0].detail.disabled === true || recipeClicks[0].detail.button !== 0) {
    fail("trusted_recipe_click_invalid", "input_trust",
      "accepted preview lacks one exact trusted recipe click", allRecipeClicks);
  }
  const commitClicks = clicks.filter((event) => (
    String(event.detail.selector).includes("crafting-commit-btn")
      || String(event.detail.selector).includes("data-commit-primary")
  ));
  if (commitClicks.length !== 1
      || commitClicks[0].sequence <= previewCall.responseEvent.sequence
      || commitClicks[0].sequence >= commitCall.event.sequence
      || commitClicks[0].detail.disabled === true || commitClicks[0].detail.button !== 0) {
    fail("trusted_commit_click_invalid", "input_trust", "commit click boundary is not exact", commitClicks);
  }

  const correlation = correlateHostCalls(calls, input.logRecords);
  const poststate = verifyPoststate(
    previewCall.response,
    commit,
    freshSnapshotCall.response,
    freshPreviewCall.response
  );
  return {
    ownerPanel: "crafting",
    panelInstanceId: owner,
    category: previewCall.response.category,
    recipeIndex: previewCall.response.recipeIndex,
    craftCount: previewCall.response.craftCount,
    selector: recipeClicks[recipeClicks.length - 1].detail.selector,
    identityTriple: {
      name: previewCall.response.output.name,
      displayName: previewCall.response.output.displayName,
      icon: previewCall.response.output.icon
    },
    craftToken: previewCall.response.craftToken,
    previewCallId: previewCall.message.callId,
    commitCallId: commitCall.message.callId,
    freshSnapshotCallId: freshSnapshotCall.message.callId,
    freshPreviewCallId: freshPreviewCall.message.callId,
    commitResponse: commit,
    freshPoststate: {
      snapshot: freshSnapshotCall.response,
      preview: freshPreviewCall.response,
      proof: poststate
    },
    hostCorrelation: correlation,
    trustedWebClicks: true,
    exactlyOneWrite: true,
    singleFlight: true
  };
}

function verifyReadbackJourney(input) {
  const events = assertTranscript(input.transcript);
  const floor = input.interactionFloorSequence;
  const owner = input.ingress && input.ingress.panelInstanceId;
  const expected = input.expectedPoststate;
  if (!Number.isInteger(floor) || !OWNER_RE.test(String(owner || ""))
      || !expected || !isObject(expected.snapshot) || !isObject(expected.preview)) {
    fail("readback_input_invalid", "readback", "readback verifier input is malformed");
  }
  const calls = collectCalls(events, floor, owner);
  if (calls.some((call) => call.message.cmd === "commit")) {
    fail("readback_write_detected", "readback", "readback phase must remain read-only");
  }
  const previews = calls.filter((call) => call.message.cmd === "preview"
    && call.response && call.response.success === true
    && call.response.recipeIndex === expected.recipeIndex
    && call.response.craftCount === expected.craftCount);
  if (previews.length !== 1) {
    fail("readback_preview_count_invalid", "readback",
      "expected exactly one selected recipe readback preview", { count: previews.length });
  }
  const preview = previews[0];
  if (preview.response.category !== input.ingress.category) {
    fail("readback_category_drift", "readback",
      "readback preview escaped the production ingress category");
  }
  const clicks = findRelevantClicks(events, floor);
  assertNoUntrustedBusinessClick(clicks);
  const allRecipeClicks = clicks.filter((event) =>
    String(event.detail.selector).includes("crafting-recipe-card"));
  const recipeClicks = allRecipeClicks.filter((event) => String(event.detail.workbenchKey)
    === String(expected.recipeIndex));
  if (allRecipeClicks.length !== 1 || recipeClicks.length !== 1
      || recipeClicks[0].sequence >= preview.event.sequence
      || recipeClicks[0].detail.disabled === true || recipeClicks[0].detail.button !== 0) {
    fail("readback_trusted_click_missing", "readback", "readback preview lacks one trusted click");
  }
  const snapshotMessages = events.filter((event) => event.sequence < preview.event.sequence)
    .map(hostMessage).filter((message) => isCraftingResponse(message)
      && message.panelInstanceId === owner && message.cmd === "snapshot" && message.success === true);
  const snapshot = snapshotMessages.pop();
  const recipe = snapshotRecipe(snapshot, expected.recipeIndex);
  const expectedRecipe = snapshotRecipe(expected.snapshot, expected.recipeIndex);
  const snapshotBody = snapshot && {
    v: snapshot.v, category: snapshot.category, gender: snapshot.gender,
    recipes: snapshot.recipes, balance: snapshot.balance, skills: snapshot.skills, note: snapshot.note
  };
  const expectedSnapshotBody = {
    v: expected.snapshot.v, category: expected.snapshot.category, gender: expected.snapshot.gender,
    recipes: expected.snapshot.recipes, balance: expected.snapshot.balance,
    skills: expected.snapshot.skills, note: expected.snapshot.note
  };
  const previewBody = Object.assign({}, preview.response);
  const expectedPreviewBody = Object.assign({}, expected.preview);
  delete previewBody.type; delete previewBody.domain; delete previewBody.panel;
  delete previewBody.panelInstanceId; delete previewBody.cmd; delete previewBody.callId;
  delete previewBody.success; delete previewBody.craftToken;
  delete expectedPreviewBody.type; delete expectedPreviewBody.domain; delete expectedPreviewBody.panel;
  delete expectedPreviewBody.panelInstanceId; delete expectedPreviewBody.cmd;
  delete expectedPreviewBody.callId; delete expectedPreviewBody.success;
  delete expectedPreviewBody.craftToken;
  if (!recipe || !expectedRecipe || !deepEqual(recipe, expectedRecipe)
      || !deepEqual(snapshotBody, expectedSnapshotBody)
      || !deepEqual(previewBody, expectedPreviewBody)) {
    fail("readback_authority_mismatch", "readback", "restart authority did not match fresh poststate");
  }
  return {
    panelInstanceId: owner,
    category: preview.response.category,
    recipeIndex: preview.response.recipeIndex,
    previewCallId: preview.message.callId,
    identityTriple: {
      name: preview.response.output.name,
      displayName: preview.response.output.displayName,
      icon: preview.response.output.icon
    },
    hostCorrelation: correlateHostCalls(calls, input.logRecords),
    trustedWebClick: true,
    noWrite: true,
    balancePersisted: true,
    materialAuthorityPersisted: true,
    outputInventoryCountReadbackVerified: false
  };
}

function runCheck() {
  const error = new GateError("fixture", "check", "fixture");
  if (error.code !== "fixture" || !deepEqual({ b: 2, a: 1 }, { a: 1, b: 2 })) {
    throw new Error("basic verifier self-check failed");
  }
  if (!sameTriple(
    { name: "internal", displayName: "visible", icon: "asset" },
    { icon: "asset", name: "internal", displayName: "visible" }
  )) throw new Error("identity triple self-check failed");
  if (identityTriple({ name: "undefined", displayName: "visible", icon: "asset" })
      || identityTriple({ name: "internal", displayName: "   ", icon: "asset" })) {
    throw new Error("malformed identity triple was accepted");
  }
  let rejected = false;
  try {
    validateOpenMessage({
      type: "panel_cmd", cmd: "open", panel: "crafting", panelInstanceId: "panel_ok",
      initData: { mode: "runtime", category: "武器合成", source: "internal",
        debug: false, panelInstanceId: "panel_ok" }
    });
  } catch (caught) {
    rejected = caught && caught.code === "open_init_contract_invalid";
  }
  if (!rejected) throw new Error("non-production source was accepted");
  return { checks: 4 };
}

function verifyBundle(input) {
  if (isObject(input) && input.mode === "session") {
    if (!isObject(input.commit) || !isObject(input.readback)) {
      fail("verification_bundle_invalid", "bundle",
        "session bundle requires commit and readback inputs");
    }
    const commit = verifyBundle(Object.assign({}, input.commit, { mode: "commit" }));
    const derivedExpected = {
      recipeIndex: commit.recipeIndex,
      craftCount: commit.craftCount,
      snapshot: commit.freshPoststate.snapshot,
      preview: commit.freshPoststate.preview
    };
    if (input.readback.expectedPoststate
        && !deepEqual(input.readback.expectedPoststate, derivedExpected)) {
      fail("cross_bundle_expected_mismatch", "bundle",
        "readback expected poststate was not derived from the verified commit");
    }
    const readback = verifyBundle(Object.assign({}, input.readback, {
      mode: "readback",
      expectedPoststate: derivedExpected
    }));
    return {
      mode: "session",
      commit,
      readback,
      crossRestartPoststateBound: true
    };
  }
  if (!isObject(input) || (input.mode !== "commit" && input.mode !== "readback")
      || !Array.isArray(input.ingressRecords)) {
    fail("verification_bundle_invalid", "bundle",
      "bundle requires mode and raw ingressRecords");
  }
  const expectedCategory = input.mode === "readback" && input.expectedPoststate
    && input.expectedPoststate.preview ? input.expectedPoststate.preview.category : null;
  const ingress = validateIngress(input.transcript, input.ingressRecords, {
    entryFloorSequence: Number.isInteger(input.entryFloorSequence)
      ? input.entryFloorSequence : 0,
    expectedCategory
  });
  const prepared = Object.assign({}, input, { ingress });
  return input.mode === "readback"
    ? verifyReadbackJourney(prepared) : verifyCommitJourney(prepared);
}

function main(argv) {
  if (argv.length === 1 && argv[0] === "--check") {
    console.log(JSON.stringify({ ok: true, schema: "crafting-receipt-verifier.check.v1", ...runCheck() }));
    return;
  }
  if (argv.length === 2 && argv[0] === "--input") {
    const file = path.resolve(argv[1]);
    const input = JSON.parse(fs.readFileSync(file, "utf8"));
    const result = verifyBundle(input);
    console.log(JSON.stringify({ ok: true, result }, null, 2));
    return;
  }
  process.stderr.write("Usage: node verify-receipt.js --check | --input <bundle.json>\n");
  process.exitCode = 2;
}

function supersededEntry() {
  const error = new Error("SUPERSEDED / NOT_ADMITTED: use bootstrap.js --verify-bundle");
  error.code = "superseded_not_admitted";
  throw error;
}

module.exports = {
  CATEGORIES,
  GateError,
  ACTION_BY_CMD,
  assertTranscript,
  bridgeMessage,
  collectCalls,
  correlateHostCalls,
  deepEqual,
  exactKeys,
  hostMessage,
  identityTriple,
  isCraftingRequest,
  isCraftingResponse,
  parseHostFlash,
  parseXmlSocketJson,
  runCheck: supersededEntry,
  validateIngress: supersededEntry,
  validateRequestMessage,
  validateResponseMessage,
  verifyBundle: supersededEntry,
  verifyCommitJourney: supersededEntry,
  verifyReadbackJourney: supersededEntry,
};

if (require.main === module) {
  process.stderr.write("SUPERSEDED / NOT_ADMITTED: use bootstrap.js --verify-bundle <path>.\n");
  process.exitCode = 2;
}
