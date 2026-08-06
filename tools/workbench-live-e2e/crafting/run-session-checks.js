#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const Recorder = require("./passive-recorder");
const Session = require("./verify-session-evidence");
const SourceContract = require("./source-contract");

const RUN_ID = "crafting-session-fixture-20260803";
const CLONE_SLOT = "cf7_agent_a3_crafting";
const CATEGORY = "武器合成";
const TARGET_JSON = path.resolve(__dirname,
  "../../../saves/cf7_agent_a3_crafting.json");
const FIRST_OWNER = "panel_fixture_first";
const RESTART_OWNER = "panel_fixture_restart";
const HEX = Object.freeze({
  core: "A".repeat(64),
  build: "B".repeat(64),
  closure: "C".repeat(64),
  initialSemantic: "D".repeat(64),
  persistedSemantic: "E".repeat(64),
  persistedFile: "F".repeat(64)
});

function digestBytes(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
}

function digestJson(value) {
  return digestBytes(Buffer.from(JSON.stringify(value), "utf8"));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function outputItem(quantity) {
  return {
    name: "internal.output",
    displayName: "可见产物",
    icon: "asset.output",
    quantity
  };
}

function inventoryItem(quantity) {
  return {
    name: "internal.output",
    displayName: "可见产物",
    icon: "asset.output",
    majorType: "材料",
    use: "",
    actionType: "",
    weaponType: "",
    setId: "",
    setName: "",
    setOrder: 0,
    itemKind: "stack",
    quantity,
    enhancementLevel: 0,
    maxEnhancementLevel: 0,
    isMaxEnhancement: false,
    tierSlotAvailable: false,
    tierSlotUsed: false,
    modSlotCapacity: 0,
    modSlotUsed: 0,
    modSlots: [],
    modMeta: null,
    rarity: ""
  };
}

function inventorySnapshot(containerId, capacity, quantity, snapshotSeq, containerVersion) {
  const slots = [];
  const leasePrefix = containerId === "背包" ? "backpack" : "battlebox";
  for (let index = 0; index < capacity; index += 1) {
    const slot = {
      physicalSlot: index,
      occupied: index === 0 && quantity > 0,
      slotLease: "fixture-" + leasePrefix + "-" + index
    };
    if (slot.occupied) {
      slot.item = inventoryItem(quantity);
      slot.confirmProjection = {
        itemKind: slot.item.itemKind,
        name: slot.item.name,
        displayName: slot.item.displayName,
        quantity: slot.item.quantity,
        enhancementLevel: slot.item.enhancementLevel,
        rarity: slot.item.rarity,
        tier: "",
        modSignature: "",
        lastUpdate: snapshotSeq
      };
    }
    slots.push(slot);
  }
  return {
    containerId,
    capacity,
    accessibleCapacity: capacity,
    viewCapacity: capacity,
    filterKey: "all",
    pageSizeHint: capacity,
    locked: false,
    snapshotSeq,
    containerEpoch: 1,
    containerVersion,
    offset: 0,
    limit: capacity,
    slots,
    filterFacets: [],
    filterItemCount: 0,
    setFacets: [],
    setFilterItemCount: 0
  };
}

function snapshotResponse(owner, callId, money) {
  return {
    type: "panel_resp", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd: "snapshot", callId, success: true,
    v: 1, category: CATEGORY, gender: "男", recipes: [{
      recipeIndex: 7, title: "测试配方", output: outputItem(1)
    }], balance: { money, kpoints: 5 }, skills: {
      reverseLevel: 0, smithEnabled: false, smithLevel: 0
    }, note: "fixture"
  };
}

function previewResponse(owner, callId, money, token) {
  return {
    type: "panel_resp", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd: "preview", callId, success: true,
    v: 1, category: CATEGORY, recipeIndex: 7, craftCount: 1,
    batchEligible: true, maxCraftCount: 2, output: outputItem(1),
    materials: [{
      name: "internal.material",
      displayName: "可见材料",
      icon: "asset.material",
      itemKind: "stack",
      required: 2,
      owned: money === 100 ? 5 : 3,
      maxEnhancement: 0,
      isQuantity: true,
      tier: "",
      consumed: true,
      enough: true
    }],
    cost: { money: 10, kpoints: 0 }, balance: { money, kpoints: 5 },
    skills: { reverseLevel: 0, smithEnabled: false, smithLevel: 0 },
    levelAllowed: true, enoughMaterials: true, enoughMoney: true,
    enoughKpoints: true, enoughSpace: true, canCommit: true,
    blockingError: "", craftToken: token
  };
}

function commitResponse(owner, callId) {
  return {
    type: "panel_resp", domain: "crafting", panel: "crafting",
    panelInstanceId: owner, cmd: "commit", callId, success: true,
    v: 1, operation: "commit", category: CATEGORY, recipeIndex: 7,
    craftCount: 1, crafted: outputItem(1), balance: { money: 90, kpoints: 5 }
  };
}

function inventoryResponse(owner, callId, quantity, nonce) {
  const firstBefore = callId === "inventory.first.before";
  const firstAfter = callId === "inventory.first.after";
  const sequenceBase = firstBefore ? 1 : firstAfter ? 3 : 1;
  const backpackVersion = firstBefore ? 5 : firstAfter ? 6 : 0;
  const battleboxVersion = firstBefore || firstAfter ? 7 : 0;
  return {
    type: "panel_resp", domain: "inventory", panel: "crafting",
    panelInstanceId: owner, cmd: "snapshot", callId, success: true,
    v: 1, sessionNonce: nonce,
    snapshots: [
      inventorySnapshot("背包", 50, quantity, sequenceBase, backpackVersion),
      inventorySnapshot("战备箱", 40, 0, sequenceBase + 1, battleboxVersion)
    ]
  };
}

function craftRequest(owner, callId, cmd, payload) {
  return {
    type: "panel", domain: "crafting", panel: "crafting", cmd,
    panelInstanceId: owner, callId, payload
  };
}

function inventoryRequest(owner, callId) {
  return {
    type: "panel", domain: "inventory", panel: "crafting", cmd: "snapshot",
    panelInstanceId: owner, callId, payload: {
      v: 1,
      requests: [
        { containerId: "背包", offset: 0, limit: 50, filterKey: "all" },
        { containerId: "战备箱", offset: 0, limit: 40, filterKey: "all" }
      ]
    }
  };
}

function openMessage(owner) {
  return {
    type: "panel_cmd", cmd: "open", panel: "crafting", panelInstanceId: owner,
    initData: {
      mode: "runtime", category: CATEGORY, source: "world_crafting_entry",
      debug: false, panelInstanceId: owner
    }
  };
}

function event(sequence, kind, detail) {
  return {
    sequence, kind, epochMs: 1000 + sequence,
    performanceMs: sequence, detail
  };
}

function checkpoint(sequence, label, data) {
  return event(sequence, "observer_checkpoint", { label, data });
}

function bridge(sequence, message) {
  return event(sequence, "bridge_send", {
    message, argCount: 1, completed: true, returned: true, threw: null
  });
}

function host(sequence, message) {
  return event(sequence, "host_message", { message });
}

function click(sequence, selector, workbenchKey) {
  return event(sequence, "capture_click", {
    browserEventIsTrusted: true,
    selector,
    tagName: "button",
    className: selector.includes("recipe")
      ? "crafting-recipe-card craftable" : "crafting-commit-btn",
    text: "fixture",
    disabled: false,
    workbenchKey: workbenchKey || "",
    button: 0,
    detail: 1,
    ctrlKey: false,
    altKey: false,
    shiftKey: false,
    metaKey: false
  });
}

function transcript(pid, events) {
  return {
    schema: Recorder.RECORDER_SCHEMA,
    runId: RUN_ID,
    cloneSlot: CLONE_SLOT,
    processPid: pid,
    recorderId: "session-fixture-" + pid,
    domain: "crafting",
    installedAt: "2026-08-03T00:00:00.000Z",
    startedEpochMs: 1000,
    exportedAt: "2026-08-03T00:00:01.000Z",
    exportCount: 1,
    sequence: events[events.length - 1].sequence,
    bridgePatchCount: 1,
    href: "https://overlay.local/overlay.html",
    origin: "https://overlay.local",
    pathname: "/overlay.html",
    title: "fixture",
    events
  };
}

function ingressLine() {
  return "[XmlSocket:JSON] " + JSON.stringify({
    task: "panel_request", panel: "crafting", source: "world_crafting_entry",
    initData: { category: CATEGORY }
  });
}

function flashLine(domain, fid, request) {
  const prefix = domain === "crafting"
    ? "[CraftingTask] -> Flash: " : "[InventoryTask] -> Flash: ";
  const action = domain === "crafting"
    ? ({ snapshot: "craftingSnapshot", preview: "craftingPreview", commit: "craftingCommit" })[request.cmd]
    : "inventorySnapshot";
  return prefix + JSON.stringify(Object.assign({
    task: "cmd", action, callId: fid
  }, request.payload));
}

function firstJourney() {
  const initialSnapshot = craftRequest(FIRST_OWNER, "craft.first.snapshot", "snapshot", {
    category: CATEGORY, v: 1
  });
  const autoPreview = craftRequest(FIRST_OWNER, "craft.first.auto", "preview", {
    category: CATEGORY, recipeIndex: 7, craftCount: 1, v: 1
  });
  const beforeInventory = inventoryRequest(FIRST_OWNER, "inventory.first.before");
  const selectedPreview = craftRequest(FIRST_OWNER, "craft.first.selected", "preview", {
    category: CATEGORY, recipeIndex: 7, craftCount: 1, v: 1
  });
  const commit = craftRequest(FIRST_OWNER, "craft.first.commit", "commit", {
    category: CATEGORY, expectedCraftToken: "craft.first.selected.token", v: 1
  });
  const freshSnapshot = craftRequest(FIRST_OWNER, "craft.first.fresh", "snapshot", {
    category: CATEGORY, v: 1
  });
  const freshPreview = craftRequest(FIRST_OWNER, "craft.first.freshpreview", "preview", {
    category: CATEGORY, recipeIndex: 7, craftCount: 1, v: 1
  });
  const afterInventory = inventoryRequest(FIRST_OWNER, "inventory.first.after");
  const events = [
    event(1, "recorder_installed", { readyState: "complete", bridgePresent: true }),
    checkpoint(2, "first_ingress_floor", { logFloor: 100 }),
    host(3, openMessage(FIRST_OWNER)),
    bridge(4, initialSnapshot),
    host(5, snapshotResponse(FIRST_OWNER, initialSnapshot.callId, 100)),
    bridge(6, autoPreview),
    host(7, previewResponse(FIRST_OWNER, autoPreview.callId, 100, "craft.first.auto.token")),
    bridge(8, beforeInventory),
    host(9, inventoryResponse(FIRST_OWNER, beforeInventory.callId, 2, "inventory-first")),
    checkpoint(10, "first_interaction_floor", { logFloor: 104 }),
    click(11, '.crafting-catalog-grid .crafting-recipe-card[data-workbench-key="7"]', "7"),
    bridge(12, selectedPreview),
    host(13, previewResponse(FIRST_OWNER, selectedPreview.callId, 100,
      "craft.first.selected.token")),
    click(14, "[data-commit-primary]", ""),
    bridge(15, commit),
    host(16, commitResponse(FIRST_OWNER, commit.callId)),
    bridge(17, freshSnapshot),
    host(18, snapshotResponse(FIRST_OWNER, freshSnapshot.callId, 90)),
    bridge(19, freshPreview),
    host(20, previewResponse(FIRST_OWNER, freshPreview.callId, 90,
      "craft.first.fresh.token")),
    bridge(21, afterInventory),
    host(22, inventoryResponse(FIRST_OWNER, afterInventory.callId, 3,
      "inventory-first")),
    checkpoint(23, "first_tail_seal", { logEnd: 111 })
  ];
  const records = [
    { lineNumber: 101, line: ingressLine() },
    { lineNumber: 102, line: flashLine("crafting", 1, initialSnapshot) },
    { lineNumber: 103, line: flashLine("crafting", 2, autoPreview) },
    { lineNumber: 104, line: flashLine("inventory", 1, beforeInventory) },
    { lineNumber: 105, line: flashLine("crafting", 3, selectedPreview) },
    { lineNumber: 106, line: flashLine("crafting", 4, commit) },
    { lineNumber: 107, line: flashLine("crafting", 5, freshSnapshot) },
    { lineNumber: 108, line: flashLine("crafting", 6, freshPreview) },
    { lineNumber: 109, line: flashLine("inventory", 2, afterInventory) },
    { lineNumber: 110, line: "[ArchiveTask] Shadow saved: cf7_agent_a3_crafting (1234 chars) path="
      + TARGET_JSON },
    { lineNumber: 111, line: "[A3] first terminal quiet seal" }
  ];
  return {
    transcript: transcript(41001, events),
    logs: {
      runId: RUN_ID, cloneSlot: CLONE_SLOT, processPid: 41001,
      floors: {
        startLogFloor: 97,
        ingressSequence: 2, interactionSequence: 10, tailSequence: 23,
        ingressLogFloor: 100, interactionLogFloor: 104, tailLogEnd: 111
      },
      preFloorRecords: [
        { lineNumber: 98, line: "[A3] first runtime ready" },
        { lineNumber: 99, line: "[A3] first recorder attached" },
        { lineNumber: 100, line: "[A3] first ingress floor" }
      ],
      records
    }
  };
}

function restartJourney() {
  const initialSnapshot = craftRequest(RESTART_OWNER, "craft.restart.snapshot", "snapshot", {
    category: CATEGORY, v: 1
  });
  const autoPreview = craftRequest(RESTART_OWNER, "craft.restart.auto", "preview", {
    category: CATEGORY, recipeIndex: 7, craftCount: 1, v: 1
  });
  const selectedPreview = craftRequest(RESTART_OWNER, "craft.restart.selected", "preview", {
    category: CATEGORY, recipeIndex: 7, craftCount: 1, v: 1
  });
  const inventory = inventoryRequest(RESTART_OWNER, "inventory.restart.readback");
  const events = [
    event(1, "recorder_installed", { readyState: "complete", bridgePresent: true }),
    checkpoint(2, "restart_ingress_floor", { logFloor: 200 }),
    host(3, openMessage(RESTART_OWNER)),
    bridge(4, initialSnapshot),
    host(5, snapshotResponse(RESTART_OWNER, initialSnapshot.callId, 90)),
    bridge(6, autoPreview),
    host(7, previewResponse(RESTART_OWNER, autoPreview.callId, 90,
      "craft.restart.auto.token")),
    checkpoint(8, "restart_interaction_floor", { logFloor: 203 }),
    click(9, '.crafting-catalog-grid .crafting-recipe-card[data-workbench-key="7"]', "7"),
    bridge(10, selectedPreview),
    host(11, previewResponse(RESTART_OWNER, selectedPreview.callId, 90,
      "craft.restart.selected.token")),
    bridge(12, inventory),
    host(13, inventoryResponse(RESTART_OWNER, inventory.callId, 3,
      "inventory-restart")),
    checkpoint(14, "restart_tail_seal", { logEnd: 206 })
  ];
  const records = [
    { lineNumber: 201, line: ingressLine() },
    { lineNumber: 202, line: flashLine("crafting", 11, initialSnapshot) },
    { lineNumber: 203, line: flashLine("crafting", 12, autoPreview) },
    { lineNumber: 204, line: flashLine("crafting", 13, selectedPreview) },
    { lineNumber: 205, line: flashLine("inventory", 11, inventory) },
    { lineNumber: 206, line: "[A3] restart terminal quiet seal" }
  ];
  return {
    transcript: transcript(41002, events),
    logs: {
      runId: RUN_ID, cloneSlot: CLONE_SLOT, processPid: 41002,
      floors: {
        startLogFloor: 197,
        ingressSequence: 2, interactionSequence: 8, tailSequence: 14,
        ingressLogFloor: 200, interactionLogFloor: 203, tailLogEnd: 206
      },
      preFloorRecords: [
        { lineNumber: 198, line: "[A3] restart runtime ready" },
        { lineNumber: 199, line: "[A3] restart recorder attached" },
        { lineNumber: 200, line: "[A3] restart ingress floor" }
      ],
      records
    }
  };
}

function runtimeEvidence() {
  const processPath = path.resolve(__dirname,
    "../../../launcher/bin/candidate/CF7Launcher.exe");
  const expectedStable = {
    runtimeMode: "isolated_candidate", processPath,
    coreSha256: HEX.core, buildIdentity: HEX.build, payloadClosure: HEX.closure
  };
  function session(pid, httpPort, cdpPort, startLogFloor) {
    return {
      pid, httpPort, cdpPort, startLogFloor,
      identity: Object.assign({}, expectedStable, { pid, httpPort }),
      portEvidence: {
        launcherPortsBound: true, authenticatedHttpEndpoint: true,
        cdpEndpointObserved: true, httpPort, cdpPort
      }
    };
  }
  return {
    runId: RUN_ID, cloneSlot: CLONE_SLOT, expectedStable,
    first: session(41001, 43101, 44101, 97),
    restart: session(41002, 43102, 44102, 197)
  };
}

function seedInvariant() {
  const files = [
    { kind: "json", path: "slot.json", bytes: 321, sha256: "1".repeat(64) },
    { kind: "sol", path: "slot.sol", bytes: 654, sha256: "2".repeat(64) }
  ];
  const set = {
    slot: "crazyflasher7_saves_seed_a3_crafting",
    files,
    setSha256: digestJson(files)
  };
  return {
    runId: RUN_ID, cloneSlot: CLONE_SLOT,
    before: clone(set), after: clone(set)
  };
}

function sourceFingerprints() {
  const fingerprint = {
    head: "a".repeat(40),
    statusSha256: "3".repeat(64),
    diffSha256: "4".repeat(64),
    untrackedSha256: "5".repeat(64),
    statusEntries: [],
    untrackedFiles: [],
    assets: SourceContract.SOURCE_ASSETS.map((assetPath, index) => ({
      path: assetPath,
      bytes: 100 + index,
      sha256: String((index % 9) + 1).repeat(64)
    }))
  };
  return {
    runId: RUN_ID,
    cloneSlot: CLONE_SLOT,
    records: Session.SOURCE_PHASES.map((phase) => ({
      phase, fingerprint: clone(fingerprint)
    }))
  };
}

function shutdown(pid) {
  return {
    supportedShutdown: true, oldPid: pid, processExited: true,
    launcherPortsFileAbsent: true, credentialAbsent: true,
    cdpPortClosed: true, projectProcesses: []
  };
}

function persistenceEvidence(firstLogs) {
  const archive = firstLogs.records.find((record) => record.lineNumber === 110);
  return {
    runId: RUN_ID,
    cloneSlot: CLONE_SLOT,
    lock: {
      targetSlot: CLONE_SLOT, ownerRunId: RUN_ID,
      path: path.resolve(__dirname, "../../../saves/cf7_agent_a3_crafting.live-e2e.lock"),
      exclusive: true, acquired: true, acquireMode: "create_new",
      contentionProbeRejected: true, released: true,
      heldThroughFinalShutdown: true
    },
    clonePreparation: {
      seedSlot: "crazyflasher7_saves_seed_a3_crafting", targetSlot: CLONE_SLOT,
      seedSetSha256: seedInvariant().before.setSha256,
      seedJsonSha256: "1".repeat(64),
      seedSemanticSha256: HEX.initialSemantic,
      seededTargetSha256: "4".repeat(64)
    },
    initialBaseline: {
      semanticSha256: HEX.initialSemantic, sha256: "4".repeat(64), role: "fixture", level: 27
    },
    archive: {
      slot: CLONE_SLOT, status: "archived", lineNumber: archive.lineNumber,
      targetPath: TARGET_JSON, archiveChars: 1234,
      lineSha256: digestBytes(Buffer.from(archive.line, "utf8"))
    },
    persisted: {
      semanticSha256: HEX.persistedSemantic, sha256: HEX.persistedFile,
      role: "fixture", level: 27, textChars: 1234
    },
    restartBaseline: {
      semanticSha256: HEX.persistedSemantic, sha256: HEX.persistedFile,
      role: "fixture", level: 27
    },
    firstShutdown: shutdown(41001),
    finalShutdown: shutdown(41002)
  };
}

const CONTROL_STEPS = Object.freeze([
  ["first_ingress", "first"],
  ["first_inventory_before", "first"],
  ["first_recipe_select", "first"],
  ["first_commit", "first"],
  ["first_inventory_after", "first"],
  ["first_safeexit", "first"],
  ["restart_ingress", "restart"],
  ["restart_recipe_select", "restart"],
  ["restart_inventory_readback", "restart"]
]);

function controlEvidence(provider) {
  const selected = provider || "launcher_agent_computer_use";
  return {
    runId: RUN_ID,
    cloneSlot: CLONE_SLOT,
    providerSelection: {
      primary: "launcher_agent_computer_use",
      selected,
      launcherProbe: selected === "launcher_agent_computer_use"
        ? { available: true, authenticated: true }
        : { available: false, authenticated: false, reason: "capability_unavailable" },
      codexProbe: selected === "codex_computer_use"
        ? { available: true, authenticated: true } : null,
      fallbackAuthorized: selected === "codex_computer_use"
    },
    transport: {
      provenance: selected,
      captureFileSha256: "5".repeat(64),
      capturedAtEpochMs: 2000,
      expiresAtEpochMs: 32000
    },
    steps: CONTROL_STEPS.map(([step, phase], index) => {
      const requestId = "control-" + (index + 1);
      const pid = phase === "first" ? 41001 : 41002;
      const request = {
        requestId, step, runId: RUN_ID, cloneSlot: CLONE_SLOT,
        pid, requestedAtEpochMs: 3000 + index * 100
      };
      const ack = {
        requestId, step, runId: RUN_ID, cloneSlot: CLONE_SLOT,
        pid, success: true, ackedAtEpochMs: request.requestedAtEpochMs + 20,
        transportProvenance: selected,
        captureSha256: String(index + 6).slice(-1).repeat(64)
      };
      if (step === "first_ingress") ack.hostLogLine = 101;
      if (step === "restart_ingress") ack.hostLogLine = 201;
      if (step === "first_inventory_before") Object.assign(ack, {
        webCallId: "inventory.first.before", as2CallId: 1, hostLogLine: 104
      });
      if (step === "first_recipe_select") Object.assign(ack, {
        browserEventSequence: 11, webCallId: "craft.first.selected",
        as2CallId: 3, hostLogLine: 105
      });
      if (step === "first_commit") Object.assign(ack, {
        browserEventSequence: 14, webCallId: "craft.first.commit",
        as2CallId: 4, hostLogLine: 106
      });
      if (step === "first_inventory_after") Object.assign(ack, {
        webCallId: "inventory.first.after", as2CallId: 2, hostLogLine: 109
      });
      if (step === "restart_recipe_select") Object.assign(ack, {
        browserEventSequence: 9, webCallId: "craft.restart.selected",
        as2CallId: 13, hostLogLine: 204
      });
      if (step === "restart_inventory_readback") Object.assign(ack, {
        webCallId: "inventory.restart.readback", as2CallId: 11, hostLogLine: 205
      });
      if (step === "first_safeexit") ack.archiveLine = 110;
      return { step, request, ack };
    })
  };
}

function controlError(code, message, details) {
  const error = new Error(message);
  error.code = code;
  error.details = details || null;
  throw error;
}

function fixtureControlVerifier(control, context) {
  if (!control || control.runId !== context.runId || control.cloneSlot !== context.cloneSlot) {
    controlError("control_cross_binding_invalid", "control run/clone binding drifted");
  }
  const selection = control.providerSelection || {};
  const launcher = selection.launcherProbe || {};
  const codex = selection.codexProbe || {};
  const launcherSelected = selection.selected === "launcher_agent_computer_use"
    && launcher.available === true && launcher.authenticated === true
    && selection.fallbackAuthorized === false;
  const codexSelected = selection.selected === "codex_computer_use"
    && launcher.available === false && launcher.reason === "capability_unavailable"
    && codex.available === true && codex.authenticated === true
    && selection.fallbackAuthorized === true;
  if (!launcherSelected && !codexSelected) {
    controlError("control_provider_selection_invalid",
      "primary/fallback capability decision is not independently reproducible");
  }
  const transport = control.transport || {};
  if (transport.provenance !== selection.selected
      || !/^[A-F0-9]{64}$/.test(String(transport.captureFileSha256 || ""))
      || !Number.isInteger(transport.capturedAtEpochMs)
      || !Number.isInteger(transport.expiresAtEpochMs)
      || transport.expiresAtEpochMs - transport.capturedAtEpochMs > 30000) {
    controlError("control_transport_invalid", "transport provenance/TTL/capture digest failed");
  }
  if (!Array.isArray(control.steps)) {
    controlError("control_steps_invalid", "control steps are missing");
  }
  const actualNames = control.steps.map((entry) => entry.step);
  const expectedNames = CONTROL_STEPS.map((entry) => entry[0]);
  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    const safeExitMissing = !actualNames.includes("first_safeexit");
    controlError(safeExitMissing ? "control_safeexit_ack_missing" : "control_steps_invalid",
      "control step coverage/order drifted", { expectedNames, actualNames });
  }
  control.steps.forEach((entry) => {
    const request = entry.request || {};
    const ack = entry.ack || {};
    if (request.requestId !== ack.requestId || request.step !== entry.step
        || ack.step !== entry.step || request.runId !== context.runId
        || ack.runId !== context.runId || request.cloneSlot !== context.cloneSlot
        || ack.cloneSlot !== context.cloneSlot || request.pid !== ack.pid
        || ack.success !== true || ack.ackedAtEpochMs < request.requestedAtEpochMs
        || ack.ackedAtEpochMs > control.transport.expiresAtEpochMs
        || ack.transportProvenance !== selection.selected
        || !/^[A-F0-9]{64}$/.test(String(ack.captureSha256 || ""))) {
      controlError("control_request_ack_invalid", "request/ack/TTL/capture binding failed", entry);
    }
  });
  const byName = Object.fromEntries(control.steps.map((entry) => [entry.step, entry.ack]));
  function binds(ack, mapping) {
    return ack.webCallId === mapping.webCallId
      && ack.as2CallId === mapping.as2CallId
      && ack.hostLogLine === mapping.hostLogLine;
  }
  const exact = [
    byName.first_ingress.hostLogLine === context.firstIngressLogLine,
    byName.restart_ingress.hostLogLine === context.restartIngressLogLine,
    byName.first_recipe_select.browserEventSequence === context.firstRecipeClickSequence,
    byName.first_commit.browserEventSequence === context.firstCommitClickSequence,
    byName.restart_recipe_select.browserEventSequence === context.restartRecipeClickSequence,
    binds(byName.first_inventory_before, context.firstInventoryBefore),
    binds(byName.first_recipe_select, context.firstSelectedPreview),
    binds(byName.first_commit, context.firstCommit),
    binds(byName.first_inventory_after, context.firstInventoryAfter),
    binds(byName.restart_recipe_select, context.restartSelectedPreview),
    binds(byName.restart_inventory_readback, context.restartInventory),
    byName.first_safeexit.archiveLine === context.archiveLine,
    control.steps.filter((entry) => entry.request.pid === context.firstPid).length === 6,
    control.steps.filter((entry) => entry.request.pid === context.restartPid).length === 3
  ];
  if (exact.some((value) => value !== true)) {
    controlError("control_authority_binding_invalid",
      "control acks did not bind ingress/click/archive/process evidence");
  }
  return {
    verified: true,
    provider: selection.selected,
    ackCount: control.steps.length,
    browserEventAcksVerified: true,
    safeExitAcksVerified: true,
    transportProvenanceVerified: true,
    captureDigestsVerified: true,
    ttlVerified: true,
    fallbackPolicyVerified: true
  };
}

