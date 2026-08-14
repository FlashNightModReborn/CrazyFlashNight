"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const CraftingSource = require("../crafting/source-contract");
const RuntimeProducer = require("../crafting/runtime-producer");
const NpcClosure = require("../npc/production-closure");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");

const SCOPE_SCHEMA = "workbench-live-e2e.material-shop.current-tree-scope.v1";
const MAXIMUM_FILES = 8192;
const MAXIMUM_TOTAL_BYTES = 1024 * 1024 * 1024;

const ROUTE_ADDITIONS = Object.freeze([
  { role: "material_shop_host", relativePath: "launcher/src/Guardian/MaterialShopNavigationCoordinator.cs" },
  { role: "material_shop_host", relativePath: "launcher/src/Guardian/PreparedPanelReplace.cs" },
  { role: "material_shop_host", relativePath: "launcher/src/Tasks/MaterialShopAccessTask.cs" },
  { role: "material_shop_host", relativePath: "launcher/src/Tasks/MaterialShopSettlementWitness.cs" },
  { role: "material_shop_as2", relativePath: "scripts/类定义/org/flashNight/arki/item/MaterialArchiveProjector.as" },
  { role: "material_shop_as2", relativePath: "scripts/类定义/org/flashNight/gesh/xml/LoadXml/MaterialCatalogLoader.as" },
  { role: "material_shop_as2", relativePath: "scripts/类定义/org/flashNight/gesh/xml/LoadXml/MaterialDictionaryLoader.as" },
  { role: "material_shop_as2", relativePath: "scripts/类定义/org/flashNight/boot/BootSequencer.as" },
  { role: "material_catalog", relativePath: "data/dictionaries/material_catalog.xml" },
  { role: "material_dictionary", relativePath: "data/dictionaries/material_dictionary.xml" },
  { role: "material_catalog_derivation", relativePath: "data/dictionaries/material_dictionary.generated.json" },
  { role: "enemy_portrait_manifest", relativePath: "launcher/web/assets/enemy-portraits/manifest.json" },
  { role: "shop_portrait_manifest", relativePath: "launcher/web/assets/shop-portraits/manifest.json" },
  { role: "external_playwright_lock", relativePath: "launcher/perf/package-lock.json" },
  { role: "agent_runtime_a5_entry",
    relativePath: "launcher/src/AgentRuntime/TrustedRunner/TrustedUnattendedBootstrapProtocol.cs" },
  { role: "agent_runtime_a5_entry",
    relativePath: "launcher/src/AgentRuntime/Integration/TrustedUnattendedGameEntryGate.cs" },
  { role: "agent_runtime_a5_entry",
    relativePath: "launcher/src/AgentRuntime/Integration/LauncherAgentRuntimeHost.cs" },
  { role: "agent_runtime_a5_entry",
    relativePath: "launcher/src/Guardian/GameLaunchFlow.cs" },
  { role: "agent_runtime_a5_entry",
    relativePath: "launcher/src/Tasks/AgentControlTask.cs" },
]);

const LIST_POLICIES = Object.freeze([
  { relativePath: "data/enemy_properties/list.xml", tag: "items",
    base: "data/enemy_properties", role: "enemy_source_data", suffix: "" },
  { relativePath: "data/task/list.xml", tag: "task",
    base: "data/task", role: "quest_source_data", suffix: "" },
  { relativePath: "data/kshop/list.xml", tag: "kshop",
    base: "data/kshop", role: "kshop_source_data", suffix: "" },
]);

const RECURSIVE_POLICIES = Object.freeze([
  { relativePath: "launcher/web/assets/enemy-portraits/subjects",
    role: "enemy_portrait_asset" },
  { relativePath: "launcher/web/assets/shop-portraits/subjects",
    role: "shop_portrait_asset" },
]);

