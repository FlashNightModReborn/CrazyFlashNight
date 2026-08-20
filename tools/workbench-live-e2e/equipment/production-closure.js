"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const { fail } = require("./common");

const CLOSURE_SCHEMA = "workbench-live-e2e.equipment.production-closure.v5";
const BINDING_SCHEMA = "workbench-live-e2e.equipment.production-binding.v2";
const LOADED_SCHEMA = "workbench-live-e2e.equipment.loaded-production.v6";
const PRODUCER_INPUTS_SCHEMA = "workbench-live-e2e.equipment.runtime-producer-inputs.v1";
const CANDIDATE_PRODUCER_SCHEMA = "workbench-live-e2e.equipment.candidate-producer-binding.v2";
const PAGE_RESOURCE_CONTRACT_SCHEMA =
  "workbench-live-e2e.equipment.page-resource-contract.v2";
const MOD_LIST = "data/items/equipment_mods/list.xml";
const LAZY_REGISTRY_WEB = "launcher/web/modules/panels-lazy-registry.js";
const ICON_MANIFEST = "launcher/web/icons/manifest.json";
const FONT_MANIFEST = "launcher/web/assets/fonts/font-pack-manifest.json";
const SHA256_RE = /^[A-F0-9]{64}$/;
const producerInputsCache = new Map();

const BASE_PREWARM_ASSETS = Object.freeze([
  "launcher/web/assets/map/page-base.webp",
  "launcher/web/assets/map/composite/base/base-roof.webp",
  "launcher/web/assets/map/composite/base/merc-bar.webp",
  "launcher/web/assets/map/composite/base/infirmary.webp",
  "launcher/web/assets/map/composite/base/dormitory.webp",
  "launcher/web/assets/map/composite/base/base-garage.webp",
  "launcher/web/assets/map/composite/base/base-lobby.webp",
  "launcher/web/assets/map/composite/base/base-entrance.webp",
  "launcher/web/assets/map/composite/base/basement1.webp",
  "launcher/web/assets/map/composite/base/gym.webp",
  "launcher/web/assets/map/composite/base/armory.webp",
  "launcher/web/assets/map/composite/base/cafeteria.webp",
  "launcher/web/assets/map/composite/base/corridor.webp",
  "launcher/web/assets/map/composite/base/lab.webp",
  "launcher/web/assets/map/composite/base/underground-water.webp",
]);

const CONDITIONAL_CSS_ASSETS = Object.freeze([
  "launcher/web/modules/tasks/assets/task_main_bg.png",
  "launcher/web/modules/tasks/assets/task_icon_bg.png",
  "launcher/web/assets/bg/official-garage.jpg",
  "launcher/web/assets/logos/a-legion-emblem.svg",
]);

const OVERLAY_STARTUP_WEB = Object.freeze([
  "launcher/web/modules/game-ui-behavior.js",
  "launcher/web/lib/marked.min.js",
  "launcher/web/modules/perf-frame-limiter.js",
  "launcher/web/modules/bridge.js",
  "launcher/web/modules/uidata.js",
  "launcher/web/modules/toast.js",
  "launcher/web/modules/cursor-feedback.js",
  "launcher/web/modules/lazy-loader.js",
  "launcher/web/modules/panels.js",
  "launcher/web/modules/panel-scale.js",
  "launcher/web/modules/audio.js",
  "launcher/web/modules/overlay-audio-bindings.js",
  "launcher/web/modules/tooltip.js",
  "launcher/web/modules/asset-timeline.js",
  "launcher/web/modules/icons.js",
  "launcher/web/modules/map-panel-data.js",
  "launcher/web/modules/map-fit-presets.js",
]);

const OVERLAY_STYLE_WEB = Object.freeze([
  "launcher/web/css/game-ui-behavior.css",
  "launcher/web/css/overlay.css",
  "launcher/web/css/panels.css",
  "launcher/web/modules/minigames/shared/minigame-shell.css",
  "launcher/web/modules/minigames/lockbox/lockbox.css",
  "launcher/web/modules/minigames/pinalign/pinalign.css",
  "launcher/web/modules/minigames/gobang/gobang.css",
]);

const PANELS_IMPORT_STYLE_WEB = Object.freeze([
  "launcher/web/css/panels/foundation-top.css",
  "launcher/web/css/workbench/tokens.css",
  "launcher/web/css/panels/foundation-rest.css",
  "launcher/web/css/workbench/core.css",
  "launcher/web/css/workbench/profiles.css",
  "launcher/web/css/panels/features.css",
  "launcher/web/css/workbench/arena.css",
  "launcher/web/css/workbench/inventory.css",
  "launcher/web/css/workbench/skins.css",
  "launcher/web/css/workbench/entities.css",
  "launcher/web/css/workbench/crafting.css",
  "launcher/web/css/workbench/equipment-inspector.css",
  "launcher/web/css/workbench/skills.css",
  "launcher/web/css/workbench/equipment-tuning.css",
  "launcher/web/css/workbench/components.css",
  "launcher/web/css/workbench/character-build.css",
  "launcher/web/css/workbench/character-build-stats.css",
  "launcher/web/css/workbench/team.css",
  "launcher/web/css/workbench/states.css",
  "launcher/web/css/workbench/motion.css",
  "launcher/web/css/hairdresser.css",
  "launcher/web/css/workbench/utilities.css",
]);

const WORKBENCH_LAZY_WEB = Object.freeze([
  "launcher/web/modules/panel-runtime.js",
  "launcher/web/modules/workbench-lifecycle.js",
  "launcher/web/modules/workbench-focus.js",
  "launcher/web/modules/workbench-primitives.js",
  "launcher/web/modules/workbench-profile.js",
  "launcher/web/modules/workbench.js",
  "launcher/web/modules/workbench-components.js",
  "launcher/web/modules/item-filter.js",
  "launcher/web/modules/inventory-runtime.js",
  "launcher/web/modules/inventory-ui.js",
  "launcher/web/modules/inventory-workbench-config.js",
  "launcher/web/modules/inventory-workbench-preparation-menu.js",
  "launcher/web/modules/inventory-workbench-navigation.js",
  "launcher/web/modules/inventory-workbench-header.js",
  "launcher/web/modules/inventory-workbench-quick-transfer.js",
  "launcher/web/modules/inventory-workbench-owned-view.js",
  "launcher/web/modules/inventory-workbench-feature-loader.js",
  "launcher/web/modules/inventory-storage-workbench.js",
  "launcher/web/modules/inventory-workbench.js",
]);

const TUNING_LAZY_WEB = Object.freeze([
  "launcher/web/modules/asset-timeline.js",
  "launcher/web/modules/dressup-doll-renderer.js",
  "launcher/web/modules/workbench-inspection-viewport.js",
  "launcher/web/modules/equipment-inspector.js",
  "launcher/web/modules/equipment-tuning-runtime.js",
  "launcher/web/modules/equipment-tuning-model.js",
  "launcher/web/modules/equipment-tuning-decision-presenter.js",
  "launcher/web/modules/equipment-tuning-render.js",
  "launcher/web/modules/equipment-tuning-confirmation.js",
  "launcher/web/modules/equipment-tuning-interaction.js",
  "launcher/web/modules/equipment-tuning-write-lifecycle.js",
  "launcher/web/modules/equipment-tuning-loadout-lifecycle.js",
  "launcher/web/modules/equipment-tuning-source-marker.js",
  "launcher/web/modules/equipment-tuning-view.js",
  "launcher/web/modules/inventory-tuning-scope.js",
]);

const HOST_FILES = Object.freeze([
  "launcher/src/Tasks/EquipmentTuningTask.cs",
  "launcher/src/Tasks/InventoryTask.cs",
  "launcher/src/Guardian/AuthorityLogFormatter.cs",
  "launcher/src/Guardian/PanelHostController.cs",
  "launcher/src/Guardian/PanelRequestOwnerLifecycle.cs",
  "launcher/src/Guardian/WebOverlayForm.cs",
  "launcher/src/Guardian/LauncherCommandRouter.cs",
  "launcher/src/Bus/TaskRegistry.cs",
  "launcher/src/Tasks/PanelBridge.cs",
  "launcher/src/Guardian/LogManager.cs",
  "launcher/src/Bus/XmlSocketServer.cs",
  "launcher/src/Program.cs",
]);

