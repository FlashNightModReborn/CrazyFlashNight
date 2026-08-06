#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const {
  BUNDLE_SCHEMA,
  LIVE_SLOT_RE,
  NpcJourneyError,
  assertSafeSlot,
  atomicWriteJson,
  buildArtifactManifest,
  canonicalJson,
  deepClone,
  fail,
  isPlainObject,
  sha256File,
  sha256Text,
  sealEvidenceOrigin,
  sealTrustedTimeline,
  sleep,
  timestampId,
} = require("./common");
const { ControlChannel } = require("./control-channel");
const { TranscriptWriter, attachPassiveRecorder } = require("./passive-recorder");
const ProductionClosure = require("./production-closure");
const {
  assertInventorySnapshotSurface,
  inboundMessages,
  inventoryWindows,
  openCommands,
  outboundMessages,
  panelRequests,
  panelResponses,
  requestsFor,
  responseFor,
} = require("./protocol");
const { artifactRolesForBundle, finalizePreSealVerification,
  verifyBundlePreSeal } = require("./verify-evidence");
const { loadSharedAdapter } = require("./shared-adapter");

const ROOT = path.resolve(__dirname, "..", "..", "..");
const DEFAULT_SEED_SLOT = "cf7_agent_a3_kshop";
const DEFAULT_TARGET_SLOT = "cf7_agent_a3_npc_run";

function usage(message) {
  const error = new Error(message);
  error.code = "usage";
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = {
    seedSlot: DEFAULT_SEED_SLOT,
    slot: DEFAULT_TARGET_SLOT,
    readyTimeoutMs: 120000,
    evidenceTimeoutMs: 90000,
    controlTimeoutMs: 300000,
    pollMs: 250,
    saleQuantity: 1,
    allowIsolatedCommit: false,
    allowCodexCuFallback: false,
  };
  const booleans = new Set(["allowReadOnlyLiveSeed", "purchaseOnly", "allowIsolatedCommit",
    "allowCodexCuFallback", "help", "check"]);
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) usage("unexpected argument " + token);
    const key = token.slice(2).replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
    if (booleans.has(key)) { args[key] = true; continue; }
    if (index + 1 >= argv.length) usage("missing value for " + token);
    args[key] = argv[++index];
  }
  return args;
}

function validateArgs(args) {
  if (args.help || args.check) return args;
  if (!args.candidateRoot || !path.isAbsolute(String(args.candidateRoot))) {
    usage("--candidate-root is required and must be absolute");
  }
  args.candidateRoot = path.resolve(args.candidateRoot);
  assertSafeSlot(args.slot);
  if (!/^cf7_agent_[A-Za-z0-9_-]+$/.test(String(args.seedSlot || ""))
      && !(LIVE_SLOT_RE.test(String(args.seedSlot || "")) && args.allowReadOnlyLiveSeed)) {
    usage("--seed-slot must be cf7_agent_* (or an explicitly read-only live seed)");
  }
  if (args.seedSlot === args.slot) usage("seed and target slot must differ");
  if (!args.allowIsolatedCommit) usage("--allow-isolated-commit is required for bounded NPC writes");
  if (!args.allowCodexCuFallback) usage("--allow-codex-cu-fallback is required when Launcher Agent admission is unavailable");
  if (!args.purchaseOnly) {
    if (args.saleSlot != null) args.saleSlot = Number(args.saleSlot);
    args.saleQuantity = Number(args.saleQuantity);
    if ((args.saleSlot != null && (!Number.isInteger(args.saleSlot) || args.saleSlot < 0 || args.saleSlot > 49))
        || args.saleQuantity !== 1
        || (args.expectedSaleItem != null && !String(args.expectedSaleItem).trim())) {
      usage("optional sale constraint must be one exact 背包 slot/name and --sale-quantity 1");
    }
    if (args.expectedSalePreQuantity != null) {
      args.expectedSalePreQuantity = Number(args.expectedSalePreQuantity);
      if (!Number.isInteger(args.expectedSalePreQuantity) || args.expectedSalePreQuantity < 1) {
        usage("--expected-sale-pre-quantity must be a positive integer");
      }
    }
    if (args.expectedPurchaseItem != null
        && String(args.expectedPurchaseItem) === String(args.expectedSaleItem)) {
      usage("purchase and sale evidence must use different item names");
    }
  }
  ["readyTimeoutMs", "evidenceTimeoutMs", "controlTimeoutMs", "pollMs"].forEach((key) => {
    args[key] = Number(args[key]);
    if (!Number.isInteger(args[key]) || args[key] < 50 || args[key] > 600000) usage("invalid --" + key);
  });
  return args;
}

function printHelp() {
  process.stdout.write([
    "NPC Shop isolated two-process production journey (shared FROZEN-v2/GO)",
    "",
    "Full A3:",
    "  node tools/workbench-live-e2e/npc/run-live-journey.js --candidate-root <absolute> \\",
    "    --seed-slot cf7_agent_a3_kshop --slot cf7_agent_a3_npc_run \\",
    "    --allow-isolated-commit --allow-codex-cu-fallback",
    "",
    "Optional exact sale constraints: --sale-slot 0 --expected-sale-item 砍刀 --expected-sale-pre-quantity 1",
    "",
    "--purchase-only is diagnostic and never sets a3NpcClosable=true.",
  ].join("\n") + "\n");
}