const A5_TOOL_FILES = Object.freeze([
  "tools/workbench-live-e2e/material-shop/README.md",
  "tools/workbench-live-e2e/material-shop/ack-control.js",
  "tools/workbench-live-e2e/material-shop/accept-run.js",
  "tools/workbench-live-e2e/material-shop/admit-post-release-finalization.js",
  "tools/workbench-live-e2e/material-shop/agent-runtime-journey.js",
  "tools/workbench-live-e2e/material-shop/admission.js",
  "tools/workbench-live-e2e/material-shop/applicability.js",
  "tools/workbench-live-e2e/material-shop/build-candidate.js",
  "tools/workbench-live-e2e/material-shop/candidate-lifecycle.js",
  "tools/workbench-live-e2e/material-shop/capture-verifier.js",
  "tools/workbench-live-e2e/material-shop/common.js",
  "tools/workbench-live-e2e/material-shop/control-channel.js",
  "tools/workbench-live-e2e/material-shop/discard-built-run.js",
  "tools/workbench-live-e2e/material-shop/discard-pre-control-failed-run.js",
  "tools/workbench-live-e2e/material-shop/discard-seed-audit-failed-run.js",
  "tools/workbench-live-e2e/material-shop/finalize-clone-release.js",
  "tools/workbench-live-e2e/material-shop/formal-consensus-admission.js",
  "tools/workbench-live-e2e/material-shop/formal-execution-lease.js",
  "tools/workbench-live-e2e/material-shop/prepare-formal-run.js",
  "tools/workbench-live-e2e/material-shop/formal-run-protocol.js",
  "tools/workbench-live-e2e/material-shop/journey-verifier.js",
  "tools/workbench-live-e2e/material-shop/materialize.js",
  "tools/workbench-live-e2e/material-shop/prepare.js",
  "tools/workbench-live-e2e/material-shop/production-closure.js",
  "tools/workbench-live-e2e/material-shop/protocol.js",
  "tools/workbench-live-e2e/material-shop/release-worktree.js",
  "tools/workbench-live-e2e/material-shop/run-operation-lease.js",
  "tools/workbench-live-e2e/material-shop/run-live-journey.js",
  "tools/workbench-live-e2e/material-shop/scope-manifest.js",
  "tools/workbench-live-e2e/material-shop/self-test.js",
  "tools/workbench-live-e2e/material-shop/test-discard-seed-audit-failed-run.js",
  "tools/workbench-live-e2e/material-shop/formal-consensus-admission.test.js",
  "tools/workbench-live-e2e/material-shop/formal-execution-lease.test.js",
  "tools/workbench-live-e2e/material-shop/formal-preparer.test.js",
  "tools/workbench-live-e2e/material-shop/formal-run-protocol.test.js",
  "tools/workbench-live-e2e/material-shop/test-admit-post-release-finalization.js",
  "tools/workbench-live-e2e/material-shop/test-agent-runtime-capture.js",
  "tools/workbench-live-e2e/material-shop/test-agent-runtime-authorization-binding.js",
  "tools/workbench-live-e2e/material-shop/test-agent-runtime-journey.js",
  "tools/workbench-live-e2e/material-shop/test-agent-runtime-keyboard-recipe-evidence.js",
  "tools/workbench-live-e2e/material-shop/test-ignored-output-ordering.js",
  "tools/workbench-live-e2e/material-shop/test-materialized-path-budget.js",
  "tools/workbench-live-e2e/material-shop/test-agent-runtime-portrait-evidence.js",
  "tools/workbench-live-e2e/material-shop/test-raw-candidate-reader.js",
  "tools/workbench-live-e2e/material-shop/test-discard-pre-control-failed-run.js",
  "tools/workbench-live-e2e/material-shop/test-discard-built-run-history.js",
  "tools/workbench-live-e2e/material-shop/test-run-live-post-release-finalization.js",
  "tools/workbench-live-e2e/material-shop/trusted-runner-jsonl.js",
  "tools/workbench-live-e2e/material-shop/test-trusted-runner-jsonl.js",
  "tools/workbench-live-e2e/material-shop/trusted-runtime-controller.js",
  "tools/workbench-live-e2e/material-shop/test-trusted-runtime-controller.js",
  "tools/workbench-live-e2e/material-shop/test-visible-review-contract.js",
  "tools/workbench-live-e2e/material-shop/verify-run.js",
]);

// PowerShell dispatch is dynamic, so these BuildOnly entrypoints cannot be discovered by the
// CommonJS require walker. Capture them explicitly and read each one while constructing the
// scope so a missing current-tree driver fails before materialization.
const MATERIALIZED_BUILD_DRIVER_FILES = Object.freeze([
  "automation/dev.ps1",
  "automation/start.ps1",
  "launcher/build.ps1",
  "tools/verify-runtime-bundle-v2.ps1",
  "tools/verify-runtime-consensus.ps1",
  "tools/runtime-build-common.ps1",
  "tools/runtime-build-v2-common.ps1",
  "tools/runtime-build-attestation-v2-common.ps1",
  "tools/runtime-build-queue-common.ps1",
  "tools/verify-runtime-github-attestation.ps1",
  "tools/dotnet-runtime-detect.ps1",
  "tools/cf7-agent/unattended.js",
]);