const BUILD_FILES = Object.freeze([
  { role: "runtime_artifact_source", relativePath: "launcher/CRAZYFLASHER7MercenaryEmpire.csproj" },
  { role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json" },
  { role: "runtime_producer_source", relativePath: ".gitattributes" },
  { role: "runtime_producer_source", relativePath: "launcher/build-runtime-candidate.ps1" },
  { role: "runtime_producer_source", relativePath: "launcher/native/assert-pinned-tools.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/build.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/bootstrap/build.bat" },
  { role: "runtime_producer_source", relativePath: "launcher/native/sol_parser/.cargo/config.toml" },
  { role: "runtime_producer_source", relativePath: "launcher/native/sol_parser/build.bat" },
  { role: "runtime_producer_source", relativePath: "tools/check-runtime-build-env.ps1" },
  { role: "runtime_producer_source", relativePath: "tools/runtime-build-v2-common.ps1" },
  { role: "runtime_toolchain_lock", relativePath: "config/build/runtime-toolchain.lock.json" },
  { role: "runtime_toolchain_lock", relativePath: "global.json" },
  { role: "runtime_toolchain_lock", relativePath: "launcher/native/sol_parser/rust-toolchain.toml" },
]);

const AS2_FILES = Object.freeze([
  "scripts/类定义/org/flashNight/arki/item/EquipmentTuningService.as",
  "scripts/类定义/org/flashNight/arki/item/InventoryPanelService.as",
  "scripts/类定义/org/flashNight/gesh/xml/LoadXml/EquipModListLoader.as",
]);

function canonicalModDataFiles(root) {
  const listPath = path.resolve(root, MOD_LIST);
  let text;
  try { text = fs.readFileSync(listPath, "utf8"); }
  catch (_error) {
    fail("production_data_list_missing", "production_closure",
      "equipment-mod canonical list.xml is missing");
  }
  const names = [];
  const pattern = /<(items|uiPresentation)>([^<]+)<\/\1>/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    const name = match[2].trim();
    if (!/^[^\\/:*?"<>|]+\.xml$/i.test(name) || name === "." || name === "..") {
      fail("production_data_list_invalid", "production_closure",
        "equipment-mod list contains an unsafe child", { name });
    }
    names.push("data/items/equipment_mods/" + name);
  }
  if (!names.length || new Set(names.map((entry) => entry.toLowerCase())).size !== names.length) {
    fail("production_data_list_invalid", "production_closure",
      "equipment-mod list is empty or duplicated");
  }
  return [MOD_LIST].concat(names);
}

function exactText(root, relativePath, code) {
  exactFile(root, { role: "declaration", relativePath });
  try { return fs.readFileSync(path.resolve(root, relativePath.replace(/\//g, path.sep)), "utf8"); }
  catch (_error) {
    fail(code, "production_closure", "production declaration cannot be read", { relativePath });
  }
}

function verifyOverlayStartupInventory(root) {
  const text = exactText(root, "launcher/web/overlay.html", "production_startup_inventory_invalid");
  const actual = [];
  const pattern = /<script\s+src="([^"]+)"\s*><\/script>/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    const source = match[1];
    if (!/^(?:modules|lib)\/[A-Za-z0-9._/-]+\.js$/.test(source)
        || source.split("/").some((entry) => !entry || entry === "." || entry === "..")) {
      fail("production_startup_inventory_invalid", "production_closure",
        "overlay.html contains an unsafe direct script source", { source });
    }
    actual.push("launcher/web/" + source);
  }
  const expected = OVERLAY_STARTUP_WEB.concat([LAZY_REGISTRY_WEB]);
  if (Evidence.canonicalJson(actual) !== Evidence.canonicalJson(expected)) {
    fail("production_startup_inventory_invalid", "production_closure",
      "overlay.html direct script inventory drifted from the closed Equipment producer set", {
        actual, expected,
      });
  }
  return actual;
}

function verifyLazyWebInventory(root) {
  const registry = exactText(root, LAZY_REGISTRY_WEB, "production_lazy_inventory_invalid");
  const registrations = Array.from(registry.matchAll(
    /Panels\.registerLazy\(\s*['"]workbench['"]\s*,\s*\[([\s\S]*?)\]\s*,\s*noop\s*\)/g));
  if (registrations.length !== 1) {
    fail("production_lazy_inventory_invalid", "production_closure",
      "lazy registry must contain one exact Workbench declaration");
  }
  const workbench = Array.from(registrations[0][1].matchAll(/['"](modules\/[^'"]+\.js)['"]/g))
    .map((entry) => "launcher/web/" + entry[1]);
  const loaderPath = "launcher/web/modules/inventory-workbench-feature-loader.js";
  const loader = exactText(root, loaderPath, "production_lazy_inventory_invalid");
  const tuningBlocks = Array.from(loader.matchAll(/var\s+TUNING_DEPS\s*=\s*\[([\s\S]*?)\];/g));
  if (tuningBlocks.length !== 1) {
    fail("production_lazy_inventory_invalid", "production_closure",
      "Equipment feature loader must contain one exact tuning declaration");
  }
  const tuning = Array.from(tuningBlocks[0][1].matchAll(/['"](modules\/[^'"]+\.js)['"]/g))
    .map((entry) => "launcher/web/" + entry[1]);
  if (Evidence.canonicalJson(workbench) !== Evidence.canonicalJson(WORKBENCH_LAZY_WEB)
      || Evidence.canonicalJson(tuning) !== Evidence.canonicalJson(TUNING_LAZY_WEB)) {
    fail("production_lazy_inventory_invalid", "production_closure",
      "Workbench or Equipment lazy dependency order drifted", { workbench, tuning });
  }
  return { workbench, tuning };
}

function verifyOverlayStyleInventory(root) {
  const overlay = exactText(root, "launcher/web/overlay.html", "production_style_inventory_invalid");
  const links = Array.from(overlay.matchAll(
    /<link\s+rel="stylesheet"\s+href="([^"]+)"\s*>/g)).map((entry) => entry[1]);
  if (links.some((source) => !/^(?:css|modules)\/[A-Za-z0-9._/-]+\.css$/.test(source)
      || source.split("/").some((entry) => !entry || entry === "." || entry === ".."))) {
    fail("production_style_inventory_invalid", "production_closure",
      "overlay.html contains an unsafe stylesheet source", { links });
  }
  const overlayStyles = links.map((source) => "launcher/web/" + source);
  if (Evidence.canonicalJson(overlayStyles) !== Evidence.canonicalJson(OVERLAY_STYLE_WEB)) {
    fail("production_style_inventory_invalid", "production_closure",
      "overlay.html stylesheet order drifted from the closed production graph", {
        actual: overlayStyles, expected: OVERLAY_STYLE_WEB,
      });
  }
  const panels = exactText(root, "launcher/web/css/panels.css",
    "production_style_inventory_invalid");
  const imports = Array.from(panels.matchAll(/@import\s+url\("([^"]+)"\);/g))
    .map((entry) => entry[1]);
  if ((panels.match(/@import\b/g) || []).length !== imports.length
      || imports.some((source) => !/^\.\/[A-Za-z0-9._/-]+\.css$/.test(source)
        || source.slice(2).split("/").some((entry) => !entry || entry === "." || entry === ".."))) {
    fail("production_style_inventory_invalid", "production_closure",
      "panels.css contains an unsupported import declaration", { imports });
  }
  const panelStyles = imports.map((source) =>
    path.posix.normalize("launcher/web/css/" + source.slice(2)));
  if (Evidence.canonicalJson(panelStyles) !== Evidence.canonicalJson(PANELS_IMPORT_STYLE_WEB)) {
    fail("production_style_inventory_invalid", "production_closure",
      "panels.css import order drifted from the closed production graph", {
        actual: panelStyles, expected: PANELS_IMPORT_STYLE_WEB,
      });
  }
  const union = overlayStyles.concat(panelStyles);
  if (new Set(union).size !== union.length) {
    fail("production_style_inventory_invalid", "production_closure",
      "Overlay stylesheet graph contains a duplicate producer");
  }
  return { overlayStyles, panelStyles };
}

function safeRelativePath(value, code) {
  const normalized = String(value || "").replace(/\\/g, "/");
  if (!normalized || normalized.startsWith("/") || path.isAbsolute(normalized)
      || /(^|\/)\.\.(\/|$)/.test(normalized) || /[\t\r\n]/.test(normalized)) {
    fail(code, "production_closure", "runtime input contains an unsafe path", { value });
  }
  return normalized;
}

function readRuntimeInputConfig(root) {
  const relativePath = "config/build/runtime-inputs.v2.json";
  let value;
  try {
    value = JSON.parse(exactText(root, relativePath, "runtime_input_config_invalid")
      .replace(/^\uFEFF/, ""));
  } catch (error) {
    if (error && error.code) throw error;
    fail("runtime_input_config_invalid", "production_closure",
      "runtime-inputs.v2.json is not valid JSON", { message: error.message });
  }
  const requiredDomains = ["artifactSource", "producerRecipe", "toolchainLock"];
  if (!Evidence.isPlainObject(value) || value.schema !== "cf7-runtime-inputs.v2"
      || !Evidence.isPlainObject(value.domains) || !Evidence.isPlainObject(value.payload)
      || requiredDomains.some((name) => !Evidence.isPlainObject(value.domains[name])
        || !Array.isArray(value.domains[name].fixedFiles)
        || !Array.isArray(value.domains[name].trees))) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime producer input config is missing or unsupported");
  }
  return value;
}

function enumerateDomainFiles(root, config, domainName) {
  const domain = config.domains[domainName];
  const values = new Set();
  (domain.fixedFiles || []).forEach((entry) => values.add(
    safeRelativePath(entry, "runtime_input_config_invalid")));
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const relative = (base ? base + "/" : "") + entry.name;
      const normalized = safeRelativePath(
        String(tree.path).replace(/\\/g, "/").replace(/\/$/, "") + "/" + relative,
        "runtime_input_config_invalid");
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        fail("runtime_input_tree_invalid", "production_closure",
          "runtime input tree contains a symbolic link", { path: normalized });
      }
      if (entry.isDirectory()) { walk(full, relative, tree); return; }
      if (!entry.isFile()) return;
      const extensions = (tree.includeExtensions || [])
        .map((value) => String(value).toLowerCase());
      if (extensions.length && !extensions.includes(path.extname(normalized).toLowerCase())) return;
      const excludes = (tree.excludePaths || []).map((value) =>
        safeRelativePath(value, "runtime_input_config_invalid"));
      const prefixes = (tree.excludePrefixes || []).map((value) =>
        safeRelativePath(value, "runtime_input_config_invalid"));
      if (excludes.includes(normalized) || prefixes.some((prefix) => normalized.startsWith(prefix))) return;
      values.add(normalized);
    });
  }
  (domain.trees || []).forEach((tree) => {
    if (!Evidence.isPlainObject(tree)) {
      fail("runtime_input_config_invalid", "production_closure",
        "runtime input tree declaration is malformed", { domainName });
    }
    const baseRelative = safeRelativePath(tree.path, "runtime_input_config_invalid");
    const base = path.resolve(root, baseRelative.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(base); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("runtime_input_tree_invalid", "production_closure",
        "runtime producer input tree is missing or indirect", { path: baseRelative });
    }
    walk(base, "", tree);
  });
  return Array.from(values).sort();
}

function normalizedPayloadConfig(config) {
  const payload = config.payload;
  if (!Array.isArray(payload.fixedRoots) || !Array.isArray(payload.trees)
      || !Array.isArray(payload.excludePaths) || !Array.isArray(payload.excludePrefixes)) {
    fail("runtime_input_config_invalid", "production_closure",
      "runtime payload input config is incomplete");
  }
  return {
    fixedRoots: payload.fixedRoots.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid")),
    trees: payload.trees.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid").replace(/\/$/, "")),
    excludePaths: payload.excludePaths.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid")),
    excludePrefixes: payload.excludePrefixes.map((entry) => safeRelativePath(entry,
      "runtime_input_config_invalid")),
  };
}

function validateProducerInputsEnvelope(value, expectedRoot) {
  const domainNames = ["artifactSource", "producerRecipe", "toolchainLock"];
  if (!Evidence.isPlainObject(value) || value.schema !== PRODUCER_INPUTS_SCHEMA
      || path.resolve(value.root || "").toLowerCase() !== path.resolve(expectedRoot).toLowerCase()
      || !Evidence.isPlainObject(value.config)
      || value.config.role !== "runtime_input_descriptor"
      || value.config.locator !== "root:config/build/runtime-inputs.v2.json"
      || !/^[a-f0-9]{64}$/.test(String(value.config.sha256 || ""))
      || !Number.isInteger(value.config.bytes) || value.config.bytes < 1
      || !Evidence.isPlainObject(value.domains)
      || Evidence.canonicalJson(Object.keys(value.domains).sort())
        !== Evidence.canonicalJson(domainNames.slice().sort())
      || !Evidence.isPlainObject(value.payload)
      || Evidence.canonicalJson(Object.keys(value.payload).sort())
        !== Evidence.canonicalJson(["excludePaths", "excludePrefixes", "fixedRoots", "trees"])
      || !SHA256_RE.test(String(value.buildIdentityHash || ""))
      || !/^[a-f0-9]{64}$/.test(String(value.inputsSha256 || ""))) {
    fail("runtime_producer_inputs_invalid", "production_closure",
      "runtime producer input envelope is malformed");
  }
  domainNames.forEach((name) => {
    const domain = value.domains[name];
    if (!Evidence.isPlainObject(domain)
        || Evidence.canonicalJson(Object.keys(domain).sort())
          !== Evidence.canonicalJson(["fileCount", "files", "fingerprintSha256", "hash"])
        || !SHA256_RE.test(String(domain.hash || ""))
        || !/^[a-f0-9]{64}$/.test(String(domain.fingerprintSha256 || ""))
        || !Array.isArray(domain.files) || domain.fileCount !== domain.files.length
        || domain.files.length < 1) {
      fail("runtime_producer_inputs_invalid", "production_closure",
        "runtime producer input domain is malformed", { name });
    }
    const paths = domain.files.map((entry) => entry && entry.relativePath);
    if (new Set(paths).size !== paths.length
        || Evidence.canonicalJson(paths) !== Evidence.canonicalJson(paths.slice().sort())
        || domain.files.some((entry) => !Evidence.isPlainObject(entry)
          || Evidence.canonicalJson(Object.keys(entry).sort())
            !== Evidence.canonicalJson(["bytes", "relativePath", "sha256"])
          || safeRelativePath(entry.relativePath, "runtime_producer_inputs_invalid")
            !== entry.relativePath
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || !Number.isInteger(entry.bytes) || entry.bytes < 1)
        || domain.fingerprintSha256 !== Evidence.sha256Text(
          Evidence.canonicalJson(domain.files))) {
      fail("runtime_producer_inputs_invalid", "production_closure",
        "runtime producer input file inventory is malformed", { name });
    }
  });
  ["fixedRoots", "trees", "excludePaths", "excludePrefixes"].forEach((name) => {
    const values = value.payload[name];
    if (!Array.isArray(values) || new Set(values).size !== values.length
        || values.some((entry) => typeof entry !== "string"
          || safeRelativePath(entry, "runtime_producer_inputs_invalid") !== entry)) {
      fail("runtime_producer_inputs_invalid", "production_closure",
        "runtime payload declaration is malformed", { name });
    }
  });
  if (!value.payload.fixedRoots.length || !value.payload.trees.length
      || computeBuildIdentityHash(value.domains.artifactSource.hash,
        value.domains.producerRecipe.hash, value.domains.toolchainLock.hash)
        !== value.buildIdentityHash) {
    fail("runtime_producer_inputs_invalid", "production_closure",
      "runtime producer input hashes do not form one build identity");
  }
  const unsigned = Object.assign({}, value);
  delete unsigned.inputsSha256;
  if (value.inputsSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    fail("runtime_producer_inputs_invalid", "production_closure",
      "runtime producer input digest is detached");
  }
  return value;
}

function currentProducerInputs(root) {
  const resolvedRoot = path.resolve(root);
  const config = readRuntimeInputConfig(resolvedRoot);
  const names = ["artifactSource", "producerRecipe", "toolchainLock"];
  const rowsByDomain = {};
  const owners = new Map();
  names.forEach((name) => {
    const paths = enumerateDomainFiles(resolvedRoot, config, name);
    rowsByDomain[name] = paths.map((relativePath) => {
      if (owners.has(relativePath)) {
        fail("runtime_input_domain_overlap", "production_closure",
          "runtime producer input belongs to multiple identity domains", {
            relativePath, domains: [owners.get(relativePath), name],
          });
      }
      owners.set(relativePath, name);
      const file = exactFile(resolvedRoot, { role: "runtime_input", relativePath });
      return { relativePath, sha256: file.sha256, bytes: file.bytes };
    });
  });
  const configFile = exactFile(resolvedRoot, {
    role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json",
  });
  const payload = normalizedPayloadConfig(config);
  const fingerprint = Evidence.sha256Text(Evidence.canonicalJson({
    config: configFile, rowsByDomain, payload,
  }));
  const cacheKey = resolvedRoot.toLowerCase();
  const cached = producerInputsCache.get(cacheKey);
  if (cached && cached.fingerprint === fingerprint) {
    return JSON.parse(JSON.stringify(cached.value));
  }
  const script = [
    "$ErrorActionPreference='Stop'",
    "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)",
    ". (Join-Path $env:CF7_EQUIPMENT_SOURCE_ROOT 'tools/runtime-build-v2-common.ps1')",
    "$a=Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $env:CF7_EQUIPMENT_SOURCE_ROOT -Mode Worktree",
    "$p=Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $env:CF7_EQUIPMENT_SOURCE_ROOT -Mode Worktree",
    "$t=Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $env:CF7_EQUIPMENT_SOURCE_ROOT -Mode Worktree",
    "$b=Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $a -ProducerRecipeHash $p -ToolchainLockHash $t",
    "[ordered]@{artifactSourceHash=$a;producerRecipeHash=$p;toolchainLockHash=$t;buildIdentityHash=$b}|ConvertTo-Json -Compress",
  ].join("\n");
  const result = childProcess.spawnSync("powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script], {
      cwd: resolvedRoot, encoding: "utf8", windowsHide: true, maxBuffer: 4 * 1024 * 1024,
      env: Object.assign({}, process.env, { CF7_EQUIPMENT_SOURCE_ROOT: resolvedRoot }),
    });
  let hashes;
  try { hashes = JSON.parse(String(result.stdout || "").trim()); } catch (_error) { hashes = null; }
  const hashFields = ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash",
    "buildIdentityHash"];
  if (result.status !== 0 || !Evidence.isPlainObject(hashes)
      || hashFields.some((name) => !SHA256_RE.test(String(hashes[name] || "").toUpperCase()))) {
    fail("runtime_producer_hash_failed", "production_closure",
      "canonical runtime producer identity could not be recomputed", {
        status: result.status, stderr: String(result.stderr || "").slice(0, 400),
      });
  }
  const finalConfig = readRuntimeInputConfig(resolvedRoot);
  const finalRowsByDomain = {};
  names.forEach((name) => {
    finalRowsByDomain[name] = enumerateDomainFiles(resolvedRoot, finalConfig, name)
      .map((relativePath) => {
        const file = exactFile(resolvedRoot, { role: "runtime_input", relativePath });
        return { relativePath, sha256: file.sha256, bytes: file.bytes };
      });
  });
  const finalConfigFile = exactFile(resolvedRoot, {
    role: "runtime_input_descriptor", relativePath: "config/build/runtime-inputs.v2.json",
  });
  const finalPayload = normalizedPayloadConfig(finalConfig);
  const finalFingerprint = Evidence.sha256Text(Evidence.canonicalJson({
    config: finalConfigFile, rowsByDomain: finalRowsByDomain, payload: finalPayload,
  }));
  if (finalFingerprint !== fingerprint) {
    fail("runtime_producer_inputs_changed", "production_closure",
      "runtime producer inputs changed while their canonical identity was recomputed");
  }
  const domains = {};
  names.forEach((name) => {
    const files = rowsByDomain[name];
    domains[name] = { hash: String(hashes[name + "Hash"]).toUpperCase(),
      fileCount: files.length, fingerprintSha256: Evidence.sha256Text(
        Evidence.canonicalJson(files)), files };
  });
  const value = { schema: PRODUCER_INPUTS_SCHEMA, root: resolvedRoot,
    config: configFile, domains, payload,
    buildIdentityHash: String(hashes.buildIdentityHash).toUpperCase() };
  value.inputsSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  validateProducerInputsEnvelope(value, resolvedRoot);
  producerInputsCache.set(cacheKey, { fingerprint, value });
  return JSON.parse(JSON.stringify(value));
}

