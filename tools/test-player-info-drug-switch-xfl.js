#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const xflRoot = path.join(repoRoot, "flashswf", "UI", "玩家信息界面");

function read(relativePath) {
  return fs
    .readFileSync(path.join(xflRoot, relativePath), "utf8")
    .replace(/^\uFEFF/, "");
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function parseAttributes(source) {
  const result = {};
  const pattern = /([:\w-]+)="([^"]*)"/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    result[match[1]] = match[2];
  }
  return result;
}

function countMatches(source, pattern) {
  return [...source.matchAll(pattern)].length;
}

function layerBlock(source, name) {
  const startMarker = `<DOMLayer name="${name}"`;
  const start = source.indexOf(startMarker);
  assert.notStrictEqual(start, -1, `missing layer: ${name}`);
  const openEnd = source.indexOf(">", start);
  assert.notStrictEqual(openEnd, -1, `unterminated layer opening tag: ${name}`);
  const close = source.indexOf("</DOMLayer>", openEnd);
  assert.notStrictEqual(close, -1, `unterminated layer: ${name}`);
  return source.slice(start, close + "</DOMLayer>".length);
}

function frameBlock(source, index) {
  const pattern = new RegExp(`<DOMFrame\\b[^>]*\\bindex="${index}"[^>]*>`);
  const match = pattern.exec(source);
  assert.ok(match, `missing frame: ${index}`);
  const close = source.indexOf("</DOMFrame>", match.index);
  assert.notStrictEqual(close, -1, `unterminated frame: ${index}`);
  return source.slice(match.index, close + "</DOMFrame>".length);
}

function instanceBlock(source, name) {
  const pattern = new RegExp(
    `<DOMSymbolInstance\\b[^>]*\\bname="${escapeRegExp(name)}"[^>]*>`,
  );
  const match = pattern.exec(source);
  assert.ok(match, `missing instance: ${name}`);
  const close = source.indexOf("</DOMSymbolInstance>", match.index);
  assert.notStrictEqual(close, -1, `unterminated instance: ${name}`);
  return source.slice(match.index, close + "</DOMSymbolInstance>".length);
}

function instanceAttributes(block) {
  const match = block.match(/^<DOMSymbolInstance\b([^>]*)>/);
  assert.ok(match, "missing DOMSymbolInstance opening tag");
  return parseAttributes(match[1]);
}

function matrixAttributes(block) {
  const match = block.match(/<Matrix\b([^>]*)\/>/);
  assert.ok(match, "missing Matrix");
  return parseAttributes(match[1]);
}

function namedInstances(layer) {
  return [...layer.matchAll(/<DOMSymbolInstance\b([^>]*)>/g)]
    .map((match) => parseAttributes(match[1]).name)
    .filter(Boolean);
}

function assertInstance(layer, contract) {
  const block = instanceBlock(layer, contract.name);
  const attrs = instanceAttributes(block);
  const matrix = matrixAttributes(block);
  assert.strictEqual(attrs.libraryItemName, contract.libraryItemName, `${contract.name} library item`);
  assert.strictEqual(attrs.centerPoint3DX, contract.centerPoint3DX, `${contract.name} centerPoint3DX`);
  assert.strictEqual(attrs.centerPoint3DY, contract.centerPoint3DY, `${contract.name} centerPoint3DY`);
  assert.strictEqual(matrix.tx, contract.tx, `${contract.name} tx`);
  assert.strictEqual(matrix.ty, contract.ty, `${contract.name} ty`);
  return block;
}

const domDocument = read("DOMDocument.xml");
const quickHud = read(path.join("LIBRARY", "sprite", "快捷药剂界面.xml"));
const switchIcon = read(path.join("LIBRARY", "sprite", "药剂组切换图标.xml"));
const playerInfo = read(path.join("LIBRARY", "玩家信息界面.xml"));
const controllerSymbol = read(path.join("LIBRARY", "sprite", "药剂控制器.xml"));

const includePattern = /<Include\b[^>]*href="sprite\/药剂组切换图标\.xml"[^>]*\/>/g;
const includes = [...domDocument.matchAll(includePattern)];
assert.strictEqual(includes.length, 1, "switch icon Include must occur exactly once");
const includeAttrs = parseAttributes(includes[0][0]);
assert.strictEqual(includeAttrs.itemID, "68b16f5a-2a4c8d11", "switch icon Include itemID");
assert.strictEqual(
  countMatches(domDocument, /itemID="68b16f5a-2a4c8d11"/g),
  1,
  "switch icon itemID must be unique in DOMDocument",
);

