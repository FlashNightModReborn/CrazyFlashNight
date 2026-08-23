#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const runtime = require("../launcher/web/modules/settings-runtime.js");
const preferences = require("../launcher/web/modules/settings-preferences.js");

const root = path.resolve(__dirname, "..");
let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  process.stdout.write("[PASS] " + name + "\n");
}

const codes = [87,83,65,68,74,75,82,49,50,51,52,53,55,56,57,48,
  32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17];
const keys = runtime.KEY_IDS.map((id, index) => ({id, label:id, keyCode:codes[index], keyName:"K" + codes[index]}));
const settings = {
  setGlobalVolume:80, setBGMVolume:60, "性能等级上限":1,
  "是否阴影":true, "是否视觉元素":true, "是否打击数字特效":true,
  cameraZoomToggle:true, basicZoomScale:1, "开启昼夜系统":true,
  "暂停昼夜系统":false, "使用滤镜渲染":true, "立绘类型":1,
  jukeboxOverride:false, jukeboxTrueRandom:false, jukeboxPlayMode:"albumLoop"
};
const allowed = keys.map(row => ({code:row.keyCode, name:row.keyName}));

test("authoritative table contains 35 rows including run and combination", () => {
  assert.strictEqual(runtime.KEY_IDS.length, 35);
  assert.deepStrictEqual(runtime.KEY_IDS.slice(-2), ["奔跑键", "组合键"]);
  assert.strictEqual(runtime.validateKeyDraft(keys, allowed).valid, true);
});

test("duplicate, Esc and F-key bindings fail without swap", () => {
  const duplicate = runtime.copy(keys);
  duplicate[34].keyCode = duplicate[33].keyCode;
  const conflict = runtime.validateKeyDraft(duplicate, allowed);
  assert.strictEqual(conflict.error, "key_conflict");
  assert.deepStrictEqual(conflict.indexes, [33, 34]);
  const esc = runtime.copy(keys);
  esc[0].keyCode = 27;
  assert.strictEqual(runtime.validateKeyDraft(esc, allowed.concat({code:27,name:"Esc"})).error, "reserved_key");
  const f1 = runtime.copy(keys);
  f1[0].keyCode = 112;
  assert.strictEqual(runtime.validateKeyDraft(f1, allowed.concat({code:112,name:"F1"})).error, "reserved_key");
});

test("legacy conflicts can be repaired one candidate at a time", () => {
  const legacy = runtime.copy(keys);
  legacy[1].keyCode = legacy[0].keyCode;
  legacy[3].keyCode = legacy[2].keyCode;
  assert.deepStrictEqual(runtime.validateKeyDraft(legacy, allowed).indexes, [0, 1, 2, 3]);
  const extended = allowed.concat({code:90,name:"Z"});
  assert.strictEqual(runtime.validateKeyCandidate(legacy, 1, 90, extended).valid, true);
  legacy[1].keyCode = 90;
  assert.deepStrictEqual(runtime.validateKeyDraft(legacy, extended).indexes, [2, 3]);
});

test("snapshot adopts exact authority and normalizes legacy performance display", () => {
  const response = {
    success:true, v:1, revision:4, settings:Object.assign({}, settings, {"性能等级上限":3}),
    keys, defaultKeys:keys.map(row => ({id:row.id,keyCode:row.keyCode})),
    allowedKeyCodes:allowed, hostPrefs:{introEnabled:false,sfxEnabled:true,ambientEnabled:false,
      uiFontScale:1.35,mapDisplayPreference:"auto"}, challengeMode:false,
    modeLabel:"困难", cheatHelp:[], forceControls:{}, previewActive:false
  };
  const model = runtime.normalizeSnapshot(response);
  assert(model);
  assert.strictEqual(model.settings["性能等级上限"], 1);
  const draft = runtime.gameDraft(model);
  draft.settings.setGlobalVolume = 79;
  assert.strictEqual(runtime.hasGameChanges(model, draft), true);
  assert.strictEqual(runtime.applyPayload(model, draft).keys.length, 35);
});