function verifyBuildFileInventory(root) {
  const config = readRuntimeInputConfig(root);
  const declaredProducer = enumerateDomainFiles(root, config, "producerRecipe");
  const declaredToolchain = enumerateDomainFiles(root, config, "toolchainLock");
  const closedProducer = BUILD_FILES.filter((entry) => entry.role === "runtime_producer_source")
    .map((entry) => entry.relativePath).sort();
  const closedToolchain = BUILD_FILES.filter((entry) => entry.role === "runtime_toolchain_lock")
    .map((entry) => entry.relativePath).sort();
  const artifactSource = new Set(enumerateDomainFiles(root, config, "artifactSource"));
  if (Evidence.canonicalJson(declaredProducer) !== Evidence.canonicalJson(closedProducer)
      || Evidence.canonicalJson(declaredToolchain) !== Evidence.canonicalJson(closedToolchain)
      || !artifactSource.has("launcher/CRAZYFLASHER7MercenaryEmpire.csproj")
      || BUILD_FILES.filter((entry) => entry.role === "runtime_input_descriptor").length !== 1) {
    fail("production_build_inventory_invalid", "production_closure",
      "Equipment build-file surface drifted from runtime-inputs.v2", {
        declaredProducer, closedProducer, declaredToolchain, closedToolchain,
      });
  }
  return { producerRecipe: declaredProducer, toolchainLock: declaredToolchain };
}

