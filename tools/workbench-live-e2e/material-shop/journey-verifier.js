"use strict";

const crypto = require("crypto");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const ExternalToolchain = require("../lib/playwright-websocket-toolchain");
const CloneGuard = require("../lib/clone-save-guard");
const LauncherObservation = require("../lib/launcher-observation");
const NpcCommon = require("../npc/common");
const NpcProtocol = require("../npc/protocol");
const Admission = require("./admission");
const Applicability = require("./applicability");
const CandidateLifecycle = require("./candidate-lifecycle");
const CaptureVerifier = require("./capture-verifier");
const Common = require("./common");
const Control = require("./control-channel");
const Protocol = require("./protocol");
const RunOperationLease = require("./run-operation-lease");
const TrustedRunnerJsonl = require("./trusted-runner-jsonl");

const RAW_SCHEMA = "workbench-live-e2e.material-shop.raw-candidate-journey.v3";
const AGENT_RUNTIME_RAW_SCHEMA = "workbench-live-e2e.material-shop.raw-candidate-journey.v4";

function exactKeys(value, keys, code) {
  return Common.exactKeys(value, keys, code, "journey_verify");
}

function message(event) {
  const raw = event && (event.message != null ? event.message : event.payload);
  if (Evidence.isPlainObject(raw)) return raw;
  if (typeof raw !== "string") return null;
  try { const parsed = JSON.parse(raw); return Evidence.isPlainObject(parsed) ? parsed : null; }
  catch (_error) { return null; }
}

function eventMessages(events, kind) {
  return events.map((event) => ({ event, message: message(event) }))
    .filter((entry) => entry.event.kind === kind && entry.message);
}

function assertExactMessageKeys(value, keys, code) {
  if (!Evidence.isPlainObject(value)
      || Evidence.canonicalJson(Object.keys(value).sort())
        !== Evidence.canonicalJson(keys.slice().sort())) {
    Common.fail(code, "journey_verify", "runtime message key set is not exact", {
      expected: keys.slice().sort(), actual: value && Object.keys(value).sort(),
    });
  }
}

function pairResponse(request, inbound) {
  const matches = inbound.filter((entry) => entry.event.sequence > request.event.sequence
    && entry.message.type === "panel_resp"
    && entry.message.panel === request.message.panel
    && entry.message.cmd === request.message.cmd
    && entry.message.callId === request.message.callId
    && entry.message.panelInstanceId === request.message.panelInstanceId);
  if (matches.length !== 1 || matches[0].message.success !== true) {
    Common.fail("material_shop_response_pair_invalid", "journey_verify",
      "request requires one later correlated successful response", {
        cmd: request.message.cmd, callId: request.message.callId, count: matches.length,
      });
  }
  return matches[0];
}

function requireOne(values, code, messageText, details) {
  if (!Array.isArray(values) || values.length !== 1) {
    Common.fail(code, "journey_verify", messageText, Object.assign({
      count: values && values.length,
    }, details || {}));
  }
  return values[0];
}

function materialQuantity(state, itemName, phase) {
  const view = state && state.views && state.views.material;
  if (!view || !Array.isArray(view.slots)) {
    Common.fail("material_shop_material_view_missing", "journey_verify",
      "NPC authoritative material view is absent", { phase });
  }
  const matches = view.slots.filter((slot) => slot && slot.occupied === true
    && slot.item && slot.item.name === itemName);
  if (matches.length > 1) {
    Common.fail("material_shop_material_view_duplicate", "journey_verify",
      "NPC material view duplicates the exact collection key", { phase, itemName });
  }
  return matches.length ? Number(matches[0].item.quantity) : 0;
}

function assertSettlement(preview, commit, inbound, applicability) {
  const target = applicability.selectedUnlockedTarget;
  const snapshots = inbound.filter((entry) => entry.event.sequence < preview.event.sequence
    && entry.message.type === "panel_resp" && entry.message.panel === "npcshop"
    && entry.message.domain === "npcshop" && entry.message.cmd === "snapshot"
    && entry.message.panelInstanceId === preview.message.panelInstanceId
    && entry.message.success === true);
  if (!snapshots.length) {
    Common.fail("material_shop_owner_snapshot_missing", "journey_verify",
      "purchase preview lacks a prior authoritative owner snapshot");
  }
  const ownerSnapshot = snapshots[snapshots.length - 1];
  NpcProtocol.assertNpcState(ownerSnapshot.message, target.shopId,
    "material_shop_owner_snapshot");
  const baselineBalance = Number(applicability.sourceFixture.money);
  const catalog = ownerSnapshot.message.catalog.filter((entry) =>
    Number(entry.catalogIndex) === target.catalogIndex);
  const catalogTarget = requireOne(catalog, "material_shop_catalog_target_invalid",
    "owner snapshot must contain one exact selected catalog row");
  if (catalogTarget.itemName !== target.itemName || catalogTarget.locked !== false
      || Number(catalogTarget.basePrice) !== Number(target.basePrice)
      || Number(catalogTarget.maxQuantity) < 1
      || Number(ownerSnapshot.message.balance) !== baselineBalance
      || materialQuantity(ownerSnapshot.message, target.itemName, "before") !== 0) {
    Common.fail("material_shop_catalog_target_invalid", "journey_verify",
      "authoritative owner snapshot differs from the frozen target/baseline state");
  }

  assertExactMessageKeys(preview.message.payload, ["v", "shopId", "purchases", "sales"],
    "material_shop_trade_preview_invalid");
  const previewResponse = pairResponse(preview, inbound);
  const previewMessage = previewResponse.message;
  assertExactMessageKeys(previewMessage, ["type", "domain", "panel", "panelInstanceId",
    "cmd", "callId", "success", "v", "shopId", "tradeToken", "purchaseLines",
    "saleLines", "buyTotal", "sellTotal", "netDelta", "projectedBalance",
    "requiredSlots", "availableSlots", "missingSlots", "canCommit", "blockingError"],
  "material_shop_trade_preview_invalid");
  const line = requireOne(previewMessage.purchaseLines,
    "material_shop_trade_preview_invalid", "preview must contain one purchase line");
  assertExactMessageKeys(line, ["catalogIndex", "itemName", "displayName", "icon",
    "quantity", "unitPrice", "total", "maxQuantity", "purchaseLimit",
    "maxAffordable", "maxByCapacity", "maxPurchasable", "limitingReason",
    "itemKind", "destinationView"], "material_shop_trade_preview_invalid");
  const unitPrice = Number(catalogTarget.unitPrice);
  if (!Number.isFinite(unitPrice) || unitPrice < 0
      || unitPrice !== Math.floor(Number(target.basePrice)
        * Number(ownerSnapshot.message.buyMultiplier))
      || previewMessage.success !== true || previewMessage.v !== 1
      || previewMessage.shopId !== target.shopId
      || typeof previewMessage.tradeToken !== "string" || !previewMessage.tradeToken
      || !Array.isArray(previewMessage.saleLines) || previewMessage.saleLines.length !== 0
      || Number(line.catalogIndex) !== target.catalogIndex || line.itemName !== target.itemName
      || Number(line.quantity) !== 1 || Number(line.unitPrice) !== unitPrice
      || Number(line.total) !== unitPrice || line.itemKind !== "stack"
      || line.destinationView !== "material" || Number(line.maxPurchasable) < 1
      || Number(previewMessage.buyTotal) !== unitPrice
      || Number(previewMessage.sellTotal) !== 0
      || Number(previewMessage.netDelta) !== -unitPrice
      || Number(previewMessage.projectedBalance) !== baselineBalance - unitPrice
      || Number(previewMessage.requiredSlots) !== 0
      || Number(previewMessage.missingSlots) !== 0
      || previewMessage.canCommit !== true || previewMessage.blockingError !== "") {
    Common.fail("material_shop_trade_preview_projection_invalid", "journey_verify",
      "preview target, quantity, price, zero-sale, or projected balance is inconsistent");
  }

  assertExactMessageKeys(commit.message.payload, ["v", "shopId", "expectedTradeToken"],
    "material_shop_trade_commit_invalid");
  const commitResponse = pairResponse(commit, inbound);
  NpcProtocol.assertNpcState(commitResponse.message, target.shopId,
    "material_shop_trade_commit");
  if (commit.message.panelInstanceId !== preview.message.panelInstanceId) {
    Common.fail("material_shop_trade_owner_invalid", "journey_verify",
      "preview and commit must remain on one exact NPCShop owner");
  }
  const orderedSequences = [ownerSnapshot, preview, previewResponse, commit, commitResponse]
    .map((entry) => Number(entry.event.sequence));
  if (orderedSequences.some((value) => !Number.isInteger(value))
      || orderedSequences.some((value, index) => index > 0
        && value <= orderedSequences[index - 1])) {
    Common.fail("material_shop_trade_order_invalid", "journey_verify",
      "snapshot, preview, preview response, commit, and commit response are not causal", {
        sequences: orderedSequences,
      });
  }
  if (commit.message.payload.v !== 1 || commit.message.payload.shopId !== target.shopId
      || commit.message.payload.expectedTradeToken !== previewMessage.tradeToken
      || commitResponse.message.operation !== "tradeCommit"
      || Number(commitResponse.message.trade.buyTotal) !== unitPrice
      || Number(commitResponse.message.trade.sellTotal) !== 0
      || Number(commitResponse.message.trade.netDelta) !== -unitPrice
      || Number(commitResponse.message.balance) !== baselineBalance - unitPrice
      || materialQuantity(commitResponse.message, target.itemName, "after_commit") !== 1) {
    Common.fail("material_shop_trade_commit_state_invalid", "journey_verify",
      "commit does not preserve preview token, exact totals, balance, and material quantity");
  }
  return { baselineBalance, unitPrice, buyTotal: unitPrice,
    projectedBalance: baselineBalance - unitPrice, beforeOwned: 0, afterOwned: 1,
    previewCallId: preview.message.callId, commitCallId: commit.message.callId,
    panelInstanceId: preview.message.panelInstanceId, preview, previewResponse,
    commit, commitResponse, ownerSnapshot };
}

function assertSettlementHostOrder(previewMapping, commitMapping, panelInstanceId) {
  if (!previewMapping || !commitMapping
      || previewMapping.panelInstanceId !== panelInstanceId
      || commitMapping.panelInstanceId !== panelInstanceId
      || previewMapping.requestSequence >= commitMapping.requestSequence
      || previewMapping.responseLine >= commitMapping.panelLine) {
    Common.fail("material_shop_host_trade_order_invalid", "journey_verify",
      "Host preview and commit mappings are not one owner in strict response-to-request order");
  }
  return { panelInstanceId, previewResponseLine: previewMapping.responseLine,
    commitRequestLine: commitMapping.panelLine };
}

function assertControlCandidateBinding(exchange, admission, stepId) {
  Admission.validateCandidateAdmissionBundle(admission);
  const expectedBinding = {
    runId: exchange.request.runId,
    planSha256: exchange.request.planSha256,
    requestSha256: exchange.ack.requestBindingSha256,
    step: exchange.request.step,
    candidateIdentitySha256: admission.admission.candidateIdentitySha256,
    pid: admission.operatorAttestation.pid,
    window: admission.operatorAttestation.window,
    admissionSha256: admission.admission.admissionSha256,
  };
  if (Evidence.canonicalJson(exchange.ack.provider.candidateBinding)
      !== Evidence.canonicalJson(expectedBinding)) {
    Common.fail("material_shop_control_candidate_binding_drift", "journey_verify",
      "operator input was captured for another request, lifecycle, PID, or window", {
        step: stepId,
      });
  }
  return expectedBinding;
}

function verifyControls(raw, plan, runDir) {
  if (!Array.isArray(raw.controls) || raw.controls.length !== plan.steps.length) {
    Common.fail("material_shop_control_set_invalid", "journey_verify",
      "raw run does not contain one control exchange per plan step");
  }
  const transports = [];
  const restartOrdinal = plan.steps.findIndex((entry) => entry.id === "restart_candidate");
  raw.controls.forEach((exchange, index) => {
    exactKeys(exchange, ["request", "ack"], "material_shop_control_exchange_invalid");
    const step = plan.steps[index];
    Control.validateRequest(exchange.request, plan, step);
    Control.validateAck(exchange.ack, exchange.request, plan, runDir);
    if (exchange.ack.result !== "completed" || exchange.request.step !== step.id) {
      Common.fail("material_shop_control_exchange_invalid", "journey_verify",
        "control exchange was not completed in exact plan order", { step: step.id });
    }
    if (step.transportClass === "native_visible_input"
        && exchange.ack.transport !== Protocol.PREFERRED_TRANSPORT) {
      Common.fail("material_shop_native_fallback_forbidden", "journey_verify",
        "Native HUD step was not completed by Computer Use", { step: step.id });
    }
    if (step.transportClass === "runner_owned"
        && exchange.ack.transport !== Protocol.RUNNER_TRANSPORT) {
      Common.fail("material_shop_runner_transport_invalid", "journey_verify",
        "runner-owned lifecycle step has a foreign provider", { step: step.id });
    }
    if (exchange.ack.transport === Protocol.FALLBACK_TRANSPORT) {
      const prior = raw.controls.slice(0, index).reverse().find((entry) =>
        ["open_materials", "reopen_materials", "restart_open_materials"]
          .includes(entry.request.step));
      if (!prior || prior.ack.transport !== Protocol.PREFERRED_TRANSPORT
          || prior.ack.result !== "completed") {
        Common.fail("material_shop_panel_fallback_without_native_opener", "journey_verify",
          "panel CDP fallback lacks one prior Computer Use native opener", { step: step.id });
      }
    }
    if (exchange.ack.transport !== Protocol.RUNNER_TRANSPORT) {
      const admissionIndex = restartOrdinal >= 0 && index > restartOrdinal ? 1 : 0;
      const admission = raw.admissions && raw.admissions[admissionIndex];
      if (!admission) {
        Common.fail("material_shop_control_candidate_admission_missing", "journey_verify",
          "operator input lacks the candidate admission for its lifecycle", {
            step: step.id, admissionIndex,
          });
      }
      assertControlCandidateBinding(exchange, admission, step.id);
    }
    transports.push(exchange.ack.transport);
  });
  return { completedSteps: plan.steps.map((step) => step.id),
    transports, authorizationDecisionId: plan.authorization.decisionId,
    controllerBusinessApiCalls: 0 };
}