test("placeholder key labels fall back to stable logical ids", () => {
  const dirtyKeys = runtime.copy(keys);
  dirtyKeys[0].label = "undefined";
  dirtyKeys[1].label = " null ";
  const model = runtime.normalizeSnapshot({
    success:true, v:1, revision:4, settings, keys:dirtyKeys,
    defaultKeys:keys.map(row => ({id:row.id,keyCode:row.keyCode})),
    allowedKeyCodes:allowed, hostPrefs:{introEnabled:false,sfxEnabled:true,ambientEnabled:false,
      uiFontScale:1.35,mapDisplayPreference:"auto"}, challengeMode:false,
    modeLabel:"困难", cheatHelp:[], forceControls:{}, previewActive:false
  });
  assert(model);
  assert.strictEqual(model.keys[0].label, model.keys[0].id);
  assert.strictEqual(model.keys[1].label, model.keys[1].id);
});

test("entry Flash preview accepts only the bounded transient contract", () => {
  const valid = {v:1,source:"entry_flash_snapshot",width:1280,height:720,
    dataUrl:"data:image/jpeg;base64,QUJDRA=="};
  assert.deepStrictEqual(runtime.normalizeFlashPreview(valid), valid);
  assert.deepStrictEqual(runtime.normalizeFlashPreview(Object.assign({}, valid, {width:1024,height:576})),
    Object.assign({}, valid, {width:1024,height:576}));
  assert.strictEqual(runtime.normalizeFlashPreview(Object.assign({}, valid, {width:4097})), null);
  assert.strictEqual(runtime.normalizeFlashPreview(Object.assign({}, valid, {height:600})), null);
  assert.strictEqual(runtime.normalizeFlashPreview(Object.assign({}, valid, {source:"live_capture"})), null);
  assert.strictEqual(runtime.normalizeFlashPreview(Object.assign({}, valid, {dataUrl:"https://example.invalid/a.jpg"})), null);
});

test("snapshot keeps a structurally valid duplicate legacy table open for repair", () => {
  const legacyKeys = runtime.copy(keys);
  legacyKeys[34].keyCode = legacyKeys[33].keyCode;
  const model = runtime.normalizeSnapshot({
    success:true, v:1, revision:5, settings, keys:legacyKeys,
    defaultKeys:keys.map(row => ({id:row.id,keyCode:row.keyCode})),
    allowedKeyCodes:allowed, hostPrefs:{introEnabled:false,sfxEnabled:true,ambientEnabled:false,
      uiFontScale:1.35,mapDisplayPreference:"auto"}, challengeMode:false,
    modeLabel:"困难", cheatHelp:[], forceControls:{}, previewActive:false
  });
  assert(model);
  assert.strictEqual(runtime.validateKeyDraft(model.keys, model.allowedKeyCodes).error, "key_conflict");
});

test("request mux binds exact instance and correlates one response", () => {
  const sent = [];
  const callbacks = [];
  const timers = [];
  const mux = new runtime.RequestMux({
    send(message) { sent.push(message); return true; },
    setTimer(fn) { timers.push(fn); return timers.length; },
    clearTimer() {}
  });
  assert.strictEqual(mux.openSession("settings.instance.harness"), true);
  const id = mux.request("snapshot", {v:1}, {}, response => callbacks.push(response));
  assert(id);
  assert.strictEqual(sent[0].domain, "settings");
  assert.strictEqual(sent[0].panelInstanceId, "settings.instance.harness");
  assert.strictEqual(sent[0].payload.v, 1);
  assert.strictEqual(mux.handleResponse({type:"panel_resp", domain:"settings", cmd:"snapshot",
    callId:id, panelInstanceId:"settings.instance.old", success:true}), false);
  assert.strictEqual(mux.handleResponse({type:"panel_resp", domain:"settings", cmd:"snapshot",
    callId:id, panelInstanceId:"settings.instance.harness", success:true}), true);
  assert.strictEqual(callbacks.length, 1);
  mux.destroy();
});

