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

function extractDomLayer(dom, name) {
  const marker = `<DOMLayer name="${name}"`;
  const start = dom.indexOf(marker);
  if (start < 0 || dom.indexOf(marker, start + marker.length) >= 0) {
    throw new Error(`expected exactly one main timeline layer: ${name}`);
  }
  const end = dom.indexOf("</DOMLayer>", start);
  if (end < 0) throw new Error(`unterminated main timeline layer: ${name}`);
  return dom.slice(start, end + "</DOMLayer>".length);
}

function extractLayerFrames(layer) {
  return Array.from(layer.matchAll(/<DOMFrame index="(\d+)"([^>]*)>([\s\S]*?)<\/DOMFrame>/g),
    (match) => {
      const duration = /\bduration="(\d+)"/.exec(match[2]);
      return {
        index: Number(match[1]),
        duration: duration ? Number(duration[1]) : 1,
        body: match[3],
      };
    });
}

function assertNormalTimelineContract(dom) {
  const actionFrames = extractLayerFrames(extractDomLayer(dom, "as"));
  const frame81 = actionFrames.find((frame) => frame.index === 81);
  if (!frame81 || !frame81.body.includes("_root._bootstrap.sendRevealReady();")
      || frame81.body.includes("_root.notifyGameEntered();")) {
    throw new Error("headless frame 81 must emit only the bootstrap reveal checkpoint");
  }

  const retiredActionFrames = new Set([82, 83, 88, 91, 101, 110, 119, 125]);
  for (const frame of actionFrames) {
    if (!retiredActionFrames.has(frame.index)) continue;
    const script = /<script><!\[CDATA\[([\s\S]*?)\]\]><\/script>/.exec(frame.body);
    if (!script || script[1].trim() !== "stop();") {
      throw new Error(`retired author frame ${frame.index + 1} still has timeline side effects`);
    }
  }

  const retiredVisibleLayers = [
    "标题画面遮罩",
    "加载进度条",
    "Layer 177",
    "Layer 179",
    "加载背景",
  ];
  for (const name of retiredVisibleLayers) {
    const frames = extractLayerFrames(extractDomLayer(dom, name));
    for (const frame of frames) {
      if (frame.index > 125 || frame.index + frame.duration - 1 < 81) continue;
      if (!/<elements\s*\/>/.test(frame.body)
          && !/<elements>\s*<\/elements>/.test(frame.body)) {
        throw new Error(`${name} still renders legacy UI at author frame ${frame.index + 1}`);
      }
    }
  }

  const label125 = dom.indexOf('<DOMFrame index="125" duration="4" name="新人物创建中"');
  const label129 = dom.indexOf('<DOMFrame index="129" duration="6" name="读盘"');
  if (label125 < 0 || label129 < 0 || label125 >= label129) {
    throw new Error("headless new-character/read-frame gateway labels no longer preserve order");
  }
}

function assertFrontdoorServiceContract(service, installer) {
  const required = [
    '_root.gameCommands["characterCreationSnapshot"]',
    '_root.gameCommands["characterCreate"]',
    '_root.gameCommands["frontdoorEnterResolvedSave"]',
    'subscribe(\n            "SceneReady"',
    "_root._bootstrapAttemptId",
    "_root.savePath",
    "_root.notifyGameEntered();",
    'baseResponse("create", "scene_ready"',
  ];
  for (const marker of required) {
    if (!service.includes(marker)) {
      throw new Error(`CharacterCreationService is missing frontdoor marker: ${marker}`);
    }
  }
  if (service.includes("添加单次任务")) {
    throw new Error("Web frontdoor SceneReady must not use an artificial frame delay");
  }
  if (!installer.includes("CharacterCreationService.install();")) {
    throw new Error("CharacterCreationService is not installed by the save boot entrypoint");
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
  const frontdoorServicePath = "scripts/类定义/org/flashNight/neur/Server/CharacterCreationService.as";
  const equipmentRunnerPath = "tools/equipment-tuning/run-unattended.js";
  const arenaRunnerPath = "tools/arena-calibration/run-unattended.js";

  const helper = read(helperPath);
  assertAgentHelperContract(helper);
  assertNormalTimelineContract(read(domPath));
  assertFrontdoorServiceContract(read(frontdoorServicePath), helper);
  assertBootManifestContract(read(frame3Path), read(frame41Path), read(uiManagerPath));
  assertRunnerTitleFrameGate(read(equipmentRunnerPath), "equipment runner");
  assertRunnerTitleFrameGate(read(arenaRunnerPath), "arena runner");

  return {
    ok: true,
    helper: helperPath,
    normalEntry: domPath,
    frontdoorService: frontdoorServicePath,
    bootOrder: [3, 41],
    uiState: "s:1|ga:<attemptId>",
    revealGates: ["bootstrap_reveal_ready", "s:1|ga:<attemptId>"],
  };
}

module.exports = {
  assertAgentHelperContract,
  assertBootManifestContract,
  assertFrontdoorServiceContract,
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