function productionFiles(root) {
  verifyOverlayStartupInventory(root);
  verifyLazyWebInventory(root);
  verifyOverlayStyleInventory(root);
  verifyBuildFileInventory(root);
  const sharedStartupTuning = OVERLAY_STARTUP_WEB.filter((relativePath) =>
    TUNING_LAZY_WEB.includes(relativePath));
  if (Evidence.canonicalJson(sharedStartupTuning)
      !== Evidence.canonicalJson(["launcher/web/modules/asset-timeline.js"])) {
    fail("production_closure_inventory_invalid", "production_closure",
      "Equipment direct/lazy Web dependency overlap is not the one closed shared producer");
  }
  const uniqueWeb = OVERLAY_STARTUP_WEB.concat([LAZY_REGISTRY_WEB], WORKBENCH_LAZY_WEB,
    TUNING_LAZY_WEB.filter((relativePath) => !OVERLAY_STARTUP_WEB.includes(relativePath)),
    OVERLAY_STYLE_WEB, PANELS_IMPORT_STYLE_WEB);
  if (new Set(uniqueWeb).size !== uniqueWeb.length) {
    fail("production_closure_inventory_invalid", "production_closure",
      "Equipment Web dependency union contains unexpected duplicates");
  }
  const all = [
    { role: "page", relativePath: "launcher/web/overlay.html" },
    ...OVERLAY_STARTUP_WEB.map((relativePath) => ({
      role: TUNING_LAZY_WEB.includes(relativePath)
        ? "overlay_startup_tuning_web" : "overlay_startup_web",
      relativePath,
    })),
    { role: "lazy_registry", relativePath: LAZY_REGISTRY_WEB },
    ...WORKBENCH_LAZY_WEB.map((relativePath) => ({ role: "workbench_lazy_web", relativePath })),
    ...TUNING_LAZY_WEB.filter((relativePath) => !OVERLAY_STARTUP_WEB.includes(relativePath))
      .map((relativePath) => ({ role: "tuning_lazy_web", relativePath })),
    ...OVERLAY_STYLE_WEB.map((relativePath) => ({ role: "overlay_stylesheet", relativePath })),
    ...PANELS_IMPORT_STYLE_WEB.map((relativePath) => ({
      role: "panels_import_stylesheet", relativePath,
    })),
    { role: "icon_manifest", relativePath: ICON_MANIFEST },
    { role: "font_manifest", relativePath: FONT_MANIFEST },
    { role: "font_fallback_asset",
      relativePath: "launcher/web/assets/fonts/jetbrains-mono.woff2" },
    ...BASE_PREWARM_ASSETS.map((relativePath) => ({
      role: "page_fixed_image", relativePath,
    })),
    ...CONDITIONAL_CSS_ASSETS.map((relativePath) => ({
      role: "page_conditional_asset", relativePath,
    })),
    ...HOST_FILES.map((relativePath) => ({ role: "host_source", relativePath })),
    ...BUILD_FILES,
    ...AS2_FILES.map((relativePath) => ({ role: "as2_source", relativePath })),
    ...canonicalModDataFiles(root).map((relativePath) => ({ role: "equipment_mod_data", relativePath })),
    { role: "as2_swf", relativePath: "scripts/asLoader.swf" },
  ];
  if (new Set(all.map((entry) => entry.relativePath.toLowerCase())).size !== all.length) {
    fail("production_closure_inventory_invalid", "production_closure",
      "Equipment production closure contains duplicate paths");
  }
  return all;
}