test("request mux marks only dispatched non-preview client timeouts for reconcile", () => {
  const timers = [];
  const callbacks = [];
  let sendResult = true;
  const mux = new runtime.RequestMux({
    send() { return sendResult; },
    setTimer(fn) { timers.push(fn); return timers.length; },
    clearTimer() {}
  });
  assert.strictEqual(mux.openSession("settings.instance.timeout"), true);
  ["apply", "cancel", "save", "cheat", "return_base", "try_revive", "host_set"].forEach(cmd => {
    const timerIndex = timers.length;
    assert(mux.request(cmd, {v:1}, {kind:"timeout." + cmd}, response => callbacks.push(response)));
    timers[timerIndex]();
    const response = callbacks[callbacks.length - 1];
    assert.strictEqual(response.error, "client_timeout");
    assert.strictEqual(response.requiresReconcile, true, cmd);
  });
  ["snapshot", "preview"].forEach(cmd => {
    const timerIndex = timers.length;
    assert(mux.request(cmd, {v:1}, {kind:"timeout." + cmd}, response => callbacks.push(response)));
    timers[timerIndex]();
    const response = callbacks[callbacks.length - 1];
    assert.strictEqual(response.error, "client_timeout");
    assert.strictEqual(response.requiresReconcile, undefined, cmd);
  });
  sendResult = false;
  assert(mux.request("apply", {v:1}, {kind:"not-sent"}, response => callbacks.push(response)));
  const notSent = callbacks[callbacks.length - 1];
  assert.strictEqual(notSent.error, "not_sent");
  assert.strictEqual(notSent.requiresReconcile, undefined);
  assert.strictEqual(mux.debugState().pendingCount, 0);
  mux.destroy();
});

test("central Web preferences reuse shipped storage keys and reject unknown values", () => {
  const state = Object.create(null);
  const storage = {
    getItem(key) { return Object.prototype.hasOwnProperty.call(state, key) ? state[key] : null; },
    setItem(key, value) { state[key] = String(value); },
    removeItem(key) { delete state[key]; }
  };
  const rows = preferences.list(storage);
  assert(rows.some(row => row.key === "cf7.skills.loadoutConfirmationMode"));
  assert(rows.some(row => row.key === "cf7.equipmentTuning.modConfirmationMode"));
  assert(rows.some(row => row.key === "cf7.dialogueMode"));
  assert(rows.some(row => row.key === "cf7-jukebox-theme"));
  assert(rows.some(row => row.key === "cf7.itemgrid.mode.arena"));
  assert(rows.some(row => row.key === "cf7.gobang.audio.muted"));
  assert.strictEqual(preferences.read("cf7.itemgrid.mode.workbench", storage), "compact");
  assert.strictEqual(preferences.read("cf7.itemgrid.mode.crafting-recipes", storage), "full");
  assert.strictEqual(preferences.read("cf7.gobang.audio.muted", storage), "0");
  assert.strictEqual(preferences.write("cf7.itemgrid.mode.workbench", "compact", storage), true);
  assert.strictEqual(preferences.read("cf7.itemgrid.mode.workbench", storage), "compact");
  assert.strictEqual(preferences.write("cf7.itemgrid.mode.workbench", "tiny", storage), false);
});