function staticAdmissionIdentity(bundle) {
  const value = Object.assign({}, bundle.request.candidateIdentity);
  delete value.pid;
  return value;
}

function verifyAdmissions(raw, plan, build, runDir) {
  if (!Array.isArray(raw.admissions) || raw.admissions.length !== 2) {
    Common.fail("material_shop_candidate_admission_set_invalid", "journey_verify",
      "first and restart candidate processes each require one UI admission");
  }
  raw.admissions.forEach((bundle) => {
    Admission.validateCandidateAdmissionBundle(bundle);
    if (bundle.request.runId !== plan.runId || bundle.request.planSha256 !== plan.planSha256) {
      Common.fail("material_shop_candidate_admission_plan_drift", "journey_verify",
        "candidate UI admission is detached from the plan");
    }
    if (!Evidence.pathInside(path.resolve(runDir),
      path.resolve(bundle.operatorAttestation.rawOperationArtifact.sourcePath))) {
      Common.fail("material_shop_candidate_operation_artifact_foreign", "journey_verify",
        "candidate admission raw operation artifact escaped the exact run directory");
    }
    if (Evidence.canonicalJson(staticAdmissionIdentity(bundle))
        !== Evidence.canonicalJson(build.candidateIdentity)) {
      Common.fail("material_shop_candidate_admission_identity_drift", "journey_verify",
        "candidate UI admission does not bind the exact built identity");
    }
  });
  const pids = raw.admissions.map((entry) => entry.operatorAttestation.pid);
  if (new Set(pids).size !== 2) {
    Common.fail("material_shop_restart_pid_reused", "journey_verify",
      "restart admission did not bind a fresh candidate PID");
  }
  return true;
}

function verifyTranscript(raw, plan, applicability) {
  const transcript = raw.transcript;
  if (!Evidence.isPlainObject(transcript) || !Array.isArray(transcript.events)
      || transcript.eventCount !== transcript.events.length || transcript.events.length < 1) {
    Common.fail("material_shop_transcript_invalid", "journey_verify",
      "passive browser transcript is absent or malformed");
  }
  NpcCommon.verifyEventChain(transcript);
  const outbound = eventMessages(transcript.events, "bridge_send");
  const inbound = eventMessages(transcript.events, "webview_message");
  const forwards = outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "crafting" && entry.message.cmd === "open_npc_shop");
  const lockedRequired = plan.applicability.locked.status === "required_candidate_journey";
  const maxRequired = plan.applicability.max.status === "required_candidate_journey";
  const forwardCount = 2 + (lockedRequired ? 1 : 0) + (maxRequired ? 1 : 0);
  if (forwards.length !== forwardCount) {
    Common.fail("material_shop_forward_count_invalid", "journey_verify",
      "material source navigation count differs from applicability", { forwardCount: forwards.length });
  }
  forwards.forEach((entry) => {
    assertExactMessageKeys(entry.message, ["type", "panel", "cmd", "callId",
      "panelInstanceId", "source", "materialSnapshotId", "materialName", "shopId",
      "catalogIndex"], "material_shop_forward_envelope_invalid");
    if (entry.message.source !== "crafting_materials"
        || entry.message.materialName !== applicability.selectedUnlockedTarget.itemName
        || entry.message.shopId !== applicability.selectedUnlockedTarget.shopId
        || entry.message.catalogIndex !== applicability.selectedUnlockedTarget.catalogIndex) {
      Common.fail("material_shop_forward_target_invalid", "journey_verify",
        "material navigation did not preserve exact shop/index/item snapshot identity");
    }
  });
  const opens = inbound.filter((entry) => entry.message.type === "panel_cmd"
    && entry.message.panel === "npcshop" && entry.message.cmd === "open"
    && entry.message.initData && entry.message.initData.source === "crafting_materials");
  if (opens.length !== forwardCount) {
    Common.fail("material_shop_host_open_count_invalid", "journey_verify",
      "Host did not commit one NPCShop open per material forward request");
  }
  opens.forEach((entry) => {
    const init = entry.message.initData;
    assertExactMessageKeys(init, ["mode", "source", "debug", "shopId", "panelInstanceId",
      "preferredItemName", "preferredCatalogIndex", "canReturnCraftingMaterials",
      "navigationOrigin"], "material_shop_init_data_invalid");
    if (init.shopId !== applicability.selectedUnlockedTarget.shopId
        || init.preferredItemName !== applicability.selectedUnlockedTarget.itemName
        || init.preferredCatalogIndex !== applicability.selectedUnlockedTarget.catalogIndex
        || init.canReturnCraftingMaterials !== true
        || init.navigationOrigin !== "crafting_materials") {
      Common.fail("material_shop_init_data_invalid", "journey_verify",
        "NPCShop initData did not preserve exact material-origin target");
    }
  });
  const reverses = outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "npcshop" && entry.message.cmd === "return_crafting_materials");
  const reverseCount = 1 + (lockedRequired ? 1 : 0) + (maxRequired ? 1 : 0);
  if (reverses.length !== reverseCount) {
    Common.fail("material_shop_reverse_count_invalid", "journey_verify",
      "explicit Return to Materials count differs from applicability");
  }
  const returnOpens = [];
  reverses.forEach((entry, index) => {
    assertExactMessageKeys(entry.message, ["type", "panel", "cmd", "callId",
      "panelInstanceId"], "material_shop_reverse_envelope_invalid");
    const nextReverse = reverses[index + 1];
    const failures = inbound.filter((candidate) => candidate.event.sequence > entry.event.sequence
      && (!nextReverse || candidate.event.sequence < nextReverse.event.sequence)
      && candidate.message.type === "panel_resp" && candidate.message.panel === "npcshop"
      && candidate.message.cmd === "return_crafting_materials"
      && candidate.message.callId === entry.message.callId
      && candidate.message.panelInstanceId === entry.message.panelInstanceId);
    if (failures.length !== 0) {
      Common.fail("material_shop_reverse_failure_observed", "journey_verify",
        "successful reverse navigation must not be signed by a failure response", {
          callId: entry.message.callId,
        });
    }
    const targets = inbound.filter((candidate) => candidate.event.sequence > entry.event.sequence
      && (!nextReverse || candidate.event.sequence < nextReverse.event.sequence)
      && candidate.message.type === "panel_cmd" && candidate.message.panel === "crafting"
      && candidate.message.cmd === "open" && candidate.message.initData
      && candidate.message.initData.source === "npcshop_return");
    const targetOpen = requireOne(targets, "material_shop_reverse_target_invalid",
      "reverse success requires one exact later crafting target open", {
        callId: entry.message.callId,
      });
    assertExactMessageKeys(targetOpen.message.initData, ["mode", "view", "source", "debug",
      "panelInstanceId", "preferredMaterialName"], "material_shop_reverse_target_invalid");
    if (targetOpen.message.initData.mode !== "runtime"
        || targetOpen.message.initData.view !== "materials"
        || targetOpen.message.initData.debug !== false
        || targetOpen.message.initData.preferredMaterialName
          !== applicability.selectedUnlockedTarget.itemName
        || !Common.ID_RE.test(String(targetOpen.message.initData.panelInstanceId || ""))) {
      Common.fail("material_shop_reverse_target_invalid", "journey_verify",
        "crafting return target did not preserve exact material-origin state");
    }
    const sourceReuse = inbound.filter((candidate) =>
      candidate.event.sequence > targetOpen.event.sequence
      && candidate.message.panelInstanceId === entry.message.panelInstanceId
      && candidate.message.panel === "npcshop");
    if (sourceReuse.length !== 0) {
      Common.fail("material_shop_reverse_source_not_retired", "journey_verify",
        "retired NPCShop source instance produced later panel traffic");
    }
    returnOpens.push(targetOpen);
  });
  const closes = outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "npcshop" && entry.message.cmd === "close");
  if (closes.length !== 1) {
    Common.fail("material_shop_ordinary_close_count_invalid", "journey_verify",
      "ordinary NPCShop close must occur exactly once");
  }
  assertExactMessageKeys(closes[0].message, ["type", "cmd", "panel", "panelInstanceId", "reason"],
    "material_shop_ordinary_close_envelope_invalid");
  if (!Protocol.CLOSE_REASONS.includes(closes[0].message.reason)) {
    Common.fail("material_shop_ordinary_close_reason_invalid", "journey_verify",
      "ordinary close reason is outside the frozen four reasons");
  }
  const craftingCloses = outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "crafting" && entry.message.cmd === "close");
  const restartClose = requireOne(craftingCloses, "material_shop_restart_close_count_invalid",
    "fresh restart material archive must close exactly once");
  assertExactMessageKeys(restartClose.message,
    ["type", "cmd", "panel", "panelInstanceId", "reason"],
    "material_shop_restart_close_envelope_invalid");
  if (!Protocol.CLOSE_REASONS.includes(restartClose.message.reason)) {
    Common.fail("material_shop_restart_close_reason_invalid", "journey_verify",
      "restart material archive close reason is outside the frozen four reasons");
  }
  const previews = outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "npcshop" && entry.message.domain === "npcshop"
    && entry.message.cmd === "tradePreview");
  const commits = outbound.filter((entry) => entry.message.type === "panel"
    && entry.message.panel === "npcshop" && entry.message.domain === "npcshop"
    && entry.message.cmd === "tradeCommit");
  if (previews.length !== 1 || commits.length !== 1) {
    Common.fail("material_shop_trade_count_invalid", "journey_verify",
      "material journey requires one preview and one commit only");
  }
  const preview = previews[0];
  const commit = commits[0];
  const target = applicability.selectedUnlockedTarget;
  if (!preview.message.payload || preview.message.payload.shopId !== target.shopId
      || Evidence.canonicalJson(preview.message.payload.purchases)
        !== Evidence.canonicalJson([{ catalogIndex: target.catalogIndex, quantity: 1 }])
      || !Array.isArray(preview.message.payload.sales) || preview.message.payload.sales.length !== 0) {
    Common.fail("material_shop_trade_preview_invalid", "journey_verify",
      "trade preview is not exact quantity-one purchase/zero sale");
  }
  const settlement = assertSettlement(preview, commit, inbound, applicability);
  const focus = transcript.events.filter((event) => event.kind === "dom_input"
    && event.eventType === "focusin" && event.panelState && event.panelState.panel === "npcshop"
    && event.target && event.target.attributes
    && event.target.attributes["data-navigation-focus"] === "true"
    && String(event.target.attributes["data-workbench-key"] || "") === String(target.catalogIndex));
  if (focus.length < forwardCount) {
    Common.fail("material_shop_navigation_focus_invalid", "journey_verify",
      "each material-origin open requires exact navigation focus evidence");
  }
  const detailResponses = inbound.map((entry) => entry.message)
    .filter((entry) => entry.type === "panel_resp" && entry.panel === "crafting"
      && entry.cmd === "materialDetail" && entry.success === true && Array.isArray(entry.sources));
  let multi = null;
  detailResponses.some((response) => (response.sources || []).some((source) => {
    if (source && source.kind === "enemy" && typeof source.enemyType === "string"
        && Array.isArray(source.variants) && source.variants.length >= 2) {
      const indices = source.variants.map((variant) => variant.occurrenceIndex);
      if (indices.every((value, index) => value === index)) {
        multi = { enemyType: source.enemyType, occurrenceIndices: indices, allVisible: true };
        return true;
      }
    }
    return false;
  }));
  if (!multi) {
    Common.fail("material_shop_multi_drop_evidence_missing", "journey_verify",
      "transcript lacks one structured enemy source with all ordered drop occurrences");
  }
  const restartBoundary = transcript.events.filter((event) =>
    event.kind === "cdp_endpoint_bound").at(-1);
  if (!restartBoundary) {
    Common.fail("material_shop_restart_readback_missing", "journey_verify",
      "fresh restart observer boundary is absent");
  }
  const restartDetails = inbound.filter((entry) => entry.event.sequence > restartBoundary.sequence
    && entry.message.type === "panel_resp" && entry.message.panel === "crafting"
    && entry.message.cmd === "materialDetail" && entry.message.success === true
    && entry.message.material && entry.message.material.name === target.itemName);
  const restartDetail = requireOne(restartDetails, "material_shop_restart_readback_missing",
    "fresh restart requires one exact purchased-material detail readback");
  if (Number(restartDetail.message.material.owned) !== 1) {
    Common.fail("material_shop_restart_readback_invalid", "journey_verify",
      "fresh restart material detail did not read the committed quantity");
  }
  const restartDetailRequests = outbound.filter((entry) =>
    entry.message.type === "panel" && entry.message.panel === "crafting"
    && entry.message.domain === "crafting" && entry.message.cmd === "materialDetail"
    && entry.message.callId === restartDetail.message.callId
    && entry.message.panelInstanceId === restartDetail.message.panelInstanceId
    && entry.event.sequence < restartDetail.event.sequence
    && entry.event.sequence > restartBoundary.sequence);
  const restartDetailRequest = requireOne(restartDetailRequests,
    "material_shop_restart_readback_request_missing",
    "restart material detail lacks one exact correlated request");
  return { forwardCount, reverseCount, ordinaryCloseReason: closes[0].message.reason,
    multi, settlement, forwards, opens, reverses, returnOpens,
    ordinaryClose: closes[0], restartClose, restartDetailRequest,
    restartDetailResponse: restartDetail, restartOwned: 1 };
}