function makeArtifacts(provider) {
  const first = firstJourney();
  const restart = restartJourney();
  return {
    firstTranscript: first.transcript,
    firstLogs: first.logs,
    restartTranscript: restart.transcript,
    restartLogs: restart.logs,
    runtime: runtimeEvidence(),
    persistence: persistenceEvidence(first.logs),
    sourceFingerprints: sourceFingerprints(),
    seedInvariant: seedInvariant(),
    control: controlEvidence(provider)
  };
}

function makeBundle(artifacts) {
  return {
    schema: Session.SESSION_SCHEMA,
    runId: RUN_ID,
    cloneSlot: CLONE_SLOT,
    deploymentStatus: "NOT_DEPLOYED",
    artifactManifest: Session.RAW_ROLES.map((role) => {
      const bytes = Buffer.from(JSON.stringify(artifacts[role]), "utf8");
      return {
        role,
        path: role + ".json",
        bytes: bytes.length,
        sha256: digestBytes(bytes)
      };
    })
  };
}

function verify(artifacts, controlVerifier) {
  return Session.verifySessionEvidence(makeBundle(artifacts), {
    artifacts,
    testOnlyAllowInjectedArtifacts: true,
    controlVerifier: controlVerifier || fixtureControlVerifier
  });
}

function expectFailure(label, mutate, code, counters, options) {
  const artifacts = makeArtifacts();
  let bundle = null;
  if (mutate) mutate(artifacts);
  bundle = makeBundle(artifacts);
  if (options && typeof options.mutateBundle === "function") options.mutateBundle(bundle);
  let caught = null;
  try {
    const verifyOptions = {
      artifacts,
      controlVerifier: options && Object.prototype.hasOwnProperty.call(options, "controlVerifier")
        ? options.controlVerifier : fixtureControlVerifier
    };
    if (!options || options.allowInjectedArtifacts !== false) {
      verifyOptions.testOnlyAllowInjectedArtifacts = true;
    }
    Session.verifySessionEvidence(bundle, verifyOptions);
  } catch (error) { caught = error; }
  if (!caught || caught.code !== code) {
    throw new Error(label + " expected " + code + ", got "
      + (caught ? caught.code + ": " + caught.message : "PASS"));
  }
  counters.negative += 1;
}