const SEED_FIXTURE_FILES = Object.freeze([
  "saves/cf7_agent_arena_calibration.json",
  "saves/cf7_agent_character_build_b4.json",
  "saves/cf7_agent_character_build_final.json",
  "saves/cf7_agent_equipment_tuning.json",
]);

// These are executable roots, not a hand-maintained dependency closure. Every static local
// CommonJS dependency reachable from them is discovered below and overlaid byte-for-byte.
// Dynamic production entrypoints (the browser runner and passive recorder) remain explicit
// roots because their consumers intentionally load them by resolved absolute path.
const SHARED_PRODUCER_ENTRYPOINTS = Object.freeze([
  { role: "crafting_browser_gate_producer",
    relativePath: "tools/workbench-live-e2e/crafting/browser-bootstrap.js" },
  { role: "crafting_browser_module_inventory",
    relativePath: "tools/workbench-live-e2e/crafting/browser-module-inventory.v1.json" },
  { role: "crafting_browser_resource_inventory",
    relativePath: "tools/workbench-live-e2e/crafting/browser-resource-inventory.v1.json" },
  { role: "crafting_browser_gate_dependency",
    relativePath: "tools/run-crafting-harness.js" },
  { role: "material_shop_materialized_production_entrypoint",
    relativePath: "tools/workbench-live-e2e/material-shop/production-closure.js" },
  { role: "material_shop_materialized_lifecycle_entrypoint",
    relativePath: "tools/workbench-live-e2e/material-shop/candidate-lifecycle.js" },
  { role: "npc_passive_evidence_producer",
    relativePath: "tools/workbench-live-e2e/npc/passive-recorder.js" },
  { role: "material_shop_external_toolchain_contract",
    relativePath: "tools/workbench-live-e2e/lib/playwright-websocket-toolchain.js" },
]);

function skipQuoted(text, index, quote) {
  let cursor = index + 1;
  while (cursor < text.length) {
    if (text[cursor] === "\\") { cursor += 2; continue; }
    if (text[cursor] === quote) return cursor + 1;
    cursor += 1;
  }
  return text.length;
}

function staticLocalRequires(sourceValue, relativePath) {
  const text = String(sourceValue || "");
  const requests = [];
  let cursor = 0;
  while (cursor < text.length) {
    const character = text[cursor];
    if (character === "'" || character === '"' || character === "`") {
      cursor = skipQuoted(text, cursor, character);
      continue;
    }
    if (character === "/" && text[cursor + 1] === "/") {
      const lineEnd = text.indexOf("\n", cursor + 2);
      cursor = lineEnd < 0 ? text.length : lineEnd + 1;
      continue;
    }
    if (character === "/" && text[cursor + 1] === "*") {
      const commentEnd = text.indexOf("*/", cursor + 2);
      cursor = commentEnd < 0 ? text.length : commentEnd + 2;
      continue;
    }
    if (text.slice(cursor, cursor + 7) !== "require"
        || cursor > 0 && /[A-Za-z0-9_$\.]/.test(text[cursor - 1])
        || /[A-Za-z0-9_$]/.test(text[cursor + 7] || "")) {
      cursor += 1;
      continue;
    }
    let argument = cursor + 7;
    while (/\s/.test(text[argument] || "")) argument += 1;
    if (text[argument] !== "(") { cursor += 7; continue; }
    argument += 1;
    while (/\s/.test(text[argument] || "")) argument += 1;
    const quote = text[argument];
    if (quote !== "'" && quote !== '"') { cursor = argument + 1; continue; }
    const end = skipQuoted(text, argument, quote) - 1;
    const request = text.slice(argument + 1, end);
    if (request.includes("\\")) {
      Common.fail("material_shop_shared_producer_require_invalid", "scope",
        "local producer require path contains an unsupported escape", {
          relativePath, request,
        });
    }
    if (request.startsWith(".")) requests.push(request);
    cursor = end + 1;
  }
  return Array.from(new Set(requests)).sort();
}