function exactFile(root, descriptor) {
  const canonicalRoot = path.resolve(root);
  const filePath = path.resolve(canonicalRoot, descriptor.relativePath.replace(/\//g, path.sep));
  const relative = path.relative(canonicalRoot, filePath);
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)) {
    fail("production_closure_path_invalid", "production_closure",
      "production closure path escaped the canonical root", descriptor);
  }
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (_error) {
    fail("production_closure_file_missing", "production_closure",
      "required Equipment production file is missing", descriptor);
  }
  if (!stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()) {
    fail("production_closure_file_invalid", "production_closure",
      "required Equipment production path is not one exact regular file", descriptor);
  }
  const bytes = fs.readFileSync(filePath);
  return { role: descriptor.role,
    locator: "root:" + descriptor.relativePath.replace(/\\/g, "/"),
    sha256: Evidence.sha256Bytes(bytes), bytes: bytes.length };
}

function resourceMime(relativePath) {
  const extension = path.extname(relativePath).toLowerCase();
  return extension === ".html" ? "text/html"
    : extension === ".js" ? "text/javascript"
      : extension === ".css" ? "text/css"
        : extension === ".json" ? "application/json"
        : extension === ".webp" ? "image/webp"
          : extension === ".png" ? "image/png"
            : extension === ".jpg" || extension === ".jpeg" ? "image/jpeg"
              : extension === ".svg" ? "image/svg+xml"
                : extension === ".woff2" ? "font/woff2"
                  : extension === ".ttf" ? "font/ttf"
                    : extension === ".otf" ? "font/otf" : "application/octet-stream";
}

function overlayUrl(relativePath) {
  const prefix = "launcher/web/";
  if (!String(relativePath || "").startsWith(prefix)) {
    fail("page_resource_locator_invalid", "production_closure",
      "page resource locator is outside launcher/web", { relativePath });
  }
  return "https://overlay.local/" + relativePath.slice(prefix.length);
}

function closedRoute(entry, relativePath, resourceType, required) {
  if (!entry || entry.locator !== "root:" + relativePath) {
    fail("page_resource_locator_invalid", "production_closure",
      "page resource route is detached from the production file closure", { relativePath });
  }
  return { url: overlayUrl(relativePath), resourceType, mimeType: resourceMime(relativePath),
    locator: entry.locator, sha256: entry.sha256, bytes: entry.bytes, required: required === true };
}

function exactJson(root, relativePath, code) {
  const filePath = path.resolve(root, relativePath.replace(/\//g, path.sep));
  let value;
  try { value = JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) {
    fail(code, "production_closure", "canonical resource manifest is malformed", {
      relativePath, message: error.message,
    });
  }
  return value;
}

function safeIconFileName(value) {
  return typeof value === "string" && /^[A-Za-z0-9._-]+\.(?:png|webp)$/i.test(value)
    && value !== "." && value !== "..";
}

function normalizedFrameUris(entry) {
  if (!Evidence.isPlainObject(entry)) return [];
  if (entry.format === "webp-animated") {
    const first = typeof entry.uri === "string" && entry.uri ? entry.uri
      : Array.isArray(entry.frames) && entry.frames[0]
        ? entry.frames[0].uri || entry.frames[0].file || entry.frames[0].filename
        : entry.f1;
    return safeIconFileName(first) ? [first] : [];
  }
  const raw = Array.isArray(entry.timelineFrames) && entry.timelineFrames.length
    ? entry.timelineFrames : Array.isArray(entry.frames) ? entry.frames : [];
  const ordered = [];
  raw.forEach((frame) => {
    const uri = frame && (frame.uri || frame.file || frame.filename);
    if (safeIconFileName(uri) && !ordered.includes(uri)) ordered.push(uri);
  });
  if (safeIconFileName(entry.f1) && !ordered.includes(entry.f1)) ordered.unshift(entry.f1);
  if (safeIconFileName(entry.f2) && !ordered.includes(entry.f2)) ordered.push(entry.f2);
  const animated = entry.animated === true
    || typeof entry.playback === "string" && entry.playback
      && !["static", "static-first-frame"].includes(entry.playback);
  return animated ? ordered : ordered.slice(0, 1);
}

function exactIconResource(root, name, fileName, required) {
  if (!safeIconFileName(fileName)) {
    fail("icon_resource_manifest_invalid", "production_closure",
      "icon manifest contains an unsafe resource filename", { name, fileName });
  }
  const relativePath = "launcher/web/icons/" + fileName;
  const exact = exactFile(root, { role: "dynamic_icon_asset", relativePath });
  return { url: overlayUrl(relativePath), resourceType: "Image", mimeType: resourceMime(relativePath),
    locator: exact.locator, sha256: exact.sha256, bytes: exact.bytes, required: required === true };
}

function capturedFontRoutes(root) {
  const manifest = exactJson(root, FONT_MANIFEST, "font_resource_manifest_invalid");
  const routes = [];
  const names = new Set();
  Object.values(manifest.groups || {}).forEach((group) => {
    (group && Array.isArray(group.files) ? group.files : []).forEach((entry) => {
      const name = entry && entry.name;
      if (typeof name !== "string" || !/^[A-Za-z0-9._-]+\.(?:woff2|ttf|otf)$/i.test(name)
          || names.has(name) || !Number.isInteger(entry.bytes) || entry.bytes < 1
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))) {
        fail("font_resource_manifest_invalid", "production_closure",
          "font manifest route is malformed or duplicated", { name });
      }
      names.add(name);
      routes.push({ url: "https://cfn-fonts.local/" + name, resourceType: "Font",
        mimeType: resourceMime(name), locator: "font-manifest:" + name,
        sha256: entry.sha256, bytes: entry.bytes,
        required: name === "lxgw-wenkai-screen.ttf" });
    });
  });
  if (!routes.some((entry) => entry.required)) {
    fail("font_resource_manifest_invalid", "production_closure",
      "the required LXGW font route is absent from the canonical font manifest");
  }
  return routes.sort((left, right) => left.url.localeCompare(right.url));
}

