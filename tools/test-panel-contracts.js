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
    assert(report.contractVersion === 2, "expected strict panel contract v2");
    assert(report.checked.domains === 4, "expected four governed domains");
    assert(report.checked.commands === 21, "expected twenty-one governed command mappings");
    const hairdresser = contract.domains.find(function (domain) {
      return domain.id === "hairdresser";
    });
    assert(hairdresser && hairdresser.hostPayloadMode === "normalized",
      "F3 hairdresser domain must use the normalized Host boundary");
    assert(hairdresser.commands.length === 2
      && hairdresser.commands[0].cmd === "snapshot"
      && hairdresser.commands[1].cmd === "commit",
      "hairdresser must expose only the frozen snapshot/commit pair");
    assert(hairdresser.numericFields.length === 0
      && hairdresser.sourceChecks.length === 0
      && !contract.vectors.hairdresser,
      "hairdresser must not invent numeric boundaries or filler vectors");
  });

  test("hairdresser AS2 opener is Web-only and retired renderer cannot return", function () {
    const service = read("scripts/类定义/org/flashNight/arki/ui/HairdresserPanelService.as");
    const install = read("scripts/展现/UI交互/UI交互_lsy_UI管理.as");
    const npc = read(
      "flashswf/levels/基地场景合集/LIBRARY/sprite/理发师/理发师-NPC.xml");
    const uiDocument = read("flashswf/UI/基地特殊UI合集/DOMDocument.xml");
    const uiLibrary = read("flashswf/UI/基地特殊UI合集/LIBRARY/素材库-基地特殊UI.xml");
    const mainDocument = read("CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml");
    assert((service.match(/_root\.gameCommands\["openHairdresser"\]\s*=/g) || []).length === 1,
      "expected one openHairdresser command registration");
    assert(service.includes(
      'org.flashNight.arki.ui.PanelRequestEnvelope.build(\n'
      + '            "hairdresser", "world_hairdresser", [], []\n'
      + "        )"),
      "openHairdresser must emit the exact field-free panel_request");
    assert((install.match(
      /org\.flashNight\.arki\.ui\.HairdresserPanelService\.install\(\);/g) || []).length === 1,
      "production activation must install HairdresserPanelService exactly once");
    assert((npc.match(/_root\.gameCommands\["openHairdresser"\]\(\)/g) || []).length === 1,
      "the production hairdresser NPC must call openHairdresser exactly once");
    assert(!npc.includes("理发店界面") && !npc.includes("if (!opened)"),
      "the production hairdresser NPC must fail closed without the retired renderer");
    assert(!uiDocument.includes('href="理发店界面.xml"')
      && !uiDocument.includes('libraryItemName="理发店界面"')
      && !uiLibrary.includes('libraryItemName="理发店界面"'),
      "the retired renderer must not remain bound into the base UI XFL");
    assert(!fs.existsSync(path.join(
      ROOT, "flashswf/UI/基地特殊UI合集/LIBRARY/理发店界面.xml"))
      && !fs.existsSync(path.join(
        ROOT, "flashswf/UI/基地特殊UI合集/LIBRARY/sprite/Symbol 31.xml")),
      "the retired renderer and 发型TAB linkage sources must be deleted");
    ["改变发型", "预览发型", "恢复发型"].forEach(function (name) {
      assert(!new RegExp("function\\s+" + name + "\\s*\\(").test(mainDocument),
        "retired global function must stay absent: " + name);
    });
    assert((mainDocument.match(
      /_root\.发型 = "发型-男式-黑暴走头";/g) || []).length === 1
      && (mainDocument.match(
        /_root\.发型 = "发型-女式-咖啡色中长马尾";/g) || []).length === 1,
      "new-character male/female default hair writers must remain exact");
    assert((mainDocument.match(/name="界面-发型选择[1-4]"/g) || []).length === 8
      && (mainDocument.match(/控制值 = "发型";/g) || []).length === 2,
      "new-character appearance selectors must remain outside hairdresser cleanup");
  });

  test("hairdresser Web activation remains exact and production-reachable", function () {
    const registry = read("launcher/web/modules/panels-lazy-registry.js");
    const match = registry.match(
      /Panels\.registerLazy\('hairdresser',([\s\S]*?)\n\s*noop\);/);
    assert(match, "hairdresser lazy registration is missing");
    const dependencies = Array.from(match[1].matchAll(/'([^']+\.js)'/g),
      function (entry) { return entry[1]; });
    assert(JSON.stringify(dependencies) === JSON.stringify([
      "modules/panel-runtime.js",
      "modules/asset-timeline.js",
      "modules/dressup-doll-renderer.js",
      "modules/hairdresser-runtime.js",
      "modules/hairdresser.js"
    ]), "hairdresser lazy dependencies must remain minimal and ordered");
    assert(!match[1].includes("panel-scale.js"),
      "boot-loaded PanelScale must not be executed again by the lazy loader");

    const cssFacade = read("launcher/web/css/panels.css");
    assert((cssFacade.match(/@import url\("\.\/hairdresser\.css"\);/g) || []).length === 1,
      "production panels CSS must import hairdresser.css exactly once");
    const harness = read("launcher/web/modules/hairdresser/dev/harness.html");
    assert(!harness.includes('href="/launcher/web/css/hairdresser.css"'),
      "hairdresser harness must exercise the production CSS facade");
  });

  test("transaction previews remain read access without collapsing into queries", function () {
    const previewCommands = [
      contract.domains[0].commands.find(function (command) { return command.cmd === "batchPreview"; }),
      contract.domains[0].commands.find(function (command) { return command.cmd === "tradePreview"; }),
      contract.domains[1].commands.find(function (command) { return command.cmd === "preview"; }),
      contract.domains.find(function (domain) { return domain.id === "kshop"; })
        .commands.find(function (command) { return command.cmd === "checkoutPreview"; })
    ];
    assert(previewCommands.every(function (command) {
      return command && command.capability === "transaction" && command.access === "read";
    }), "token/plan previews must remain transaction/read");
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

  test("v1 manifests cannot silently acquire v2 semantics", function () {
    const fixture = clone(contract);
    fixture.contractVersion = 1;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.version");
  });

  test("command capability is required", function () {
    const fixture = clone(contract);
    delete fixture.domains[0].commands[0].capability;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "schema.missing_key");
  });

  test("command business decision owner is required", function () {
    const fixture = clone(contract);
    delete fixture.domains[0].commands[0].businessDecisionOwner;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "schema.missing_key");
  });

  test("Flash command handler binding is explicit and string-or-null", function () {
    const missing = clone(contract);
    delete missing.domains[0].flashCommandHandler;
    assertError(validator.validateRepository({ root: ROOT, contract: missing }), "schema.missing_key");

    const invalid = clone(contract);
    invalid.domains[0].flashCommandHandler = {};
    assertError(validator.validateRepository({ root: ROOT, contract: invalid }), "schema.string_or_null");
  });

  test("unknown command capability is rejected", function () {
    const fixture = clone(contract);
    fixture.domains[0].commands[0].capability = "stream";
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "schema.enum");
  });

  test("query capability cannot acquire write access", function () {
    const fixture = clone(contract);
    fixture.domains[0].commands[0].access = "write";
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.capability_access_conflict");
  });

  test("business decision owner cannot drift away from AS2", function () {
    const fixture = clone(contract);
    fixture.domains[0].commands[0].businessDecisionOwner = "host";
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }),
      "contract.business_decision_owner_conflict");
  });

  test("duplicate commands are rejected", function () {
    const fixture = clone(contract);
    fixture.domains[0].commands.push(clone(fixture.domains[0].commands[0]));
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.duplicate_cmd");
  });

  test("Flash actions are globally unique across domains", function () {
    const fixture = clone(contract);
    fixture.domains[1].commands[0].action = fixture.domains[0].commands[0].action;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.duplicate_action");
  });

  test("Host response handlers cannot be shared by two domains", function () {
    const fixture = clone(contract);
    fixture.domains[1].hostResponseHandler = fixture.domains[0].hostResponseHandler;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }),
      "contract.duplicate_response_handler");
  });

  test("wire domain and cmd form a globally unique command identity", function () {
    const fixture = clone(contract);
    fixture.domains[1].wireDomain = fixture.domains[0].wireDomain;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.duplicate_wire_cmd");
  });

  test("Host domain guards must match the contracted wire identity", function () {
    const fixture = clone(contract);
    fixture.domains[0].wireDomain = "npcshop_typo";
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }),
      "source.csharp_domain_identity_drift");
  });

  test("reference Host domain guards cannot disappear", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const mutated = replaceOnce(read(file),
      /if\s*\(!string\.Equals\(parsed\.Value<string>\("domain"\),\s*"npcshop",\s*StringComparison\.Ordinal\)\)/,
      "if (false)",
      "NpcShop required domain guard");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_domain_identity_drift");
  });

  test("Host domain guard evidence must come from HandleWebRequest", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    let mutated = replaceOnce(read(file),
      /if\s*\(!string\.Equals\(parsed\.Value<string>\("domain"\),\s*"npcshop",\s*StringComparison\.Ordinal\)\)/,
      "if (false)",
      "NpcShop actual domain guard removal");
    mutated = replaceOnce(mutated,
      /(\s+)(private\s+static\s+bool\s+TryResolveCommand\s*\()/,
      function (_match, whitespace, methodStart) {
        return whitespace
          + "private static void UnusedDomainGuard(JObject parsed)\n"
          + "        {\n"
          + '            if (!string.Equals(parsed.Value<string>("domain"), "npcshop", StringComparison.Ordinal)) return;\n'
          + "        }"
          + whitespace
          + methodStart;
      },
      "NpcShop unused guard decoy");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_domain_identity_drift");
  });

  test("Host domain guard must execute the fail-closed rejection branch", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const mutated = replaceOnce(read(file),
      /\{\s*RejectAndRemember\(callId,\s*cmd,\s*"unsupported_domain"\);\s*return;\s*\}/,
      "{ }",
      "NpcShop no-op domain guard branch");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_domain_identity_drift");
  });

  test("authority kind set rejects duplicate filler", function () {
    const fixture = clone(contract);
    fixture.authorityKinds.push("protocol");
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.authority_kinds");
  });

  test("numeric-less domains cannot carry vector filler", function () {
    const fixture = clone(contract);
    fixture.domains[0].numericFields = [];
    fixture.domains[0].sourceChecks = [];
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }),
      "contract.vector_without_numeric_fields");
  });

  test("required boundary vectors cannot disappear with their numeric field", function () {
    const fixture = clone(contract);
    fixture.domains[0].numericFields = [];
    fixture.domains[0].sourceChecks = [];
    delete fixture.vectors.npcshop;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.required_vector");
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

  test("required NPC interaction policy cannot be removed", function () {
    const fixture = clone(contract);
    delete fixture.domains[0].numericFields[0].interactionPolicy;
    assertError(validator.validateRepository({ root: ROOT, contract: fixture }), "contract.interaction_policy_missing");
  });

  test("NPC preview and direct-commit maxima cannot be conflated", function () {
    const fixture = clone(contract);
    fixture.domains[0].numericFields[0].interactionPolicy.previewInputMaximumField = "maxPurchasable";
    const conflated = validator.validateRepository({ root: ROOT, contract: fixture });
    assertError(conflated, "contract.interaction_policy_distinct");
    assertError(conflated, "contract.interaction_policy_drift");

    const unknown = clone(contract);
    unknown.domains[0].numericFields[0].interactionPolicy.previewInputMaximumField = "inventedLimit";
    assertError(validator.validateRepository({ root: ROOT, contract: unknown }), "contract.interaction_policy_response_field");
  });

  test("NPC preview-in-flight clicks cannot regress to a silent-drop policy", function () {
    const fixture = clone(contract);
    fixture.domains[0].numericFields[0].interactionPolicy.previewInFlight = "silent-drop";
    const silentDrop = validator.validateRepository({ root: ROOT, contract: fixture });
    assertError(silentDrop, "schema.enum");

    const extraKey = clone(contract);
    extraKey.domains[0].numericFields[0].interactionPolicy.uncontractedClickPolicy = true;
    assertError(validator.validateRepository({ root: ROOT, contract: extraKey }), "schema.unknown_key");
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

    const conflictingGuard = replaceOnce(read(file),
      '|| !TryReadInteger(payload["quantity"], 1, MaxPurchaseQuantity, out quantity))',
      '|| !TryReadInteger(payload["quantity"], 1, MaxPurchaseQuantity, out quantity)\n'
        + '                    || !TryReadInteger(payload["quantity"], 1, 100, out quantity))',
      "NpcShop conflicting purchase quantity guard");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: conflictingGuard }
    }), "source.csharp_guard_drift");
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

    const maintenanceEquivalent = read(file)
      + "\nvar OLD_MAX_CRAFT_COUNT:Number = 99;\n";
    const maintenanceReport = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: maintenanceEquivalent }
    });
    assert(maintenanceReport.ok, JSON.stringify(maintenanceReport.errors));
  });

  test("source-check literals inside strings are not executable evidence", function () {
    const file = "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as";
    let mutated = replaceOnce(read(file),
      /MAX_CRAFT_COUNT:Number\s*=\s*99\s*;/,
      "MAX_CRAFT_COUNT:Number = 98 + 0;",
      "Crafting non-literal protocol maximum");
    mutated += '\nvar contractProbe:String = "MAX_CRAFT_COUNT:Number = 99;";\n';
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

    const decoy = replaceOnce(read(file),
      "var flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);",
      "PanelBridge.BuildFlashCommand(action, fid, parsed);\n"
        + "            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, new JObject());",
      "ShopTask unused raw forward decoy");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: decoy }
    }), "source.csharp_flash_dispatch_drift");
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

    const dispatchDrift = replaceOnce(read(file),
      "PanelBridge.BuildFlashCommand(action, fid, normalized)",
      'PanelBridge.BuildFlashCommand("wrongAction", fid, normalized)',
      "NpcShop actual Flash dispatch action");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: dispatchDrift }
    }), "source.csharp_flash_dispatch_drift");
  });

  test("C# command cases reject overwrite and ambiguous return shapes", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const source = read(file);
    [
      'case "buy": action = "npcShopBuy"; action = null; isWrite = true; return true;',
      'case "buy": action = "npcShopBuy"; isWrite = true; isWrite = false; return true;',
      'case "buy": action = "npcShopBuy"; isWrite = true; if (false) return true; return false;'
    ].forEach(function (replacement) {
      const mutated = replaceOnce(source,
        /case\s+"buy"\s*:\s*action\s*=\s*"npcShopBuy"\s*;\s*isWrite\s*=\s*true\s*;\s*return\s+true\s*;/,
        replacement,
        "NpcShop strict command case");
      const report = validator.validateRepository({
        root: ROOT,
        contract: clone(contract),
        sourceOverrides: { [file]: mutated }
      });
      assertError(report, "source.csharp_command_case");
    });
  });

  test("qualified object properties do not impersonate Host out assignments", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const mutated = replaceOnce(read(file),
      'case "snapshot": action = "npcShopSnapshot"; return true;',
      'case "snapshot": audit . action = "telemetry"; audit /* probe */ . isWrite = false; '
        + 'action = "npcShopSnapshot"; isWrite = false; return true;',
      "NpcShop qualified audit properties");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assert(report.ok, JSON.stringify(report.errors));
  });

  test("HandleWebRequest must execute the contracted command resolver", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    let mutated = replaceOnce(read(file),
      "if (!TryResolveCommand(cmd, out action, out isWrite))",
      "if (!TryResolveCommandUnchecked(cmd, out action, out isWrite))",
      "NpcShop command resolver invocation");
    mutated = replaceOnce(mutated,
      /(\s+)(private\s+static\s+bool\s+TryResolveCommand\s*\()/,
      function (_match, whitespace, methodStart) {
        return whitespace
          + "private static bool TryResolveCommandUnchecked(string cmd, out string action, out bool isWrite)\n"
          + "        { action = \"npcShopBuy\"; isWrite = false; return true; }"
          + whitespace
          + methodStart;
      },
      "NpcShop alternate resolver helper");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_command_resolution_drift");

    const qualified = replaceOnce(read(file),
      "if (!TryResolveCommand(cmd, out action, out isWrite))",
      "if (!LegacyResolver /* probe */ . TryResolveCommand(cmd, out action, out isWrite))",
      "NpcShop qualified alternate resolver");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: qualified }
    }), "source.csharp_command_resolution_drift");

    const discardedResult = replaceOnce(read(file),
      /if\s*\(!TryResolveCommand\(cmd,\s*out action,\s*out isWrite\)\)\s*\{\s*RejectAndRemember\(callId,\s*cmd,\s*"unsupported_cmd"\);\s*return;\s*\}/,
      'TryResolveCommand(cmd, out action, out isWrite);\n'
        + '            if (false) { RejectAndRemember(callId, cmd, "unsupported_cmd"); return; }',
      "NpcShop discarded resolver result");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: discardedResult }
    }), "source.csharp_command_resolution_drift");

    [
      'action = "wrongAction";',
      "isWrite = false;"
    ].forEach(function (overwrite) {
      const withOverwrite = replaceOnce(read(file),
        "{ RejectAndRemember(callId, cmd, \"unsupported_cmd\"); return; }",
        "{ RejectAndRemember(callId, cmd, \"unsupported_cmd\"); return; }\n"
          + "            " + overwrite,
        "NpcShop resolver output overwrite");
      assertError(validator.validateRepository({
        root: ROOT,
        contract: clone(contract),
        sourceOverrides: { [file]: withOverwrite }
      }), "source.csharp_command_output_drift");
    });
  });

  test("Host commands absent from the contract are rejected", function () {
    const file = "launcher/src/Tasks/NpcShopTask.cs";
    const mutated = replaceOnce(read(file),
      /(\s+)(default:\s*action\s*=\s*null;\s*return\s+false;)/,
      function (_match, whitespace, defaultCase) {
        return whitespace + 'case "uncontracted": action = "npcShopUncontracted"; return true;'
          + whitespace + defaultCase;
      },
      "NpcShop uncontracted Host command");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.csharp_command_uncontracted");
  });

  test("AS2 action wrappers must dispatch the contracted cmd", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const mutated = replaceOnce(read(file),
      /(_root\.gameCommands\["npcShopSnapshot"\]\s*=\s*function\(params\)\s*\{\s*_root\.UI系统\.NPC商店WebView\.handle\(")snapshot("\s*,\s*params\);\s*\};)/,
      function (_match, prefix, suffix) { return prefix + "tooltip" + suffix; },
      "NpcShop AS2 action dispatch");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_command_dispatch_drift");
  });

  test("delegated AS2 domains cannot collapse to another wrapper primitive", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const occurrences = (source.match(/_root\.UI系统\.NPC商店WebView\.handle\(/g) || []).length;
    assert(occurrences === 8, "expected all eight NpcShop delegated wrappers");
    const mutated = source.replace(/_root\.UI系统\.NPC商店WebView\.handle\(/g,
      "_root.UI系统.NPC商店WebView.dispatch(");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_command_dispatch_drift");

    const unreachable = replaceOnce(source,
      '_root.gameCommands["npcShopSnapshot"] = function(params) { '
        + '_root.UI系统.NPC商店WebView.handle("snapshot", params); };',
      '_root.gameCommands["npcShopSnapshot"] = function(params) { '
        + 'return; _root.UI系统.NPC商店WebView.handle("snapshot", params); };',
      "NpcShop unreachable delegated wrapper");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: unreachable }
    }), "source.flash_command_dispatch_drift");
  });

  test("AS2 wrapper parameter names are not part of the contract", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const mutated = replaceOnce(read(file),
      /(_root\.gameCommands\["npcShopSnapshot"\]\s*=\s*function\()params(\)\s*\{\s*_root\.UI系统\.NPC商店WebView\.handle\("snapshot",\s*)params(\);\s*\};)/,
      function (_match, prefix, middle, suffix) { return prefix + "请求" + middle + "请求" + suffix; },
      "NpcShop AS2 formal parameter rename");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assert(report.ok, JSON.stringify(report.errors));
  });

  test("AS2 strings cannot impersonate wrapper calls", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const mutated = read(file)
      + '\nvar wrapperProbe:String = "Fake.handle(\\\"snapshot\\\", params)";\n';
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assert(report.ok, JSON.stringify(report.errors));
  });

  test("AS2 wrappers cannot drift to a second service receiver", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const mutated = replaceOnce(read(file),
      '_root.UI系统.NPC商店WebView.handle("snapshot", params)',
      'org.flashNight.arki.item.CraftingPanelService.handle("snapshot", params)',
      "NpcShop AS2 handler receiver");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_command_handler_drift");
  });

  test("delegated AS2 handler receiver cannot drift as a whole domain", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const occurrences = (source.match(/_root\.UI系统\.NPC商店WebView\.handle\(/g) || []).length;
    assert(occurrences === 8, "expected all eight NpcShop delegated wrappers");
    const mutated = source.replace(/_root\.UI系统\.NPC商店WebView\.handle\(/g,
      "_root.UI系统.OtherService.handle(");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_command_handler_drift");
  });

  test("inline AS2 domains cannot silently acquire delegated handle wrappers", function () {
    const file = "scripts/逻辑系统分区/商城系统_WebView.as";
    const mutated = replaceOnce(read(file),
      '_root.gameCommands["shopBulkQuery"] = function(params) {',
      '_root.gameCommands["shopBulkQuery"] = function(params) {\n'
        + '    _root.UI系统.商城WebView.handle("bulkQuery", params);',
      "KShop delegated handle insertion");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_dispatch_mode_drift");

    const responseDrift = replaceOnce(read(file),
      'var resp = { task: "shop_response", callId: callId, success: true };',
      'var resp = { task: "wrong_response", callId: callId, success: true };',
      "KShop SaveCart response task");
    assertError(validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: responseDrift }
    }), "source.flash_response_task_drift");
  });

  test("duplicate executable AS2 action registrations are rejected", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const anchor = '_root.gameCommands["npcShopSnapshot"] = function(params) { _root.UI系统.NPC商店WebView.handle("snapshot", params); };';
    assert(source.includes(anchor), "NpcShop executable registration anchor is missing");
    const mutated = source.replace(anchor, anchor + "\n" + anchor);
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_action_drift");
  });

  test("non-function AS2 action overwrites are counted as duplicate assignments", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const anchor = '_root.gameCommands["npcShopSnapshot"] = function(params) { _root.UI系统.NPC商店WebView.handle("snapshot", params); };';
    assert(source.includes(anchor), "NpcShop executable registration anchor is missing");
    const mutated = source.replace(anchor,
      anchor + '\n_root . gameCommands["npcShopSnapshot"] = _root.npcShopSnapshotAlias;');
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_action_drift");
  });

  test("static dot-property AS2 action overwrites are counted", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const anchor = '_root.gameCommands["npcShopSnapshot"] = function(params) { _root.UI系统.NPC商店WebView.handle("snapshot", params); };';
    assert(source.includes(anchor), "NpcShop executable registration anchor is missing");
    const mutated = source.replace(anchor,
      anchor + "\n_root.gameCommands.npcShopSnapshot = _root.npcShopSnapshotAlias;");
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_action_drift");
  });

  test("AS2 strings cannot impersonate action assignments", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const mutated = source
      + '\nvar assignmentProbe:String = "_root.gameCommands[\\\"npcShopSnapshot\\\"] = _root.npcShopSnapshotAlias;";\n';
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assert(report.ok, JSON.stringify(report.errors));
  });

  test("non-global root-like identifiers do not impersonate gameCommands", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    const source = read(file);
    const mutated = source
      + '\nbackup_root.gameCommands.npcShopSnapshot = function(params) {};\n'
      + '前_root.gameCommands.npcShopSnapshot = function(params) {};\n'
      + 'backup /* probe */ . _root . gameCommands.npcShopSnapshot = function(params) {};\n';
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assert(report.ok, JSON.stringify(report.errors));
  });

  test("duplicate AS2 actions in another contracted Flash source are rejected", function () {
    const file = "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as";
    const mutated = read(file)
      + '\n_root.gameCommands["npcShopSnapshot"] = function(params) { '
      + '_root.UI系统.NPC商店WebView.handle("snapshot", params); };\n';
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_action_drift");
  });

  test("AS2 action registrations must remain in their domain sources", function () {
    const npcFile = "scripts/逻辑系统分区/商店系统_兼容.as";
    const craftingFile = "scripts/类定义/org/flashNight/arki/item/CraftingPanelService.as";
    const anchor = '_root.gameCommands["npcShopSnapshot"] = function(params) { _root.UI系统.NPC商店WebView.handle("snapshot", params); };';
    const npcSource = replaceOnce(read(npcFile), anchor, "", "NpcShop source ownership removal");
    const craftingSource = read(craftingFile) + "\n" + anchor + "\n";
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: {
        [npcFile]: npcSource,
        [craftingFile]: craftingSource
      }
    });
    assertError(report, "source.flash_action_source_drift");
  });

  test("Flash response task drift is detected across AS2 and TaskRegistry", function () {
    const fixture = clone(contract);
    fixture.domains[0].flashResponseTask = "npcshop_response_drift";
    const report = validator.validateRepository({ root: ROOT, contract: fixture });
    assertError(report, "source.flash_response_task_drift");
    assertError(report, "source.csharp_response_task_drift");
  });

  test("Flash response task evidence must be a static task assignment", function () {
    const file = "scripts/逻辑系统分区/商店系统_兼容.as";
    let mutated = replaceOnce(read(file),
      'response.task = "npcshop_response";',
      'response.task = "wrong_response";',
      "NpcShop actual response task");
    mutated += '\nvar contractProbe:String = "npcshop_response";\n';
    const report = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: mutated }
    });
    assertError(report, "source.flash_response_task_drift");

    const bracketEquivalent = replaceOnce(read(file),
      'response.task = "npcshop_response";',
      'response["task"] = "npcshop_response";',
      "NpcShop bracket response task");
    const equivalentReport = validator.validateRepository({
      root: ROOT,
      contract: clone(contract),
      sourceOverrides: { [file]: bracketEquivalent }
    });
    assert(equivalentReport.ok, JSON.stringify(equivalentReport.errors));
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

  test("TaskRegistry bindings must use the MessageRouter receiver", function () {
    const file = "launcher/src/Bus/TaskRegistry.cs";
    const mutated = replaceOnce(read(file),
      'router.RegisterAsync("npcshop_response", npcShopTask.HandleFlashResponse);',
      'auditRouter.RegisterAsync("npcshop_response", npcShopTask.HandleFlashResponse);',
      "NpcShop TaskRegistry receiver");
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

  test("TaskRegistry handlers cannot acquire an alias response task", function () {
    const file = "launcher/src/Bus/TaskRegistry.cs";
    const source = read(file);
    const anchor = 'router.RegisterAsync("npcshop_response", npcShopTask.HandleFlashResponse);';
    assert(source.includes(anchor), "NpcShop TaskRegistry registration anchor is missing");
    const mutated = source.replace(anchor,
      anchor + '\n                router.RegisterAsync("npcshop_alias_response", npcShopTask . HandleFlashResponse);');
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