function resolveStaticDependency(rootValue, fromRelativePath, request) {
  const root = path.resolve(rootValue);
  const fromDirectory = path.dirname(Common.resolveWithin(root, fromRelativePath, "scope").absolute);
  const requested = path.resolve(fromDirectory, request);
  if (!Evidence.pathInside(root, requested)) {
    Common.fail("material_shop_shared_producer_dependency_escape", "scope",
      "shared producer dependency escaped the repository", { fromRelativePath, request });
  }
  const requestedRelative = path.relative(root, requested).replace(/\\/g, "/");
  if (requestedRelative.split("/").includes("node_modules")) return null;
  const candidates = path.extname(requested)
    ? [requested]
    : [requested, requested + ".js", requested + ".json",
      path.join(requested, "index.js"), path.join(requested, "index.json")];
  const existing = candidates.filter((candidate) => {
    try { return fs.lstatSync(candidate).isFile(); } catch (_error) { return false; }
  });
  if (existing.length < 1) {
    Common.fail("material_shop_shared_producer_dependency_missing", "scope",
      "static local require is absent from the shared producer closure", {
        fromRelativePath, request,
      });
  }
  const resolved = existing[0];
  return Common.normalizeRelative(path.relative(root, resolved).replace(/\\/g, "/"));
}

function sharedProducerDescriptors(rootValue, entrypointsValue) {
  const root = path.resolve(rootValue);
  const entrypoints = entrypointsValue || SHARED_PRODUCER_ENTRYPOINTS;
  const byPath = new Map();
  const queue = entrypoints.map((entry) => ({ role: entry.role,
    relativePath: Common.normalizeRelative(entry.relativePath) }));
  while (queue.length) {
    const descriptor = queue.shift();
    const key = descriptor.relativePath.toLowerCase();
    const previous = byPath.get(key);
    if (previous) {
      if (!previous.roles.includes(descriptor.role)) previous.roles.push(descriptor.role);
      continue;
    }
    const file = exactRegularFile(root, descriptor);
    const entry = { relativePath: file.relativePath, roles: [descriptor.role] };
    byPath.set(key, entry);
    if (!file.relativePath.endsWith(".js")) continue;
    const source = fs.readFileSync(Common.resolveWithin(root, file.relativePath, "scope").absolute,
      "utf8").replace(/^\uFEFF/, "");
    staticLocalRequires(source,
      file.relativePath).forEach((request) => {
      const dependency = resolveStaticDependency(root, file.relativePath, request);
      if (dependency) queue.push({ role: "material_shop_shared_producer_dependency",
        relativePath: dependency });
    });
  }
  return Array.from(byPath.values()).sort((left, right) =>
    left.relativePath.localeCompare(right.relativePath)).flatMap((entry) =>
    entry.roles.slice().sort().map((role) => ({ role, relativePath: entry.relativePath })));
}

function gitHead(root) {
  const result = childProcess.spawnSync("git", ["rev-parse", "HEAD"], {
    cwd: root, encoding: "utf8", windowsHide: true, timeout: 10000,
  });
  const head = String(result.stdout || "").trim().toLowerCase();
  if (result.status !== 0 || !Common.GIT_OID_RE.test(head)) {
    Common.fail("material_shop_git_head_invalid", "scope",
      "current Git HEAD could not be bound");
  }
  return head;
}

function exactRegularFile(root, descriptor) {
  const resolved = Common.resolveWithin(root, descriptor.relativePath, "scope");
  let stat;
  let real;
  try {
    stat = fs.lstatSync(resolved.absolute);
    real = fs.realpathSync.native(resolved.absolute);
  } catch (_error) {
    Common.fail("material_shop_scope_file_missing", "scope",
      "required A5 source file is missing", descriptor);
  }
  if (!stat.isFile() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== resolved.absolute.toLowerCase()) {
    Common.fail("material_shop_scope_file_invalid", "scope",
      "required A5 source path is not one exact regular file", descriptor);
  }
  const bytes = fs.readFileSync(resolved.absolute);
  if (bytes.length < 1) {
    Common.fail("material_shop_scope_file_empty", "scope",
      "required A5 source file is empty", descriptor);
  }
  return {
    relativePath: resolved.relative,
    bytes: bytes.length,
    sha256: Evidence.sha256Bytes(bytes),
  };
}