function parseStructured(record, prefix, keys, code) {
  if (!record || !String(record.body || "").startsWith(prefix)) return null;
  const text = String(record.body).slice(prefix.length).trim();
  const values = {};
  const ordered = [];
  if (text) text.split(/\s+/).forEach((part) => {
    const separator = part.indexOf("=");
    if (separator <= 0 || separator === part.length - 1) {
      Common.fail(code, "journey_verify", "Host structured record contains a malformed token", {
        lineNumber: record.lineNumber,
      });
    }
    const key = part.slice(0, separator);
    if (Object.prototype.hasOwnProperty.call(values, key)) {
      Common.fail(code, "journey_verify", "Host structured record repeats a field", {
        lineNumber: record.lineNumber, key,
      });
    }
    ordered.push(key);
    values[key] = part.slice(separator + 1);
  });
  if (Evidence.canonicalJson(ordered) !== Evidence.canonicalJson(keys)) {
    Common.fail(code, "journey_verify", "Host structured record key order/set is not exact", {
      lineNumber: record.lineNumber, expected: keys, actual: ordered,
    });
  }
  return values;
}

function authorityReference(value) {
  return "sha256_" + crypto.createHash("sha256").update(String(value), "utf8")
    .digest("hex").slice(0, 24);
}

function materialForwardMapping(forward, targetOpen, records) {
  const panelPrefix = "[Panel] HandlePanelMessage: ";
  const panels = records.map((record) => ({ record,
    fields: record.body.includes(" panel=crafting domain=other cmd=open_npc_shop callId="
      + forward.message.callId + " ") ? parseStructured(record, panelPrefix,
      ["task", "panel", "domain", "cmd", "callId", "payload", "len"],
      "material_shop_forward_host_panel_invalid") : null }))
    .filter((entry) => entry.fields && entry.fields.task === "panel"
      && entry.fields.panel === "crafting" && entry.fields.domain === "other"
      && entry.fields.cmd === "open_npc_shop"
      && entry.fields.callId === forward.message.callId
      && entry.fields.payload === "redacted" && /^\d+$/.test(entry.fields.len));
  const panel = requireOne(panels, "material_shop_forward_host_panel_count_invalid",
    "forward Web envelope must occur exactly once in the bounded Host suffix");
  const receipts = records.map((record) => ({ record,
    fields: record.body.startsWith("event=authority_flash_call_bound domain=material_shop_access ")
      ? parseStructured(record, "", ["event", "domain", "webCallIdRef",
        "flashCallId", "panel", "panelInstanceIdRef", "cmd", "action"],
      "material_shop_forward_host_binding_invalid") : null }))
    .filter((entry) => entry.fields && entry.record.lineNumber > panel.record.lineNumber
      && entry.fields.event === "authority_flash_call_bound"
      && entry.fields.domain === "material_shop_access"
      && entry.fields.webCallIdRef === authorityReference(forward.message.callId)
      && entry.fields.panel === "crafting"
      && entry.fields.panelInstanceIdRef === authorityReference(forward.message.panelInstanceId)
      && entry.fields.cmd === "open_npc_shop"
      && entry.fields.action === "craftingMaterialShopAuthorize"
      && /^\d+$/.test(entry.fields.flashCallId));
  const receipt = requireOne(receipts, "material_shop_forward_host_binding_count_invalid",
    "forward request lacks one exact hashed Web/owner to Flash fid binding");
  const fid = Number(receipt.fields.flashCallId);
  const sends = records.map((record) => ({ record,
    fields: parseStructured(record, "[MaterialShopAccessTask] -> Flash:",
      ["task", "cmd", "callId", "payload", "len"],
      "material_shop_forward_host_send_invalid") }))
    .filter((entry) => entry.fields && entry.record.lineNumber > receipt.record.lineNumber
      && entry.fields.task === "cmd" && entry.fields.cmd === "craftingMaterialShopAuthorize"
      && Number(entry.fields.callId) === fid && entry.fields.payload === "redacted"
      && /^\d+$/.test(entry.fields.len));
  const send = requireOne(sends, "material_shop_forward_host_send_count_invalid",
    "forward binding lacks one same-fid material authorization send");
  const responses = records.map((record) => ({ record,
    fields: record.body.startsWith("[XmlSocket:JSON] task=material_shop_access_response ")
      ? parseStructured(record, "[XmlSocket:JSON] ",
      ["task", "cmd", "callId", "success", "payload", "len"],
      "material_shop_forward_host_response_invalid") : null }))
    .filter((entry) => entry.fields && entry.record.lineNumber > send.record.lineNumber
      && entry.fields.task === "material_shop_access_response"
      && entry.fields.cmd === "craftingMaterialShopAuthorize"
      && Number(entry.fields.callId) === fid && entry.fields.success === "true"
      && entry.fields.payload === "redacted" && /^\d+$/.test(entry.fields.len));
  const response = requireOne(responses, "material_shop_forward_host_response_count_invalid",
    "forward authorization lacks one same-fid successful Flash response");
  const times = [forward.event.observedAt, panel.record.observedAt, receipt.record.observedAt,
    send.record.observedAt, response.record.observedAt, targetOpen.event.observedAt].map(Date.parse);
  if (times.some((value) => !Number.isFinite(value))
      || times.some((value, index) => index > 0 && value < times[index - 1])) {
    Common.fail("material_shop_forward_host_timeline_invalid", "journey_verify",
      "forward Web→Host→fid→Flash→target-open chain is not monotonic");
  }
  return { domain: "material_shop_access", cmd: "open_npc_shop",
    webCallId: forward.message.callId, panelInstanceId: forward.message.panelInstanceId,
    flashCallId: fid, requestSequence: forward.event.sequence,
    panelLine: panel.record.lineNumber, receiptLine: receipt.record.lineNumber,
    flashLine: send.record.lineNumber, responseLine: response.record.lineNumber };
}

function reverseHostMapping(reverse, targetOpen, records) {
  const panels = records.map((record) => ({ record,
    fields: record.body.includes(" panel=npcshop domain=other cmd=return_crafting_materials callId="
      + reverse.message.callId + " ") ? parseStructured(record, "[Panel] HandlePanelMessage: ",
      ["task", "panel", "domain", "cmd", "callId", "payload", "len"],
      "material_shop_reverse_host_panel_invalid") : null }))
    .filter((entry) => entry.fields && entry.fields.task === "panel"
      && entry.fields.panel === "npcshop" && entry.fields.domain === "other"
      && entry.fields.cmd === "return_crafting_materials"
      && entry.fields.callId === reverse.message.callId
      && entry.fields.payload === "redacted" && /^\d+$/.test(entry.fields.len));
  const panel = requireOne(panels, "material_shop_reverse_host_panel_count_invalid",
    "reverse Web envelope must occur exactly once in the bounded Host suffix");
  const nextPanel = records.find((record) => record.lineNumber > panel.record.lineNumber
    && record.body.startsWith("[Panel] HandlePanelMessage: "));
  const beforeNext = (record) => !nextPanel || record.lineNumber < nextPanel.lineNumber;
  const closed = requireOne(records.filter((record) => record.lineNumber > panel.record.lineNumber
    && beforeNext(record) && record.body === "[PanelHost] closed: npcshop"),
  "material_shop_reverse_host_close_invalid",
  "reverse Host transition must retire the exact NPCShop source once");
  const opened = requireOne(records.filter((record) => record.lineNumber > closed.lineNumber
    && beforeNext(record) && /^\[PanelHost\] opened: crafting rect=[1-9]\d*x[1-9]\d*$/.test(record.body)),
  "material_shop_reverse_host_open_invalid",
  "reverse Host transition must open the crafting target once");
  const times = [reverse.event.observedAt, panel.record.observedAt, closed.observedAt,
    opened.observedAt, targetOpen.event.observedAt].map(Date.parse);
  if (times.some((value) => !Number.isFinite(value))
      || times.some((value, index) => index > 0 && value < times[index - 1])) {
    Common.fail("material_shop_reverse_host_timeline_invalid", "journey_verify",
      "reverse Web→Host source-retire→target-open chain is not monotonic");
  }
  return { webCallId: reverse.message.callId, sourceInstanceId: reverse.message.panelInstanceId,
    panelLine: panel.record.lineNumber, closedLine: closed.lineNumber,
    openedLine: opened.lineNumber };
}

function closeHostMapping(close, panelName, records, settledRecords) {
  const panels = records.map((record) => ({ record,
    fields: record.body.includes(" panel=" + panelName
      + " domain=other cmd=close callId=other ")
      ? parseStructured(record, "[Panel] HandlePanelMessage: ",
      ["task", "panel", "domain", "cmd", "callId", "payload", "len"],
      "material_shop_close_host_panel_invalid") : null }))
    .filter((entry) => entry.fields && entry.fields.task === "panel"
      && entry.fields.panel === panelName && entry.fields.domain === "other"
      && entry.fields.cmd === "close" && entry.fields.callId === "other"
      && entry.fields.payload === "redacted" && /^\d+$/.test(entry.fields.len));
  const panel = requireOne(panels, "material_shop_close_host_panel_count_invalid",
    "owner close must occur once with Host's exact domain/callId projection", { panelName });
  const completionBody = "event=panel_exact_close_completed panel=" + panelName
    + " panelInstanceId=" + close.message.panelInstanceId;
  const completion = requireOne(records.filter((record) => record.body === completionBody),
    "material_shop_close_host_completion_invalid",
    "owner close lacks one exact panel-instance completion receipt", { panelName });
  const closed = requireOne(records.filter((record) => record.lineNumber > panel.record.lineNumber
    && record.lineNumber < completion.lineNumber
    && record.body === "[PanelHost] closed: " + panelName),
  "material_shop_close_host_retire_invalid", "owner close did not retire its panel exactly once",
  { panelName });
  if (!(panel.record.lineNumber < closed.lineNumber && closed.lineNumber < completion.lineNumber)
      || !settledRecords.some((record) => record.lineNumber === completion.lineNumber
        && record.body === completionBody)) {
    Common.fail("material_shop_close_host_order_invalid", "journey_verify",
      "owner close request→retire→completion is absent from close-settled evidence", { panelName });
  }
  const settledRelevant = settledRecords.filter((record) =>
    /^(?:\[Panel\]|\[PanelHost\]|event=authority_flash_call_bound|event=panel_exact_close_completed|\[(?:NpcShopTask|CraftingTask|MaterialShopAccessTask)\]|\[XmlSocket:JSON\])/.test(record.body));
  if (!settledRelevant.length
      || settledRelevant[settledRelevant.length - 1].lineNumber !== completion.lineNumber) {
    Common.fail("material_shop_close_settlement_invalid", "journey_verify",
      "close-settled suffix did not end at the exact owner completion", { panelName });
  }
  const timeline = [close.event.observedAt, panel.record.observedAt, closed.observedAt,
    completion.observedAt].map(Date.parse);
  if (timeline.some((value) => !Number.isFinite(value))
      || timeline.some((value, index) => index > 0 && value < timeline[index - 1])) {
    Common.fail("material_shop_close_host_timeline_invalid", "journey_verify",
      "Web close and Host exact completion are not monotonic", { panelName });
  }
  return { panelName, panelInstanceId: close.message.panelInstanceId,
    requestLine: panel.record.lineNumber, closedLine: closed.lineNumber,
    completionLine: completion.lineNumber };
}

