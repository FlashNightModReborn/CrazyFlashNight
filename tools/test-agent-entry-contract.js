#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(ROOT, relativePath), "utf8");
}

function extractAssignedFunction(source, assignment, label) {
  const assignmentIndex = source.indexOf(assignment);
  if (assignmentIndex < 0) throw new Error(label + " assignment is missing");
  const open = source.indexOf("{", assignmentIndex + assignment.length);
  if (open < 0) throw new Error(label + " function body is missing");

  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    const character = source[index];
    if (character === "{") depth += 1;
    else if (character === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, index);
    }
  }
  throw new Error(label + " function body is unterminated");
}

function assertAgentHelperContract(source) {
  const body = extractAssignedFunction(
    source,
    "_root.agentEnterResolvedSave = function()",
    "agentEnterResolvedSave"
  );
  const guard = body.indexOf('typeof _root.notifyGameEntered != "function"');
  const notify = body.indexOf("_root.notifyGameEntered();");
  const loaded = body.indexOf("_root._saveRuntimeLoaded == true");
  const readFrame = body.indexOf('_root.gotoAndStop("读盘")');

  if (guard < 0 || notify < 0 || loaded < 0 || readFrame < 0) {
    throw new Error("agentEnterResolvedSave is missing notify/readiness/read-frame contract markers");
  }
  if (!(guard < notify && notify < loaded && loaded < readFrame)) {
    throw new Error("agentEnterResolvedSave must guard, notify, check loaded, then enter the read frame");
  }
  if (!body.slice(guard, notify).includes("return false;")) {
    throw new Error("agentEnterResolvedSave notify guard is not fail-closed");
  }
  if (/\bloadAll\s*\(/.test(body) || /_root\.读取存盘\s*\(/.test(body)) {
    throw new Error("agentEnterResolvedSave must not consume the launcher snapshot directly");
  }
  if (body.includes('_root.gotoAndPlay("读盘")')) {
    throw new Error("agentEnterResolvedSave must use the same gotoAndStop read-frame transition as the title button");
  }
}

function assertNormalTimelineContract(dom) {
  const titleRead = dom.indexOf('_root.gotoAndStop("读盘");');
  const titleNotify = dom.lastIndexOf("_root.notifyGameEntered();", titleRead);
  const titleRelease = dom.lastIndexOf("on (release) {", titleRead);
  const titleScriptEnd = dom.indexOf("]]></script>", titleRead);
  if (titleRead < 0 || titleNotify < 0 || titleRelease < 0 || titleScriptEnd < 0
      || !(titleRelease < titleNotify && titleNotify < titleRead && titleRead < titleScriptEnd)) {
    throw new Error("title save-entry timeline no longer preserves notifyGameEntered -> 读盘 order");
  }

  const frame125Blocks = dom.match(/<DOMFrame index="125"[^>]*>[\s\S]*?<\/DOMFrame>/g) || [];
  if (!frame125Blocks.some((block) => block.includes("_root.notifyGameEntered();"))) {
    throw new Error("new-character frame 125 no longer emits notifyGameEntered");
  }
  const label125 = dom.indexOf('<DOMFrame index="125" duration="4" name="新人物创建中"');
  const label129 = dom.indexOf('<DOMFrame index="129" duration="6" name="读盘"');
  if (label125 < 0 || label129 < 0 || label125 >= label129) {
    throw new Error("new-character/read-frame labels no longer preserve the expected order");
  }
}

function assertBootManifestContract(frame3, frame41, uiManager) {
  const saveInclude = '#include "../通信/通信_lsy_原版存档系统.as"';
  const uiInclude = '#include "../展现/UI交互/UI交互_lsy_UI管理.as"';
  if (!frame3.includes(saveInclude)) {
    throw new Error("asLoader frame3 no longer includes the agent save-entry helper");
  }
  if (!frame41.includes(uiInclude)) {
    throw new Error("asLoader frame41 no longer includes notifyGameEntered");
  }

  const notifyBody = extractAssignedFunction(
    uiManager,
    "_root.notifyGameEntered = function()",
    "notifyGameEntered"
  );
  if (!notifyBody.includes('FrameBroadcaster.pushUiState("s:1")')) {
    throw new Error("notifyGameEntered no longer emits the s:1 UI-state contract");
  }
  if (!notifyBody.includes('FrameBroadcaster.pushUiState("ga:" + String(_root._bootstrapAttemptId))')) {
    throw new Error("notifyGameEntered no longer binds s:1 to the launcher attempt");
  }
}

function assertRunnerTitleFrameGate(source, label) {
  const required = [
    "findFreshTitleFrame",
    "findFreshRevealWatchdog",
    "titleFrameEvidence",
    "title_frame_not_observed",
  ];
  for (const marker of required) {
    if (!source.includes(marker)) {
      throw new Error(label + " no longer enforces the real title-frame/watchdog gate: " + marker);
    }
  }
}

function checkAgentEntryContract() {
  const helperPath = "scripts/通信/通信_lsy_原版存档系统.as";
  const domPath = "CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml";
  const frame3Path = "scripts/asLoaderManifest/frame3.as";
  const frame41Path = "scripts/asLoaderManifest/frame41.as";
  const uiManagerPath = "scripts/展现/UI交互/UI交互_lsy_UI管理.as";
  const equipmentRunnerPath = "tools/equipment-tuning/run-unattended.js";
  const arenaRunnerPath = "tools/arena-calibration/run-unattended.js";

  assertAgentHelperContract(read(helperPath));
  assertNormalTimelineContract(read(domPath));
  assertBootManifestContract(read(frame3Path), read(frame41Path), read(uiManagerPath));
  assertRunnerTitleFrameGate(read(equipmentRunnerPath), "equipment runner");
  assertRunnerTitleFrameGate(read(arenaRunnerPath), "arena runner");

  return {
    ok: true,
    helper: helperPath,
    normalEntry: domPath,
    bootOrder: [3, 41],
    uiState: "s:1|ga:<attemptId>",
    titleFrameGate: "bootstrap_reveal_ready",
  };
}

module.exports = {
  assertAgentHelperContract,
  assertBootManifestContract,
  assertNormalTimelineContract,
  assertRunnerTitleFrameGate,
  checkAgentEntryContract,
  extractAssignedFunction,
};

if (require.main === module) {
  try {
    console.log(JSON.stringify(checkAgentEntryContract(), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
