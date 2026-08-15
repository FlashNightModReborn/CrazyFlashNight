#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const runner = require("./run-unattended");
const commitVerifier = require("./verify-commit-journey");

const root = path.resolve(__dirname, "../..");
const runnerPath = path.join(__dirname, "run-unattended.js");
const journeyVerifierPath = path.join(__dirname, "verify-journey.js");
const commitJourneyVerifierPath = path.join(
  __dirname,
  "verify-commit-journey.js"
);
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
  runNode(["--check", journeyVerifierPath], "verify-journey.js syntax");
  runNode(
    ["--check", commitJourneyVerifierPath],
    "verify-commit-journey.js syntax"
  );
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
  const journeyOutput = runNode(
    [journeyVerifierPath, "--check"],
    "verify-journey.js --check"
  );
  const journey = JSON.parse(journeyOutput);
  if (journey.ok !== true
      || journey.gate !== "PG-TUNE-PREVIEW"
      || journey.scope !== "preview_only"
      || !journey.fixtures
      || journey.fixtures.positive !== 3
      || journey.fixtures.negative !== 25) {
    throw new Error("journey verifier self-check returned an unexpected contract");
  }
  const commitJourneyOutput = runNode(
    [commitJourneyVerifierPath, "--check"],
    "verify-commit-journey.js --check"
  );
  const commitJourney = JSON.parse(commitJourneyOutput);
  if (commitJourney.ok !== true
      || commitJourney.gate !== "PG-TUNE-E2E"
      || commitJourney.scope !== "offline_contract_only_no_save_or_runtime_access"
      || commitJourney.positive !== 8
      || commitJourney.negative !== 78) {
    throw new Error("commit journey verifier self-check returned an unexpected contract");
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
        + "viewSessionId=view.contract.1 "
        + "sourceKey=inventory%3A%E8%83%8C%E5%8C%85%3A7%3Alease.contract "
        + "stateRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa writeEpoch=4",
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
      + "viewSessionId=view.contract.1 "
      + "sourceKey=inventory%3A%E8%83%8C%E5%8C%85%3A7%3Alease.contract "
      + "stateRef=sha256_aaaaaaaaaaaaaaaaaaaaaaaa",
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

  const commitSource = fs.readFileSync(commitJourneyVerifierPath, "utf8");
  const previewSource = fs.readFileSync(journeyVerifierPath, "utf8");
  [
    "verifyRuntimeIdentity",
    "runtime_identity_before_preview",
    "runtime_identity_after_preview",
    "fullRuntimeIdentityReverified",
    "open_report_outside_opener_directory",
  ].forEach((needle) => {
    if (!previewSource.includes(needle)) {
      throw new Error("preview verifier is missing a full identity/safety marker: " + needle);
    }
  });
  [
    'opener.agent(port, "preview"',
    'opener.agent(port, "commit"',
    'opener.agent(port, "snapshot"',
    'opener.agent(port, "reconcile"',
    '"/console"',
    "fresh: true",
  ].forEach((needle) => {
    if (commitSource.includes(needle)) {
      throw new Error("commit verifier contains a business/save backdoor: " + needle);
    }
  });
  [
    "verifyRuntimeIdentity",
    "waiting_for_computer_use_safe_commit",
    "waiting_for_clone_archive_and_exit",
    "[ArchiveTask] Shadow saved:",
    "readFinalLogSnapshotFromDisk",
    "reload_launcher_already_running",
    "waiting_for_reload_source_selection",
    "unknownWriteReconcileJourneyVerified: false",
    "safeExitUiJourneyVerified: false",
    "previewGate.resolveOpenReport",
  ].forEach((needle) => {
    if (!commitSource.includes(needle)) {
      throw new Error("commit verifier is missing a fail-closed marker: " + needle);
    }
  });
}