function exactRunDir(slot) {
  const base = path.join(ROOT, "tmp", "workbench-live-e2e", "npc");
  fs.mkdirSync(base, { recursive: true });
  const runDir = path.join(base, timestampId() + "-" + slot);
  fs.mkdirSync(runDir);
  return runDir;
}

function publicError(error) {
  return {
    code: error && error.code || "npc_live_failed",
    phase: error && error.phase || "unknown",
    message: error && error.message || String(error),
    details: error && error.details || null,
    manualRecoveryRequired: !!(error && error.details && error.details.manualRecoveryRequired),
  };
}

function messageEntries(writer) {
  const outbound = outboundMessages(writer.events);
  const inbound = inboundMessages(writer.events);
  return { outbound, inbound, requests: panelRequests(outbound), responses: panelResponses(inbound) };
}

async function waitFor(label, args, predicate) {
  const deadline = Date.now() + args.evidenceTimeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    last = predicate();
    if (last) return last;
    await sleep(args.pollMs);
  }
  fail("evidence_timeout", label, "timed out waiting for " + label, { last });
}

async function waitOpen(writer, afterSequence, args, excluded) {
  return waitFor("npc_panel_open", args, () => {
    const opens = openCommands(inboundMessages(writer.events));
    return opens.find((entry) => entry.event.sequence > afterSequence
      && !(excluded || []).includes(entry.message.panelInstanceId)) || null;
  });
}

async function waitPair(writer, panelInstanceId, cmd, domain, afterSequence, args, occurrence) {
  return waitFor(domain + ":" + cmd, args, () => {
    const entries = messageEntries(writer);
    const requests = requestsFor(entries.requests, panelInstanceId, cmd, domain)
      .filter((entry) => entry.event.sequence > afterSequence);
    const request = requests[Number(occurrence || 0)];
    if (!request) return null;
    const matches = entries.responses.filter((entry) => entry.event.sequence > request.event.sequence
      && entry.message.panelInstanceId === panelInstanceId
      && entry.message.domain === domain && entry.message.cmd === cmd
      && entry.message.callId === request.message.callId);
    return matches.length === 1 ? { request, response: matches[0] } : null;
  });
}

async function waitInventorySurface(writer, panelInstanceId, afterSequence, args, phase) {
  const first = await waitPair(writer, panelInstanceId, "snapshot", "inventory",
    afterSequence, args, 0);
  ensureSuccess(first, phase);
  const battle = first.response.message.snapshots.find((snapshot) => snapshot.containerId === "战备箱");
  const accessible = Number(battle && battle.accessibleCapacity);
  const expectedPairs = accessible > 200 ? 3 : accessible > 100 ? 2 : 1;
  const pairs = [first];
  for (let ordinal = 1; ordinal < expectedPairs; ordinal += 1) {
    const pair = await waitPair(writer, panelInstanceId, "snapshot", "inventory",
      afterSequence, args, ordinal);
    ensureSuccess(pair, phase);
    pairs.push(pair);
  }
  return assertInventorySnapshotSurface(pairs, phase);
}

function ensureSuccess(pair, phase) {
  if (!pair || !pair.response || pair.response.message.success !== true) {
    fail("authority_response_failed", phase, "authoritative request failed", {
      response: pair && pair.response && pair.response.message,
    });
  }
  return pair.response.message;
}

function selectPurchaseTarget(snapshot, args) {
  const catalog = Array.isArray(snapshot.catalog) ? snapshot.catalog : [];
  let candidates = catalog.filter((entry) => entry && entry.locked === false
    && Number.isInteger(Number(entry.catalogIndex)) && Number(entry.maxQuantity) >= 1
    && Number.isFinite(Number(entry.unitPrice)) && Number(entry.unitPrice) > 0
    && Number(entry.unitPrice) <= Number(snapshot.balance)
    && typeof entry.itemName === "string" && entry.itemName
    && typeof entry.displayName === "string" && entry.displayName
    && typeof entry.icon === "string" && entry.icon
    && ["武器", "防具"].includes(entry.majorType));
  if (args.purchaseCatalogIndex != null) {
    const expected = Number(args.purchaseCatalogIndex);
    candidates = candidates.filter((entry) => Number(entry.catalogIndex) === expected);
  }
  if (args.expectedPurchaseItem) {
    candidates = candidates.filter((entry) => entry.itemName === args.expectedPurchaseItem);
  }
  if (!args.purchaseOnly && args.expectedSaleItem) {
    candidates = candidates.filter((entry) => entry.itemName !== args.expectedSaleItem);
  }
  candidates.sort((left, right) => Number(left.unitPrice) - Number(right.unitPrice)
    || Number(left.catalogIndex) - Number(right.catalogIndex));
  if (!candidates.length) {
    fail("safe_purchase_target_missing", "purchase", "no unlocked affordable exact catalog target is available");
  }
  const selected = candidates[0];
  return {
    catalogIndex: Number(selected.catalogIndex),
    itemName: selected.itemName,
    displayName: selected.displayName,
    icon: selected.icon,
    basePrice: Number(selected.basePrice),
    unitPrice: Number(selected.unitPrice),
    buyMultiplier: Number(snapshot.buyMultiplier),
    maxQuantity: Number(selected.maxQuantity),
    itemKind: "equipment",
    destinationView: "bag",
    quantity: 1,
  };
}