function closeSettledRecords(hostLog, label) {
  const lifecycle = hostLog.lifecycles[label];
  const suffix = LauncherObservation.recordsAfterTerminalBoundary(
    lifecycle.startBoundary, lifecycle.closeSettledSnapshot);
  const timeline = NpcProtocol.resolveHostTimeline(lifecycle.closeSettledSnapshot,
    hostLog.utcOffsetMinutes, "material_shop_close_" + label);
  const byLine = new Map(timeline.map((record) => [record.lineNumber, record]));
  return suffix.map((record) => {
    const resolved = byLine.get(record.lineNumber);
    if (!resolved || resolved.line !== record.line) {
      Common.fail("material_shop_close_timeline_binding_invalid", "journey_verify",
        "close-settled suffix is detached from authenticated Host bytes", { label });
    }
    return { lifecycle: label, lineNumber: record.lineNumber, body: resolved.body,
      observedAt: resolved.observedAt, hostTimeOfDayMs: resolved.hostTimeOfDayMs };
  });
}

function verifyHostLogs(raw, route) {
  const hostLog = raw.hostLogs;
  if (!Evidence.isPlainObject(hostLog)
      || hostLog.schema !== "workbench-live-e2e.npc.host-evidence.v4") {
    Common.fail("material_shop_host_log_set_invalid", "journey_verify",
      "first/restart bounded Host lifecycle evidence is required");
  }
  const firstRecords = NpcProtocol.hostLifecycleRecords(hostLog, "first");
  const restartRecords = NpcProtocol.hostLifecycleRecords(hostLog, "restart");
  [["first", firstRecords, 0], ["restart", restartRecords, 1]].forEach((entry) => {
    const lifecycle = hostLog.lifecycles[entry[0]];
    const pid = raw.admissions[entry[2]].operatorAttestation.pid;
    const snapshots = [lifecycle.startBoundary.snapshot, lifecycle.closeSettledSnapshot,
      lifecycle.terminalSnapshot];
    if (snapshots.some((snapshot) => snapshot.sessionPid !== pid)) {
      Common.fail("material_shop_host_log_pid_drift", "journey_verify",
        "every authenticated Host boundary differs from candidate admission PID", {
          lifecycle: entry[0],
        });
    }
  });
  const forwardMappings = route.forwards.map((forward, index) => {
    const open = route.opens[index];
    if (!open || open.event.sequence <= forward.event.sequence) {
      Common.fail("material_shop_forward_target_order_invalid", "journey_verify",
        "forward target open does not follow its exact source request", { index });
    }
    return materialForwardMapping(forward, open, firstRecords);
  });
  const reverseMappings = route.reverses.map((reverse, index) =>
    reverseHostMapping(reverse, route.returnOpens[index], firstRecords));
  const previewMapping = NpcProtocol.assertHostMapping(route.settlement.preview,
    firstRecords, route.settlement.previewResponse);
  const commitMapping = NpcProtocol.assertHostMapping(route.settlement.commit,
    firstRecords, route.settlement.commitResponse);
  const settlementHostOrder = assertSettlementHostOrder(previewMapping, commitMapping,
    route.settlement.panelInstanceId);
  const restartDetailMapping = NpcProtocol.assertHostMapping(route.restartDetailRequest,
    restartRecords, route.restartDetailResponse);
  NpcProtocol.assertUniqueMappings(forwardMappings.concat([previewMapping, commitMapping,
    restartDetailMapping]));
  NpcProtocol.assertNoUnmappedHostWrites(firstRecords, [commitMapping], null);
  NpcProtocol.assertNoUnmappedHostWrites(restartRecords, [], null);
  const ordinaryClose = closeHostMapping(route.ordinaryClose, "npcshop", firstRecords,
    closeSettledRecords(hostLog, "first"));
  const restartClose = closeHostMapping(route.restartClose, "crafting", restartRecords,
    closeSettledRecords(hostLog, "restart"));
  const rejection = firstRecords.concat(restartRecords).filter((record) =>
    /near_match|malformed|rejected|not queued|superseded|ignored after replacement|expired\/foreign|success=false/i
      .test(record.body));
  if (rejection.length) {
    Common.fail("material_shop_host_rejection_observed", "journey_verify",
      "bounded Host suffix contains a rejection, failure, or near-match authority record", {
        lines: rejection.map((record) => record.lineNumber),
      });
  }
  const lateRestart = restartRecords.filter((record) =>
    record.lineNumber > restartClose.completionLine
    && /(?:domain=(?:npcshop|material_shop_access)|\[(?:NpcShopTask|MaterialShopAccessTask)\]|task=(?:npcshop_response|material_shop_access_response))/.test(record.body));
  if (lateRestart.length) {
    Common.fail("material_shop_restart_late_authority_invalid", "journey_verify",
      "NPC/material-shop authority traffic appeared after restart crafting close", {
        lines: lateRestart.map((record) => record.lineNumber),
      });
  }
  return { forwardMappings, reverseMappings, previewMapping, commitMapping,
    settlementHostOrder, restartDetailMapping, ordinaryClose, restartClose };
}

function verifyPublicArtifactSet(value, expectedSlot, code) {
  if (!Evidence.isPlainObject(value)) {
    Common.fail(code, "journey_verify", "public slot artifact set is absent");
  }
  exactKeys(value, ["slot", "jsonSha256", "solSetSha256", "solFiles",
    "artifactSetSha256", "manifest"], code);
  const manifest = value.manifest;
  exactKeys(manifest, ["schema", "slot", "capturedAt", "sourceSetSha256", "artifacts",
    "evidenceSha256"], code);
  const unsignedManifest = Object.assign({}, manifest);
  delete unsignedManifest.evidenceSha256;
  const json = manifest.artifacts.filter((entry) => entry.kind === "json");
  const sols = manifest.artifacts.filter((entry) => entry.kind === "sol");
  if (value.slot !== expectedSlot || manifest.slot !== expectedSlot
      || manifest.schema !== "workbench-live-e2e.npc.disk-artifact-set.v1"
      || !Number.isFinite(Date.parse(manifest.capturedAt))
      || manifest.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsignedManifest))
      || value.artifactSetSha256 !== manifest.sourceSetSha256
      || !Common.SHA256_RE.test(String(value.artifactSetSha256 || ""))
      || json.length !== 1 || value.jsonSha256 !== json[0].sha256
      || Evidence.canonicalJson(value.solFiles) !== Evidence.canonicalJson(sols)
      || value.solSetSha256 !== Evidence.sha256Text(Evidence.canonicalJson(sols))) {
    Common.fail(code, "journey_verify", "public slot artifact set is malformed or detached");
  }
  return value;
}

function archiveLineBody(record) {
  return String(record && record.line || "").replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
}

function verifyArchiveBundle(raw, sealedArchive) {
  const bundle = raw.persistence.archive;
  exactKeys(bundle, ["schema", "evidence", "snapshot", "bundleSha256"],
    "material_shop_archive_bundle_invalid");
  const unsignedBundle = Object.assign({}, bundle);
  delete unsignedBundle.bundleSha256;
  const archive = bundle.evidence;
  if (bundle.schema !== "workbench-live-e2e.npc.archive-capture-bundle.v1"
      || bundle.bundleSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsignedBundle))) {
    Common.fail("material_shop_archive_bundle_invalid", "journey_verify",
      "SAFEEXIT archive bundle digest is invalid");
  }
  LauncherObservation.verifyLogSnapshot(bundle.snapshot);
  if (bundle.snapshot.sessionPid !== raw.admissions[0].operatorAttestation.pid) {
    Common.fail("material_shop_archive_pid_drift", "journey_verify",
      "SAFEEXIT archive snapshot is detached from the first candidate PID");
  }
  const unsignedArchive = Object.assign({}, archive);
  delete unsignedArchive.evidenceSha256;
  if (!Evidence.isPlainObject(archive)
      || archive.schema !== LauncherObservation.ARCHIVE_SCHEMA
      || archive.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsignedArchive))) {
    Common.fail("material_shop_archive_evidence_invalid", "journey_verify",
      "SAFEEXIT archive evidence digest is invalid");
  }
  Common.exactKeys(archive.disk, ["schema", "slot", "path", "sha256", "bytes",
    "textCharacters", "capturedAt"], "material_shop_archive_evidence_invalid",
  "journey_verify");
  const expectedPath = CloneGuard.saveJsonPath(raw.lifecycle.resourcesRoot,
    raw.lifecycle.slots.targetSlot);
  const records = LauncherObservation.recordsAfterTerminalBoundary(
    archive.boundary, bundle.snapshot);
  const archiveRecords = records.filter((record) => archiveLineBody(record)
    .startsWith("[ArchiveTask] Shadow saved:"));
  const exactArchive = archiveRecords.filter((record) => {
    const body = archiveLineBody(record);
    const match = body.match(/^\[ArchiveTask\] Shadow saved: ([A-Za-z0-9_-]+) \((\d+) chars\) path=(.+)$/);
    return match && match[1] === raw.lifecycle.slots.targetSlot
      && Number(match[2]) === archive.disk.textCharacters
      && path.resolve(match[3]).toLowerCase() === expectedPath.toLowerCase();
  });
  const marker = (name) => records.filter((record) => {
    const body = archiveLineBody(record);
    const matches = body.match(new RegExp("(^|[\\s|])" + name.replace(":", "\\:")
      + "(?=$|[\\s|])", "g"));
    return matches && matches.length === 1;
  });
  const sv1 = marker("sv:1");
  const sv2 = marker("sv:2");
  const sv3 = marker("sv:3");
  if (archive.disk.schema !== "workbench-live-e2e.disk-save-evidence.v1"
      || archive.disk.slot !== raw.lifecycle.slots.targetSlot
      || path.resolve(archive.disk.path).toLowerCase() !== expectedPath.toLowerCase()
      || archive.disk.sha256 !== sealedArchive.receipt.sha256
      || archive.disk.bytes !== sealedArchive.receipt.bytes
      || archive.disk.textCharacters !== sealedArchive.fileTextCharacters
      || archive.finalSnapshotSha256 !== bundle.snapshot.tailSha256
      || Evidence.canonicalJson(archive.requiredOrder)
        !== Evidence.canonicalJson(["sv1", "sv2", "archive"])
      || archiveRecords.length !== 1 || exactArchive.length !== 1
      || sv1.length !== 1 || sv2.length !== 1 || sv3.length !== 0
      || archive.positions.sv1.lineNumber !== sv1[0].lineNumber
      || archive.positions.sv2.lineNumber !== sv2[0].lineNumber
      || archive.positions.archive.lineNumber !== exactArchive[0].lineNumber
      || !(archive.positions.sv1.lineNumber < archive.positions.sv2.lineNumber
        && archive.positions.sv2.lineNumber < archive.positions.archive.lineNumber)
      || archive.archive.lineNumber !== exactArchive[0].lineNumber) {
    Common.fail("material_shop_archive_replay_drift", "journey_verify",
      "sealed JSON bytes and bounded SAFEEXIT log do not replay the captured archive evidence");
  }
  return archive;
}

function verifyShutdownAndResidue(raw) {
  const shutdown = raw.persistence.shutdown;
  exactKeys(shutdown, ["shutdown", "response", "residue"],
    "material_shop_shutdown_invalid");
  const receipt = shutdown.shutdown;
  exactKeys(receipt, ["schema", "lifecycle", "action", "pid", "requestedAt",
    "completedAt", "responseSha256", "responseSucceeded", "evidenceSha256"],
  "material_shop_shutdown_invalid");
  const unsigned = Object.assign({}, receipt);
  delete unsigned.evidenceSha256;
  if (receipt.schema !== "workbench-live-e2e.npc.supported-shutdown.v1"
      || receipt.lifecycle !== "restart" || receipt.action !== "shutdown"
      || receipt.pid !== raw.admissions[1].operatorAttestation.pid
      || !Number.isFinite(Date.parse(receipt.requestedAt))
      || !Number.isFinite(Date.parse(receipt.completedAt))
      || Date.parse(receipt.completedAt) < Date.parse(receipt.requestedAt)
      || receipt.responseSha256 !== Evidence.sha256Text(Evidence.canonicalJson(shutdown.response))
      || receipt.responseSucceeded !== true
      || receipt.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_shutdown_invalid", "journey_verify",
      "supported shutdown receipt is malformed or detached from the restart PID");
  }
  LauncherObservation.assertResponseSucceeded(shutdown.response, "journey_verify",
    "material shop supported shutdown");
  LauncherObservation.assertResidueClean(shutdown.residue);
  const residue = raw.persistence.residue;
  exactKeys(residue, ["schema", "checkedAfterRestartShutdown", "checkedAt", "first",
    "restart", "evidenceSha256"], "material_shop_residue_invalid");
  const unsignedResidue = Object.assign({}, residue);
  delete unsignedResidue.evidenceSha256;
  if (residue.schema !== "workbench-live-e2e.npc.runtime-residue.v2"
      || residue.checkedAfterRestartShutdown !== true
      || residue.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsignedResidue))
      || Evidence.canonicalJson(residue.restart) !== Evidence.canonicalJson(shutdown.residue)) {
    Common.fail("material_shop_residue_invalid", "journey_verify",
      "first/restart residue envelope is malformed or detached");
  }
  LauncherObservation.assertResidueClean(residue.first);
  LauncherObservation.assertResidueClean(residue.restart);
  return true;
}