function checkCloneFilesystemSafety() {
  const parent = path.join(root, "tmp", "equipment-tuning");
  fs.mkdirSync(parent, { recursive: true });
  const checkRoot = fs.mkdtempSync(path.join(parent, "gate-fs-check-"));
  const expectedPrefix = path.resolve(parent) + path.sep;
  if (!path.resolve(checkRoot).startsWith(expectedPrefix)) {
    throw new Error("filesystem check directory escaped the equipment-tuning tmp root");
  }
  try {
    const saves = path.join(checkRoot, "saves");
    fs.mkdirSync(saves);
    const target = path.join(saves, "cf7_agent_equipment_tuning.json");
    fs.writeFileSync(target, "old", { flag: "wx" });
    const before = runner.readRegularFileSnapshot(target, false, "check_fs");
    if (typeof before.stat.ino !== "bigint"
        || typeof before.stat.mtimeNs !== "bigint"
        || before.raw.toString("utf8") !== "old") {
      throw new Error("bound file read did not preserve BigInt file identity");
    }
    if (!runner.sameBoundFileIdentity(before.stat, before.stat)
        || runner.sameBoundFileIdentity(before.stat, Object.assign({}, before.stat, {
          ino: before.stat.ino + 1n,
        }))) {
      throw new Error("file-handle identity change fixture was not rejected");
    }
    const written = runner.writeAtomicRegularFile(checkRoot, target, "new", "check_fs");
    if (written.raw.toString("utf8") !== "new"
        || fs.readFileSync(target, "utf8") !== "new") {
      throw new Error("exclusive target replacement fixture failed");
    }
    const leftovers = fs.readdirSync(saves).filter((name) => name !== path.basename(target));
    if (leftovers.length !== 0) {
      throw new Error("exclusive target replacement left temporary files behind");
    }

    const baselineText = JSON.stringify({ lastSaved: "2026-08-02 08:00:00" });
    const baselineFile = runner.writeAtomicRegularFile(
      checkRoot,
      target,
      baselineText,
      "check_fs"
    );
    const baseline = {
      path: target,
      sha256: crypto.createHash("sha256").update(baselineFile.raw).digest("hex"),
      utf8Bytes: baselineFile.raw.length,
      deviceId: String(baselineFile.stat.dev),
      fileId: String(baselineFile.stat.ino),
      mtimeNs: String(baselineFile.stat.mtimeNs),
      lastWriteTimeUtc: new Date(
        Number(baselineFile.stat.mtimeNs / 1000000n)
      ).toISOString(),
      lastSaved: "2026-08-02 08:00:00",
    };
    commitVerifier.assertCloneMatchesBaseline(baseline, "check_fs");
    fs.writeFileSync(target, JSON.stringify({
      lastSaved: "2026-08-02 08:00:01",
    }), "utf8");
    expectRejected(
      "clone drift during verifier wait",
      () => commitVerifier.assertCloneMatchesBaseline(baseline, "check_fs"),
      "clone_changed_during_gate"
    );

    const outside = path.join(checkRoot, "outside");
    const junction = path.join(checkRoot, "saves-junction");
    fs.mkdirSync(outside);
    fs.symlinkSync(outside, junction, "junction");
    expectRejected(
      "reparse directory chain",
      () => runner.assertCanonicalDirectoryChain(checkRoot, junction, "check_fs"),
      "directory_chain_reparse"
    );

    const syntheticFileSymlink = {
      isFile: () => false,
      isSymbolicLink: () => true,
    };
    expectRejected(
      "target file symlink metadata",
      () => runner.assertRegularFileLstat(
        syntheticFileSymlink,
        target,
        "check_fs_target_symlink"
      ),
      "regular_file_reparse"
    );
    expectRejected(
      "seed file symlink metadata",
      () => runner.assertRegularFileLstat(
        syntheticFileSymlink,
        path.join(saves, "crazyflasher7_saves2.json"),
        "check_fs_seed_symlink"
      ),
      "regular_file_reparse"
    );

    const symlinkTarget = path.join(saves, "symlink-target.json");
    let symlinkCreated = false;
    try {
      fs.symlinkSync(target, symlinkTarget, "file");
      symlinkCreated = true;
    } catch (error) {
      if (!error || !["EPERM", "EACCES", "UNKNOWN"].includes(error.code)) throw error;
    }
    if (symlinkCreated) {
      expectRejected(
        "real target file symlink",
        () => runner.readRegularFileSnapshot(symlinkTarget, false, "check_fs_symlink"),
        "regular_file_reparse"
      );
    }

    runner.assertExclusiveLauncherProcess([], null);
    runner.assertExclusiveLauncherProcess([{ pid: 1234, processPath: "fixture" }], 1234);
    expectRejected(
      "unverified Launcher process",
      () => runner.assertExclusiveLauncherProcess([
        { pid: 1234, processPath: "fixture" },
      ], null),
      "unverified_launcher_process_present"
    );
    expectRejected(
      "second Launcher process",
      () => runner.assertExclusiveLauncherProcess([
        { pid: 1234, processPath: "fixture" },
        { pid: 5678, processPath: "fixture-two" },
      ], 1234),
      "launcher_process_not_exclusive"
    );
  } finally {
    fs.rmSync(checkRoot, { recursive: true, force: true });
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
  checkCloneFilesystemSafety();
  checkNoUiBusinessControlBackdoor();
  console.log(JSON.stringify({
    ok: true,
    suites: 9,
    runnerScope: "open_snapshot_gate_only",
    journeyGate: "PG-TUNE-PREVIEW",
    journeyScope: "preview_only",
    commitJourneyGate: "PG-TUNE-E2E",
    commitJourneyScope: "clone_commit_persist_restart_readback",
    targetSlot: runner.DEFAULT_AGENT_SLOT,
  }, null, 2));
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