function selectSaleTarget(inventoryMessage, purchasePolicy, args) {
  const bag = inventoryWindows(inventoryMessage, "sale_selector").get("背包");
  if (!bag) fail("safe_sale_target_missing", "sale", "fresh post-purchase 背包 snapshot is absent");
  const safe = bag.slots.filter((slot) => slot && slot.occupied && slot.item
    && slot.item.name !== purchasePolicy.itemName && Number(slot.item.quantity) >= 1
    && !(slot.item.itemKind === "equipment"
      && (Number(slot.item.enhancementLevel || 0) > 1 || slot.item.tierSlotUsed === true
        || Number(slot.item.modSlotUsed || 0) > 0)));
  const exact = safe.filter((slot) => (args.saleSlot == null || slot.physicalSlot === args.saleSlot)
    && (args.expectedSaleItem == null || slot.item.name === args.expectedSaleItem)
    && (args.expectedSalePreQuantity == null
      || Number(slot.item.quantity) === Number(args.expectedSalePreQuantity)));
  let selected = exact.find((slot) => slot.physicalSlot === 0 && slot.item.name === "砍刀"
    && Number(slot.item.quantity) === 1);
  if (!selected) {
    const uniqueNames = new Map();
    exact.forEach((slot) => uniqueNames.set(slot.item.name,
      (uniqueNames.get(slot.item.name) || 0) + 1));
    const candidates = exact.filter((slot) => uniqueNames.get(slot.item.name) === 1)
      .sort((left, right) => left.physicalSlot - right.physicalSlot);
    selected = candidates[0];
  }
  if (!selected || !selected.slotLease) {
    fail("safe_sale_target_missing", "sale",
      "no unique plain lease-bound bag item satisfies the optional sale constraints");
  }
  return { explicitAllowlist: true, containerId: "背包", slot: selected.physicalSlot,
    expectedItem: selected.item.name, expectedPreQuantity: Number(selected.item.quantity),
    expectedLease: selected.slotLease, quantity: 1,
    requiresQuantityAdjustment: Number(selected.item.quantity) > 1 };
}

function eventBinding(entry, role) {
  return { sequence: entry.event.sequence, eventHash: entry.event.eventHash, role };
}

function relative(runDir, filePath) {
  return path.relative(runDir, filePath).replace(/\\/g, "/");
}

function controlRequestOutputRecord(step, request) {
  return {
    type: "control_request",
    step,
    requestId: request.requestId,
    requestPath: request.requestPath,
    expiresAt: request.expiresAt,
  };
}

async function controlStep(state, step, options) {
  const settings = options || {};
  const prefix = state.writer.prefix();
  const request = state.channel.issue(step, {
    actionClass: settings.actionClass || "business",
    allowedTransports: settings.allowedTransports,
    ttlMs: state.args.controlTimeoutMs,
    transcriptPrefix: prefix,
    instruction: settings.instruction,
    expected: settings.expected,
  });
  atomicWriteJson(path.join(state.runDir, "status.json"), {
    schema: "workbench-live-e2e.npc.status.v1",
    state: "waiting_control",
    step,
    requestId: request.requestId,
    requestPath: request.requestPath,
    expiresAt: request.expiresAt,
  });
  process.stdout.write(JSON.stringify(controlRequestOutputRecord(step, request)) + "\n");
  const ack = await state.channel.wait(request, state.args.pollMs);
  if (settings.acceptResults && !settings.acceptResults.includes(ack.result)) {
    fail("control_result_invalid", "control", "control result cannot continue the journey", { step, result: ack.result });
  }
  const evidence = settings.collect ? await settings.collect(prefix.eventCount) : [];
  if (!settings.skipObserverHealth) await state.observer.health();
  state.controls.push({
    step,
    requestId: request.requestId,
    requestArtifact: relative(state.runDir, request.requestPath),
    ackArtifact: relative(state.runDir, ack.ackPath),
    events: evidence,
  });
  return { request, ack, evidence };
}

function findDom(writer, afterSequence, predicate) {
  const matches = writer.events.filter((event) => event.sequence > afterSequence
    && event.kind === "dom_input" && predicate(event));
  return matches.length === 1 ? { event: matches[0] } : null;
}

async function openPanel(state, step, excluded, instruction) {
  const result = await controlStep(state, step, {
    allowedTransports: [state.selectedTransport],
    acceptResults: ["completed"],
    instruction,
    collect: async (after) => {
      const open = await waitOpen(state.writer, after, state.args, excluded);
      return [eventBinding(open, "panel_open")];
    },
  });
  const sequence = result.evidence[0].sequence;
  return openCommands(inboundMessages(state.writer.events)).find((entry) => entry.event.sequence === sequence);
}

async function waitInitialAuthority(state, open) {
  const id = open.message.panelInstanceId;
  const inventory = await waitInventorySurface(state.writer, id, open.event.sequence,
    state.args, "inventory_snapshot");
  const snapshot = await waitPair(state.writer, id, "snapshot", "npcshop", open.event.sequence, state.args, 0);
  ensureSuccess(snapshot, "npc_snapshot");
  if (inventory.firstPair.request.event.sequence >= snapshot.request.event.sequence) {
    fail("initial_request_order_invalid", "snapshot",
      "production NPC open must request Inventory authority before NPC authority");
  }
  return { id, snapshot, inventory };
}

function inputTarget(event, name) {
  return event && event.target && event.target.attributes ? event.target.attributes[name] : undefined;
}