function verifyPersistence(raw, applicability, route, runDir) {
  const p = raw.persistence;
  exactKeys(p, ["archive", "seedInvariant", "recoveryInvariant", "targetAfterRestart",
    "saveStates", "shutdown", "residue"], "material_shop_persistence_raw_invalid");
  exactKeys(p.saveStates, ["baseline", "archive", "restart"],
    "material_shop_save_state_set_invalid");
  const itemName = applicability.selectedUnlockedTarget.itemName;
  const slot = raw.lifecycle.slots.targetSlot;
  const baseline = CandidateLifecycle.verifySaveStateArtifact(runDir,
    p.saveStates.baseline, "baseline", slot, itemName);
  const archiveState = CandidateLifecycle.verifySaveStateArtifact(runDir,
    p.saveStates.archive, "archive", slot, itemName);
  const restartState = CandidateLifecycle.verifySaveStateArtifact(runDir,
    p.saveStates.restart, "restart", slot, itemName);
  const archivedBytes = Evidence.readExactRegularFile(path.resolve(runDir,
    p.saveStates.archive.relativePath.replace(/\//g, path.sep)), {
    phase: "journey_verify", maximumBytes: 128 * 1024 * 1024,
  }).bytes;
  archiveState.fileTextCharacters = archivedBytes.toString("utf8").length;
  const sourceJson = applicability.sourceFixture.artifacts.find((entry) => entry.kind === "json");
  const seed = verifyPublicArtifactSet(p.seedInvariant, raw.lifecycle.slots.seedSlot,
    "material_shop_seed_invariant_invalid");
  const target = verifyPublicArtifactSet(p.targetAfterRestart, raw.lifecycle.slots.targetSlot,
    "material_shop_target_readback_invalid");
  const seedJson = seed.manifest.artifacts.find((entry) => entry.kind === "json");
  CloneGuard.verifyArtifactSet(raw.lifecycle.recoveryBaseline);
  CloneGuard.verifyArtifactSet(p.recoveryInvariant);
  CloneGuard.assertArtifactSetInvariant(raw.lifecycle.recoveryBaseline, p.recoveryInvariant,
    "material_shop_recovery_changed");
  const archive = verifyArchiveBundle(raw, archiveState);
  verifyShutdownAndResidue(raw);
  if (!sourceJson || seedJson.sha256 !== sourceJson.sha256
      || target.jsonSha256 !== archive.disk.sha256
      || raw.lifecycle.targetClone.baselineJsonSha256 === archive.disk.sha256
      || p.recoveryInvariant.slot !== raw.lifecycle.slots.recoverySlot
      || Evidence.canonicalJson(raw.lifecycle.baselineSaveState)
        !== Evidence.canonicalJson(p.saveStates.baseline)
      || baseline.receipt.sha256 !== raw.lifecycle.targetClone.baselineJsonSha256
      || archiveState.receipt.sha256 !== archive.disk.sha256
      || restartState.receipt.sha256 !== target.jsonSha256
      || archiveState.receipt.sha256 !== restartState.receipt.sha256
      || baseline.projection.money !== applicability.sourceFixture.money
      || baseline.projection.owned !== 0
      || archiveState.projection.money !== route.settlement.projectedBalance
      || restartState.projection.money !== route.settlement.projectedBalance
      || archiveState.projection.owned !== 1 || restartState.projection.owned !== 1
      || route.settlement.beforeOwned !== 0 || route.settlement.afterOwned !== 1
      || route.restartOwned !== 1
      || route.settlement.baselineBalance !== baseline.projection.money
      || route.settlement.buyTotal !== route.settlement.unitPrice
      || route.settlement.projectedBalance
        !== route.settlement.baselineBalance - route.settlement.buyTotal) {
    Common.fail("material_shop_persistence_raw_invalid", "journey_verify",
      "exact settlement, sealed save mutation, SAFEEXIT/restart, recovery, or shutdown is incomplete");
  }
  return { baselineMoney: baseline.projection.money, beforeOwned: baseline.projection.owned,
    unitPrice: route.settlement.unitPrice, buyTotal: route.settlement.buyTotal,
    settledMoney: archiveState.projection.money, archiveOwned: archiveState.projection.owned,
    restartOwned: restartState.projection.owned, archiveSha256: archiveState.receipt.sha256,
    restartSha256: restartState.receipt.sha256 };
}

function verifyLifecycle(raw, plan, applicability, build) {
  const value = raw.lifecycle;
  exactKeys(value, ["schema", "preparedAt", "resourcesRoot", "candidateIdentity", "slots",
    "fixtureAuthorityBinding", "seedImport", "recoveryBaseline", "recoveryLockReleased", "targetClone",
    "baselineSaveState", "preparationSha256"], "material_shop_lifecycle_invalid");
  const unsigned = Object.assign({}, value);
  delete unsigned.preparationSha256;
  if (value.schema !== "workbench-live-e2e.material-shop.lifecycle-preparation.v2"
      || value.preparationSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))
      || Evidence.canonicalJson(value.candidateIdentity)
        !== Evidence.canonicalJson(build.candidateIdentity)
      || Evidence.canonicalJson(value.slots) !== Evidence.canonicalJson(plan.slots)
      || value.recoveryLockReleased !== true) {
    Common.fail("material_shop_lifecycle_invalid", "journey_verify",
      "candidate lifecycle is malformed or detached from build/plan");
  }
  exactKeys(value.seedImport, ["sourceFixtureSlot", "dedicatedSeedSlot", "transformId",
    "sourcePath", "destination", "sourceSha256", "destinationSha256", "bytes"],
  "material_shop_seed_import_invalid");
  const sourceJson = applicability.sourceFixture.artifacts.find((entry) => entry.kind === "json");
  Common.assertCanonicalRoot(value.fixtureAuthorityBinding
    && value.fixtureAuthorityBinding.root);
  Applicability.replayFixtureAuthorityBinding(value.fixtureAuthorityBinding,
    applicability, { resourcesRoot: value.resourcesRoot, appData: process.env.APPDATA });
  if (!sourceJson || value.seedImport.sourceFixtureSlot !== Common.SOURCE_FIXTURE_SLOT
      || value.seedImport.dedicatedSeedSlot !== plan.slots.seedSlot
      || value.seedImport.transformId !== "exact-byte-copy"
      || value.seedImport.sourceSha256 !== sourceJson.sha256
      || value.seedImport.destinationSha256 !== sourceJson.sha256
      || value.seedImport.bytes !== sourceJson.bytes
      || !Evidence.pathInside(value.resourcesRoot, value.seedImport.destination)) {
    Common.fail("material_shop_seed_import_invalid", "journey_verify",
      "b4 to dedicated A5 seed exact-byte receipt is invalid");
  }
  CloneGuard.verifyArtifactSet(value.recoveryBaseline);
  if (!Evidence.isPlainObject(value.targetClone)
      || !Common.SHA256_RE.test(String(value.targetClone.baselineJsonSha256 || ""))
      || value.targetClone.afterArchiveJsonSha256 !== null) {
    Common.fail("material_shop_target_clone_invalid", "journey_verify",
      "lifecycle preparation must freeze the target baseline before runtime archive mutation");
  }
  return value;
}

function verifyAgentRuntimeSessions(raw, build) {
  if (!Array.isArray(raw.sessions) || raw.sessions.length !== 2) {
    Common.fail("material_shop_agent_runtime_session_set_invalid", "journey_verify",
      "Agent Runtime raw evidence requires exact first and restart trusted-runner sessions");
  }
  const expectedLabels = ["first", "restart"];
  const completions = raw.sessions.map((session, index) => {
    exactKeys(session, ["label", "status", "completion", "transcript", "transcriptSha256",
      "ledger", "ledgerSha256", "cleanExit"],
    "material_shop_agent_runtime_session_invalid");
    if (session.label !== expectedLabels[index] || session.cleanExit !== true
        || !Evidence.isPlainObject(session.status)
        || session.status.projectRunning !== true
        || session.status.qualificationState !== "verified"
        || typeof session.status.lifecycleRef !== "string" || !session.status.lifecycleRef
        || !Array.isArray(session.transcript) || !Array.isArray(session.ledger)
        || session.transcriptSha256
          !== Evidence.sha256Text(Evidence.canonicalJson(session.transcript))
        || session.ledgerSha256 !== Evidence.sha256Text(Evidence.canonicalJson(session.ledger))) {
      Common.fail("material_shop_agent_runtime_session_invalid", "journey_verify",
        "trusted-runner status, transcript, ledger, or clean-exit binding is invalid", {
          label: expectedLabels[index],
        });
    }
    session.ledger.forEach((entry) => {
      if (!Evidence.isPlainObject(entry) || !Evidence.isPlainObject(entry.request)
          || typeof entry.request.method !== "string" || entry.request.method.length < 1
          || entry.error !== null) {
        Common.fail("material_shop_agent_runtime_ledger_invalid", "journey_verify",
          "trusted controller ledger contains a malformed or failed RPC", {
            label: session.label,
          });
      }
    });
    const preparation = { resourcesRoot: raw.lifecycle.resourcesRoot,
      candidateRoot: build.candidateRoot, candidateIdentity: build.candidateIdentity };
    const completion = TrustedRunnerJsonl.validateCompletion(session.completion,
      preparation, { candidateRoot: build.candidateRoot });
    return { value: completion,
      sha256: Evidence.sha256Text(Evidence.canonicalJson(completion)) };
  });
  if (raw.sessions[0].status.lifecycleRef === raw.sessions[1].status.lifecycleRef
      || completions[0].value.guardianProcessId === completions[1].value.guardianProcessId
      || completions.some((entry) => entry.value.runtimeMode !== "isolated_candidate")
      || completions.some((entry) => entry.value.processPath
        .toLowerCase() !== build.candidateIdentity.processPath.toLowerCase())
      || completions[0].value.coreSha256.toLowerCase()
        !== completions[1].value.coreSha256.toLowerCase()
      || completions.some((entry) => entry.value.buildIdentity
        .toLowerCase() !== build.candidateIdentity.buildIdentity.toLowerCase())
      || completions.some((entry) => entry.value.payloadClosure
        .toLowerCase() !== build.candidateIdentity.payloadClosure.toLowerCase())) {
    Common.fail("material_shop_agent_runtime_restart_invalid", "journey_verify",
      "trusted runner restart did not produce two fresh clean sessions for one exact candidate");
  }
  return completions;
}

function verifyAgentRuntimeCapture(value, runDir, root) {
  return CaptureVerifier.verifyAgentRuntimeCapture(root, runDir, value);
}

function receiptSha256(receipt) {
  return Evidence.sha256Text(Evidence.canonicalJson(receipt));
}

function sameSha256(left, right) {
  const normalizedLeft = String(left || "").toLowerCase();
  const normalizedRight = String(right || "").toLowerCase();
  return Common.SHA256_RE.test(normalizedLeft)
    && Common.SHA256_RE.test(normalizedRight)
    && normalizedLeft === normalizedRight;
}

function actionIntentSequenceSha256(intents) {
  return Evidence.sha256Text(Evidence.canonicalJson(intents.map((intent) => ({
    stepId: intent.stepId, role: intent.role, method: intent.method,
    arguments: intent.arguments, actionId: intent.actionId,
    receiptSha256: intent.receiptSha256,
  }))));
}

function verifyAgentRuntimeActionIntent(intent, control, receiptByHash, ledgerEntries) {
  exactKeys(intent, ["role", "method", "arguments", "actionId", "receiptSha256"],
    "material_shop_agent_runtime_action_intent_invalid");
  const receipt = receiptByHash.get(intent.receiptSha256);
  const matches = ledgerEntries.filter((entry) => entry.request.method === intent.method
    && entry.request.params && entry.request.params.actionId === intent.actionId
    && entry.request.params.operation === intent.method
    && Evidence.canonicalJson(entry.request.params.arguments)
      === Evidence.canonicalJson(intent.arguments));
  if (typeof intent.role !== "string" || !intent.role
      || !Protocol.AGENT_RUNTIME_RPC_METHODS.includes(intent.method)
      || !Evidence.isPlainObject(intent.arguments)
      || typeof intent.actionId !== "string" || !intent.actionId
      || !Common.SHA256_RE.test(String(intent.receiptSha256 || ""))
      || !receipt || receipt.actionId !== intent.actionId || matches.length !== 1
      || Evidence.canonicalJson(matches[0].result) !== Evidence.canonicalJson(receipt)) {
    Common.fail("material_shop_agent_runtime_action_intent_invalid", "journey_verify",
      "action intent is not uniquely bound to its exact receipt and trusted-session RPC", {
        stepId: control.stepId, role: intent.role, matches: matches.length,
      });
  }
  return intent;
}