const switchRootMatch = switchIcon.match(/^<DOMSymbolItem\b([^>]*)>/);
assert.ok(switchRootMatch, "switch icon DOMSymbolItem root");
const switchRootAttrs = parseAttributes(switchRootMatch[1]);
assert.strictEqual(switchRootAttrs.name, "sprite/药剂组切换图标", "switch icon symbol name");
assert.strictEqual(switchRootAttrs.itemID, "68b16f5a-2a4c8d11", "switch icon symbol itemID");
assert.doesNotMatch(switchIcon, /linkage(?:ExportForAS|Identifier|ClassName)=/, "switch icon must have no linkage");
assert.doesNotMatch(switchIcon, /libraryItemName=/, "switch icon must be self-contained");

const labelLayer = layerBlock(switchIcon, "Labels Layer");
const scriptLayer = layerBlock(switchIcon, "Script Layer");
const visualLayer = layerBlock(switchIcon, "图形");
assert.deepStrictEqual(
  [...labelLayer.matchAll(/<DOMFrame\b[^>]*index="(\d+)"[^>]*name="([^"]+)"/g)].map((match) => [match[1], match[2]]),
  [["0", "I"], ["1", "II"]],
  "switch icon frame labels",
);
assert.deepStrictEqual(
  [...scriptLayer.matchAll(/<DOMFrame\b[^>]*index="(\d+)"/g)].map((match) => match[1]),
  ["0", "1"],
  "switch icon script frames",
);
assert.strictEqual(countMatches(scriptLayer, /<!\[CDATA\[stop\(\);\s*\]\]>/g), 2, "each switch frame must stop");
assert.deepStrictEqual(
  [...visualLayer.matchAll(/<characters>([^<]+)<\/characters>/g)].map((match) => match[1]),
  ["1", "2"],
  "switch icon visible states",
);
const firstBankVisual = frameBlock(visualLayer, 0);
const secondBankVisual = frameBlock(visualLayer, 1);
assert.strictEqual(countMatches(firstBankVisual, /<DOMShape>/g), 1, "bank I has one self-contained circle shape");
assert.strictEqual(countMatches(secondBankVisual, /<DOMShape>/g), 1, "bank II has one self-contained cross shape");
assert.strictEqual(countMatches(firstBankVisual, /<Edge\b/g), 1, "bank I circle is one continuous vector edge");
assert.strictEqual(countMatches(secondBankVisual, /<Edge\b/g), 1, "bank II cross is one vector edge");
assert.match(
  firstBankVisual,
  /<Edge strokeStyle="1" edges="!-90 -190\[10 -190 10 -90!10 -90\[10 10 -90 10!-90 10\[-190 10 -190 -90!-190 -90\[-190 -190 -90 -190"\/>/,
  "bank I uses the accepted bounded four-segment curve circle",
);
assert.match(
  secondBankVisual,
  /<Edge strokeStyle="1" edges="!-180 -180\|0 0!-180 0\|0 -180"\/>/,
  "bank II uses the bounded diagonal cross",
);
assert.strictEqual(countMatches(visualLayer, /<SolidStroke scaleMode="normal" weight="1\.8">/g), 2, "circle and cross share a low-resolution stroke weight");
assert.strictEqual(countMatches(visualLayer, /<SolidColor color="#F7FAFC"\/>/g), 2, "circle and cross share one neutral shape color");
assert.doesNotMatch(visualLayer, /fillStyle[01]=/, "circle and cross remain outline-only rather than implying enabled versus disabled");
const textStyles = [...visualLayer.matchAll(/<DOMTextAttrs\b([^>]*)\/>/g)].map((match) => parseAttributes(match[1]));
assert.strictEqual(textStyles.length, 2, "one visible text run per switch state");
assert.deepStrictEqual(textStyles[0], textStyles[1], "1 and 2 must use the same visual style");
assert.strictEqual(textStyles[0].fillColor, "#FFD45A", "numeric bank labels share one high-contrast accent");
assert.strictEqual(textStyles[0].face, "MicrosoftYaHei", "switch state font");
assert.strictEqual(textStyles[0].size, "13", "switch state font size");

const numberLayer = layerBlock(quickHud, "数字");
const cooldownLayer = layerBlock(quickHud, "冷却条");
const slotLayer = layerBlock(quickHud, "快捷边框与内部");
const backgroundLayer = layerBlock(quickHud, "纯图形");
assert.deepStrictEqual(
  namedInstances(numberLayer),
  ["控制器4", "控制器0", "控制器1", "控制器2", "控制器3"],
  "controller z-order and columns",
);
assert.deepStrictEqual(
  namedInstances(cooldownLayer),
  ["进度条4", "进度条0", "进度条1", "进度条2", "进度条3"],
  "cooldown z-order and columns",
);
assert.deepStrictEqual(
  namedInstances(slotLayer),
  ["药剂组切换图标", "位置示意0", "位置示意1", "位置示意2", "位置示意3"],
  "slot z-order and columns",
);
assert.doesNotMatch(quickHud, /name="位置示意4"/, "the fifth item anchor must be removed");
assert.strictEqual(
  countMatches(quickHud, /libraryItemName="sprite\/药剂组切换图标"/g),
  1,
  "switch icon must be directly placed exactly once",
);