async function selectPurchase(state, panel, policy) {
  await controlStep(state, "select_purchase", {
    allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
    instruction: "在 NPC 商店商品栏点击唯一 catalogIndex=" + policy.catalogIndex
      + "、显示名“" + policy.displayName + "”的卡片；不要打开开发工具或调用内部 API。",
    expected: policy,
    collect: async (after) => {
      const input = await waitFor("purchase_card_input", state.args, () => findDom(state.writer, after,
        (event) => event.eventType === "click"
          && event.isTrusted === true && event.target && event.target.tagName === "ARTICLE"
          && event.target.selector === "article[data-workbench-key=\"" + policy.catalogIndex + "\"]"
          && String(inputTarget(event, "data-workbench-key")) === String(policy.catalogIndex)
          && String(event.target && event.target.text || "").includes(policy.displayName)));
      return [eventBinding(input, "dom_input")];
    },
  });
}

async function openSettlement(state, step, panelId, priorPreviewCount) {
  let pair;
  await controlStep(state, step, {
    allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
    instruction: "点击 NPC 商店顶部“结算”按钮，等待权威交易预览完整显示。",
    collect: async (after) => {
      const input = await waitFor("settlement_input", state.args, () => findDom(state.writer, after,
        (event) => event.eventType === "click" && event.isTrusted === true
          && event.target && event.target.tagName === "BUTTON"
          && event.target.selector === "button.npcshop-checkout-btn"));
      pair = await waitPair(state.writer, panelId, "tradePreview", "npcshop", after,
        state.args, Number(priorPreviewCount || 0));
      ensureSuccess(pair, "trade_preview");
      return [eventBinding(input, "domain_request"), eventBinding(pair.request, "domain_request")];
    },
  });
  return pair;
}

async function commitTrade(state, step, panelId, afterSequence) {
  let pair;
  await controlStep(state, step, {
    allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
    instruction: "核对结算页后点击“确认交易”一次；不得连点，不得通过脚本发送消息。",
    collect: async (after) => {
      const input = await waitFor("trade_commit_input", state.args, () => findDom(state.writer, after,
        (event) => event.eventType === "click" && event.isTrusted === true
          && event.target && event.target.tagName === "BUTTON"
          && event.target.selector === "button[data-trade-commit]"
          && Object.prototype.hasOwnProperty.call(
          event.target && event.target.attributes || {}, "data-trade-commit")));
      pair = await waitPair(state.writer, panelId, "tradeCommit", "npcshop",
        Math.max(after, afterSequence || 0), state.args, 0);
      ensureSuccess(pair, "trade_commit");
      return [eventBinding(input, "domain_write"), eventBinding(pair.request, "domain_write")];
    },
  });
  return pair;
}

async function closePanel(state, step, panelId) {
  let closeEntry;
  await controlStep(state, step, {
    allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
    instruction: "点击 NPC 商店右上角关闭按钮一次，等待面板完全关闭。",
    collect: async (after) => {
      const input = await waitFor("panel_close_input", state.args, () => findDom(state.writer, after,
        (event) => event.eventType === "click" && event.isTrusted === true
          && event.target && event.target.tagName === "BUTTON"
          && event.target.selector === "button[aria-label=\"关闭 NPC 商店\"]"
          && inputTarget(event, "aria-label") === "关闭 NPC 商店"));
      closeEntry = await waitFor("panel_close_request", state.args, () => {
        const requests = panelRequests(outboundMessages(state.writer.events));
        return requests.find((entry) => entry.event.sequence > after
          && entry.message.panelInstanceId === panelId && entry.message.cmd === "close") || null;
      });
      return [eventBinding(input, "panel_close"), eventBinding(closeEntry, "panel_close")];
    },
  });
  return closeEntry;
}

async function selectSale(state, panel, policy) {
  await controlStep(state, "select_sale", {
    allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
    instruction: "在右侧背包点击 physicalSlot=" + policy.slot + "、物品“" + policy.expectedItem
      + "”的唯一卡片；不得点击同名其他槽。",
    expected: policy,
    collect: async (after) => {
      const input = await waitFor("sale_slot_input", state.args, () => findDom(state.writer, after,
        (event) => event.eventType === "click"
          && event.isTrusted === true && event.target && event.target.tagName === "ARTICLE"
          && event.target.selector === "article[data-workbench-key=\"" + policy.slot + "\"]"
          && String(inputTarget(event, "data-workbench-key")) === String(policy.slot)
          && String(event.target && event.target.text || "").includes(policy.expectedItem)));
      return [eventBinding(input, "dom_input")];
    },
  });
}

async function setSaleQuantity(state, panelId, priorPreviewCount) {
  let pair;
  await controlStep(state, "set_sale_quantity", {
    allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
    instruction: "在出售行数量控件中把数量精确改为 1，等待新的权威预览；不要点击同名全售。",
    collect: async (after) => {
      const input = await waitFor("sale_quantity_input", state.args, () => findDom(state.writer, after,
        (event) => event.eventType === "input"
          && event.isTrusted === true && event.target && event.target.tagName === "INPUT"
          && event.target.selector === "input.workbench-quantity-number"
          && String(inputTarget(event, "aria-label") || "").includes("数量")));
      pair = await waitPair(state.writer, panelId, "tradePreview", "npcshop", after,
        state.args, Number(priorPreviewCount || 0));
      ensureSuccess(pair, "sale_final_preview");
      return [eventBinding(input, "domain_request"), eventBinding(pair.request, "domain_request")];
    },
  });
  return pair;
}