function verifyAgentRuntimeKeyboardSequence(byStep) {
  const relevantSteps = new Set(Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions
    .map((entry) => entry.stepId));
  const actual = [];
  byStep.forEach((control) => {
    if (!relevantSteps.has(control.stepId)) return;
    control.actionIntents.forEach((intent) => actual.push(Object.assign({
      stepId: control.stepId,
    }, intent)));
  });
  if (actual.length !== Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.length) {
    Common.fail("material_shop_agent_runtime_keyboard_sequence_invalid", "journey_verify",
      "key-only material/recipe path contains a missing or extra action", {
        expected: Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.length,
        actual: actual.length,
      });
  }
  Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.forEach((expected, index) => {
    const intent = actual[index];
    if (intent.stepId !== expected.stepId || intent.role !== expected.role
        || intent.method !== "input.press_key"
        || Evidence.canonicalJson(intent.arguments) !== Evidence.canonicalJson({
          key: expected.key, modifiers: expected.modifiers, repeat: expected.repeat,
        })) {
      Common.fail("material_shop_agent_runtime_keyboard_sequence_invalid", "journey_verify",
        "key-only material/recipe path differs from the exact frozen ordered sequence", {
          index, expectedStepId: expected.stepId, expectedRole: expected.role,
          actualStepId: intent.stepId, actualRole: intent.role,
        });
    }
  });
  return { count: actual.length, sha256: actionIntentSequenceSha256(actual) };
}

function verifyAgentRuntimeCloseOutcome(byStep, captures, sessions, options) {
  const settings = options || {};
  const closeControl = byStep.get(settings.closeStepId);
  const successorControl = byStep.get(settings.successorStepId);
  const closeIntent = closeControl && closeControl.actionIntents.find(
    (intent) => intent.role === settings.closeRole && intent.method === settings.closeMethod);
  const successorIntent = successorControl && successorControl.actionIntents.find(
    (intent) => intent.role === "open_materials" && intent.method === "panel.open"
      && Evidence.canonicalJson(intent.arguments)
        === Evidence.canonicalJson({ panel: "materials" }));
  const ordinaryClickValid = settings.closeMethod !== "input.click" || closeIntent
    && Evidence.isPlainObject(closeIntent.arguments)
    && Object.keys(closeIntent.arguments).sort().join("|")
      === ["button", "clickCount", "coordinateSpace", "x", "y"].sort().join("|")
    && closeIntent.arguments.coordinateSpace === "observation_px"
    && Number.isInteger(closeIntent.arguments.x) && closeIntent.arguments.x >= 0
    && Number.isInteger(closeIntent.arguments.y) && closeIntent.arguments.y >= 0
    && closeIntent.arguments.button === "primary" && closeIntent.arguments.clickCount === 1;
  const successorCaptures = captures.filter((entry) => entry.stepId === settings.successorStepId);
  const successorCapture = successorCaptures.length === 1 ? successorCaptures[0] : null;
  const closeOrdinal = closeControl && closeControl.ordinal;
  const successorOrdinal = successorControl && successorControl.ordinal;
  const firstSession = sessions.find((session) => session.label === "first");
  const restartSession = sessions.find((session) => session.label === "restart");
  const firstLedger = firstSession && firstSession.ledger;
  const firstActionLedger = Array.isArray(firstLedger) ? firstLedger.filter((entry) =>
    ["panel.open", "input.click", "input.press_key", "input.type_text"]
      .includes(entry.request.method)) : [];
  const closeActionIndex = firstActionLedger.findIndex((entry) => entry.request.params
    && entry.request.params.actionId === (closeIntent && closeIntent.actionId));
  const successorActionIndex = firstActionLedger.findIndex((entry) => entry.request.params
    && entry.request.params.actionId === (successorIntent && successorIntent.actionId));
  const restartHasEitherAction = restartSession && restartSession.ledger.some((entry) =>
    entry.request.params && [closeIntent && closeIntent.actionId,
      successorIntent && successorIntent.actionId].includes(entry.request.params.actionId));
  const successorLedgerIndex = Array.isArray(firstLedger) ? firstLedger.findIndex((entry) =>
    entry.request.method === "panel.open" && entry.request.params
      && entry.request.params.actionId === (successorIntent && successorIntent.actionId)) : -1;
  const observationsAfterSuccessor = Array.isArray(firstLedger) ? firstLedger.map(
    (entry, index) => ({ entry, index })).filter(({ entry, index }) =>
      index > successorLedgerIndex && entry.request.method === "observation.capture") : [];
  const observationMatches = observationsAfterSuccessor.filter(({ entry }) =>
    entry.request.params
    && entry.request.params.observationGrantId
      === (successorCapture && successorCapture.grantId)
    && entry.request.params.targetId === (successorCapture && successorCapture.targetId)
    && entry.request.params.dataScope === "pixels"
    && entry.request.params.allowValidatedFlashKeyframeFallback === false
    && entry.result && entry.request.params.sessionId === entry.result.sessionId
    && entry.result.visible === true && entry.result.minimized === false
    && typeof entry.result.panelInstanceId === "string" && entry.result.panelInstanceId.length > 0
    && Number.isInteger(entry.result.documentGeneration)
    && entry.result.observationId === (successorCapture && successorCapture.observationId)
    && entry.result.observationGrantId === (successorCapture && successorCapture.grantId)
    && entry.result.targetId === (successorCapture && successorCapture.targetId)
    && Array.isArray(entry.result.frames)
    && entry.result.frames.length === 1
    && entry.result.frames[0].observationId === (successorCapture && successorCapture.observationId)
    && entry.result.frames[0].frameId === (successorCapture && successorCapture.frameId)
    && entry.result.frames[0].targetId === (successorCapture && successorCapture.targetId)
    && typeof entry.result.frames[0].opaqueContentHandle === "string"
    && entry.result.frames[0].opaqueContentHandle.length > 0
    && entry.result.frames[0].sourceLayer === "web_overlay"
    && entry.result.frames[0].pixelFormat === "bgra8_premultiplied"
    && sameSha256(entry.result.frames[0].contentHash,
      successorCapture && successorCapture.frameContentHash)
    && entry.result.frames[0].width === (successorCapture && successorCapture.width)
    && entry.result.frames[0].height === (successorCapture && successorCapture.height));
  const observation = observationMatches.length === 1 ? observationMatches[0] : null;
  const frame = observation && observation.entry.result.frames[0];
  const contentMatches = observation && firstLedger.map((entry, index) => ({ entry, index }))
    .filter(({ entry, index }) => index === observation.index + 1
      && entry.request.method === "content.read" && entry.request.params
      && entry.request.params.handle === frame.opaqueContentHandle
      && entry.request.params.totalLength === successorCapture.source.bytes
      && sameSha256(entry.request.params.contentHash, successorCapture.frameContentHash)
      && entry.result && entry.result.returnedBytes === successorCapture.source.bytes
      && sameSha256(entry.result.contentHash, successorCapture.frameContentHash));
  if (!closeControl || !successorControl || !closeIntent || !successorIntent
      || !ordinaryClickValid
      || closeControl.actionIntents.length !== 1 || successorControl.actionIntents.length !== 1
      || successorCaptures.length !== 1 || !successorCapture
      || successorCapture.sessionLabel !== "first"
      || successorCapture.source.pixelFormat !== "bgra8_premultiplied"
      || successorCapture.source.bytes !== successorCapture.width * successorCapture.height * 4
      || !sameSha256(successorCapture.source.sha256, successorCapture.frameContentHash)
      || successorControl.captureRefs.length !== 1
      || successorControl.captureRefs[0] !== successorCapture.captureSha256
      || !Number.isInteger(closeOrdinal) || !Number.isInteger(successorOrdinal)
      || successorOrdinal !== closeOrdinal + 1
      || closeActionIndex < 0 || successorActionIndex !== closeActionIndex + 1
      || restartHasEitherAction || successorLedgerIndex < 0
      || !observation || observationsAfterSuccessor[0].index !== observation.index
      || observationMatches.length !== 1 || !contentMatches || contentMatches.length !== 1) {
    Common.fail("material_shop_agent_runtime_close_outcome_invalid", "journey_verify",
      "close completion lacks its ordered idle-gated materials reopen and fresh visible capture", {
        closeStepId: settings.closeStepId, successorStepId: settings.successorStepId,
      });
  }
  return {
    closeStepId: settings.closeStepId,
    closeRole: settings.closeRole,
    closeMethod: settings.closeMethod,
    closeActionReceiptSha256: closeIntent.receiptSha256,
    successorStepId: settings.successorStepId,
    successorMethod: "panel.open",
    successorActionReceiptSha256: successorIntent.receiptSha256,
    successorCaptureSha256: successorCapture.captureSha256,
    successorSessionLabel: "first",
    successorObservationId: successorCapture.observationId,
    successorFrameId: successorCapture.frameId,
    successorFrameContentHash: successorCapture.frameContentHash,
    admissionFence: "prior_tracked_visual_idle_required",
    successorPanel: "materials",
  };
}

function verifyAgentRuntimeControls(raw, plan, captures) {
  const legacy = plan.schema === Protocol.LEGACY_AGENT_RUNTIME_PLAN_SCHEMA;
  if (!Array.isArray(raw.controls) || raw.controls.length !== plan.steps.length) {
    Common.fail("material_shop_agent_runtime_control_set_invalid", "journey_verify",
      "Agent Runtime raw evidence requires the exact plan ledger");
  }
  const captureBySha = new Map(captures.map((entry) => [entry.captureSha256, entry]));
  const actualRpcMethods = new Set(raw.sessions.flatMap((session) => session.ledger
    .map((entry) => entry.request.method)));
  const ledgerEntries = raw.sessions.flatMap((session) => session.ledger);
  const actionMethods = new Set(["panel.open", "input.click", "input.press_key",
    "input.type_text"]);
  const byStep = new Map();
  raw.controls.forEach((control, index) => {
    exactKeys(control, ["stepId", "ordinal", "transport", "methods",
      ...(legacy ? [] : ["actionIntents"]), "actionReceipts",
      "captureRefs", "completedAt"], "material_shop_agent_runtime_control_invalid");
    const step = plan.steps[index];
    if (control.stepId !== step.id || control.ordinal !== index
        || control.transport !== Protocol.AGENT_RUNTIME_TRANSPORT
        || Evidence.canonicalJson(control.methods) !== Evidence.canonicalJson(step.driverMethods)
        || !legacy && !Array.isArray(control.actionIntents)
        || !Array.isArray(control.actionReceipts) || !Array.isArray(control.captureRefs)
        || !Number.isFinite(Date.parse(control.completedAt))
        || control.captureRefs.some((sha256) => !captureBySha.has(sha256))
        || control.captureRefs.some((sha256) => captureBySha.get(sha256).stepId !== step.id)
        || step.requiresCapture && control.captureRefs.length < 1
        || control.methods.some((method) => Protocol.AGENT_RUNTIME_RPC_METHODS.includes(method)
          && !actualRpcMethods.has(method))) {
      Common.fail("material_shop_agent_runtime_control_invalid", "journey_verify",
        "Agent Runtime control ledger differs from the exact plan or visible captures", {
          stepId: step.id,
        });
    }
    const requiresActionReceipt = control.methods.some((method) => actionMethods.has(method));
    if (requiresActionReceipt && control.actionReceipts.length < 1) {
      Common.fail("material_shop_agent_runtime_action_receipt_invalid", "journey_verify",
        "visible write step lacks a terminal action receipt", { stepId: step.id });
    }
    control.actionReceipts.forEach((receipt) => {
      if (!Evidence.isPlainObject(receipt) || receipt.terminal !== true
          || receipt.outcome !== "input_dispatched"
          || receipt.evidenceKind !== "broker_dispatch"
          || receipt.reasonCode !== "none"
          || receipt.reconcileKind !== "none"
          || receipt.retryable !== false) {
        Common.fail("material_shop_agent_runtime_action_receipt_invalid", "journey_verify",
          "visible write action lacks one exact broker-dispatch receipt", { stepId: step.id });
      }
    });
    if (!legacy) {
      const expectedActionMethods = control.methods.filter((method) => actionMethods.has(method));
      const actualActionMethods = Array.from(new Set(control.actionIntents.map(
        (intent) => intent.method)));
      const receiptByHash = new Map(control.actionReceipts.map((receipt) =>
        [receiptSha256(receipt), receipt]));
      if (Evidence.canonicalJson(actualActionMethods)
            !== Evidence.canonicalJson(expectedActionMethods)
          || new Set(control.actionIntents.map((intent) => intent.actionId)).size
          !== control.actionIntents.length
          || new Set(control.actionIntents.map((intent) => intent.receiptSha256)).size
            !== control.actionIntents.length
          || control.actionIntents.length !== control.actionReceipts.length) {
        Common.fail("material_shop_agent_runtime_action_intent_invalid", "journey_verify",
          "action intents and receipts are not a one-to-one exact set", { stepId: step.id });
      }
      if (["open_materials", "recipe_reopen_materials", "reopen_materials",
        "restart_open_materials"].includes(step.id)
          && (control.actionIntents.length !== 1
            || control.actionIntents[0].role !== "open_materials"
            || control.actionIntents[0].method !== "panel.open"
            || Evidence.canonicalJson(control.actionIntents[0].arguments)
              !== Evidence.canonicalJson({ panel: "materials" }))) {
        Common.fail("material_shop_agent_runtime_action_intent_invalid", "journey_verify",
          "structured materials opener is not exact-bound to its control step", {
            stepId: step.id,
          });
      }
      control.actionIntents.forEach((intent) => verifyAgentRuntimeActionIntent(
        intent, control, receiptByHash, ledgerEntries));
    }
    byStep.set(step.id, control);
  });
  if (!legacy) {
    const orderedIntents = raw.controls.flatMap((control) => control.actionIntents.map(
      (intent) => Object.assign({ stepId: control.stepId }, intent)));
    const actionLedgerEntries = ledgerEntries.filter((entry) =>
      actionMethods.has(entry.request.method));
    if (new Set(orderedIntents.map((intent) => intent.actionId)).size
          !== orderedIntents.length
        || new Set(orderedIntents.map((intent) => intent.receiptSha256)).size
          !== orderedIntents.length
        || actionLedgerEntries.length !== orderedIntents.length) {
      Common.fail("material_shop_agent_runtime_action_sequence_invalid", "journey_verify",
        "action intents must be a globally unique one-to-one ordered ledger projection", {
          actionIntentCount: orderedIntents.length,
          actionLedgerCount: actionLedgerEntries.length,
        });
    }
    orderedIntents.forEach((intent, index) => {
      const entry = actionLedgerEntries[index];
      if (entry.request.method !== intent.method || !entry.request.params
          || entry.request.params.actionId !== intent.actionId
          || entry.request.params.operation !== intent.method
          || Evidence.canonicalJson(entry.request.params.arguments)
            !== Evidence.canonicalJson(intent.arguments)
          || receiptSha256(entry.result) !== intent.receiptSha256) {
        Common.fail("material_shop_agent_runtime_action_sequence_invalid", "journey_verify",
          "trusted action ledger order differs from the frozen control-step order", {
            index, stepId: intent.stepId, role: intent.role,
          });
      }
    });
  }
  if (new Set(captures.map((entry) => entry.captureSha256)).size !== captures.length
      || captures.some((entry) => !byStep.has(entry.stepId))) {
    Common.fail("material_shop_agent_runtime_capture_set_invalid", "journey_verify",
      "visible captures are duplicated or detached from the exact step ledger");
  }
  const keyboard = legacy ? null : verifyAgentRuntimeKeyboardSequence(byStep);
  const closeOutcomes = legacy ? null : {
    recipe: verifyAgentRuntimeCloseOutcome(byStep, captures, raw.sessions, {
      closeStepId: "recipe_escape_close", closeRole: "recipe_close_with_escape",
      closeMethod: "input.press_key", successorStepId: "recipe_reopen_materials",
    }),
    ordinary: verifyAgentRuntimeCloseOutcome(byStep, captures, raw.sessions, {
      closeStepId: "ordinary_close", closeRole: "npcshop_close",
      closeMethod: "input.click", successorStepId: "reopen_materials",
    }),
  };
  const actionIntentCount = legacy ? 0 : raw.controls.reduce(
    (sum, control) => sum + control.actionIntents.length, 0);
  return { byStep, keyboard, closeOutcomes,
    summary: { completedSteps: plan.steps.map((step) => step.id),
    provider: Protocol.AGENT_RUNTIME_PROVIDER, transport: Protocol.AGENT_RUNTIME_TRANSPORT,
    authorizationDecisionId: plan.authorization.decisionId,
    controllerBusinessApiCalls: 0, sessionCount: 2, visibleCaptureCount: captures.length,
    ...(legacy ? {} : { actionIntentCount, keyboardActionIntentCount: keyboard.count,
      keyboardSequenceSha256: keyboard.sha256 }) } };
}