function buildDriverDescriptors(rootValue, filesValue) {
  const root = path.resolve(rootValue);
  const files = filesValue || MATERIALIZED_BUILD_DRIVER_FILES;
  return files.map((relativePath) => {
    const descriptor = { role: "material_shop_build_driver", relativePath,
      origin: "material_shop_build_driver" };
    exactRegularFile(root, descriptor);
    return descriptor;
  });
}

function assertDirectDirectory(root, relativePath) {
  const resolved = Common.resolveWithin(root, relativePath, "scope");
  let stat;
  let real;
  try {
    stat = fs.lstatSync(resolved.absolute);
    real = fs.realpathSync.native(resolved.absolute);
  } catch (_error) {
    Common.fail("material_shop_scope_directory_missing", "scope",
      "required A5 source directory is missing", { relativePath });
  }
  if (!stat.isDirectory() || stat.isSymbolicLink()
      || path.resolve(real).toLowerCase() !== resolved.absolute.toLowerCase()) {
    Common.fail("material_shop_scope_directory_invalid", "scope",
      "required A5 source directory is indirect", { relativePath });
  }
  return resolved;
}

function recursiveFiles(root, relativePath, role) {
  const base = assertDirectDirectory(root, relativePath);
  const output = [];
  function walk(directory, relative) {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .slice().sort((left, right) => left.name.localeCompare(right.name));
    entries.forEach((entry) => {
      const childRelative = relative + "/" + entry.name;
      const child = Common.resolveWithin(root, childRelative, "scope");
      if (entry.isSymbolicLink()) {
        Common.fail("material_shop_scope_reparse_forbidden", "scope",
          "A5 recursive source closure contains a symbolic link", { relativePath: childRelative });
      }
      if (entry.isDirectory()) {
        assertDirectDirectory(root, childRelative);
        walk(child.absolute, childRelative);
      } else if (entry.isFile()) {
        output.push({ role, relativePath: childRelative, origin: "material_shop_extension" });
      } else {
        Common.fail("material_shop_scope_entry_invalid", "scope",
          "A5 recursive source closure contains a non-file entry", { relativePath: childRelative });
      }
    });
  }
  walk(base.absolute, base.relative);
  if (!output.length) {
    Common.fail("material_shop_scope_directory_empty", "scope",
      "A5 recursive source directory is empty", { relativePath });
  }
  return output;
}

function listedFiles(root, policy) {
  const list = exactRegularFile(root, { relativePath: policy.relativePath });
  const text = fs.readFileSync(Common.resolveWithin(root, policy.relativePath, "scope").absolute,
    "utf8").replace(/^\uFEFF/, "");
  const pattern = new RegExp("<" + policy.tag + ">([^<]+)</" + policy.tag + ">", "g");
  const output = [{ role: policy.role + "_list", relativePath: list.relativePath,
    origin: "material_shop_extension" }];
  let match;
  while ((match = pattern.exec(text)) !== null) {
    const name = String(match[1] || "").trim().replace(/\\/g, "/");
    if (!name || name.startsWith("/") || name.split("/").some((part) => !part || part === "." || part === "..")) {
      Common.fail("material_shop_data_list_invalid", "scope",
        "A5 data list contains an unsafe child", { list: policy.relativePath, name });
    }
    output.push({ role: policy.role, relativePath: policy.base + "/" + name + policy.suffix,
      origin: "material_shop_extension" });
  }
  if (output.length < 2) {
    Common.fail("material_shop_data_list_empty", "scope",
      "A5 data list contains no children", { list: policy.relativePath });
  }
  return output;
}