function addArtifact(manifest, runDir, filePath, role) {
  const resolved = path.resolve(filePath);
  const relativePath = relative(runDir, resolved);
  const stat = fs.lstatSync(resolved);
  if (!stat.isFile() || stat.isSymbolicLink()) fail("artifact_invalid", "finalize", "evidence artifact is not a plain file");
  manifest.push({ path: relativePath, role, bytes: stat.size, sha256: sha256File(resolved) });
  return relativePath;
}

async function execute(args, adapterOverride, lifecycle) {
  const productionClosure = ProductionClosure.captureProductionClosure(ROOT);
  const runDir = exactRunDir(args.slot);
  const runId = "npc." + path.basename(runDir).replace(/[^A-Za-z0-9._~-]/g, ".");
  const diagnosticPath = path.join(runDir, "diagnostic.json");
  const adapter = adapterOverride || loadSharedAdapter(ROOT);
  const writer = new TranscriptWriter(runDir);
  const state = { args, runDir, runId, writer, controls: [], selectedTransport: null,
    channel: new ControlChannel(ROOT, runDir, runId), observer: null };
  let session = null;
  let sessionReleased = false;
  let commitMayHaveReachedAuthority = false;
  try {
    session = await adapter.prepare({ root: ROOT, runDir, runId,
      candidateRoot: args.candidateRoot, seedSlot: args.seedSlot, slot: args.slot,
      allowReadOnlyLiveSeed: args.allowReadOnlyLiveSeed === true });
    const candidateProducer = ProductionClosure.captureCandidateProducerBinding(
      args.candidateRoot, session.candidate.stableIdentity, productionClosure);
    const productionBinding = ProductionClosure.bindProductionClosure(
      productionClosure, session.candidate.stableIdentity, runId, candidateProducer);
    if (lifecycle) lifecycle.checkpoint("clone_prepared");
    const first = await session.start("first", { readyTimeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
    state.observer = await attachPassiveRecorder({ root: ROOT, runDir, writer,
      cdpBinding: first.cdpBinding, runtimeIdentity: first.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });

    const capability = await controlStep(state, "capability_probe", {
      actionClass: "capability_probe", allowedTransports: ["launcher_agent_runtime"],
      acceptResults: ["completed", "unavailable"],
      instruction: "探测 Launcher Agent Runtime 是否暴露 NPC/Flash/WebView 的可见输入能力；不可用时给出 reason-code 和截图。",
      collect: async () => [],
    });
    if (capability.ack.result === "completed") state.selectedTransport = "launcher_agent_runtime";
    else {
      const authorization = await controlStep(state, "authorize_codex_fallback", {
        actionClass: "authorization", allowedTransports: ["codex_computer_use"],
        acceptResults: ["completed"],
        instruction: "确认 Launcher Agent 缺少 NPC 输入能力，显式授权本次运行改用 Codex computer-use；回执必须引用 capability request/reason。",
        collect: async () => [],
      });
      const capabilityDetails = capability.ack.providerEvidence
        && capability.ack.providerEvidence.details;
      const authorizationDetails = authorization.ack.providerEvidence
        && authorization.ack.providerEvidence.details;
      if (!capabilityDetails || !authorizationDetails
          || authorizationDetails.capabilityRequestId !== capability.request.requestId
          || authorizationDetails.capabilityReasonCode !== capabilityDetails.reasonCode
          || authorizationDetails.explicitAuthorization !== true) {
        fail("fallback_authorization_invalid", "control", "fallback authorization does not bind capability failure");
      }
      state.selectedTransport = "codex_computer_use";
    }

    const excluded = [];
    const initialOpen = await openPanel(state, "open_first", excluded,
      "通过真实 NPC 对话/联系人入口打开物品商店；禁止 /console、Panels.open、Bridge.send 或内部 opener。");
    excluded.push(initialOpen.message.panelInstanceId);
    const initial = await waitInitialAuthority(state, initialOpen);
    const shopId = initialOpen.message.initData && initialOpen.message.initData.shopId;
    if (!shopId || initial.snapshot.response.message.shopId !== shopId) {
      fail("shop_owner_mismatch", "snapshot", "panel initData shopId differs from authority snapshot");
    }
    const actualShopBinding = ProductionClosure.bindActualShop(
      ROOT, productionClosure, shopId);
    let firstLoadedProduction = null;
    const purchasePolicy = selectPurchaseTarget(initial.snapshot.response.message, args);
    await selectPurchase(state, initial, purchasePolicy);
    const purchasePreview = await openSettlement(state, "open_purchase_settlement", initial.id, 0);
    const purchaseLine = purchasePreview.response.message.purchaseLines;
    if (!Array.isArray(purchaseLine) || purchaseLine.length !== 1
        || !Array.isArray(purchasePreview.response.message.saleLines)
        || purchasePreview.response.message.saleLines.length !== 0
        || purchaseLine[0].destinationView !== "bag" || purchaseLine[0].quantity !== 1
        || purchasePreview.response.message.canCommit !== true) {
      fail("purchase_preview_not_safe", "purchase", "selected purchase is not an exact one-unit bag acquisition");
    }
    commitMayHaveReachedAuthority = true;
    const purchaseCommit = await commitTrade(state, "commit_purchase", initial.id,
      purchasePreview.response.event.sequence);
    const purchasePostInventory = await waitInventorySurface(writer, initial.id,
      purchaseCommit.response.event.sequence, args, "purchase_post_inventory");

    let salePolicy = null;
    let salePreviews = [];
    let saleCommit = null;
    let salePostInventory = null;
    if (!args.purchaseOnly) {
      salePolicy = selectSaleTarget(purchasePostInventory, purchasePolicy, args);
      await selectSale(state, initial, salePolicy);
      salePreviews.push(await openSettlement(state, "open_sale_settlement", initial.id, 0));
      if (salePolicy.requiresQuantityAdjustment) {
        salePreviews.push(await setSaleQuantity(state, initial.id, 0));
      }
      const finalPreview = salePreviews.at(-1).response.message;
      const saleLine = finalPreview.saleLines;
      if (!Array.isArray(finalPreview.purchaseLines) || finalPreview.purchaseLines.length !== 0
          || !Array.isArray(saleLine) || saleLine.length !== 1 || saleLine[0].sourceIdentity !== "bag:" + salePolicy.slot
          || saleLine[0].quantity !== 1 || saleLine[0].matchedCount !== 1
          || saleLine[0].eligibleCount !== 1 || saleLine[0].protectedCount !== 0
          || finalPreview.canCommit !== true) {
        fail("sale_preview_not_safe", "sale", "final preview did not prove exact one-unit eligible/protected sale");
      }
      saleCommit = await commitTrade(state, "commit_sale", initial.id,
        salePreviews.at(-1).response.event.sequence);
      salePostInventory = await waitInventorySurface(writer, initial.id,
        saleCommit.response.event.sequence, args, "sale_post_inventory");
    }
    await closePanel(state, "close_before_exit", initial.id);
    await session.awaitExactClose("first", initial.id, {
      timeoutMs: args.evidenceTimeoutMs, pollMs: args.pollMs,
    });
    await state.observer.sealPageHooksForFinalCapture();
    firstLoadedProduction = await state.observer.captureProductionClosure(
      productionClosure, productionBinding, "first", runId);
    await state.observer.detach();

    const safeExitControl = await controlStep(state, "safe_exit", {
      actionClass: "lifecycle",
      skipObserverHealth: true,
      allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
      instruction: "点击 Launcher 原生 SAFEEXIT 一次，等待存档状态完成；此时不要确认退出。",
      collect: async () => [],
    });
    const safeExitProviderBoundary = await session.captureHostBoundary(
      "first", "safe_exit_provider_completed");
    const archive = await session.awaitArchive("first", {
      lastCommitResponseSequence: saleCommit
        ? saleCommit.response.event.sequence : purchaseCommit.response.event.sequence,
      timeoutMs: args.evidenceTimeoutMs,
      pollMs: args.pollMs,
    });
    await controlStep(state, "exit_confirm", {
      actionClass: "lifecycle",
      skipObserverHealth: true,
      allowedTransports: [state.selectedTransport], acceptResults: ["completed"],
      instruction: "仅在存档状态完成后点击 Launcher 原生 EXIT_CONFIRM 一次，等待首进程退出。",
      collect: async () => [],
    });
    await session.awaitExit("first", { timeoutMs: args.evidenceTimeoutMs, pollMs: args.pollMs });
    if (lifecycle) lifecycle.checkpoint("first_captured");
    const restart = await session.start("restart", { readyTimeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
    state.observer = await attachPassiveRecorder({ root: ROOT, runDir, writer,
      cdpBinding: restart.cdpBinding, runtimeIdentity: restart.identity,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
    const restartOpen = await openPanel(state, "open_restart_readback", excluded,
      "在 fresh PID 上通过真实 NPC 入口打开同一商店，只读核对最终持久化状态。禁止内部 opener。");
    excluded.push(restartOpen.message.panelInstanceId);
    const restartAuthority = await waitInitialAuthority(state, restartOpen);
    let restartLoadedProduction = null;
    await closePanel(state, "close_restart_readback", restartAuthority.id);
    await session.awaitExactClose("restart", restartAuthority.id, {
      timeoutMs: args.evidenceTimeoutMs, pollMs: args.pollMs,
    });
    await state.observer.sealPageHooksForFinalCapture();
    restartLoadedProduction = await state.observer.captureProductionClosure(
      productionClosure, productionBinding, "restart", runId);
    await state.observer.detach();
    const shutdownResult = await session.shutdownFinal("restart", {
      timeoutMs: args.evidenceTimeoutMs, pollMs: args.pollMs,
    });
    const runtimeResidue = await session.verifyResidue({ expectCloneLockHeld: true });
    const seedAfter = await session.captureSeedInvariant("after");
    const cloneAfter = await session.captureCloneAfterRestart();
    const hostSlice = await session.captureHostLog();
    const postRestartProductionClosure = ProductionClosure.captureProductionClosure(ROOT);
    ProductionClosure.sameProductionTree(productionClosure, postRestartProductionClosure);
    const candidateEvidence = deepClone(session.candidate);
    const cloneEvidence = deepClone(session.clone);
    const releaseEvidence = await session.release({
      afterResidueCheckedAt: runtimeResidue && runtimeResidue.checkedAt,
    });
    sessionReleased = true;
    if (lifecycle) lifecycle.checkpoint("restart_captured");
    if (!releaseEvidence || releaseEvidence.cloneLockReleased !== true
        || !Number.isFinite(Date.parse(releaseEvidence.releasedAt))
        || !runtimeResidue || !Number.isFinite(Date.parse(runtimeResidue.checkedAt))
        || Date.parse(releaseEvidence.releasedAt) < Date.parse(runtimeResidue.checkedAt)) {
      fail("clone_release_evidence_invalid", "residue",
        "clone lock release must be proven after the post-restart runtime residue check");
    }
    const residue = Object.assign({}, runtimeResidue, {
      cloneLockReleased: true,
      cloneLockReleasedAt: releaseEvidence.releasedAt,
    });
    delete residue.evidenceSha256;
    residue.evidenceSha256 = sha256Text(canonicalJson(residue));
    const hostLogPath = path.join(runDir, "host-log.json");
    atomicWriteJson(hostLogPath, hostSlice);
    const seedBeforePath = path.join(runDir, "seed-before.json");
    const seedAfterPath = path.join(runDir, "seed-after.json");
    const archiveDiskPath = path.join(runDir, "clone-after-archive.json");
    const restartDiskPath = path.join(runDir, "clone-after-restart.json");
    const shutdownResponsePath = path.join(runDir, "supported-shutdown-response.json");
    atomicWriteJson(seedBeforePath, session.seedBefore);
    atomicWriteJson(seedAfterPath, seedAfter);
    atomicWriteJson(archiveDiskPath, cloneEvidence.afterArchiveManifest);
    atomicWriteJson(restartDiskPath, cloneAfter.manifest);
    atomicWriteJson(shutdownResponsePath, shutdownResult.response);
    writer.flush({ detachedAt: new Date().toISOString() });

    const transcriptArtifact = relative(runDir, writer.summaryPath);
    const hostLogArtifact = relative(runDir, hostLogPath);
    const seedBeforeArtifact = relative(runDir, seedBeforePath);
    const seedAfterArtifact = relative(runDir, seedAfterPath);
    const afterArchiveArtifact = relative(runDir, archiveDiskPath);
    const afterRestartArtifact = relative(runDir, restartDiskPath);
    const shutdownResponseArtifact = relative(runDir, shutdownResponsePath);
    function controlIdentity(step) {
      const binding = state.controls.find((entry) => entry.step === step);
      const ack = JSON.parse(fs.readFileSync(path.join(runDir, binding.ackArtifact), "utf8"));
      const provider = JSON.parse(fs.readFileSync(path.join(runDir,
        ack.providerReceipt.artifact), "utf8"));
      return { requestId: binding.requestId, providerOperationId: provider.providerOperationId };
    }
    const safeExitIdentity = controlIdentity("safe_exit");
    const exitConfirmIdentity = controlIdentity("exit_confirm");
    const inventoryEvents = [
      ["initial", initial.inventory],
      ["purchase-post", purchasePostInventory],
    ].concat(salePostInventory ? [["sale-post", salePostInventory]] : [], [
      ["restart", restartAuthority.inventory],
    ]).flatMap(([phase, surface]) => surface.pairs.map((pair, pairOrdinal) => ({
      phase,
      pairOrdinal,
      callId: pair.request.message.callId,
      requestAt: pair.request.event.observedAt,
      responseAt: pair.response.event.observedAt,
    })));
    const trustedTimeline = sealTrustedTimeline({
      runId,
      transcriptSha256: sha256File(path.join(runDir, transcriptArtifact)),
      hostLogSha256: sha256File(path.join(runDir, hostLogArtifact)),
      safeExitRequestId: safeExitIdentity.requestId,
      safeExitProviderOperationId: safeExitIdentity.providerOperationId,
      exitConfirmRequestId: exitConfirmIdentity.requestId,
      exitConfirmProviderOperationId: exitConfirmIdentity.providerOperationId,
      safeExitProviderBoundarySha256: sha256Text(canonicalJson(safeExitProviderBoundary)),
      archiveHostLine: archive.hostLine,
      shutdownSha256: shutdownResult.shutdown.evidenceSha256,
      residueSha256: residue.evidenceSha256,
      inventoryEvents,
    });
    const calls = {
      initialNpcSnapshot: initial.snapshot.request.message.callId,
      initialInventorySnapshots: initial.inventory.callIds.slice(),
      initialInventorySnapshot: initial.inventory.callIds[0],
      purchasePreview: purchasePreview.request.message.callId,
      purchaseCommit: purchaseCommit.request.message.callId,
      purchasePostInventories: purchasePostInventory.callIds.slice(),
      purchasePostInventory: purchasePostInventory.callIds[0],
      salePreviews: salePreviews.map((pair) => pair.request.message.callId),
      saleCommit: saleCommit && saleCommit.request.message.callId,
      salePostInventories: salePostInventory ? salePostInventory.callIds.slice() : [],
      salePostInventory: salePostInventory && salePostInventory.callIds[0],
      restartNpcSnapshot: restartAuthority.snapshot.request.message.callId,
      restartInventorySnapshots: restartAuthority.inventory.callIds.slice(),
      restartInventorySnapshot: restartAuthority.inventory.callIds[0],
    };
    const bundle = {
      schema: BUNDLE_SCHEMA,
      evidenceMode: "live_capture",
      runId,
      root: ROOT,
      runDir,
      candidateRoot: args.candidateRoot,
      slot: args.slot,
      shopId,
      journeyMode: args.purchaseOnly ? "purchase_only" : "purchase_then_explicit_sale",
      artifactManifest: null,
      transcriptArtifact,
      hostLogArtifact,
      controls: state.controls,
      instances: { first: initial.id, restart: restartAuthority.id },
      calls,
      purchasePolicy,
      salePolicy,
      candidate: candidateEvidence,
      clone: Object.assign({}, cloneEvidence, {
        slot: args.slot,
        seedBeforeArtifact,
        seedAfterArtifact,
        afterArchiveArtifact,
        afterRestartArtifact,
        afterRestartJsonSha256: cloneAfter.jsonSha256,
        afterRestartArtifactSetSha256: cloneAfter.artifactSetSha256,
        afterRestartSolSetSha256: cloneAfter.solSetSha256,
        lockReleasedAfterResidue: true,
        lockReleasedAt: releaseEvidence.releasedAt,
      }),
      productionClosure,
      postRestartProductionClosure,
      candidateProducer,
      productionBinding,
      actualShopBinding,
      runtime: {
        first: Object.assign({}, first.publicEvidence, { loadedProduction: firstLoadedProduction }),
        restart: Object.assign({}, restart.publicEvidence, { loadedProduction: restartLoadedProduction }),
      },
      archive,
      shutdown: shutdownResult.shutdown,
      shutdownResponseArtifact,
      timelineBoundaries: { safeExitProviderBoundary },
      trustedTimeline,
      safeExitUiJourneyVerified: true,
      exitMethod: "native_safe_exit",
      residue,
      moduleJournal: null,
    };
    return { runDir, prepare(moduleManifest) {
      if (bundle.moduleJournal !== null) {
        fail("preseal_verification_reused", "module_journal",
          "NPC live evidence may be prepared exactly once");
      }
      bundle.moduleJournal = { manifest: moduleManifest, artifact: null };
      const fullScopeEligible = bundle.journeyMode === "purchase_then_explicit_sale";
      bundle.evidenceOrigin = sealEvidenceOrigin({
        origin: "bootstrap_live_capture",
        profile: fullScopeEligible ? "npc_a3_full_live_v1" : "npc_a3_purchase_diagnostic_v1",
        evidenceMode: "live_capture",
        runId: bundle.runId,
        root: ROOT,
        journeyMode: bundle.journeyMode,
        fullScopeEligible,
        requiredPhases: ["domain_loaded", "clone_prepared", "first_captured",
          "restart_captured", "verification_executed", "terminal"],
        sourceGenerator: "tools/workbench-live-e2e/npc/bootstrap.js",
        moduleManifestSha256: moduleManifest.manifestSha256,
        moduleJournalSha256: null,
      });
      bundle.artifactManifest = buildArtifactManifest(runDir, runId,
        artifactRolesForBundle(bundle));
      const preSealVerification = verifyBundlePreSeal(bundle, runDir);
      let completed = false;
      return { complete(moduleArtifact) {
        if (completed) {
          fail("sealed_finalization_reused", "module_journal",
            "sealed NPC finalization is one-shot");
        }
        completed = true;
        bundle.moduleJournal.artifact = moduleArtifact;
        const originFields = deepClone(bundle.evidenceOrigin);
        delete originFields.schema;
        delete originFields.evidenceSha256;
        originFields.moduleJournalSha256 = moduleArtifact.evidenceSha256;
        bundle.evidenceOrigin = sealEvidenceOrigin(originFields);
        const bundlePath = path.join(runDir, "evidence-bundle.json");
        atomicWriteJson(bundlePath, bundle);
        atomicWriteJson(path.join(runDir, "artifact-manifest.json"), bundle.artifactManifest);
        const receipt = finalizePreSealVerification(bundle, runDir, preSealVerification);
        receipt.deployment = "NOT_DEPLOYED";
        delete receipt.receiptSha256;
        receipt.receiptSha256 = sha256Text(canonicalJson(receipt));
        const receiptPath = path.join(runDir, "receipt.json");
        atomicWriteJson(receiptPath, receipt);
        atomicWriteJson(path.join(runDir, "status.json"), {
          schema: "workbench-live-e2e.npc.status.v1", state: "verified",
          receiptPath, scopeComplete: receipt.scopeComplete,
        });
        return { bundlePath, receiptPath, receipt };
      } };
    } };
  } catch (error) {
    const diagnostic = { schema: "workbench-live-e2e.npc.diagnostic.v1",
      runId, failedAt: new Date().toISOString(), error: publicError(error),
      transcript: writer.snapshot(), controls: state.controls };
    atomicWriteJson(diagnosticPath, diagnostic);
    if (!sessionReleased && session && typeof session.cleanupFailure === "function") {
      try { await session.cleanupFailure({ commitMayHaveReachedAuthority }); } catch (_cleanupError) {}
    }
    throw error;
  }
}

async function main(argv, lifecycle) {
  const args = validateArgs(parseArgs(argv));
  if (args.help) { printHelp(); return { help: true }; }
  if (args.check) return { ok: true, schema: BUNDLE_SCHEMA,
    sharedAdmission: "FROZEN-v2_GO", consumerAdmission: "OFFLINE_VERIFIED",
    liveAdmission: "LIVE_BLOCKED", fixedEntry: "tools/workbench-live-e2e/npc/bootstrap.js" };
  return execute(args, null, lifecycle);
}

module.exports = {
  controlRequestOutputRecord,
  execute,
  main,
  parseArgs,
  selectPurchaseTarget,
  selectSaleTarget,
  validateArgs,
};

if (require.main === module) {
  process.stderr.write("run-live-journey.js is Superseded / NOT_ADMITTED; use npc/bootstrap.js\n");
  process.exitCode = 2;
}