test("panel keeps cheat bridge internal and exposes only agreed rescue controls", () => {
  const panel = fs.readFileSync(path.join(root, "launcher/web/modules/settings-panel.js"), "utf8");
  assert(panel.includes("function onOpen(el, initData)"));
  assert(panel.includes("onRebind:onRebind"));
  assert(!panel.includes("/console"));
  assert(panel.includes("try_revive"));
  assert(panel.includes("return_base"));
  assert(!panel.includes("safe_exit"));
  assert(!panel.includes("一键回血"));
  assert(!panel.includes("一键无敌"));
  assert(panel.includes("settings-terminal-shell settings-panel"));
  assert(!panel.includes("workbench-shell settings-panel"));
  assert(panel.includes("settings-camera-preview"));
  assert(panel.includes("settings-camera-modal"));
  assert(panel.includes("_init.initialView === 'camera_preview'"));
  assert(panel.includes("openCameraSimulator(cameraTrigger)"));
  assert(panel.includes("打开镜头预览"));
  assert(panel.includes("作弊码帮助"));
  assert(panel.includes("settings-copy-command"));
  assert(panel.includes("sendTool('return_base',{v:1},true)"));
  assert(!panel.includes("confirmThen('return_base'"));
  assert(!panel.includes("Panels.close()"));
  assert(panel.includes("正在等待 Host 确认关闭"));
  assert(panel.includes("function reconcileUnknownWrite(message)"));
  assert(panel.includes("_requiresReconcile = true"));
  assert(panel.includes("写入状态等待权威核对"));
  assert(panel.includes("权威状态读取失败，写入仍保持锁定"));
  assert(panel.includes("该权威快照早于未决写入终态，写入仍保持锁定；请重新读取。"));
  assert(panel.includes("_mux.closeSession()"));
  assert(!panel.includes("_generation"));
  assert(panel.includes("保存结果未知，正在重新读取游戏权威状态；不会自动重试。"));
  assert(panel.includes("关闭前试听恢复结果未知，正在重新读取权威状态；面板保持打开。"));
  assert(panel.includes("本机偏好结果未知，正在重新读取权威状态；不会自动重试。"));
  const tokens = fs.readFileSync(path.join(root, "launcher/web/css/workbench/tokens.css"), "utf8");
  const welcome = fs.readFileSync(path.join(root, "launcher/web/css/welcome.css"), "utf8");
  const settingsCss = fs.readFileSync(path.join(root, "launcher/web/css/settings-panel.css"), "utf8");
  assert(tokens.includes("--launcher-rust:") && tokens.includes("--launcher-bone:"));
  assert(welcome.includes("--rust: var(--launcher-rust)"));
  assert(/--settings-rust\s*:\s*var\(--launcher-rust\)/.test(settingsCss));
  assert(settingsCss.includes(".settings-key-board"));
  assert(settingsCss.includes(".settings-camera-simulator-body"));
  assert(settingsCss.includes(".settings-camera-simulator-viewport img"));
  assert(/object-fit\s*:\s*cover/.test(settingsCss));
});

test("three setting pages share the launcher header and annotations use PanelTooltip", () => {
  const panel = fs.readFileSync(path.join(root, "launcher/web/modules/settings-panel.js"), "utf8");
  const css = fs.readFileSync(path.join(root, "launcher/web/css/settings-panel.css"), "utf8");
  const build = panel.slice(panel.indexOf("function buildDOM()"), panel.indexOf("function requestSnapshot()"));
  assert(build.includes("[['game','游戏'],['keys','键位'],['local','本机与 Web']]"));
  assert(!build.includes("'tools'"));
  assert(/header\.appendChild\(tabs\)[\s\S]*header\.appendChild\(_status\)/.test(build));
  assert(!build.includes("_root.appendChild(tabs)"));
  assert(/grid-template-rows\s*:\s*62px\s+minmax\(0\s*,\s*1fr\)\s+52px/.test(css));
  assert(panel.includes("PanelTooltip.createScope('settings', {profile:'simple-tooltip'})"));
  assert(panel.includes("_tooltipScope.bindAsync"));
  assert(panel.includes("target.removeAttribute('title')"));
  assert(css.includes(".settings-simple-tooltip"));
});

test("rescue is in the default view and jukebox rules are grouped with local Web settings", () => {
  const panel = fs.readFileSync(path.join(root, "launcher/web/modules/settings-panel.js"), "utf8");
  const game = panel.slice(panel.indexOf("function renderGame()"), panel.indexOf("function volumeField"));
  const local = panel.slice(panel.indexOf("function renderLocal()"), panel.indexOf("function hostBoolean"));
  assert(game.indexOf("renderRescueControls()") >= 0);
  assert(game.indexOf("renderRescueControls()") < game.indexOf("声音试听"));
  assert(!game.includes("点歌器运行规则"));
  assert(local.includes("点歌器运行规则"));
  const foundation = fs.readFileSync(path.join(root, "launcher/web/css/panels/foundation-rest.css"), "utf8");
  assert(foundation.includes('#panel-container[data-panel="settings"] #panel-content'));
});

test("frequent cheat entry is available on the game home without taking modifier shortcuts", () => {
  const panel = fs.readFileSync(path.join(root, "launcher/web/modules/settings-panel.js"), "utf8");
  const game = panel.slice(panel.indexOf("function renderGame()"), panel.indexOf("function volumeField"));
  const form = panel.slice(panel.indexOf("function cheatCommandForm"), panel.indexOf("function rescueCard"));
  assert(game.includes("cheatCommandForm()"));
  assert(game.includes("gameBand('作弊码', 'COMMAND LINK'"));
  assert(form.includes("settings-home-cheat"));
  assert(form.includes("再次点击确认执行命令"));
  assert(form.includes("作弊码帮助"));
  assert(!game.includes("一键回血") && !game.includes("一键无敌") && !game.includes("一键升级"));
});

