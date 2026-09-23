#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { validate, readSources, CONTRACT } = require("./validate-gym-contract");

const root = path.resolve(__dirname, "..");
const baselineContract = JSON.parse(
  fs.readFileSync(path.join(root, CONTRACT), "utf8"));
const baselineSources = readSources(root);
const baselineErrors = validate(baselineContract, baselineSources);
if (baselineErrors.length) {
  throw new Error("baseline gym contract fails: " + baselineErrors.join(", "));
}

const cases = [
  ["Flash finish action must remain registered", "flash",
    'gameCommands["gymFinish"]', 'gameCommands["gymOther"]',
    "flash.wrapper.finish"],
  ["Host finish action mapping must remain exact", "host",
    'case "finish": return "gymFinish"', 'case "finish": return "gymOther"',
    "host.action.finish"],
  ["response task binding must remain exact", "registry",
    'router.RegisterAsync("gym_training_response", gymTrainingTask.HandleFlashResponse)',
    'router.RegisterAsync("gym_other_response", gymTrainingTask.HandleFlashResponse)',
    "host.response_route"],
  ["Web request must have exact gym owner", "router",
    'HasExactActivePanelOwnerBinding(parsed, "gym")',
    'HasExactActivePanelOwnerBinding(parsed, "sleep")',
    "host.exact_panel_route"],
  ["starved clock cannot credit an unbounded gap", "host",
    "Math.Min(MaxObservedClockStepMs,", "Math.Min(99999999,",
    "host.monotonic_finish"],
  ["Web must never call finish directly", "host",
    'new[] { "start", "cancel", "status", "query", "retrySave" }',
    'new[] { "start", "cancel", "status", "query", "retrySave", "finish" }',
    "host.finish_not_web"],
  ["pending opener must be validated", "open",
    'ValidPendingSession(snapshot["pendingSession"]',
    'ValidPendingSession(snapshot["otherPendingSession"]',
    "host.open_v2_pending"],
  ["recovery query must stay available", "host",
    '_session.Phase != "needs_reconcile"',
    '_session.Phase != "other_reconcile"',
    "host.exact_recovery_gate"],
  ["fixed clone-slot opener must stay wired", "program",
    "agentControlTask.SetGymOpenAction",
    "agentControlTask.SetOtherOpenAction",
    "host.fixed_agent_opener"]
];

let passed = 0;
for (const [title, key, before, after, expected] of cases) {
  const original = baselineSources[key];
  if (!original.includes(before)) {
    throw new Error("mutation needle absent: " + title);
  }
  const sources = { ...baselineSources, [key]: original.replace(before, after) };
  const errors = validate(baselineContract, sources);
  if (!errors.includes(expected)) {
    throw new Error(title + " escaped gym gate: " + errors.join(", "));
  }
  passed++;
}

const alteredContract = {
  ...baselineContract,
  unknownFinishRecovery: "repeat finish automatically"
};
if (!validate(alteredContract, baselineSources).includes("contract.unknown_write")) {
  throw new Error("unknown write contract mutation escaped gym gate");
}
passed++;

process.stdout.write(JSON.stringify({
  tool: "test-gym-contract", ok: true, passed,
  total: cases.length + 1
}, null, 2) + "\n");