function verifyAgentRuntimeAuthority(raw, plan, applicability, controls, captures) {
  const authority = raw.authority;
  exactKeys(authority, ["target", "settlementProjection", "commitDispatch",
    "saveProjection", "restartReadback"], "material_shop_agent_runtime_authority_invalid");
  const target = applicability.selectedUnlockedTarget;
  if (Evidence.canonicalJson(authority.target) !== Evidence.canonicalJson(target)) {
    Common.fail("material_shop_agent_runtime_authority_invalid", "journey_verify",
      "authority projection is detached from the frozen applicability target");
  }
  const projection = authority.settlementProjection;
  exactKeys(projection, ["quantity", "saleCount", "baselineBalance", "unitPrice",
    "buyTotal", "projectedBalance", "beforeOwned", "afterOwned",
    "intentCaptureSha256", "settlementCaptureSha256"],
  "material_shop_agent_runtime_settlement_projection_invalid");
  const captureSet = new Set(captures.map((entry) => entry.captureSha256));
  const baselineMoney = Number(raw.persistence.saveStates.baseline.money);
  const archiveMoney = Number(raw.persistence.saveStates.archive.money);
  if (projection.quantity !== 1 || projection.saleCount !== 0
      || projection.baselineBalance !== baselineMoney
      || !Number.isFinite(projection.unitPrice) || projection.unitPrice < 0
      || projection.buyTotal !== projection.unitPrice
      || projection.projectedBalance !== baselineMoney - projection.unitPrice
      || projection.projectedBalance !== archiveMoney
      || projection.beforeOwned !== 0 || projection.afterOwned !== 1
      || !captureSet.has(projection.intentCaptureSha256)
      || !captureSet.has(projection.settlementCaptureSha256)
      || !controls.get("unlocked_intent_qty1").captureRefs
        .includes(projection.intentCaptureSha256)
      || !controls.get("unlocked_settlement").captureRefs
        .includes(projection.settlementCaptureSha256)) {
    Common.fail("material_shop_agent_runtime_settlement_projection_invalid", "journey_verify",
      "visible settlement and sealed save delta do not prove exact q1/zero-sale totals");
  }
  const dispatch = authority.commitDispatch;
  exactKeys(dispatch, ["stepId", "authorizationDecisionId", "authorizationDecisionSha256",
    "actionReceiptSha256"], "material_shop_agent_runtime_commit_dispatch_invalid");
  const commitControl = controls.get("unlocked_commit");
  const commitReceiptHashes = commitControl.actionReceipts.map(receiptSha256);
  if (dispatch.stepId !== "unlocked_commit"
      || dispatch.authorizationDecisionId !== plan.authorization.decisionId
      || dispatch.authorizationDecisionSha256 !== plan.authorization.decisionSha256
      || commitControl.actionReceipts.length !== 1
      || !commitReceiptHashes.includes(dispatch.actionReceiptSha256)) {
    Common.fail("material_shop_agent_runtime_commit_dispatch_invalid", "journey_verify",
      "one-shot authorization is not bound to the exact terminal visible commit action");
  }
  const save = authority.saveProjection;
  exactKeys(save, ["baselineMoney", "archiveMoney", "restartMoney", "beforeOwned",
    "archiveOwned", "restartOwned"], "material_shop_agent_runtime_save_projection_invalid");
  const states = raw.persistence.saveStates;
  if (save.baselineMoney !== states.baseline.money
      || save.archiveMoney !== states.archive.money || save.restartMoney !== states.restart.money
      || save.beforeOwned !== states.baseline.owned || save.archiveOwned !== states.archive.owned
      || save.restartOwned !== states.restart.owned
      || save.baselineMoney !== projection.baselineBalance
      || save.archiveMoney !== projection.projectedBalance
      || save.restartMoney !== projection.projectedBalance
      || save.beforeOwned !== 0 || save.archiveOwned !== 1 || save.restartOwned !== 1) {
    Common.fail("material_shop_agent_runtime_save_projection_invalid", "journey_verify",
      "baseline/archive/restart sealed-save projections do not prove owned 0 to 1");
  }
  exactKeys(authority.restartReadback, ["itemName", "owned", "captureSha256"],
    "material_shop_agent_runtime_restart_readback_invalid");
  if (authority.restartReadback.itemName !== target.itemName
      || authority.restartReadback.owned !== 1
      || !controls.get("restart_readback").captureRefs
        .includes(authority.restartReadback.captureSha256)) {
    Common.fail("material_shop_agent_runtime_restart_readback_invalid", "journey_verify",
      "fresh-process visible readback does not bind owned one");
  }
  return projection;
}

function verifyAgentRuntimePersistence(raw, applicability, projection, runDir, completions) {
  const p = raw.persistence;
  exactKeys(p, ["seedInvariant", "recoveryInvariant", "targetAfterRestart", "saveStates",
    "firstShutdown", "restartShutdown"], "material_shop_agent_runtime_persistence_invalid");
  exactKeys(p.saveStates, ["baseline", "archive", "restart"],
    "material_shop_save_state_set_invalid");
  const itemName = applicability.selectedUnlockedTarget.itemName;
  const slot = raw.lifecycle.slots.targetSlot;
  const baseline = CandidateLifecycle.verifySaveStateArtifact(runDir,
    p.saveStates.baseline, "baseline", slot, itemName);
  const archive = CandidateLifecycle.verifySaveStateArtifact(runDir,
    p.saveStates.archive, "archive", slot, itemName);
  const restart = CandidateLifecycle.verifySaveStateArtifact(runDir,
    p.saveStates.restart, "restart", slot, itemName);
  const sourceJson = applicability.sourceFixture.artifacts.find((entry) => entry.kind === "json");
  const seed = verifyPublicArtifactSet(p.seedInvariant, raw.lifecycle.slots.seedSlot,
    "material_shop_seed_invariant_invalid");
  const target = verifyPublicArtifactSet(p.targetAfterRestart, slot,
    "material_shop_target_readback_invalid");
  const seedJson = seed.manifest.artifacts.find((entry) => entry.kind === "json");
  CloneGuard.verifyArtifactSet(raw.lifecycle.recoveryBaseline);
  CloneGuard.verifyArtifactSet(p.recoveryInvariant);
  CloneGuard.assertArtifactSetInvariant(raw.lifecycle.recoveryBaseline, p.recoveryInvariant,
    "material_shop_recovery_changed");
  const shutdowns = [[p.firstShutdown, "first", completions[0]],
    [p.restartShutdown, "restart", completions[1]]];
  shutdowns.forEach(([shutdown, label, completion]) => {
    exactKeys(shutdown, ["sessionLabel", "completionSha256", "cleanExit"],
      "material_shop_agent_runtime_shutdown_invalid");
    if (shutdown.sessionLabel !== label || shutdown.completionSha256 !== completion.sha256
        || shutdown.cleanExit !== true) {
      Common.fail("material_shop_agent_runtime_shutdown_invalid", "journey_verify",
        "persistence shutdown is detached from its trusted-runner completion", { label });
    }
  });
  if (!sourceJson || seedJson.sha256 !== sourceJson.sha256
      || target.jsonSha256 !== restart.receipt.sha256
      || archive.semanticSha256 !== restart.semanticSha256
      || baseline.receipt.sha256 !== raw.lifecycle.targetClone.baselineJsonSha256
      || Evidence.canonicalJson(raw.lifecycle.baselineSaveState)
        !== Evidence.canonicalJson(p.saveStates.baseline)
      || p.recoveryInvariant.slot !== raw.lifecycle.slots.recoverySlot
      || baseline.projection.money !== projection.baselineBalance
      || archive.projection.money !== projection.projectedBalance
      || restart.projection.money !== projection.projectedBalance
      || baseline.projection.owned !== 0 || archive.projection.owned !== 1
      || restart.projection.owned !== 1) {
    Common.fail("material_shop_agent_runtime_persistence_invalid", "journey_verify",
      "provider-neutral seed/target/recovery/save/restart closure is incomplete");
  }
  return { baselineMoney: baseline.projection.money, settledMoney: archive.projection.money,
    beforeOwned: baseline.projection.owned, archiveOwned: archive.projection.owned,
    restartOwned: restart.projection.owned, archiveSha256: archive.receipt.sha256,
    restartSha256: restart.receipt.sha256,
    archiveSemanticSha256: archive.semanticSha256,
    restartSemanticSha256: restart.semanticSha256 };
}

