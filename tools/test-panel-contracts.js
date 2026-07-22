#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const validator = require("./validate-panel-contracts");

const ROOT = path.resolve(__dirname, "..");
const CONTRACT_PATH = path.join(ROOT, validator.DEFAULT_CONTRACT);

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertError(report, code) {
  assert(!report.ok, "mutation unexpectedly passed validation");
  assert(report.errors.some(function (error) { return error.code === code; }),
    "expected error code " + code + ", got " + report.errors.map(function (error) { return error.code; }).join(", "));
}

function replaceOnce(source, pattern, replacement, label) {
  const mutated = source.replace(pattern, replacement);
  assert(mutated !== source, "mutation fixture did not match " + label);
  return mutated;
}

function read(relativePath) {
  return fs.readFileSync(path.join(ROOT, relativePath), "utf8");
}

function run() {
  const contract = JSON.parse(fs.readFileSync(CONTRACT_PATH, "utf8"));
  const tests = [];

  function test(name, body) {
    try {
      body();
      tests.push({ name: name, ok: true });
    } catch (error) {
      tests.push({ name: name, ok: false, error: error.message });
    }
  }

  test("baseline repository contract passes", function () {
    const report = validator.validateRepository({ root: ROOT, contract: clone(contract) });
    assert(report.ok, JSON.stringify(report.errors));
    assert(report.checked.domains === 3, "expected three governed domains");
    assert(report.checked.commands === 19, "expected nineteen governed command mappings");
  });

  test("shared boundary vectors expose stable consumer paths", function () {
    const npc = contract.vectors.npcshop.purchaseQuantity;
    const crafting = contract.vectors.crafting.craftCount;
    const kshop = contract.vectors.kshop.purchaseQuantity;
    assert(JSON.stringify(npc.valid) === JSON.stringify([1, 99, 100, 101, 4549, 999999]), "npcshop valid vector drift");
    assert(JSON.stringify(npc.invalid) === JSON.stringify([0, 1000000]), "npcshop invalid vector drift");
    assert(JSON.stringify(crafting.valid) === JSON.stringify([1, 99]), "crafting valid vector drift");
    assert(JSON.stringify(crafting.invalid) === JSON.stringify([100]), "crafting invalid vector drift");
    assert(JSON.stringify(kshop.valid) === JSON.stringify(npc.valid), "kshop stack vector must match npcshop technical semantics");
    assert(JSON.stringify(kshop.invalid) === JSON.stringify(npc.invalid), "kshop invalid stack vector must match npcshop technical semantics");
    assert(npc.payloadPath === "quantity" && crafting.payloadPath === "craftCount" && kshop.payloadPath === "cart[].qty",
      "consumer payload paths drifted");
  });

  test("unknown schema properties fail closed", function () {
    const fixture = clone(contract);
    fixture.uncontractedPolicy = true;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "schema.unknown_key");
  });

  test("duplicate commands are rejected", function () {
    const fixture = clone(contract);
    fixture.domains[0].commands.push(clone(fixture.domains[0].commands[0]));
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.duplicate_cmd");
  });

  test("dynamic business maximum cannot become a Host fixed cap", function () {
    const fixture = clone(contract);
    const boundary = fixture.domains[0].numericFields[0].boundaries.find(function (entry) {
      return entry.name === "effective-maximum";
    });
    boundary.hostEnforcement = "fixed";
    boundary.value = 100;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.dynamic_host_cap");
  });

  test("required NPC large-quantity corpus cannot be silently removed", function () {
    const fixture = clone(contract);
    fixture.vectors.npcshop.purchaseQuantity.valid = fixture.vectors.npcshop.purchaseQuantity.valid.filter(function (value) {
      return value !== 4549;
    });
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.required_vector");
  });

  test("old NpcShop Host 1..100 cap mutation is detected", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const mutated = replaceOnce(read(file), /(\bMaxPurchaseQuantity\s*=\s*)999999(\s*;)/,
      function (_match, prefix, suffix) { return prefix + "100" + suffix; }, "NpcShopTask MaxPurchaseQuantity");
    assert(/\bMaxPurchaseQuantity\s*=\s*100\s*;/.test(mutated), "old Host 1..100 fixture was not constructed");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_const_drift");
  });

  test("NpcShop AS2 technical ceiling mutation is detected", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const mutated = replaceOnce(read(file),
      /(\bvar\s+technicalLimit:Number\s*=\s*equipment\s*\?[^:;]+\s*:\s*)999999(\s*;)/,
      function (_match, prefix, suffix) { return prefix + "100" + suffix; }, "NpcShop AS2 technicalLimit");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.as2_ternary_drift");
  });

  test("Crafting AS2 protocol maximum mutation is detected", function () {
    const file = "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as";
    const mutated = replaceOnce(read(file), /(\bMAX_CRAFT_COUNT:Number\s*=\s*)99(\s*;)/,
      function (_match, prefix, suffix) { return prefix + "100" + suffix; }, "Crafting MAX_CRAFT_COUNT");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.as2_assignment_drift");
  });

  test("KShop AS2 stack technical ceiling mutation is detected", function () {
    const file = "scripts/逻辑系统分区/商城系统_WebView.as";
    const mutated = replaceOnce(read(file), /(\bmaxStackPurchaseQuantity\s*=\s*)999999(\s*;)/,
      function (_match, prefix, suffix) { return prefix + "100" + suffix; }, "KShop maxStackPurchaseQuantity");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.as2_assignment_drift");
  });

  test("KShop Host passthrough cannot acquire a fixed quantity guard", function () {
    const file = "launcher/src/Tasks/ShopTask.cs";
    const mutated = replaceOnce(read(file),
      /(\s+)(var flashMsg = PanelBridge\.BuildFlashCommand\(action, fid, parsed\);)/,
      function (_match, whitespace, buildLine) {
        return whitespace + "TryReadInteger(parsed[\"quantity\"], 1, 100, out ignored);" + whitespace + buildLine;
      },
      "ShopTask passthrough insertion");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_passthrough_guard");
  });

  test("C# cmd to action mapping drift is detected", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const mutated = replaceOnce(read(file),
      /(case\s+"buy"\s*:\s*action\s*=\s*")npcShopBuy("\s*;)/,
      function (_match, prefix, suffix) { return prefix + "npcShopBuyDrift" + suffix; }, "NpcShop buy action");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_action_drift");
  });

  test("Flash response task drift is detected across AS2 and TaskRegistry", function () {
    const fixture = clone(contract);
    fixture.domains[0].flashResponseTask = "npcshop_response_drift";
    const report = validator.validateRepository({ root: ROOT, contract: fixture });
    assertError(report, "source.flash_response_task_drift");
    assertError(report, "source.csharp_response_task_drift");
  });

  test("TaskRegistry response handler cross-binding is detected", function () {
    const file = "launcher/src/Bus/TaskRegistry.cs";
    const mutated = replaceOnce(read(file),
      /(router\.RegisterAsync\s*\(\s*["']npcshop_response["']\s*,\s*)npcShopTask\.HandleFlashResponse(\s*\))/,
      function (_match, prefix, suffix) { return prefix + "craftingTask.HandleFlashResponse" + suffix; },
      "NpcShop TaskRegistry response handler");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_response_task_drift");
  });

  test("TaskRegistry duplicate cross-handler binding is detected", function () {
    const file = "launcher/src/Bus/TaskRegistry.cs";
    const source = read(file);
    const anchor = 'router.RegisterAsync("npcshop_response", npcShopTask.HandleFlashResponse);';
    assert(source.includes(anchor), "NpcShop TaskRegistry registration anchor is missing");
    const mutated = source.replace(anchor, anchor + '\n                router.RegisterAsync("npcshop_response", craftingTask.HandleFlashResponse);');
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_response_task_drift");
  });

  test("commented Flash registrations are not executable contract evidence", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const mutated = replaceOnce(read(file),
      /^(\s*)(_root\.gameCommands\["npcShopTradePreview"\][^\r\n]*)$/m,
      function (_match, indent, registration) { return indent + "// " + registration; },
      "NpcShop AS2 commented registration");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_action_drift");
  });

  test("commented TaskRegistry bindings are not executable contract evidence", function () {
    const file = "launcher/src/Bus/TaskRegistry.cs";
    const mutated = replaceOnce(read(file),
      /^(\s*)(router\.RegisterAsync\("npcshop_response",\s*npcShopTask\.HandleFlashResponse\);)$/m,
      function (_match, indent, registration) { return indent + "// " + registration; },
      "NpcShop commented TaskRegistry registration");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_response_task_drift");
  });

  const failed = tests.filter(function (entry) { return !entry.ok; }).length;
  return {
    tool: "test-panel-contracts",
    ok: failed === 0,
    summary: { total: tests.length, passed: tests.length - failed, failed: failed },
    tests: tests
  };
}

const report = run();
process.stdout.write(JSON.stringify(report, null, 2) + "\n");
process.exitCode = report.ok ? 0 : 1;