function stageFiles(root) {
  const listRelative = "data/stages/list.xml";
  const text = fs.readFileSync(Common.resolveWithin(root, listRelative, "scope").absolute,
    "utf8").replace(/^\uFEFF/, "");
  const names = [];
  let match;
  const pattern = /<stages>([^<]+)<\/stages>/g;
  while ((match = pattern.exec(text)) !== null) {
    const name = String(match[1] || "").trim();
    if (!name || /[\\/:*?"<>|]/.test(name)) {
      Common.fail("material_shop_stage_list_invalid", "scope",
        "stage list contains an unsafe directory", { name });
    }
    if (!names.includes(name)) names.push(name);
  }
  if (!names.length) {
    Common.fail("material_shop_stage_list_empty", "scope", "stage list contains no directories");
  }
  return [{ role: "stage_source_data_list", relativePath: listRelative,
    origin: "material_shop_extension" }].concat(names.flatMap((name) =>
    recursiveFiles(root, "data/stages/" + name, "stage_source_data")));
}

function descriptors(root) {
  const source = [];
  CraftingSource.descriptors(root).forEach((entry) => source.push({
    role: entry.role, relativePath: entry.relativePath, origin: "crafting_source_contract",
  }));
  NpcClosure.productionFiles(root).forEach((entry) => source.push({
    role: entry.role, relativePath: entry.relativePath, origin: "npc_production_closure",
  }));
  const producerInputs = RuntimeProducer.currentProducerInputs(root);
  source.push({ role: "runtime_input_descriptor",
    relativePath: producerInputs.config.locator.slice("root:".length),
    origin: "runtime_producer_inputs" });
  Object.keys(producerInputs.domains).forEach((domain) => {
    producerInputs.domains[domain].files.forEach((entry) => source.push({
      role: "runtime_" + domain.replace(/([A-Z])/g, "_$1").toLowerCase(),
      relativePath: entry.relativePath,
      origin: "runtime_producer_inputs",
    }));
  });
  ROUTE_ADDITIONS.forEach((entry) => source.push(Object.assign({
    origin: "material_shop_extension",
  }, entry)));
  LIST_POLICIES.forEach((policy) => source.push(...listedFiles(root, policy)));
  source.push(...stageFiles(root));
  RECURSIVE_POLICIES.forEach((policy) => source.push(...recursiveFiles(
    root, policy.relativePath, policy.role)));
  A5_TOOL_FILES.forEach((relativePath) => source.push({ role: "material_shop_a5_tool",
    relativePath, origin: "material_shop_a5_tooling" }));
  source.push(...buildDriverDescriptors(root));
  sharedProducerDescriptors(root).forEach((entry) => source.push({ role: entry.role,
    relativePath: entry.relativePath, origin: "material_shop_shared_producer" }));
  SEED_FIXTURE_FILES.forEach((relativePath) => source.push({ role: "material_shop_seed_fixture",
    relativePath, origin: "material_shop_a5_tooling" }));
  return source;
}

function stableProjection(value) {
  return {
    schema: value.schema,
    root: value.root,
    head: value.head,
    composition: value.composition,
    fileCount: value.fileCount,
    totalBytes: value.totalBytes,
    files: value.files,
  };
}

function captureCurrentTreeScope(rootValue, capturedAt) {
  const root = Common.assertCanonicalRoot(rootValue);
  const byPath = new Map();
  descriptors(root).forEach((descriptor) => {
    const relativePath = Common.normalizeRelative(descriptor.relativePath);
    const key = relativePath.toLowerCase();
    let entry = byPath.get(key);
    if (!entry) {
      entry = { relativePath, roles: [], origins: [] };
      byPath.set(key, entry);
    } else if (entry.relativePath !== relativePath) {
      Common.fail("material_shop_scope_case_collision", "scope",
        "A5 scope has a case-insensitive path collision", {
          left: entry.relativePath, right: relativePath,
        });
    }
    if (!entry.roles.includes(descriptor.role)) entry.roles.push(descriptor.role);
    if (!entry.origins.includes(descriptor.origin)) entry.origins.push(descriptor.origin);
  });
  if (!byPath.size || byPath.size > MAXIMUM_FILES) {
    Common.fail("material_shop_scope_size_invalid", "scope",
      "A5 current-tree scope file count is outside policy", { fileCount: byPath.size });
  }
  const files = Array.from(byPath.values()).sort((left, right) =>
    left.relativePath.localeCompare(right.relativePath)).map((entry, index) => {
    const file = exactRegularFile(root, entry);
    return {
      ordinal: index,
      relativePath: file.relativePath,
      roles: entry.roles.slice().sort(),
      origins: entry.origins.slice().sort(),
      bytes: file.bytes,
      sha256: file.sha256,
    };
  });
  const totalBytes = files.reduce((sum, entry) => sum + entry.bytes, 0);
  if (totalBytes > MAXIMUM_TOTAL_BYTES) {
    Common.fail("material_shop_scope_bytes_invalid", "scope",
      "A5 current-tree scope exceeds its byte budget", { totalBytes });
  }
  const originCounts = {};
  files.forEach((entry) => entry.origins.forEach((origin) => {
    originCounts[origin] = (originCounts[origin] || 0) + 1;
  }));
  const value = {
    schema: SCOPE_SCHEMA,
    capturedAt: capturedAt || new Date().toISOString(),
    root,
    head: gitHead(root),
    composition: {
      craftingProvider: "tools/workbench-live-e2e/crafting/source-contract.js#descriptors",
      npcProvider: "tools/workbench-live-e2e/npc/production-closure.js#productionFiles",
      runtimeProducerProvider: "tools/workbench-live-e2e/crafting/runtime-producer.js#currentProducerInputs",
      extensionPolicy: "material_shop_route_data_portraits_v1",
      originCounts,
    },
    fileCount: files.length,
    totalBytes,
    files,
  };
  value.scopeSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableProjection(value)));
  return value;
}