function verifyAgentRuntimeRawCandidateJourney(raw, plan, applicability, runDir, build) {
  Protocol.validateAgentRuntimeControlPlan(plan);
  const legacy = plan.schema === Protocol.LEGACY_AGENT_RUNTIME_PLAN_SCHEMA;
  exactKeys(raw, ["schema", "capturedAt", "runId", "planSha256", "buildSha256",
    "operationLease", "materializedProducerBinding", "lifecycle", "sessions", "controls",
    "captures", "authority", "persistence", "boundaries", "rawSha256"],
  "material_shop_agent_runtime_raw_invalid");
  const unsigned = Object.assign({}, raw);
  delete unsigned.rawSha256;
  if (raw.schema !== AGENT_RUNTIME_RAW_SCHEMA || !Number.isFinite(Date.parse(raw.capturedAt))
      || raw.runId !== plan.runId || raw.planSha256 !== plan.planSha256
      || !build || raw.buildSha256 !== build.buildSha256
      || Evidence.canonicalJson(raw.materializedProducerBinding)
        !== Evidence.canonicalJson(build.materializedProducerBinding)
      || raw.rawSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_agent_runtime_raw_invalid", "journey_verify",
      "Agent Runtime raw journey is malformed or detached from plan/build/producer");
  }
  const operationLease = RunOperationLease.validateLease(raw.operationLease, runDir);
  if (operationLease.runId !== plan.runId || operationLease.mode !== "live_execution"
      || operationLease.preparationSha256 !== build.preparationSha256
      || operationLease.buildSha256 !== build.buildSha256) {
    Common.fail("material_shop_raw_operation_lease_invalid", "journey_verify",
      "Agent Runtime journey captured a foreign shared operation lease");
  }
  exactKeys(raw.boundaries, ["realGuiExecuted", "candidateBuilt", "candidateExecuted",
    "e2eVerified", "promoted", "standardEntryVerified"],
  "material_shop_raw_boundary_invalid");
  if (raw.boundaries.realGuiExecuted !== true || raw.boundaries.candidateBuilt !== true
      || raw.boundaries.candidateExecuted !== true || raw.boundaries.e2eVerified !== false
      || raw.boundaries.promoted !== false || raw.boundaries.standardEntryVerified !== false) {
    Common.fail("material_shop_raw_boundary_invalid", "journey_verify",
      "Agent Runtime raw journey boundaries overclaim candidate evidence");
  }
  verifyLifecycle(raw, plan, applicability, build);
  const completions = verifyAgentRuntimeSessions(raw, build);
  if (!Array.isArray(raw.captures) || raw.captures.length < 1) {
    Common.fail("material_shop_agent_runtime_capture_set_invalid", "journey_verify",
      "Agent Runtime journey has no visible WGC PNG captures");
  }
  const captures = raw.captures.map((entry) =>
    verifyAgentRuntimeCapture(entry, runDir, raw.lifecycle.fixtureAuthorityBinding.root));
  const controls = verifyAgentRuntimeControls(raw, plan, captures);
  const projection = verifyAgentRuntimeAuthority(raw, plan, applicability,
    controls.byStep, captures);
  const persistence = verifyAgentRuntimePersistence(raw, applicability, projection,
    runDir, completions);
  const na = (summary) => ({ status: "not_applicable_current_data",
    applicabilitySha256: plan.applicability.applicabilitySha256,
    qualifyingOccurrenceCount: summary.qualifyingOccurrenceCount });
  const target = { shopId: applicability.selectedUnlockedTarget.shopId,
    catalogIndex: applicability.selectedUnlockedTarget.catalogIndex,
    itemName: applicability.selectedUnlockedTarget.itemName };
  const captureForStep = (stepId) => captures.find((entry) => entry.stepId === stepId);
  const captureStep = (stepId) => !!captureForStep(stepId);
  const multiCapture = captureForStep("materials_multi_variant");
  const portraitCapture = captureForStep("materials_portraits");
  const recipeCapture = legacy ? null : captureForStep("materials_recipe_jump");
  if (!legacy && (!recipeCapture || !controls.byStep.get("materials_recipe_jump").captureRefs
    .includes(recipeCapture.captureSha256))) {
    Common.fail("material_shop_recipe_jump_evidence_invalid", "journey_verify",
      "exact recipe evidence lacks its mechanically bound visible capture");
  }
  const journey = {
    operationLease: { leaseSha256: raw.operationLease.leaseSha256,
      mode: raw.operationLease.mode, activeAtCapture: true },
    agentRuntime: { provider: Protocol.AGENT_RUNTIME_PROVIDER,
      transport: Protocol.AGENT_RUNTIME_TRANSPORT,
      trustedRunnerSlot: Protocol.AGENT_RUNTIME_SLOT,
      candidateLeaf: Protocol.AGENT_RUNTIME_CANDIDATE_LEAF, sessionCount: 2,
      firstCompletionSha256: completions[0].sha256,
      restartCompletionSha256: completions[1].sha256 },
    materials: { archiveOrder: "authored_xml", visualVerified: captureStep("open_materials")
        && captureStep("materials_visual_current_window"),
      keyboardJourneyVerified: legacy ? captureStep("materials_keyboard")
        : controls.keyboard && controls.keyboard.count
          === Protocol.AGENT_RUNTIME_RECIPE_JUMP.keyboardActions.length,
      candidateViewport: "current_window", responsiveThreeViewportGateBound: true,
      multiVariant: { enemyType: "visible structured multi-occurrence source",
        occurrenceIndices: [0, 1], allVisible: !!multiCapture },
      portraits: Protocol.createAgentRuntimePortraitEvidence(plan, !!portraitCapture),
      ...(!legacy ? { recipeJump: { materialName: plan.recipeJump.materialName,
        category: plan.recipeJump.category, recipeIndex: plan.recipeJump.recipeIndex,
        productName: plan.recipeJump.productName,
        keyboardSequenceSha256: controls.keyboard.sha256,
        visibleCaptureSha256: recipeCapture.captureSha256,
        keySequenceVerified: true,
        escapeCloseOutcome: controls.closeOutcomes.recipe } } : {}) },
    routes: { locked: na(plan.applicability.locked),
      ordinaryClose: { target, forwardCommitted: true, ordinaryCloseCommitted: true,
        ...(!legacy ? { closeOutcome: controls.closeOutcomes.ordinary } : {}) },
      unlocked: { target, forwardCommitted: true, locatedExact: true,
        navigationFocus: "data-navigation-focus", quantity: 1, saleCount: 0,
        settlementProjectionCount: 1, commitDispatchCount: 1,
        settled: true, returnCommitted: true,
        settlement: { baselineBalance: projection.baselineBalance,
          unitPrice: projection.unitPrice, buyTotal: projection.buyTotal,
          projectedBalance: projection.projectedBalance, beforeOwned: 0, afterOwned: 1 } },
      max: na(plan.applicability.max) },
    persistence: { trustedPersistenceShutdown: true, trustedFinalShutdown: true,
      seedReadOnly: true, targetIsolated: true, recoveryAvailable: true,
      restartFreshProcess: true, restartReadbackEqual: true,
      baselineMoney: persistence.baselineMoney, settledMoney: persistence.settledMoney,
      beforeOwned: persistence.beforeOwned, archiveOwned: persistence.archiveOwned,
      restartOwned: persistence.restartOwned, archiveSha256: persistence.archiveSha256,
      restartSha256: persistence.restartSha256,
      archiveSemanticSha256: persistence.archiveSemanticSha256,
      restartSemanticSha256: persistence.restartSemanticSha256 },
    authorityCounts: { settlementProjection: 1, commitDispatch: 1, sale: 0 },
  };
  const evidence = Protocol.createAgentRuntimeJourneyEvidence({ plan,
    controls: controls.summary, journey, boundaries: raw.boundaries });
  const portraitReviewBoundary = Protocol.agentRuntimePortraitReviewBoundary(
    plan, !!portraitCapture);
  return { projection, persistence, sessions: completions, captures, evidence,
    portraitReviewBoundary };
}

function verifyRawCandidateJourney(raw, plan, applicability, runDir, build) {
  if (raw && raw.schema === AGENT_RUNTIME_RAW_SCHEMA) {
    return verifyAgentRuntimeRawCandidateJourney(raw, plan, applicability, runDir, build);
  }
  Protocol.validateControlPlan(plan);
  exactKeys(raw, ["schema", "capturedAt", "runId", "planSha256", "buildSha256", "operationLease",
    "externalToolchainRuntime", "materializedProducerBinding", "lifecycle", "admissions",
    "controls", "transcript",
    "hostLogs", "persistence",
    "boundaries", "rawSha256"], "material_shop_raw_journey_invalid");
  const unsigned = Object.assign({}, raw);
  delete unsigned.rawSha256;
  if (raw.schema !== RAW_SCHEMA || raw.runId !== plan.runId || raw.planSha256 !== plan.planSha256
      || !build || raw.buildSha256 !== build.buildSha256
      || !build.externalToolchain
      || Evidence.canonicalJson(raw.materializedProducerBinding)
        !== Evidence.canonicalJson(build.materializedProducerBinding)
      || raw.rawSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_raw_journey_invalid", "journey_verify",
      "raw candidate journey is malformed or detached");
  }
  ExternalToolchain.replayRuntimeBinding(build.externalToolchain,
    raw.externalToolchainRuntime);
  const operationLease = RunOperationLease.validateLease(raw.operationLease, runDir);
  if (operationLease.runId !== plan.runId || operationLease.mode !== "live_execution"
      || operationLease.preparationSha256 !== build.preparationSha256
      || operationLease.buildSha256 !== build.buildSha256) {
    Common.fail("material_shop_raw_operation_lease_invalid", "journey_verify",
      "raw journey captured a foreign shared run operation lease");
  }
  exactKeys(raw.boundaries, ["realGuiExecuted", "candidateBuilt", "candidateExecuted",
    "e2eVerified", "promoted", "standardEntryVerified"],
  "material_shop_raw_boundary_invalid");
  if (raw.boundaries.realGuiExecuted !== true || raw.boundaries.candidateBuilt !== true
      || raw.boundaries.candidateExecuted !== true || raw.boundaries.e2eVerified !== false
      || raw.boundaries.promoted !== false || raw.boundaries.standardEntryVerified !== false) {
    Common.fail("material_shop_raw_boundary_invalid", "journey_verify",
      "raw journey boundaries overclaim candidate evidence");
  }
  verifyLifecycle(raw, plan, applicability, build);
  verifyAdmissions(raw, plan, build, runDir);
  const controls = verifyControls(raw, plan, runDir);
  const route = verifyTranscript(raw, plan, applicability);
  const host = verifyHostLogs(raw, route);
  const persistence = verifyPersistence(raw, applicability, route, runDir);
  const na = (summary) => ({ status: "not_applicable_current_data",
    applicabilitySha256: plan.applicability.applicabilitySha256,
    qualifyingOccurrenceCount: summary.qualifyingOccurrenceCount });
  const target = applicability.selectedUnlockedTarget;
  const journey = {
    operationLease: { leaseSha256: raw.operationLease.leaseSha256,
      mode: raw.operationLease.mode, activeAtCapture: true },
    externalToolchain: {
      descriptorSha256: build.externalToolchain.descriptorSha256,
      runtimeBindingSha256: raw.externalToolchainRuntime.bindingSha256,
      guardedExactTwoFileLoad: true,
    },
    materials: { archiveOrder: "authored_xml", visualVerified: true,
      keyboardJourneyVerified: true, candidateViewport: "current_window",
      responsiveThreeViewportGateBound: true,
      multiVariant: route.multi,
      portraits: { enemyResolved: true, shopResolved: true, fallbackHarnessBound: true,
        identityLeak: false } },
    routes: {
      locked: plan.applicability.locked.status === "not_applicable_current_data"
        ? na(plan.applicability.locked) : raw.routes.locked,
      ordinaryClose: { target: { shopId: target.shopId, catalogIndex: target.catalogIndex,
        itemName: target.itemName }, forwardCommitted: true, reason: route.ordinaryCloseReason,
        reverseSent: false, ordinaryCloseCommitted: true },
      unlocked: { target: { shopId: target.shopId, catalogIndex: target.catalogIndex,
        itemName: target.itemName }, forwardCommitted: true, locatedExact: true,
        navigationFocus: "data-navigation-focus", quantity: 1, saleCount: 0,
        tradePreviewCount: 1, tradeCommitCount: 1, settled: true, returnCommitted: true,
        settlement: { baselineBalance: route.settlement.baselineBalance,
          unitPrice: route.settlement.unitPrice, buyTotal: route.settlement.buyTotal,
          projectedBalance: route.settlement.projectedBalance,
          beforeOwned: route.settlement.beforeOwned,
          afterOwned: route.settlement.afterOwned } },
      max: plan.applicability.max.status === "not_applicable_current_data"
        ? na(plan.applicability.max) : raw.routes.max,
    },
    persistence: { safeExitCommitted: true, seedReadOnly: true, targetIsolated: true,
      recoveryAvailable: true, restartFreshProcess: true, restartReadbackEqual: true,
      supportedShutdown: true, baselineMoney: persistence.baselineMoney,
      settledMoney: persistence.settledMoney, beforeOwned: persistence.beforeOwned,
      archiveOwned: persistence.archiveOwned, restartOwned: persistence.restartOwned,
      archiveSha256: persistence.archiveSha256, restartSha256: persistence.restartSha256 },
    authorityCounts: { forward: route.forwardCount, reverse: route.reverseCount,
      ordinaryClose: 1, tradePreview: 1, tradeCommit: 1, sale: 0 },
  };
  const evidence = Protocol.createJourneyEvidence({ plan, controls, journey,
    boundaries: raw.boundaries });
  return { route, host, persistence, evidence };
}

function verifyOperationTerminal(raw, runDir, build) {
  const terminal = RunOperationLease.terminalFromArchive(runDir, raw.operationLease);
  return RunOperationLease.validateTerminal(terminal, { runId: raw.runId,
    mode: "live_execution", preparationSha256: build.preparationSha256,
    buildSha256: build.buildSha256 });
}

module.exports = {
  AGENT_RUNTIME_RAW_SCHEMA,
  RAW_SCHEMA,
  assertControlCandidateBinding,
  assertSettlement,
  assertSettlementHostOrder,
  authorityReference,
  closeHostMapping,
  eventMessages,
  materialForwardMapping,
  materialQuantity,
  message,
  parseStructured,
  reverseHostMapping,
  verifyAdmissions,
  verifyAgentRuntimeControls,
  verifyAgentRuntimeRawCandidateJourney,
  verifyControls,
  verifyHostLogs,
  verifyPersistence,
  verifyRawCandidateJourney,
  verifyOperationTerminal,
  verifyTranscript,
};
