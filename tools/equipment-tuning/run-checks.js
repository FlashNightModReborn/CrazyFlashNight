#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const runner = require("./run-unattended");

const root = path.resolve(__dirname, "../..");
const runnerPath = path.join(__dirname, "run-unattended.js");
const checksPath = path.join(__dirname, "run-checks.js");
const agentEntryContractPath = path.join(root, "tools", "test-agent-entry-contract.js");

function runNode(args, label) {
  const result = childProcess.spawnSync(process.execPath, args, {
    cwd: root,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    throw new Error(label + " failed with exit code " + result.status);
  }
  return result.stdout || "";
}

function expectRejected(label, callback, expectedCode) {
  let error = null;
  try {
    callback();
  } catch (caught) {
    error = caught;
  }
  if (!error) throw new Error(label + " was not rejected");
  if (expectedCode && error.code !== expectedCode) {
    throw new Error(label + " returned " + error.code + ", expected " + expectedCode);
  }
}

function checkSyntaxAndSelfCheck() {
  runNode(["--check", runnerPath], "run-unattended.js syntax");
  runNode(["--check", checksPath], "run-checks.js syntax");
  runNode(["--check", agentEntryContractPath], "test-agent-entry-contract.js syntax");
  const contract = JSON.parse(runNode(
    [agentEntryContractPath],
    "test-agent-entry-contract.js"
  ));
  if (contract.ok !== true
      || contract.uiState !== "s:1|ga:<attemptId>"
      || contract.titleFrameGate !== "bootstrap_reveal_ready") {
    throw new Error("agent entry static contract returned an unexpected result");
  }
  const output = runNode([runnerPath, "--check"], "run-unattended.js --check");
  const parsed = JSON.parse(output);
  if (parsed.ok !== true
      || parsed.slot !== runner.DEFAULT_AGENT_SLOT
      || parsed.scope !== "open_snapshot_gate_only") {
    throw new Error("runner self-check returned an unexpected contract");
  }
}

function checkArgumentSafety() {
  const args = runner.parseArgs(["--seed-slot", "crazyflasher7_saves2"]);
  runner.assertSafeArgs(args);
  if (args.slot !== "cf7_agent_equipment_tuning") {
    throw new Error("default target slot is not the dedicated equipment-tuning slot");
  }

  expectRejected(
    "live target",
    () => runner.assertSafeArgs(Object.assign({}, args, {
      slot: "crazyflasher7_saves",
    })),
    "unsafe_target_slot"
  );
  expectRejected(
    "fresh flow",
    () => runner.assertSafeArgs(Object.assign({}, args, { fresh: true })),
    "fresh_forbidden"
  );
  expectRejected(
    "missing explicit seed",
    () => runner.assertSafeArgs(Object.assign({}, args, { seedSlot: null })),
    "seed_slot_required"
  );
  expectRejected(
    "path-like seed",
    () => runner.assertSafeArgs(Object.assign({}, args, {
      seedSlot: "..\\crazyflasher7_saves2",
    })),
    "unsafe_seed_slot"
  );
}

function checkLogWatermarks() {
  const records = runner.freshLogRecords(
    { total: 2 },
    {
      total: 4,
      lines: [
        "old-one",
        "old-two",
        "[BootstrapAS] event=handoff",
        "new-line",
      ],
    }
  );
  if (records.length !== 2
      || records[0].lineNumber !== 3
      || !runner.findFreshHandoff(records)) {
    throw new Error("fresh log slicing did not honor the pre-start watermark");
  }

  expectRejected(
    "log tail gap",
    () => runner.freshLogRecords(
      { total: 0 },
      { total: 2001, lines: new Array(2000).fill("line") }
    ),
    "log_gap_after_watermark"
  );
  expectRejected(
    "log reset",
    () => runner.freshLogRecords(
      { total: 20 },
      { total: 5, lines: new Array(5).fill("line") }
    ),
    "log_reset_after_watermark"
  );
}

function checkCorrelatedSnapshotGate() {
  const valid = [
    {
      lineNumber: 21,
      line: "2026-07-16 event=equipment_tuning_panel_bound "
        + "panelInstanceId=panel.workbench.21",
    },
    {
      lineNumber: 22,
      line: "2026-07-16 event=equipment_tuning_snapshot_confirmed "
        + "callId=tune.contract.1 panelInstanceId=panel.workbench.21 "
        + "viewSessionId=view.contract.1 writeEpoch=4",
    },
  ];
  const gate = runner.selectWorkbenchSnapshotGate(valid);
  if (!gate
      || gate.activeWorkbench.panelInstanceId !== "panel.workbench.21"
      || gate.tuningSnapshot.viewSessionId !== "view.contract.1"
      || gate.tuningSnapshot.writeEpoch !== 4) {
    throw new Error("valid correlated snapshot gate was not accepted");
  }

  const wrongOrder = [valid[1], valid[0]];
  wrongOrder[0] = Object.assign({}, wrongOrder[0], { lineNumber: 20 });
  if (runner.selectWorkbenchSnapshotGate(wrongOrder)) {
    throw new Error("snapshot before active workbench was accepted");
  }

  const wrongInstance = JSON.parse(JSON.stringify(valid));
  wrongInstance[1].line = wrongInstance[1].line.replace(
    "panel.workbench.21",
    "panel.workbench.22"
  );
  if (runner.selectWorkbenchSnapshotGate(wrongInstance)) {
    throw new Error("cross-instance snapshot was accepted");
  }

  const incomplete = runner.parseSnapshotEvidence({
    lineNumber: 22,
    line: "event=equipment_tuning_snapshot_confirmed "
      + "callId=tune.contract.1 panelInstanceId=panel.workbench.21 "
      + "viewSessionId=view.contract.1",
  });
  if (incomplete) throw new Error("snapshot without writeEpoch was accepted");
}

function checkRuntimeWatermarks() {
  const status = {
    success: true,
    launchState: "Ready",
    revealPerformed: true,
    socketConnected: true,
    gameEnteredObserved: true,
    gameEnteredAttemptId: "attempt-contract",
    readyForRuntimeAutomation: true,
    runtimeReadyBlockedBy: [],
    save: {
      decision: "snapshot",
      kind: "Snapshot",
      slot: runner.DEFAULT_AGENT_SLOT,
      attemptId: "attempt-contract",
    },
    saveRuntime: {
      loaded: true,
      savePath: runner.DEFAULT_AGENT_SLOT,
      attemptId: "attempt-contract",
      role: "contract-role",
      level: 20,
    },
  };
  runner.assertRuntimeReadyStatus(
    status,
    runner.DEFAULT_AGENT_SLOT,
    "attempt-contract"
  );

  const missingGameEnter = JSON.parse(JSON.stringify(status));
  missingGameEnter.gameEnteredObserved = false;
  expectRejected(
    "missing game-enter receipt",
    () => runner.assertRuntimeReadyStatus(
      missingGameEnter,
      runner.DEFAULT_AGENT_SLOT,
      "attempt-contract"
    ),
    "game_enter_not_observed"
  );

  const staleGameEnter = JSON.parse(JSON.stringify(status));
  staleGameEnter.gameEnteredAttemptId = "attempt-stale";
  expectRejected(
    "stale game-enter receipt",
    () => runner.assertRuntimeReadyStatus(
      staleGameEnter,
      runner.DEFAULT_AGENT_SLOT,
      "attempt-contract"
    ),
    "game_enter_attempt_mismatch"
  );

  const stale = JSON.parse(JSON.stringify(status));
  stale.saveRuntime.attemptId = "attempt-stale";
  expectRejected(
    "stale runtime acknowledgement",
    () => runner.assertRuntimeReadyStatus(
      stale,
      runner.DEFAULT_AGENT_SLOT,
      "attempt-contract"
    ),
    "runtime_save_watermark_mismatch"
  );

  const pending = JSON.parse(JSON.stringify(status));
  pending.readyForRuntimeAutomation = false;
  pending.runtimeReadyBlockedBy = ["runtime_save_not_loaded"];
  const state = {
    expectedSlot: runner.DEFAULT_AGENT_SLOT,
    expectedAttemptId: "attempt-contract",
    handoffEvidence: null,
    titleFrameEvidence: null,
    enterRequested: false,
  };
  if (runner.shouldRequestAgentEnter(pending, state)) {
    throw new Error("agent enter was allowed without a fresh handoff");
  }
  state.handoffEvidence = {
    lineNumber: 10,
    line: runner.HANDOFF_MARKER,
  };
  if (runner.shouldRequestAgentEnter(pending, state)) {
    throw new Error("agent enter was allowed without a real title-frame receipt");
  }
  state.titleFrameEvidence = {
    lineNumber: 11,
    line: runner.TITLE_FRAME_MARKER,
  };
  if (!runner.shouldRequestAgentEnter(pending, state)) {
    throw new Error("agent enter was blocked after all narrow gates passed");
  }
  state.enterRequested = true;
  if (runner.shouldRequestAgentEnter(pending, state)) {
    throw new Error("agent enter could be requested more than once");
  }
}

function checkNoUiBusinessControlBackdoor() {
  const source = fs.readFileSync(runnerPath, "utf8");
  const forbidden = [
    "PanelHost.OpenPanel",
    "Panels.open(",
    "expectedTuningToken",
    "agent(port, \"preview\"",
    "agent(port, \"commit\"",
  ];
  forbidden.forEach((needle) => {
    if (source.includes(needle)) {
      throw new Error("runner contains forbidden business/UI backdoor: " + needle);
    }
  });

  const required = [
    "openEquipmentTuning",
    "expectedSlot",
    "expectedAttemptId",
    "event=equipment_tuning_panel_bound",
    "event=equipment_tuning_snapshot_confirmed",
    "businessWritesAttempted: false",
    "uiBusinessClicks: false",
  ];
  required.forEach((needle) => {
    if (!source.includes(needle)) {
      throw new Error("runner is missing required gate/boundary marker: " + needle);
    }
  });

  if (!source.includes("consoleCommand(port, AGENT_ENTER_COMMAND)")
      || runner.AGENT_ENTER_COMMAND !== "#func:_root.agentEnterResolvedSave()") {
    throw new Error("the sole console escape is not the fixed agent save-entry command");
  }
}

function main(argv) {
  if (argv.length > 0 && !(argv.length === 1 && argv[0] === "--check")) {
    throw new Error("run-checks.js accepts only --check");
  }
  checkSyntaxAndSelfCheck();
  checkArgumentSafety();
  checkLogWatermarks();
  checkCorrelatedSnapshotGate();
  checkRuntimeWatermarks();
  checkNoUiBusinessControlBackdoor();
  console.log(JSON.stringify({
    ok: true,
    suites: 6,
    runnerScope: "open_snapshot_gate_only",
    targetSlot: runner.DEFAULT_AGENT_SLOT,
  }, null, 2));
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