function replaceFirstTailInventoryWithCommit(artifacts) {
  const request = craftRequest(FIRST_OWNER, "craft.first.extra", "commit", {
    category: CATEGORY, expectedCraftToken: "craft.first.fresh.token", v: 1
  });
  artifacts.firstTranscript.events.find((entry) => entry.sequence === 21).detail.message = request;
  artifacts.firstTranscript.events.find((entry) => entry.sequence === 22).detail.message
    = commitResponse(FIRST_OWNER, request.callId);
  artifacts.firstLogs.records.find((record) => record.lineNumber === 109).line
    = flashLine("crafting", 7, request);
}

function replaceRestartInventoryWithCommit(artifacts) {
  const request = craftRequest(RESTART_OWNER, "craft.restart.extra", "commit", {
    category: CATEGORY, expectedCraftToken: "craft.restart.selected.token", v: 1
  });
  artifacts.restartTranscript.events.find((entry) => entry.sequence === 12).detail.message = request;
  artifacts.restartTranscript.events.find((entry) => entry.sequence === 13).detail.message
    = commitResponse(RESTART_OWNER, request.callId);
  artifacts.restartLogs.records.find((record) => record.lineNumber === 205).line
    = flashLine("crafting", 14, request);
}

function runChecks(options) {
  const counters = { positive: 0, negative: 0, mechanical: 0 };

  const primary = verify(makeArtifacts("launcher_agent_computer_use"));
  if (primary.status !== "e2e_verified" || primary.first.inventoryCounts.delta !== 1
      || primary.restart.inventoryCount !== 3 || primary.first.exactCallMappings !== 8
      || primary.restart.exactCallMappings !== 4 || primary.control.ackCount !== 9) {
    throw new Error("positive Launcher-control session fixture did not close all gates");
  }
  counters.positive += 1;

  const fallback = verify(makeArtifacts("codex_computer_use"));
  if (fallback.control.provider !== "codex_computer_use") {
    throw new Error("verifiable Codex computer-use fallback fixture did not close");
  }
  counters.positive += 1;

  const diskArtifacts = makeArtifacts("launcher_agent_computer_use");
  const diskBundle = makeBundle(diskArtifacts);
  const diskDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "crafting-session-check-"));
  try {
    Session.RAW_ROLES.forEach((role) => {
      fs.writeFileSync(path.join(diskDirectory, role + ".json"),
        JSON.stringify(diskArtifacts[role]), { flag: "wx" });
    });
    const diskResult = Session.verifySessionEvidence(diskBundle, {
      baseDirectory: diskDirectory,
      controlVerifier: fixtureControlVerifier
    });
    if (diskResult.status !== "e2e_verified") {
      throw new Error("on-disk raw artifact manifest did not verify");
    }
  } finally {
    fs.rmSync(diskDirectory, { recursive: true, force: false });
  }
  counters.positive += 1;

  expectFailure("runtime PID reuse", (a) => {
    a.runtime.restart.pid = a.runtime.first.pid;
    a.runtime.restart.identity.pid = a.runtime.first.pid;
    a.restartTranscript.processPid = a.runtime.first.pid;
    a.restartLogs.processPid = a.runtime.first.pid;
  }, "runtime_pid_reused", counters);
  expectFailure("stable runtime drift", (a) => {
    a.runtime.restart.identity.coreSha256 = "9".repeat(64);
  }, "runtime_stable_identity_drift", counters);
  expectFailure("runtime port drift", (a) => {
    a.runtime.restart.portEvidence.cdpPort += 1;
  }, "runtime_port_evidence_invalid", counters);
  expectFailure("untrusted browser commit", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 14)
      .detail.browserEventIsTrusted = false;
  }, "untrusted_business_click", counters);
  expectFailure("missing Host fid", (a) => {
    a.firstLogs.records.find((record) => record.lineNumber === 102).line = "[A3] missing fid";
  }, "host_fid_count_invalid", counters);
  expectFailure("extra Host fid", (a) => {
    const request = craftRequest(FIRST_OWNER, "craft.host.extra", "snapshot", {
      category: CATEGORY, v: 1
    });
    a.firstLogs.records.find((record) => record.lineNumber === 111).line
      = flashLine("crafting", 99, request);
  }, "host_fid_count_invalid", counters);
  expectFailure("wrong Web owner", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 4)
      .detail.message.panelInstanceId = "panel_wrong";
  }, "request_envelope_invalid", counters);
  expectFailure("wrong Host domain order", (a) => {
    const left = a.firstLogs.records.find((record) => record.lineNumber === 103);
    const right = a.firstLogs.records.find((record) => record.lineNumber === 104);
    const temporary = left.line; left.line = right.line; right.line = temporary;
  }, "host_fid_order_invalid", counters);
  expectFailure("business traffic before ingress floor", (a) => {
    a.firstTranscript.events[0] = bridge(1,
      craftRequest(FIRST_OWNER, "craft.prefloor", "snapshot", { category: CATEGORY, v: 1 }));
  }, "business_before_ingress_floor", counters);
  expectFailure("Host business traffic before ingress floor", (a) => {
    const request = craftRequest(FIRST_OWNER, "craft.prefloor.host", "snapshot", {
      category: CATEGORY, v: 1
    });
    a.firstLogs.preFloorRecords[1].line = flashLine("crafting", 88, request);
  }, "business_before_ingress_log_floor", counters);
  expectFailure("AS2 ingress outside double floor", (a) => {
    a.firstLogs.records.find((record) => record.lineNumber === 101).line = "[A3] hidden ingress";
    a.firstLogs.records.find((record) => record.lineNumber === 110).line = ingressLine();
  }, "ingress_floor_order_invalid", counters);
  expectFailure("initial snapshot preview order drift", (a) => {
    const events = a.firstTranscript.events;
    const requestA = events.find((entry) => entry.sequence === 4).detail.message;
    const requestB = events.find((entry) => entry.sequence === 6).detail.message;
    const responseA = events.find((entry) => entry.sequence === 5).detail.message;
    const responseB = events.find((entry) => entry.sequence === 7).detail.message;
    events.find((entry) => entry.sequence === 4).detail.message = requestB;
    events.find((entry) => entry.sequence === 6).detail.message = requestA;
    events.find((entry) => entry.sequence === 5).detail.message = responseB;
    events.find((entry) => entry.sequence === 7).detail.message = responseA;
    const logA = a.firstLogs.records.find((record) => record.lineNumber === 102);
    const logB = a.firstLogs.records.find((record) => record.lineNumber === 103);
    const line = logA.line; logA.line = logB.line; logB.line = line;
  }, "initial_authority_order_invalid", counters);
  expectFailure("initial category escaped production ingress", (a) => {
    [4, 6].forEach((sequence) => {
      a.firstTranscript.events.find((entry) => entry.sequence === sequence)
        .detail.message.payload.category = "饰品合成";
    });
    [5, 7].forEach((sequence) => {
      a.firstTranscript.events.find((entry) => entry.sequence === sequence)
        .detail.message.category = "饰品合成";
    });
    [102, 103].forEach((lineNumber) => {
      const record = a.firstLogs.records.find((entry) => entry.lineNumber === lineNumber);
      record.line = record.line.replace("武器合成", "饰品合成");
    });
  }, "initial_category_drift", counters);
  expectFailure("commit authority chain order drift", (a) => {
    const events = a.firstTranscript.events;
    const requestA = events.find((entry) => entry.sequence === 17).detail.message;
    const requestB = events.find((entry) => entry.sequence === 19).detail.message;
    const responseA = events.find((entry) => entry.sequence === 18).detail.message;
    const responseB = events.find((entry) => entry.sequence === 20).detail.message;
    events.find((entry) => entry.sequence === 17).detail.message = requestB;
    events.find((entry) => entry.sequence === 19).detail.message = requestA;
    events.find((entry) => entry.sequence === 18).detail.message = responseB;
    events.find((entry) => entry.sequence === 20).detail.message = responseA;
    const logA = a.firstLogs.records.find((record) => record.lineNumber === 107);
    const logB = a.firstLogs.records.find((record) => record.lineNumber === 108);
    const line = logA.line; logA.line = logB.line; logB.line = line;
  }, "commit_authority_order_invalid", counters);
  expectFailure("fresh preview output identity drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 20)
      .detail.message.output.displayName = "错误产物";
  }, "crafted_identity_drift", counters);
  expectFailure("fresh snapshot recipe identity drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 18)
      .detail.message.recipes[0].output.icon = "asset.wrong";
  }, "fresh_recipe_identity_mismatch", counters);
  expectFailure("fresh balance drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 18)
      .detail.message.balance.money = 91;
  }, "balance_poststate_mismatch", counters);
  expectFailure("fresh material delta drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 20)
      .detail.message.materials[0].owned = 4;
  }, "stack_material_delta_mismatch", counters);
  expectFailure("production preview material identity malformed", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 13)
      .detail.message.materials[0].icon = "undefined";
  }, "production_response_rejected", counters);
  expectFailure("consumed preview token reused", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 20)
      .detail.message.craftToken = "craft.first.selected.token";
  }, "fresh_preview_token_reused", counters);

  expectFailure("first Web tail write", replaceFirstTailInventoryWithCommit,
    "tail_write_detected", counters);
  expectFailure("first Host-only tail write", (a) => {
    const request = craftRequest(FIRST_OWNER, "craft.host.write", "commit", {
      category: CATEGORY, expectedCraftToken: "craft.first.fresh.token", v: 1
    });
    a.firstLogs.records.find((record) => record.lineNumber === 111).line
      = flashLine("crafting", 98, request);
  }, "tail_write_detected", counters);
  expectFailure("restart Web tail write", replaceRestartInventoryWithCommit,
    "tail_write_detected", counters);
  expectFailure("restart Host-only tail write", (a) => {
    const request = craftRequest(RESTART_OWNER, "craft.restart.hostwrite", "commit", {
      category: CATEGORY, expectedCraftToken: "craft.restart.selected.token", v: 1
    });
    a.restartLogs.records.find((record) => record.lineNumber === 206).line
      = flashLine("crafting", 98, request);
  }, "tail_write_detected", counters);

  expectFailure("zero observable Inventory delta", (a) => {
    const slot = a.firstTranscript.events.find((entry) => entry.sequence === 22)
      .detail.message.snapshots[0].slots[0];
    slot.item.quantity = 2;
    slot.confirmProjection.quantity = 2;
  }, "inventory_output_delta_invalid", counters);
  expectFailure("Inventory identity drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 22)
      .detail.message.snapshots[0].slots[0].item.icon = "asset.wrong";
  }, "inventory_output_identity_mismatch", counters);
  expectFailure("restart Inventory mismatch", (a) => {
    const slot = a.restartTranscript.events.find((entry) => entry.sequence === 13)
      .detail.message.snapshots[0].slots[0];
    slot.item.quantity = 2;
    slot.confirmProjection.quantity = 2;
  }, "restart_inventory_mismatch", counters);
  expectFailure("first process Inventory nonce drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 22)
      .detail.message.sessionNonce = "inventory-wrong";
  }, "inventory_session_nonce_drift", counters);
  expectFailure("post-commit Inventory snapshot sequence stale", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 22)
      .detail.message.snapshots[0].snapshotSeq = 1;
  }, "inventory_freshness_invalid", counters);
  expectFailure("post-commit backpack version stale", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 22)
      .detail.message.snapshots[0].containerVersion = 5;
  }, "inventory_freshness_invalid", counters);
  expectFailure("restart Inventory nonce reuse", (a) => {
    a.restartTranscript.events.find((entry) => entry.sequence === 13)
      .detail.message.sessionNonce = "inventory-first";
  }, "restart_inventory_nonce_reused", counters);
  expectFailure("restart owner reuse", (a) => {
    a.restartTranscript.events.forEach((entry) => {
      const message = entry.detail && entry.detail.message;
      if (!message || typeof message !== "object") return;
      if (message.panelInstanceId === RESTART_OWNER) message.panelInstanceId = FIRST_OWNER;
      if (message.initData && message.initData.panelInstanceId === RESTART_OWNER) {
        message.initData.panelInstanceId = FIRST_OWNER;
      }
    });
  }, "restart_owner_reused", counters);
  expectFailure("invalid production Inventory projection", (a) => {
    delete a.firstTranscript.events.find((entry) => entry.sequence === 9)
      .detail.message.snapshots[0].slots[0].slotLease;
  }, "inventory_snapshot_projection_invalid", counters);
  expectFailure("Inventory response window drift", (a) => {
    a.firstTranscript.events.find((entry) => entry.sequence === 9)
      .detail.message.snapshots[0].pageSizeHint = 49;
  }, "inventory_snapshot_window_mismatch", counters);
  expectFailure("seed JSON drift", (a) => {
    a.seedInvariant.after.files[0].sha256 = "6".repeat(64);
    a.seedInvariant.after.setSha256 = digestJson(a.seedInvariant.after.files);
  }, "seed_source_changed", counters);
  expectFailure("seed SOL set drift", (a) => {
    a.seedInvariant.after.files.push({
      kind: "sol", path: "zz.sol", bytes: 1, sha256: "7".repeat(64)
    });
    a.seedInvariant.after.setSha256 = digestJson(a.seedInvariant.after.files);
  }, "seed_source_changed", counters);
  expectFailure("development overlay origin", (a) => {
    Object.assign(a.firstTranscript, {
      href: "http://127.0.0.1:8080/harness.html",
      origin: "http://127.0.0.1:8080", pathname: "/harness.html"
    });
  }, "transcript_invalid", counters);
  expectFailure("clone lock not acquired", (a) => {
    a.persistence.lock.acquired = false;
  }, "persistence_evidence_invalid", counters);
  expectFailure("clone seed set binding drift", (a) => {
    a.persistence.clonePreparation.seedSetSha256 = "0".repeat(64);
  }, "clone_archive_readback_invalid", counters);
  expectFailure("seeded target baseline hash drift", (a) => {
    a.persistence.clonePreparation.seededTargetSha256 = "0".repeat(64);
  }, "clone_archive_readback_invalid", counters);
  expectFailure("missing persisted role", (a) => {
    delete a.persistence.initialBaseline.role;
    delete a.persistence.persisted.role;
    delete a.persistence.restartBaseline.role;
  }, "clone_archive_readback_invalid", counters);
  expectFailure("persisted level type coercion", (a) => {
    a.persistence.persisted.level = "27";
  }, "clone_archive_readback_invalid", counters);
  expectFailure("final source fingerprint drift", (a) => {
    a.sourceFingerprints.records[a.sourceFingerprints.records.length - 1]
      .fingerprint.statusSha256 = "8".repeat(64);
  }, "source_fingerprint_drift", counters);
  expectFailure("source asset closure incomplete", (a) => {
    a.sourceFingerprints.records.forEach((record) => record.fingerprint.assets.pop());
  }, "source_fingerprint_shape_invalid", counters);
  expectFailure("artifact digest drift", null, "artifact_digest_mismatch", counters, {
    mutateBundle(bundle) { bundle.artifactManifest[0].sha256 = "0".repeat(64); }
  });
  expectFailure("artifact path traversal", null, "artifact_path_invalid", counters, {
    mutateBundle(bundle) { bundle.artifactManifest[0].path = "../escape.json"; }
  });
  expectFailure("artifact path reused across roles", null,
    "artifact_manifest_path_reused", counters, {
      mutateBundle(bundle) { bundle.artifactManifest[1].path = bundle.artifactManifest[0].path; }
    });
  expectFailure("implicit artifact injection", null, "artifact_injection_forbidden", counters, {
    allowInjectedArtifacts: false
  });
  expectFailure("archive outside terminal seal", (a) => {
    const record = a.firstLogs.records.find((entry) => entry.lineNumber === 111);
    a.persistence.archive.lineNumber = 111;
    a.persistence.archive.lineSha256 = digestBytes(Buffer.from(record.line, "utf8"));
  }, "clone_archive_readback_invalid", counters);
  expectFailure("restart save hash mismatch", (a) => {
    a.persistence.restartBaseline.sha256 = "0".repeat(64);
  }, "clone_archive_readback_invalid", counters);
  expectFailure("shutdown residue", (a) => {
    a.persistence.finalShutdown.projectProcesses = ["CF7Launcher"];
  }, "shutdown_residue_invalid", counters);
  expectFailure("raw artifact run binding drift", (a) => {
    a.firstTranscript.runId = "wrong-run-id";
  }, "session_cross_binding_invalid", counters);
  expectFailure("process artifact binding drift", (a) => {
    a.restartLogs.processPid += 10;
  }, "session_process_binding_invalid", counters);
  expectFailure("boolean control placeholder", (a) => {
    a.control.verified = true;
  }, "control_verifier_unavailable", counters, { controlVerifier: null });
  expectFailure("SAFEEXIT ack missing", (a) => {
    a.control.steps = a.control.steps.filter((entry) => entry.step !== "first_safeexit");
  }, "control_safeexit_ack_missing", counters);
  expectFailure("control capture digest drift", (a) => {
    a.control.steps[0].ack.captureSha256 = "bad";
  }, "control_request_ack_invalid", counters);
  expectFailure("control authority mapping drift", (a) => {
    a.control.steps.find((entry) => entry.step === "first_commit").ack.as2CallId = 999;
  }, "control_authority_binding_invalid", counters);
  expectFailure("control TTL drift", (a) => {
    a.control.transport.expiresAtEpochMs = 999999;
  }, "control_transport_invalid", counters);
  expectFailure("incomplete artifact role set", null, "artifact_manifest_invalid", counters, {
    mutateBundle(bundle) { bundle.artifactManifest.pop(); }
  });

  counters.mechanical += 1;
  const result = {
    ok: true,
    schema: "crafting-production-session-checks.v2",
    counters,
    total: counters.positive + counters.negative + counters.mechanical
  };
  if (!options || options.silent !== true) console.log(JSON.stringify(result, null, 2));
  return result;
}

function supersededEntry() {
  const error = new Error("SUPERSEDED / NOT_ADMITTED: use crafting/self-test.js only");
  error.code = "superseded_not_admitted";
  throw error;
}

module.exports = {
  fixtureControlVerifier,
  makeArtifacts,
  makeBundle,
  runChecks: supersededEntry
};

if (require.main === module) {
  process.stderr.write("SUPERSEDED / NOT_ADMITTED: use crafting/self-test.js only.\n");
  process.exitCode = 2;
}