test("camera simulator applies fixed basic scale even when dynamic camera adjustment is off", () => {
  const panel = fs.readFileSync(path.join(root, "launcher/web/modules/settings-panel.js"), "utf8");
  const update = panel.slice(panel.indexOf("function updateCameraPreview()"), panel.indexOf("function volumeField"));
  const simulator = panel.slice(panel.indexOf("function openCameraSimulator"), panel.indexOf("function openCheatHelp"));
  assert(update.includes("var relativeScale = scale / baseline"));
  assert(!update.includes("cameraZoomToggle === true\n            ? Number"));
  assert(update.includes("固定基础倍率"));
  assert(simulator.includes("动态镜头调节"));
  assert(simulator.includes("关闭时仍使用固定基础倍率"));
});

test("maintained cheat help covers every implemented command and challenge disclosure boundary", () => {
  const source = fs.readFileSync(path.join(root, "scripts/引擎/引擎_aka_作弊码.as"), "utf8");
  const markdown = fs.readFileSync(path.join(root, "launcher/web/help/cheat-codes.md"), "utf8");
  const commands = Array.from(source.matchAll(/cheatFunction\.([A-Za-z0-9_]+)\s*=/g), match => match[1])
    .filter((value, index, all) => all.indexOf(value) === index);
  commands.forEach(command => assert(markdown.includes("`" + command + "`"), "missing command " + command));
  const prefixes = Array.from(source.matchAll(/indexOf\("(#[^"]+)"\)>-1/g), match => match[1])
    .filter((value, index, all) => all.indexOf(value) === index)
    .concat("..");
  prefixes.forEach(prefix => assert(markdown.includes(prefix), "missing prefix " + prefix));
  markdown.split(/\r?\n/).filter(line => /^- `/.test(line)).forEach(line => {
    assert.strictEqual((line.match(/`/g) || []).length, 2, "one copyable command per help row: " + line);
  });
  assert(markdown.includes("`#level:15`"));
  assert(!markdown.includes("/console"));
  const challenge = runtime.selectCheatHelpMarkdown(markdown, true);
  assert(challenge.includes("hardmode") && challenge.includes("easymode") && challenge.includes("challengemode"));
  assert(!challenge.includes("#level:15") && !challenge.includes("status") && !challenge.includes("heal"));
  assert.strictEqual(runtime.selectCheatHelpMarkdown(markdown, false), markdown);
});

test("aggregated preferences are re-read by long-lived panels on reopen", () => {
  const skills = fs.readFileSync(path.join(root, "launcher/web/modules/skills.js"), "utf8");
  const tasks = fs.readFileSync(path.join(root, "launcher/web/modules/tasks/task-panel.js"), "utf8");
  const jukebox = fs.readFileSync(path.join(root, "launcher/web/modules/jukebox/jukebox-panel.js"), "utf8");
  const arena = fs.readFileSync(path.join(root, "launcher/web/modules/arena/arena-shell.js"), "utf8");
  const gobang = fs.readFileSync(path.join(root, "launcher/web/modules/minigames/gobang/gobang-panel.js"), "utf8");
  assert(/function beginOpen\(initData\)[\s\S]*?_loadoutConfirmationMode = readLoadoutConfirmationMode\(\)/.test(skills));
  assert(/function onOpen\(el, initData\)[\s\S]*?localStorage\.getItem\('cf7\.dialogueMode'\)/.test(tasks));
  assert(/function onOpen\(\)[\s\S]*?applyTheme\(loadTheme\(\)\)/.test(jukebox));
  assert(/function onOpen\(el, initData\)[\s\S]*?ItemGrid\.getLayoutMode\('arena'/.test(arena));
  assert(/function onOpen\(el, initData\)[\s\S]*?reloadPreference\(\)/.test(gobang));
});

process.stdout.write("Settings panel harness: " + passed + "/" + passed + " passed\n");