function capturePageResourceContract(root, files) {
  const byLocator = new Map(files.map((entry) => [entry.locator, entry]));
  const fileRoute = (relativePath, resourceType, required) => closedRoute(
    byLocator.get("root:" + relativePath), relativePath, resourceType, required);
  const iconManifest = exactJson(root, ICON_MANIFEST, "icon_resource_manifest_invalid");
  const iconRoutes = Object.keys(iconManifest).sort().map((name) => {
    const uris = normalizedFrameUris(iconManifest[name]);
    if (!uris.length) {
      fail("icon_resource_manifest_invalid", "production_closure",
        "icon manifest entry has no production-renderable resource", { name });
    }
    return { name, resources: uris.map((uri, index) =>
      exactIconResource(root, name, uri, index === 0)) };
  });
  const value = {
    schema: PAGE_RESOURCE_CONTRACT_SCHEMA,
    document: fileRoute("launcher/web/overlay.html", "Document", true),
    scripts: scriptFiles({ files }).map((entry) => {
      const relativePath = entry.locator.slice("root:".length);
      return fileRoute(relativePath, "Script", true);
    }),
    styles: styleFiles({ files }).map((entry) => {
      const relativePath = entry.locator.slice("root:".length);
      return fileRoute(relativePath, "Stylesheet", true);
    }),
    fixedImages: BASE_PREWARM_ASSETS.map((relativePath) =>
      fileRoute(relativePath, "Image", true)),
    conditionalAssets: CONDITIONAL_CSS_ASSETS.map((relativePath) =>
      fileRoute(relativePath, "Image", false)),
    fonts: capturedFontRoutes(root),
    iconManifest: fileRoute(ICON_MANIFEST, "Fetch", true),
    iconRoutes,
  };
  value.contractSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function validatePageResourceContract(contract, files) {
  const unsigned = Object.assign({}, contract);
  delete unsigned.contractSha256;
  const contractKeys = ["conditionalAssets", "contractSha256", "document", "fixedImages",
    "fonts", "iconManifest", "iconRoutes", "schema", "scripts", "styles"];
  const routeKeys = ["bytes", "locator", "mimeType", "required", "resourceType", "sha256", "url"];
  const groups = contract && [contract.document, contract.iconManifest]
    .concat(contract.scripts || [], contract.styles || [],
    contract.fixedImages || [], contract.conditionalAssets || [], contract.fonts || []);
  const routes = Array.isArray(groups) ? groups : [];
  const iconResources = [];
  (contract && Array.isArray(contract.iconRoutes) ? contract.iconRoutes : []).forEach((entry) => {
    if (!Evidence.isPlainObject(entry)
        || Evidence.canonicalJson(Object.keys(entry).sort())
          !== Evidence.canonicalJson(["name", "resources"])
        || typeof entry.name !== "string" || !entry.name || !Array.isArray(entry.resources)
        || !entry.resources.length) {
      fail("page_resource_contract_invalid", "production_closure",
        "dynamic icon resource route is malformed");
    }
    iconResources.push(...entry.resources);
  });
  const allRoutes = routes.concat(iconResources);
  if (!Evidence.isPlainObject(contract)
      || Evidence.canonicalJson(Object.keys(contract).sort()) !== Evidence.canonicalJson(contractKeys)
      || contract.schema !== PAGE_RESOURCE_CONTRACT_SCHEMA
      || !Evidence.isPlainObject(contract.document) || !Array.isArray(contract.scripts)
      || !Array.isArray(contract.styles) || !Array.isArray(contract.fixedImages)
      || !Array.isArray(contract.conditionalAssets) || !Array.isArray(contract.fonts)
      || !Array.isArray(contract.iconRoutes) || !Evidence.isPlainObject(contract.iconManifest)
      || contract.contractSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))
      || allRoutes.some((entry) => !Evidence.isPlainObject(entry)
        || Evidence.canonicalJson(Object.keys(entry).sort()) !== Evidence.canonicalJson(routeKeys)
        || typeof entry.url !== "string" || !/^https:\/\/(?:overlay|cfn-fonts)\.local\//.test(entry.url)
        || !["Document", "Script", "Stylesheet", "Image", "Font", "Fetch"]
          .includes(entry.resourceType)
        || typeof entry.mimeType !== "string" || !entry.mimeType
        || typeof entry.locator !== "string" || !entry.locator
        || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1 || typeof entry.required !== "boolean")) {
    fail("page_resource_contract_invalid", "production_closure",
      "production Page resource contract is malformed, duplicated, or digest-detached");
  }
  if (contract.document.resourceType !== "Document"
      || contract.iconManifest.resourceType !== "Fetch" || contract.iconManifest.required !== true
      || contract.scripts.some((entry) => entry.resourceType !== "Script" || entry.required !== true)
      || contract.styles.some((entry) => entry.resourceType !== "Stylesheet" || entry.required !== true)
      || contract.fixedImages.some((entry) => entry.resourceType !== "Image" || entry.required !== true)
      || contract.conditionalAssets.some((entry) => entry.resourceType !== "Image"
        || entry.required !== false)
      || contract.fonts.some((entry) => entry.resourceType !== "Font")
      || contract.iconRoutes.some((entry) => entry.resources.some((resource) =>
        resource.resourceType !== "Image"))
      || new Set(contract.iconRoutes.map((entry) => entry.name)).size !== contract.iconRoutes.length
      || Evidence.canonicalJson(contract.iconRoutes.map((entry) => entry.name))
        !== Evidence.canonicalJson(contract.iconRoutes.map((entry) => entry.name).slice().sort())) {
    fail("page_resource_contract_invalid", "production_closure",
      "production Page resource groups, requiredness, or icon-name order drifted");
  }
  if (new Set(routes.map((entry) => entry.url)).size !== routes.length
      || contract.iconRoutes.some((entry) =>
        new Set(entry.resources.map((resource) => resource.url)).size !== entry.resources.length)) {
    fail("page_resource_contract_invalid", "production_closure",
      "fixed Page routes or one icon route contains duplicate URLs");
  }
  const closedFiles = new Map((files || []).map((entry) => [entry.locator, entry]));
  routes.filter((entry) => entry.locator.startsWith("root:")).forEach((entry) => {
    const closed = closedFiles.get(entry.locator);
    if (!closed || closed.sha256 !== entry.sha256 || closed.bytes !== entry.bytes) {
      fail("page_resource_contract_invalid", "production_closure",
        "Page resource route differs from its exact production file", { locator: entry.locator });
    }
  });
  if (contract.document.url !== "https://overlay.local/overlay.html"
      || contract.document.resourceType !== "Document" || contract.document.required !== true
      || contract.scripts.length !== scriptFiles({ files }).length
      || contract.styles.length !== styleFiles({ files }).length
      || contract.fixedImages.length !== BASE_PREWARM_ASSETS.length
      || contract.fixedImages.some((entry) => entry.required !== true)
      || !contract.fonts.some((entry) => entry.url
        === "https://cfn-fonts.local/lxgw-wenkai-screen.ttf" && entry.required === true)
      || contract.iconManifest.locator !== "root:" + ICON_MANIFEST
      || contract.iconManifest.url !== "https://overlay.local/icons/manifest.json"
      || contract.iconManifest.mimeType !== "application/json") {
    fail("page_resource_contract_invalid", "production_closure",
      "production Page fixed/dynamic route inventory is incomplete");
  }
  return contract;
}

