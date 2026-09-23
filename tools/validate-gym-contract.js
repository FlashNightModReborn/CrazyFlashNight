#!/usr/bin/env node
// Dedicated source closure for the Host-clock gym panel. The general panel
// contract parser assumes every Web command directly dispatches to Flash;
// gym status is local and finish is Host-only, so it has its own exact gate.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const CONTRACT = "launcher/contracts/gym-training.v1.json";
const FILES = Object.freeze({
  flash: "scripts/类定义/org/flashNight/arki/ui/GymTrainingPanelService.as",
  flashOpen: "scripts/类定义/org/flashNight/arki/ui/GymPreviewPanelService.as",
  host: "launcher/src/Tasks/GymTrainingTask.cs",
  open: "launcher/src/Tasks/GymPreviewOpenData.cs",
  router: "launcher/src/Guardian/WebOverlayForm.cs",
  registry: "launcher/src/Bus/TaskRegistry.cs",
  program: "launcher/src/Program.cs",
  web: "launcher/web/modules/gym/gym-panel.js"
});
const WEB_COMMANDS = ["start", "cancel", "status", "query", "retrySave"];
const ACTIONS = {
  start: "gymStart", cancel: "gymCancel", finish: "gymFinish",
  query: "gymQuery", retrySave: "gymRetrySave"
};

function readSources(root) {
  const sources = {};
  for (const [name, relative] of Object.entries(FILES)) {
    sources[name] = fs.readFileSync(path.join(root, relative), "utf8");
  }
  return sources;
}

function methodBody(source, name) {
  const match = new RegExp(
    "\\b(?:public|private|internal|protected)\\s+(?:static\\s+)?"
    + "[A-Za-z0-9_<>]+\\s+" + name + "\\s*\\(").exec(source);
  if (!match) return null;
  const open = source.indexOf("{", match.index);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === "{") depth++;
    else if (source[i] === "}" && --depth === 0) return source.slice(open + 1, i);
  }
  return null;
}

function validate(contract, source) {
  const errors = [];
  function check(ok, code) { if (!ok) errors.push(code); }
  check(contract && contract.schema === "cf7-gym-training-contract-v1"
    && contract.panel === "gym" && contract.wireDomain === "gym"
    && contract.businessAuthority === "as2"
    && contract.openSnapshotVersion === 2, "contract.identity");
  check(Array.isArray(contract.webCommands)
    && JSON.stringify(contract.webCommands) === JSON.stringify(WEB_COMMANDS),
    "contract.web_commands");
  check(JSON.stringify(contract.flashActions) === JSON.stringify(ACTIONS),
    "contract.flash_actions");
  check(contract.hostOnly && contract.hostOnly.status === "local clock projection"
    && contract.hostOnly.finish === "monotonic active-time endpoint",
    "contract.host_only");
  check(contract.flashResponseTask === "gym_training_response",
    "contract.response_task");
  check(contract.unknownFinishRecovery ===
    "exact gymQuery, never blind gymFinish replay", "contract.unknown_write");
  check(contract.pendingSaveRecovery ===
    "exact gymQuery then gymRetrySave without business replay",
    "contract.pending_save");

  for (const [operation, action] of Object.entries(ACTIONS)) {
    const wrapper = new RegExp(
      "gameCommands\\[\\\"" + action
      + "\\\"\\]\\s*=\\s*function\\s*\\(params\\)\\s*\\{"
      + "[^}]*GymTrainingPanelService\\.handle\\(\\\"" + operation
      + "\\\",\\s*params\\)");
    check(wrapper.test(source.flash), "flash.wrapper." + operation);
    const mapping = new RegExp(
      "case\\s+\\\"" + operation + "\\\":\\s*return\\s+\\\""
      + action + "\\\"");
    check(mapping.test(methodBody(source.host, "FlashActionFor") || ""),
      "host.action." + operation);
  }
  check(/result\.task\s*=\s*"gym_training_response"/.test(source.flash),
    "flash.response_task");
  check(/RegisterAsync\("gym_training_response",\s*gymTrainingTask\.HandleFlashResponse\)/.test(
    source.registry), "host.response_route");
  check(/snapshot\["v"\],\s*2,\s*2/.test(source.open)
    && /ValidPendingSession\(snapshot\["pendingSession"\]/.test(source.open),
    "host.open_v2_pending");
  check(/prepareOpen\(stationId\)/.test(source.flashOpen)
    && /openGymForAgent/.test(source.flashOpen),
    "flash.production_opener");
  check(/domain == "gym"\) return PanelDomainRoute\.Gym/.test(source.router)
    && /HasExactActivePanelOwnerBinding\(parsed, "gym"\)/.test(source.router),
    "host.exact_panel_route");
  check(/SetGymTrainingTask\(gymTrainingTask\)/.test(source.program)
    && /gymTrainingTask\.HandlePanelClosed\(panelInstanceId\)/.test(source.program)
    && /gymTrainingTask\.SetActivityProbe/.test(source.program),
    "host.lifecycle_wiring");
  check(/SetGymOpenAction/.test(source.program)
    && /openGymForAgent/.test(source.program),
    "host.fixed_agent_opener");

  const webIngress = methodBody(source.host, "HandleWebRequest") || "";
  for (const command of WEB_COMMANDS) {
    check(webIngress.includes('"' + command + '"'),
      "host.web_command." + command);
  }
  check(!webIngress.includes('"finish"'), "host.finish_not_web");
  const clock = methodBody(source.host, "Tick") || "";
  check(/Stopwatch\.GetTimestamp/.test(source.host)
    && /MaxObservedClockStepMs\s*=\s*400/.test(source.host)
    && /Math\.Min\(MaxObservedClockStepMs/.test(clock)
    && /SessionRequestLocked\("finish"/.test(clock),
    "host.monotonic_finish");
  check(/_session\.Phase != "needs_reconcile"/.test(webIngress)
    && /_session\.Phase != "save_pending"/.test(webIngress)
    && /PendingReopenUnqueried/.test(webIngress),
    "host.exact_recovery_gate");
  check(/GymPanel/.test(source.web)
    && /Bridge\.on\('panel_event'/.test(source.web)
    && /domain:'gym'/.test(source.web)
    && /snapshot\.pendingSession/.test(source.web),
    "web.session_consumer");
  return errors;
}

function main() {
  const contract = JSON.parse(fs.readFileSync(path.join(ROOT, CONTRACT), "utf8"));
  const errors = validate(contract, readSources(ROOT));
  process.stdout.write(JSON.stringify({
    tool: "validate-gym-contract", ok: errors.length === 0,
    schema: contract.schema, checkedSources: Object.keys(FILES).length,
    errors
  }, null, 2) + "\n");
  if (errors.length) process.exitCode = 1;
}

if (require.main === module) main();
module.exports = { validate, readSources, FILES, CONTRACT };