const controllerContracts = [
  ["控制器4", "20.6", "27.95", "28.75", "38.85"],
  ["控制器0", "55.5", "27.95", "63.65", "38.85"],
  ["控制器1", "90.4", "27.95", "98.55", "38.85"],
  ["控制器2", "125.3", "27.95", "133.45", "38.85"],
  ["控制器3", "160", "27.95", "168.15", "38.85"],
];
for (const [name, tx, ty, centerPoint3DX, centerPoint3DY] of controllerContracts) {
  assertInstance(numberLayer, {
    name,
    libraryItemName: "sprite/药剂控制器",
    tx,
    ty,
    centerPoint3DX,
    centerPoint3DY,
  });
}

const cooldownContracts = [
  ["进度条4", "20.6", "6.75", "33.35", "19.6"],
  ["进度条0", "55.5", "6.75", "68.25", "19.6"],
  ["进度条1", "90.4", "6.75", "103.15", "19.6"],
  ["进度条2", "125.3", "6.75", "138.05", "19.6"],
  ["进度条3", "160", "6.75", "172.75", "19.6"],
];
for (const [name, tx, ty, centerPoint3DX, centerPoint3DY] of cooldownContracts) {
  assertInstance(cooldownLayer, {
    name,
    libraryItemName: "sprite/Symbol 1791",
    tx,
    ty,
    centerPoint3DX,
    centerPoint3DY,
  });
}

const slotContracts = [
  ["药剂组切换图标", "sprite/药剂组切换图标", "20.5", "6.55", "33.8", "20.7"],
  ["位置示意0", "sprite/物品栏/物品图标位置示意", "55.4", "6.55", "68.7", "20.7"],
  ["位置示意1", "sprite/物品栏/物品图标位置示意", "90.3", "6.55", "103.6", "20.7"],
  ["位置示意2", "sprite/物品栏/物品图标位置示意", "125.2", "6.55", "138.5", "20.7"],
  ["位置示意3", "sprite/物品栏/物品图标位置示意", "159.9", "6.55", "173.2", "20.7"],
];
for (const [name, libraryItemName, tx, ty, centerPoint3DX, centerPoint3DY] of slotContracts) {
  assertInstance(slotLayer, { name, libraryItemName, tx, ty, centerPoint3DX, centerPoint3DY });
}

const controller4 = instanceBlock(numberLayer, "控制器4");
assert.match(controller4, /扳机键 = "药剂组切换键";/, "controller4 switch key parameter");
assert.match(controller4, /控制参数 = "药剂组切换图标";/, "controller4 switch target parameter");
assert.match(controller4, /控制参数2 = "进度条4";/, "controller4 cooldown parameter");
assert.doesNotMatch(quickHud, /快捷物品栏键5/, "legacy fifth-slot key must not survive");
assert.match(controllerSymbol, /this\.药剂栏 = _parent\[控制参数\];/, "controller resolves configured projection target");
assert.match(controllerSymbol, /this\.药剂进度条 = _parent\[控制参数2\];/, "controller resolves configured cooldown target");

const backgroundBlocks = [...backgroundLayer.matchAll(
  /<DOMSymbolInstance\b[^>]*libraryItemName="UI重构\/快捷道具格子"[^>]*>[\s\S]*?<\/DOMSymbolInstance>/g,
)].map((match) => match[0]);
assert.strictEqual(backgroundBlocks.length, 5, "five slot backgrounds must remain");
assert.deepStrictEqual(
  backgroundBlocks.map((block) => {
    const matrix = matrixAttributes(block);
    return [matrix.tx, matrix.ty];
  }),
  [["20.55", "6.7"], ["55.45", "6.7"], ["90.35", "6.7"], ["125.25", "6.7"], ["160.15", "6.7"]],
  "slot backgrounds must not move",
);

const playerInfoQuickHud = instanceBlock(playerInfo, "快捷药剂界面");
assert.strictEqual(instanceAttributes(playerInfoQuickHud).libraryItemName, "sprite/快捷药剂界面", "parent HUD symbol");
assert.deepStrictEqual(matrixAttributes(playerInfoQuickHud), { tx: "301.4", ty: "29.8" }, "parent HUD anchor");

console.log("[PASS] PlayerInfo drug-switch XFL contract: direct no-linkage circle/cross plus 1/2, fixed five-column layout, and controller parameters");