function captureProductionClosure(root, capturedAt) {
  const descriptors = productionFiles(root);
  const files = descriptors.map((entry) => exactFile(root, entry));
  const value = { schema: CLOSURE_SCHEMA,
    capturedAt: capturedAt || new Date().toISOString(), root: path.resolve(root),
    files,
    pageResourceContract: capturePageResourceContract(root, files),
    producerInputs: currentProducerInputs(root) };
  value.closureSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function verifyProductionClosure(root, closure) {
  const descriptors = productionFiles(root);
  if (!Evidence.isPlainObject(closure) || closure.schema !== CLOSURE_SCHEMA
      || path.resolve(closure.root || "").toLowerCase() !== path.resolve(root).toLowerCase()
      || !Number.isFinite(Date.parse(closure.capturedAt))
      || !Array.isArray(closure.files) || closure.files.length !== descriptors.length
      || !Evidence.isPlainObject(closure.pageResourceContract)
      || !Evidence.isPlainObject(closure.producerInputs)) {
    fail("production_closure_invalid", "production_closure",
      "Equipment production closure envelope is missing or incomplete");
  }
  const unsigned = Object.assign({}, closure);
  delete unsigned.closureSha256;
  if (closure.closureSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    fail("production_closure_digest_invalid", "production_closure",
      "Equipment production closure digest is detached");
  }
  const current = descriptors.map((entry) => exactFile(root, entry));
  if (Evidence.canonicalJson(current) !== Evidence.canonicalJson(closure.files)) {
    fail("production_closure_current_tree_mismatch", "production_closure",
      "captured Equipment production bytes differ from the current canonical tree");
  }
  const producerInputs = currentProducerInputs(root);
  if (Evidence.canonicalJson(producerInputs) !== Evidence.canonicalJson(closure.producerInputs)) {
    fail("production_producer_inputs_current_tree_mismatch", "production_closure",
      "captured runtime producer inputs differ from the current canonical tree");
  }
  const currentPageResources = capturePageResourceContract(root, current);
  if (Evidence.canonicalJson(currentPageResources)
      !== Evidence.canonicalJson(closure.pageResourceContract)) {
    fail("page_resource_contract_current_tree_mismatch", "production_closure",
      "captured Page resources differ from the current canonical tree/manifests");
  }
  validatePageResourceContract(closure.pageResourceContract, closure.files);
  return closure;
}

function normalizedHash(value, field) {
  const normalized = String(value || "").toUpperCase();
  if (!SHA256_RE.test(normalized)) {
    fail("candidate_producer_hash_invalid", "production_closure",
      "candidate producer field is not SHA-256", { field });
  }
  return normalized;
}

function computeBuildIdentityHash(artifactSourceHash, producerRecipeHash, toolchainLockHash) {
  return Evidence.sha256Text("artifactSourceHash\t"
    + normalizedHash(artifactSourceHash, "artifactSourceHash") + "\n"
    + "producerRecipeHash\t" + normalizedHash(producerRecipeHash, "producerRecipeHash") + "\n"
    + "toolchainLockHash\t" + normalizedHash(toolchainLockHash, "toolchainLockHash") + "\n")
    .toUpperCase();
}

function exactCandidateFile(candidateRoot, relativePath, maximumBytes, allowEmpty) {
  const resolvedRoot = path.resolve(candidateRoot);
  let rootStat;
  let rootReal;
  try { rootStat = fs.lstatSync(resolvedRoot); rootReal = fs.realpathSync.native(resolvedRoot); }
  catch (_error) { rootStat = null; rootReal = null; }
  if (!rootStat || !rootStat.isDirectory() || rootStat.isSymbolicLink()
      || path.resolve(rootReal).toLowerCase() !== resolvedRoot.toLowerCase()) {
    fail("candidate_producer_root_invalid", "production_closure",
      "candidate producer root is missing or indirect");
  }
  const safe = safeRelativePath(relativePath, "candidate_producer_path_invalid");
  const filePath = path.resolve(resolvedRoot, safe.replace(/\//g, path.sep));
  const relative = path.relative(resolvedRoot, filePath);
  let stat;
  let real;
  try { stat = fs.lstatSync(filePath); real = fs.realpathSync.native(filePath); }
  catch (_error) {
    fail("candidate_producer_file_missing", "production_closure",
      "candidate producer evidence file is missing", { relativePath: safe });
  }
  if (!relative || relative.startsWith(".." + path.sep) || path.isAbsolute(relative)
      || !stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== filePath.toLowerCase()
      || stat.size < (allowEmpty === true ? 0 : 1) || stat.size > maximumBytes) {
    fail("candidate_producer_file_invalid", "production_closure",
      "candidate producer evidence is not one bounded exact regular file", { relativePath: safe });
  }
  const bytes = fs.readFileSync(filePath);
  return { filePath, bytes, sha256: Evidence.sha256Bytes(bytes).toUpperCase(), size: bytes.length };
}

function excludedPayloadPath(relativePath, payload) {
  return payload.excludePaths.includes(relativePath)
    || payload.excludePrefixes.some((prefix) => relativePath.startsWith(prefix));
}

function enumerateCandidatePayload(candidateRoot, payload) {
  const values = new Set();
  payload.fixedRoots.forEach((relativePath) => {
    if (!excludedPayloadPath(relativePath, payload)) values.add(relativePath);
  });
  function walk(directory, base, tree) {
    fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
      const relative = tree + "/" + (base ? base + "/" : "") + entry.name;
      const full = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) {
        fail("candidate_payload_file_invalid", "production_closure",
          "candidate payload contains a symbolic link", { path: relative });
      }
      if (entry.isDirectory()) { walk(full, (base ? base + "/" : "") + entry.name, tree); return; }
      if (entry.isFile() && !excludedPayloadPath(relative, payload)) values.add(relative);
    });
  }
  payload.trees.forEach((tree) => {
    const directory = path.resolve(candidateRoot, tree.replace(/\//g, path.sep));
    let stat;
    try { stat = fs.lstatSync(directory); } catch (_error) { stat = null; }
    if (!stat || !stat.isDirectory() || stat.isSymbolicLink()) {
      fail("candidate_payload_tree_invalid", "production_closure",
        "candidate payload tree is missing or indirect", { tree });
    }
    walk(directory, "", tree);
  });
  const paths = Array.from(values).sort();
  return paths.map((relativePath) => {
    const file = exactCandidateFile(candidateRoot, relativePath, 1024 * 1024 * 1024, true);
    return { path: relativePath, size: file.size, sha256: file.sha256 };
  });
}

function canonicalPayloadClosureHash(files) {
  const sorted = files.slice().sort((left, right) =>
    String(left.path) < String(right.path) ? -1 : (String(left.path) > String(right.path) ? 1 : 0));
  if (!sorted.length || new Set(sorted.map((entry) => String(entry.path).toLowerCase())).size
      !== sorted.length) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload file set is empty or duplicated");
  }
  const canonical = sorted.map((row) => {
    const relative = safeRelativePath(row.path, "candidate_payload_manifest_invalid");
    const size = Number(row.size);
    const digest = normalizedHash(row.sha256, "payload.sha256");
    if (!Number.isSafeInteger(size) || size < 0) {
      fail("candidate_payload_manifest_invalid", "production_closure",
        "candidate payload size is malformed", { relative, size });
    }
    return relative + "\t" + size + "\t" + digest;
  }).join("\n") + "\n";
  return Evidence.sha256Text(canonical).toUpperCase();
}

function parseCandidateManifest(candidateRoot, manifestFile, payload) {
  const lines = manifestFile.bytes.toString("utf8").replace(/\r/g, "").split("\n");
  if (lines.pop() !== "" || lines.shift() !== "cf7-runtime-manifest-v2") {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest header or terminal newline is unsupported");
  }
  const metadataNames = ["publishMode", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "toolchainBaseline", "buildIdentityHash", "payloadClosureHash"];
  const metadata = Object.create(null);
  const files = [];
  lines.forEach((line) => {
    const fields = line.split("\t");
    if (fields[0] === "file") {
      if (fields.length !== 4 || !/^\d+$/.test(fields[2])) {
        fail("candidate_payload_manifest_invalid", "production_closure",
          "candidate payload row is malformed");
      }
      files.push({ path: safeRelativePath(fields[1], "candidate_payload_manifest_invalid"),
        size: Number(fields[2]), sha256: normalizedHash(fields[3], "payload.sha256") });
      return;
    }
    if (fields.length !== 2 || !metadataNames.includes(fields[0])
        || Object.prototype.hasOwnProperty.call(metadata, fields[0]) || !fields[1]) {
      fail("candidate_producer_manifest_invalid", "production_closure",
        "candidate runtime manifest metadata is missing, duplicated, or extra", { line });
    }
    metadata[fields[0]] = fields[1];
  });
  if (Object.keys(metadata).length !== metadataNames.length
      || metadata.publishMode !== "framework-dependent" || !metadata.toolchainBaseline.trim()) {
    fail("candidate_producer_manifest_invalid", "production_closure",
      "candidate runtime manifest metadata set is incomplete or unsupported");
  }
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((name) => { metadata[name] = normalizedHash(metadata[name], name); });
  const sorted = files.slice().sort((left, right) =>
    left.path < right.path ? -1 : (left.path > right.path ? 1 : 0));
  if (Evidence.canonicalJson(files) !== Evidence.canonicalJson(sorted)) {
    fail("candidate_payload_manifest_invalid", "production_closure",
      "candidate payload rows are not in canonical ordinal order");
  }
  const actualFiles = enumerateCandidatePayload(candidateRoot, payload);
  if (Evidence.canonicalJson(files) !== Evidence.canonicalJson(actualFiles)) {
    fail("candidate_payload_file_mismatch", "production_closure",
      "candidate payload manifest differs from the exact candidate payload files");
  }
  if (canonicalPayloadClosureHash(files) !== metadata.payloadClosureHash) {
    fail("candidate_payload_closure_mismatch", "production_closure",
      "candidate payload closure differs from its exact manifest rows");
  }
  return { metadata, files };
}

function captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure) {
  validateProducerInputsEnvelope(closure && closure.producerInputs, closure && closure.root);
  const metadataFile = exactCandidateFile(candidateRoot, "runtime-build-metadata.v2.json",
    64 * 1024);
  const manifestFile = exactCandidateFile(candidateRoot,
    "runtime/cf7-runtime-manifest.tsv", 8 * 1024 * 1024);
  let metadata;
  try { metadata = JSON.parse(metadataFile.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (_error) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata is not valid JSON");
  }
  const metadataKeys = ["schema", "builderLabel", "artifactSourceHash", "producerRecipeHash",
    "toolchainLockHash", "buildIdentityHash", "payloadClosureHash", "createdAtUtc"].sort();
  if (!Evidence.isPlainObject(metadata) || metadata.schema !== "cf7-runtime-candidate-metadata.v2"
      || Evidence.canonicalJson(Object.keys(metadata).sort()) !== Evidence.canonicalJson(metadataKeys)
      || typeof metadata.builderLabel !== "string" || !metadata.builderLabel.trim()
      || !Number.isFinite(Date.parse(metadata.createdAtUtc))) {
    fail("candidate_producer_metadata_invalid", "production_closure",
      "candidate build metadata does not have the exact v2 producer schema");
  }
  const hashes = {};
  ["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].forEach((field) => { hashes[field] = normalizedHash(metadata[field], field); });
  const parsed = parseCandidateManifest(candidateRoot, manifestFile,
    closure.producerInputs.payload);
  const current = closure.producerInputs;
  if (["artifactSourceHash", "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash"].some((field) => parsed.metadata[field] !== hashes[field])
      || hashes.artifactSourceHash !== current.domains.artifactSource.hash
      || hashes.producerRecipeHash !== current.domains.producerRecipe.hash
      || hashes.toolchainLockHash !== current.domains.toolchainLock.hash
      || hashes.buildIdentityHash !== current.buildIdentityHash
      || computeBuildIdentityHash(hashes.artifactSourceHash, hashes.producerRecipeHash,
        hashes.toolchainLockHash) !== hashes.buildIdentityHash
      || hashes.buildIdentityHash !== normalizedHash(candidateIdentity.buildIdentity,
        "candidateIdentity.buildIdentity")
      || hashes.payloadClosureHash !== normalizedHash(candidateIdentity.payloadClosure,
        "candidateIdentity.payloadClosure")) {
    fail("candidate_producer_identity_mismatch", "production_closure",
      "candidate producer identity is detached from current runtime inputs or authenticated runtime");
  }
  const core = parsed.files.filter((entry) =>
    entry.path.toLowerCase() === "runtime/crazyflasher7mercenaryempire.core.dll");
  if (core.length !== 1 || core[0].sha256 !== normalizedHash(candidateIdentity.coreSha256,
    "candidateIdentity.coreSha256")) {
    fail("candidate_core_identity_mismatch", "production_closure",
      "candidate runtime identity is detached from the payload manifest Core DLL row");
  }
  const resolvedCandidateRoot = path.resolve(candidateRoot);
  const resolvedProcessPath = path.resolve(candidateIdentity.processPath || "");
  const processRelative = safeRelativePath(path.relative(resolvedCandidateRoot,
    resolvedProcessPath).replace(/\\/g, "/"), "candidate_process_path_invalid");
  if (path.resolve(resolvedCandidateRoot, processRelative.replace(/\//g, path.sep))
      .toLowerCase() !== resolvedProcessPath.toLowerCase()) {
    fail("candidate_process_path_invalid", "production_closure",
      "authenticated candidate process path escaped the exact candidate payload");
  }
  const processRows = parsed.files.filter((entry) => entry.path === processRelative);
  if (processRows.length !== 1) {
    fail("candidate_process_identity_mismatch", "production_closure",
      "authenticated process path is missing, duplicated, or case-drifted in the payload manifest", {
        processRelative, matches: processRows.length,
      });
  }
  const processFile = exactCandidateFile(candidateRoot, processRelative,
    1024 * 1024 * 1024, false);
  if (processRows[0].size !== processFile.size || processRows[0].sha256 !== processFile.sha256
      || processRows[0].path.toLowerCase() === core[0].path.toLowerCase()
      || processRows[0].sha256 === core[0].sha256) {
    fail("candidate_process_identity_mismatch", "production_closure",
      "authenticated process bytes/hash are absent, wrong, or confused with the Core DLL row");
  }
  const runtimeFileBinding = {
    processPath: resolvedProcessPath,
    process: { path: processRows[0].path, size: processRows[0].size,
      sha256: processRows[0].sha256 },
    core: { path: core[0].path, size: core[0].size, sha256: core[0].sha256 },
    buildIdentity: normalizedHash(candidateIdentity.buildIdentity,
      "candidateIdentity.buildIdentity"),
    payloadClosure: normalizedHash(candidateIdentity.payloadClosure,
      "candidateIdentity.payloadClosure"),
  };
  const runtimeFileBindingSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(runtimeFileBinding));
  const value = { schema: CANDIDATE_PRODUCER_SCHEMA,
    candidateRoot: path.resolve(candidateRoot),
    metadata: { locator: "candidate:runtime-build-metadata.v2.json",
      sha256: metadataFile.sha256, bytes: metadataFile.size },
    manifest: { locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: manifestFile.sha256, bytes: manifestFile.size },
    builderLabel: metadata.builderLabel, createdAtUtc: metadata.createdAtUtc,
    producerInputsSha256: current.inputsSha256,
    artifactSourceHash: hashes.artifactSourceHash,
    producerRecipeHash: hashes.producerRecipeHash,
    toolchainLockHash: hashes.toolchainLockHash,
    buildIdentityHash: hashes.buildIdentityHash,
    payloadClosureHash: hashes.payloadClosureHash,
    payloadFileCount: parsed.files.length,
    runtimeFileBinding,
    runtimeFileBindingSha256 };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function verifyCandidateProducerBinding(candidateRoot, candidateIdentity, closure, evidence) {
  const current = captureCandidateProducerBinding(candidateRoot, candidateIdentity, closure);
  if (!Evidence.isPlainObject(evidence) || evidence.schema !== CANDIDATE_PRODUCER_SCHEMA
      || Evidence.canonicalJson(current) !== Evidence.canonicalJson(evidence)) {
    fail("candidate_producer_evidence_mismatch", "production_closure",
      "captured candidate producer evidence differs from exact current candidate files");
  }
  return evidence;
}

function publicCandidateIdentity(candidateIdentity) {
  return {
    runtimeMode: candidateIdentity.runtimeMode,
    processPath: path.resolve(candidateIdentity.processPath || ""),
    coreSha256: candidateIdentity.coreSha256,
    buildIdentity: candidateIdentity.buildIdentity,
    payloadClosure: candidateIdentity.payloadClosure,
  };
}

function bindProductionClosure(closure, candidateIdentity, runId, candidateProducer) {
  const value = { schema: BINDING_SCHEMA, runId,
    productionClosureSha256: closure.closureSha256,
    producerInputsSha256: closure.producerInputs && closure.producerInputs.inputsSha256,
    candidateIdentitySha256: Evidence.sha256Text(
      Evidence.canonicalJson(publicCandidateIdentity(candidateIdentity))),
    candidateProducerSha256: candidateProducer && candidateProducer.evidenceSha256 };
  value.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function webFiles(closure) {
  return closure.files.filter((entry) => ["page", "overlay_startup_web",
    "overlay_startup_tuning_web", "lazy_registry", "workbench_lazy_web",
    "tuning_lazy_web", "overlay_stylesheet", "panels_import_stylesheet"]
    .includes(entry.role));
}

function scriptFiles(closure) {
  return webFiles(closure).filter((entry) => entry.role !== "page"
    && entry.locator.endsWith(".js"));
}

function styleFiles(closure) {
  return webFiles(closure).filter((entry) => entry.locator.endsWith(".css"));
}

module.exports = {
  AS2_FILES,
  BASE_PREWARM_ASSETS,
  BINDING_SCHEMA,
  BUILD_FILES,
  CANDIDATE_PRODUCER_SCHEMA,
  CLOSURE_SCHEMA,
  HOST_FILES,
  CONDITIONAL_CSS_ASSETS,
  FONT_MANIFEST,
  ICON_MANIFEST,
  LAZY_REGISTRY_WEB,
  LOADED_SCHEMA,
  MOD_LIST,
  OVERLAY_STARTUP_WEB,
  OVERLAY_STYLE_WEB,
  PAGE_RESOURCE_CONTRACT_SCHEMA,
  PANELS_IMPORT_STYLE_WEB,
  PRODUCER_INPUTS_SCHEMA,
  TUNING_LAZY_WEB,
  WORKBENCH_LAZY_WEB,
  bindProductionClosure,
  canonicalPayloadClosureHash,
  captureCandidateProducerBinding,
  captureProductionClosure,
  capturePageResourceContract,
  computeBuildIdentityHash,
  currentProducerInputs,
  productionFiles,
  publicCandidateIdentity,
  scriptFiles,
  styleFiles,
  validatePageResourceContract,
  verifyCandidateProducerBinding,
  verifyBuildFileInventory,
  verifyLazyWebInventory,
  verifyOverlayStartupInventory,
  verifyOverlayStyleInventory,
  validateProducerInputsEnvelope,
  verifyProductionClosure,
  webFiles,
};