function verifyScopeManifest(value, options) {
  const settings = options || {};
  Common.exactKeys(value, ["schema", "capturedAt", "root", "head", "composition",
    "fileCount", "totalBytes", "files", "scopeSha256"],
  "material_shop_scope_manifest_invalid", "scope");
  if (value.schema !== SCOPE_SCHEMA || !Number.isFinite(Date.parse(value.capturedAt))
      || !Common.GIT_OID_RE.test(String(value.head || ""))
      || !Number.isInteger(value.fileCount) || value.fileCount < 1
      || value.fileCount > MAXIMUM_FILES || !Number.isInteger(value.totalBytes)
      || value.totalBytes < 1 || value.totalBytes > MAXIMUM_TOTAL_BYTES
      || !Array.isArray(value.files) || value.files.length !== value.fileCount
      || value.scopeSha256 !== Evidence.sha256Text(Evidence.canonicalJson(stableProjection(value)))) {
    Common.fail("material_shop_scope_manifest_invalid", "scope",
      "A5 current-tree scope envelope or digest is invalid");
  }
  let bytes = 0;
  let previous = null;
  const seen = new Set();
  value.files.forEach((entry, index) => {
    Common.exactKeys(entry, ["ordinal", "relativePath", "roles", "origins", "bytes", "sha256"],
      "material_shop_scope_file_record_invalid", "scope");
    const relative = Common.normalizeRelative(entry.relativePath);
    const key = relative.toLowerCase();
    if (entry.ordinal !== index || seen.has(key) || previous != null
        && previous.localeCompare(relative) >= 0 || !Array.isArray(entry.roles)
        || !entry.roles.length || !Array.isArray(entry.origins) || !entry.origins.length
        || entry.roles.some((role) => !/^[a-z0-9_]+$/.test(String(role || "")))
        || entry.origins.some((origin) => !/^[a-z0-9_]+$/.test(String(origin || "")))
        || Evidence.canonicalJson(entry.roles) !== Evidence.canonicalJson(entry.roles.slice().sort())
        || Evidence.canonicalJson(entry.origins) !== Evidence.canonicalJson(entry.origins.slice().sort())
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || !Common.SHA256_RE.test(String(entry.sha256 || ""))) {
      Common.fail("material_shop_scope_file_record_invalid", "scope",
        "A5 scope file record is malformed, duplicated, or unordered", { index, relative });
    }
    seen.add(key);
    previous = relative;
    bytes += entry.bytes;
  });
  if (bytes !== value.totalBytes) {
    Common.fail("material_shop_scope_total_mismatch", "scope",
      "A5 scope total bytes are detached", { expected: value.totalBytes, actual: bytes });
  }
  if (settings.currentTree !== false) {
    const current = captureCurrentTreeScope(value.root);
    if (Evidence.canonicalJson(stableProjection(current))
        !== Evidence.canonicalJson(stableProjection(value))) {
      Common.fail("material_shop_scope_current_tree_drift", "scope",
        "A5 current-tree scope changed after capture");
    }
  }
  return value;
}

module.exports = {
  A5_TOOL_FILES,
  LIST_POLICIES,
  MAXIMUM_FILES,
  MAXIMUM_TOTAL_BYTES,
  MATERIALIZED_BUILD_DRIVER_FILES,
  RECURSIVE_POLICIES,
  ROUTE_ADDITIONS,
  SEED_FIXTURE_FILES,
  SHARED_PRODUCER_ENTRYPOINTS,
  SCOPE_SCHEMA,
  captureCurrentTreeScope,
  buildDriverDescriptors,
  descriptors,
  resolveStaticDependency,
  sharedProducerDescriptors,
  stableProjection,
  staticLocalRequires,
  verifyScopeManifest,
};
