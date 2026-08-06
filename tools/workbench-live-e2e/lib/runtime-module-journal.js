"use strict";

const Module = require("module");
const path = require("path");
const {
  assertExactDirectory,
  canonicalJson,
  contractFail,
  isPlainObject,
  pathInside,
  readExactRegularFile,
  samePath,
  sha256Text,
} = require("./evidence-artifact");

const API_VERSION = "FROZEN-v2";
const ADMISSION_STATUS = "ADMITTED";
const MANIFEST_SCHEMA = "workbench-live-e2e.explicit-module-manifest.v2";
const JOURNAL_SCHEMA = "workbench-live-e2e.runtime-module-journal.v2";
const CHECKPOINT_SCHEMA = "workbench-live-e2e.runtime-module-checkpoint.v2";
const MAXIMUM_MODULE_BYTES = 128 * 1024 * 1024;
const FIRST_PARENT_PATH = module.parent && module.parent.filename
  ? path.resolve(module.parent.filename) : null;
const BUILTINS = new Set(Module.builtinModules.concat(
  Module.builtinModules.map((entry) => "node:" + entry.replace(/^node:/, ""))));
const HIGH_RISK_BUILTINS = new Set(["child_process", "cluster", "inspector", "module", "repl",
  "vm", "worker_threads"]);
const LOADABLE_EXTENSIONS = new Set([".js", ".json"]);
const RESOLVER_FUNCTION_NAMES = Object.freeze([
  "_resolveFilename", "_findPath", "_resolveLookupPaths", "_nodeModulePaths",
]);
const REFLECT_APPLY = Reflect.apply;
const RESOLVER_PATH_DIRNAME = path.dirname;
const RESOLVER_FUNCTIONS = new Map(RESOLVER_FUNCTION_NAMES
  .map((name) => [name, Module[name]]));
const RESOLVER_PATH_CACHE = Module._pathCache;
const RESOLVER_EXTENSIONS = Module._extensions;
const RESOLVER_EXTENSION_KEYS = Reflect.ownKeys(Module._extensions);
const RESOLVER_EXTENSION_HANDLERS = new Map(RESOLVER_EXTENSION_KEYS
  .map((key) => [key, Module._extensions[key]]));
const RESOLVER_GLOBAL_PATHS = Module.globalPaths;
const RESOLVER_GLOBAL_PATHS_JSON = canonicalJson(Module.globalPaths);

function descriptorShape(object, key) {
  const descriptor = Object.getOwnPropertyDescriptor(object, key);
  return descriptor ? { data: Object.prototype.hasOwnProperty.call(descriptor, "value"),
    writable: descriptor.writable === true, enumerable: descriptor.enumerable === true,
    configurable: descriptor.configurable === true } : null;
}

const RESOLVER_MACHINERY_SHA256 = sha256Text(canonicalJson({
  nodeVersion: process.version,
  functions: RESOLVER_FUNCTION_NAMES.map((name) => ({ name,
    descriptor: descriptorShape(Module, name),
    sourceSha256: sha256Text(Function.prototype.toString.call(RESOLVER_FUNCTIONS.get(name))) })),
  pathCacheDescriptor: descriptorShape(Module, "_pathCache"),
  extensionsDescriptor: descriptorShape(Module, "_extensions"),
  extensionKeys: RESOLVER_EXTENSION_KEYS,
  extensionSources: RESOLVER_EXTENSION_KEYS.map((key) => ({ key,
    descriptor: descriptorShape(Module._extensions, key),
    sourceSha256: sha256Text(Function.prototype.toString.call(
      RESOLVER_EXTENSION_HANDLERS.get(key))) })),
  globalPathsDescriptor: descriptorShape(Module, "globalPaths"),
  globalPaths: Module.globalPaths,
  parentDirnameDescriptor: descriptorShape(path, "dirname"),
  parentDirnameSourceSha256: sha256Text(Function.prototype.toString.call(RESOLVER_PATH_DIRNAME)),
  pathCachePolicy: "identity_bound_shape_validated_isolated_recompute",
}));
let activeState = null;

function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function keyPath(value) {
  return path.resolve(value).toLowerCase();
}

function assertPhase(value, code) {
  const phase = String(value || "");
  if (!/^[A-Za-z0-9._~-]{1,80}$/.test(phase)) {
    contractFail(code || "module_journal_phase_invalid", "module_journal",
      "module journal phase is not closed", { phase });
  }
  return phase;
}

function exactRequiredPhases(values) {
  if (!Array.isArray(values) || values.length < 1 || values.length > 64) {
    contractFail("module_manifest_phases_invalid", "module_manifest",
      "explicit manifest requires one bounded phase set");
  }
  const phases = values.map((value) => assertPhase(value, "module_manifest_phases_invalid"));
  if (new Set(phases).size !== phases.length) {
    contractFail("module_manifest_phases_invalid", "module_manifest",
      "explicit manifest phases must be unique");
  }
  return phases;
}

function canonicalBuiltin(value) {
  return String(value || "").replace(/^node:/, "");
}

function exactBuiltinDeclarations(values) {
  if (!Array.isArray(values)) {
    contractFail("module_manifest_builtins_invalid", "module_manifest",
      "explicit manifest requires one exact builtin declaration array");
  }
  const declarations = values.map((entry) => {
    if (!isPlainObject(entry) || typeof entry.name !== "string") {
      contractFail("module_manifest_builtin_invalid", "module_manifest",
        "builtin declaration is malformed", { entry });
    }
    const name = canonicalBuiltin(entry.name);
    const highRisk = HIGH_RISK_BUILTINS.has(name);
    if (!BUILTINS.has(name) || !["standard", "high_risk_explicit"].includes(entry.risk)
        || highRisk !== (entry.risk === "high_risk_explicit")) {
      contractFail("module_manifest_builtin_invalid", "module_manifest",
        "builtin is unknown or lacks the exact risk declaration", { name, risk: entry.risk });
    }
    return { name, risk: entry.risk };
  }).sort((left, right) => compareText(left.name, right.name));
  if (new Set(declarations.map((entry) => entry.name)).size !== declarations.length) {
    contractFail("module_manifest_builtins_invalid", "module_manifest",
      "builtin declarations must be unique");
  }
  return declarations;
}

function locatorFor(root, filePath) {
  const absolute = path.resolve(filePath);
  return pathInside(root, absolute)
    ? "root:" + path.relative(root, absolute).replace(/\\/g, "/")
    : "external:" + absolute.replace(/\\/g, "/");
}

function pathForLocator(root, locator) {
  if (typeof locator !== "string") {
    contractFail("module_manifest_locator_invalid", "module_manifest", "module locator is missing");
  }
  if (locator.startsWith("root:")) {
    const relative = locator.slice(5);
    if (!relative || path.isAbsolute(relative) || relative.split(/[\\/]/).includes("..")) {
      contractFail("module_manifest_locator_invalid", "module_manifest",
        "repository module locator is not one closed relative path", { locator });
    }
    const absolute = path.resolve(root, relative.replace(/\//g, path.sep));
    if (!pathInside(root, absolute)) {
      contractFail("module_manifest_path_escape", "module_manifest",
        "repository module locator escaped root", { locator });
    }
    return absolute;
  }
  if (locator.startsWith("external:")) {
    const value = locator.slice(9).replace(/\//g, path.sep);
    if (!path.isAbsolute(value)) {
      contractFail("module_manifest_locator_invalid", "module_manifest",
        "external module locator must remain absolute", { locator });
    }
    const absolute = path.resolve(value);
    if (pathInside(root, absolute) || samePath(root, absolute)) {
      contractFail("module_manifest_scope_mismatch", "module_manifest",
        "external locator resolves inside repository root", { locator });
    }
    return absolute;
  }
  contractFail("module_manifest_locator_invalid", "module_manifest",
    "module locator has an unknown scope", { locator });
}

function manifestPayload(manifest) {
  const payload = Object.assign({}, manifest);
  delete payload.manifestSha256;
  return payload;
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.getOwnPropertyNames(value).forEach((key) => deepFreeze(value[key]));
    Object.freeze(value);
  }
  return value;
}

function buildExplicitModuleManifest(options) {
  const root = assertExactDirectory(path.resolve(options.root), "module_manifest");
  const requiredPhases = exactRequiredPhases(options.requiredPhases);
  const builtins = exactBuiltinDeclarations(options.builtins || []);
  if (!Array.isArray(options.entries) || options.entries.length < 3) {
    contractFail("module_manifest_entries_invalid", "module_manifest",
      "explicit manifest requires bootstrap, journal dependencies, and runtime modules");
  }
  const entries = options.entries.map((input) => {
    if (!isPlainObject(input) || typeof input.filePath !== "string"
        || !/^[A-Za-z0-9._~-]{1,80}$/.test(String(input.role || ""))
        || typeof input.loadable !== "boolean" || typeof input.preexisting !== "boolean"
        || (input.preexisting && !input.loadable)) {
      contractFail("module_manifest_entry_invalid", "module_manifest",
        "explicit module manifest entry is malformed", { input });
    }
    const file = readExactRegularFile(path.resolve(input.filePath), {
      phase: "module_manifest", maximumBytes: MAXIMUM_MODULE_BYTES,
    });
    const locator = locatorFor(root, file.path);
    if (input.loadable && !LOADABLE_EXTENSIONS.has(path.extname(file.path).toLowerCase())) {
      contractFail("module_manifest_extension_forbidden", "module_manifest",
        "admitted module journal only loads exact .js/.json files", { filePath: file.path });
    }
    const scope = locator.startsWith("root:") ? "repo" : "external";
    if ((scope === "external") !== String(input.role).startsWith("external_")) {
      contractFail("module_manifest_scope_mismatch", "module_manifest",
        "external files require an explicit external_* role", { filePath: file.path, role: input.role });
    }
    return { locator, scope, role: String(input.role), loadable: input.loadable,
      preexisting: input.preexisting, sha256: file.sha256, bytes: file.length };
  }).sort((left, right) => compareText(left.locator, right.locator));
  const preexistingRoles = entries.filter((entry) => entry.preexisting)
    .map((entry) => entry.role).sort(compareText);
  if (new Set(entries.map((entry) => entry.locator.toLowerCase())).size !== entries.length
      || entries.filter((entry) => entry.role === "bootstrap").length !== 1
      || canonicalJson(preexistingRoles) !== canonicalJson(["bootstrap", "journal", "journal_helper"])
      || entries.some((entry) => entry.role === "bootstrap"
        && (!entry.loadable || !entry.preexisting || entry.scope !== "repo"))) {
    contractFail("module_manifest_entries_invalid", "module_manifest",
      "manifest paths must be unique and contain one preexisting repository bootstrap");
  }
  const manifest = { schema: MANIFEST_SCHEMA, apiVersion: API_VERSION,
    createdAt: new Date().toISOString(), root, requiredPhases, builtins, entries };
  manifest.manifestSha256 = sha256Text(canonicalJson(manifest));
  return manifest;
}

function verifyExplicitModuleManifest(options) {
  const root = assertExactDirectory(path.resolve(options.root), "module_manifest");
  const manifest = options.manifest;
  if (!isPlainObject(manifest) || manifest.schema !== MANIFEST_SCHEMA
      || manifest.apiVersion !== API_VERSION || !samePath(manifest.root || "", root)
      || !Number.isFinite(Date.parse(manifest.createdAt))
      || !/^[a-f0-9]{64}$/.test(String(manifest.manifestSha256 || ""))
      || sha256Text(canonicalJson(manifestPayload(manifest))) !== manifest.manifestSha256) {
    contractFail("module_manifest_invalid", "module_manifest", "explicit module manifest is malformed");
  }
  const requiredPhases = exactRequiredPhases(manifest.requiredPhases);
  const builtins = exactBuiltinDeclarations(manifest.builtins);
  if (canonicalJson(requiredPhases) !== canonicalJson(manifest.requiredPhases)
      || canonicalJson(builtins) !== canonicalJson(manifest.builtins)
      || !Array.isArray(manifest.entries) || manifest.entries.length < 3) {
    contractFail("module_manifest_invalid", "module_manifest", "manifest phase/entry set is malformed");
  }
  let previous = null;
  const seen = new Set();
  manifest.entries.forEach((entry) => {
    if (!isPlainObject(entry) || !["repo", "external"].includes(entry.scope)
        || !/^[A-Za-z0-9._~-]{1,80}$/.test(String(entry.role || ""))
        || typeof entry.loadable !== "boolean" || typeof entry.preexisting !== "boolean"
        || (entry.preexisting && !entry.loadable)
        || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 0
        || (previous !== null && compareText(previous, entry.locator) >= 0)
        || seen.has(String(entry.locator).toLowerCase())) {
      contractFail("module_manifest_entry_invalid", "module_manifest",
        "explicit module manifest entries are malformed, duplicated, or unsorted");
    }
    const filePath = pathForLocator(root, entry.locator);
    if (entry.loadable && !LOADABLE_EXTENSIONS.has(path.extname(filePath).toLowerCase())) {
      contractFail("module_manifest_extension_forbidden", "module_manifest",
        "admitted module journal only loads exact .js/.json files", { locator: entry.locator });
    }
    const expectedScope = pathInside(root, filePath) ? "repo" : "external";
    if (expectedScope !== entry.scope
        || (entry.scope === "external") !== entry.role.startsWith("external_")) {
      contractFail("module_manifest_scope_mismatch", "module_manifest",
        "manifest entry scope or role changed", { locator: entry.locator });
    }
    const file = readExactRegularFile(filePath, {
      phase: "module_manifest", maximumBytes: MAXIMUM_MODULE_BYTES,
    });
    if (file.sha256 !== entry.sha256 || file.length !== entry.bytes) {
      contractFail("module_manifest_file_changed", "module_manifest",
        "explicit manifest file bytes changed", { locator: entry.locator });
    }
    previous = entry.locator;
    seen.add(entry.locator.toLowerCase());
  });
  const bootstrap = manifest.entries.filter((entry) => entry.role === "bootstrap");
  const journal = manifest.entries.filter((entry) => entry.role === "journal");
  const helper = manifest.entries.filter((entry) => entry.role === "journal_helper");
  const preexistingRoles = manifest.entries.filter((entry) => entry.preexisting)
    .map((entry) => entry.role).sort(compareText);
  if (bootstrap.length !== 1 || !bootstrap[0].loadable || !bootstrap[0].preexisting
      || bootstrap[0].scope !== "repo" || journal.length !== 1 || helper.length !== 1
      || !journal[0].preexisting || !helper[0].preexisting
      || !samePath(pathForLocator(root, journal[0].locator), __filename)
      || !samePath(pathForLocator(root, helper[0].locator), path.join(__dirname, "evidence-artifact.js"))
      || canonicalJson(preexistingRoles) !== canonicalJson(["bootstrap", "journal", "journal_helper"])) {
    contractFail("module_manifest_bootstrap_invalid", "module_manifest",
      "manifest must contain one preexisting repository bootstrap");
  }
  return manifest;
}

function manifestIndex(root, manifest) {
  const byPath = new Map();
  manifest.entries.forEach((entry) => {
    byPath.set(keyPath(pathForLocator(root, entry.locator)), entry);
  });
  return byPath;
}

function exactManifestFile(root, entry, phase) {
  const file = readExactRegularFile(pathForLocator(root, entry.locator), {
    phase, maximumBytes: MAXIMUM_MODULE_BYTES,
  });
  if (file.sha256 !== entry.sha256 || file.length !== entry.bytes) {
    contractFail("runtime_module_bytes_changed", phase,
      "loaded module bytes no longer match the explicit manifest", { locator: entry.locator });
  }
  return { locator: entry.locator, sha256: file.sha256, bytes: file.length };
}

function exactStandardDataDescriptor(object, key, expectedValue) {
  const descriptor = Object.getOwnPropertyDescriptor(object, key);
  return descriptor && Object.prototype.hasOwnProperty.call(descriptor, "value")
    && !Object.prototype.hasOwnProperty.call(descriptor, "get")
    && !Object.prototype.hasOwnProperty.call(descriptor, "set")
    && descriptor.value === expectedValue && descriptor.writable === true
    && descriptor.enumerable === true && descriptor.configurable === true;
}

function assertResolverMachinery(phase, expectedPathCache) {
  const pathCache = expectedPathCache || RESOLVER_PATH_CACHE;
  const functionInvalid = RESOLVER_FUNCTION_NAMES.some((name) =>
    !exactStandardDataDescriptor(Module, name, RESOLVER_FUNCTIONS.get(name)));
  if (functionInvalid
      || !exactStandardDataDescriptor(path, "dirname", RESOLVER_PATH_DIRNAME)
      || !exactStandardDataDescriptor(Module, "_pathCache", pathCache)
      || !exactStandardDataDescriptor(Module, "_extensions", RESOLVER_EXTENSIONS)
      || !exactStandardDataDescriptor(Module, "globalPaths", RESOLVER_GLOBAL_PATHS)
      || canonicalJson(Module.globalPaths) !== RESOLVER_GLOBAL_PATHS_JSON) {
    contractFail("runtime_module_resolver_machinery_invalid", phase,
      "CommonJS resolver property descriptor, identity, or global path baseline changed");
  }
  if (Object.getPrototypeOf(pathCache) !== null
      || Reflect.ownKeys(pathCache).some((key) => {
        if (typeof key !== "string") return true;
        const descriptor = Object.getOwnPropertyDescriptor(pathCache, key);
        return !descriptor || !Object.prototype.hasOwnProperty.call(descriptor, "value")
          || typeof descriptor.value !== "string" || descriptor.writable !== true
          || descriptor.enumerable !== true || descriptor.configurable !== true;
      })) {
    contractFail("runtime_module_resolver_path_cache_invalid", phase,
      "CommonJS resolver path cache is replaced, exotic, or contains nonstandard entries");
  }
  if (canonicalJson(Reflect.ownKeys(Module._extensions))
      !== canonicalJson(RESOLVER_EXTENSION_KEYS)
      || RESOLVER_EXTENSION_KEYS.some((key) =>
        !exactStandardDataDescriptor(Module._extensions, key,
          RESOLVER_EXTENSION_HANDLERS.get(key)))) {
    contractFail("runtime_module_resolver_extensions_invalid", phase,
      "CommonJS resolver extension table descriptor or handler identity changed");
  }
  return RESOLVER_MACHINERY_SHA256;
}

function withIsolatedResolverPathCache(phase, callback) {
  assertResolverMachinery(phase, RESOLVER_PATH_CACHE);
  const originalDescriptor = Object.getOwnPropertyDescriptor(Module, "_pathCache");
  const isolatedPathCache = Object.create(null);
  Object.defineProperty(Module, "_pathCache", Object.assign({}, originalDescriptor, {
    value: isolatedPathCache,
  }));
  let result;
  let callbackError = null;
  let integrityError = null;
  try {
    assertResolverMachinery(phase, isolatedPathCache);
    result = callback();
    assertResolverMachinery(phase, isolatedPathCache);
  } catch (error) {
    callbackError = error;
    try { assertResolverMachinery(phase, isolatedPathCache); }
    catch (resolverError) { integrityError = resolverError; }
  }
  try { Object.defineProperty(Module, "_pathCache", originalDescriptor); }
  catch (error) { integrityError = integrityError || error; }
  try { assertResolverMachinery(phase, RESOLVER_PATH_CACHE); }
  catch (error) { integrityError = integrityError || error; }
  if (integrityError) throw integrityError;
  if (callbackError) throw callbackError;
  return result;
}

function assertModuleMachinery(state, phase) {
  if (Module._cache !== state.cacheObject || require.cache !== state.cacheObject) {
    contractFail("runtime_module_cache_replaced", phase,
      "Node module cache identity changed during the journal lifecycle");
  }
  if (Module._extensions !== state.extensionsObject
      || canonicalJson(Reflect.ownKeys(Module._extensions)) !== canonicalJson(state.extensionKeys)
      || state.extensionKeys.some((key) => Module._extensions[key] !== state.extensionHandlers.get(key))) {
    state.integrityFailure = "extensions_replaced";
    contractFail("runtime_module_extensions_replaced", phase,
      "Node module extension table or handler identity changed during the journal lifecycle");
  }
  try { assertResolverMachinery(phase, RESOLVER_PATH_CACHE); }
  catch (error) {
    state.integrityFailure = error && error.code || "resolver_machinery_changed";
    throw error;
  }
}

function exactCacheDescriptor(state, filePath, phase, allowMissing) {
  const key = Reflect.ownKeys(state.cacheObject).find((candidate) =>
    typeof candidate === "string" && samePath(candidate, filePath));
  if (key == null) {
    if (allowMissing === true) return null;
    contractFail("runtime_module_cache_entry_missing", phase,
      "declared loaded module is missing from require.cache", { filePath });
  }
  const descriptor = Object.getOwnPropertyDescriptor(state.cacheObject, key);
  if (!descriptor || typeof key !== "string" || descriptor.enumerable !== true
      || descriptor.configurable !== true || descriptor.writable !== true
      || !Object.prototype.hasOwnProperty.call(descriptor, "value")
      || !(descriptor.value instanceof Module)
      || typeof descriptor.value.filename !== "string"
      || !samePath(key, descriptor.value.filename) || !samePath(filePath, descriptor.value.filename)) {
    contractFail("runtime_module_cache_entry_invalid", phase,
      "require.cache entry descriptor or Module identity is malformed", { filePath });
  }
  const entry = state.manifestByPath.get(keyPath(filePath));
  const bootstrap = entry && entry.role === "bootstrap";
  if (bootstrap) {
    if (descriptor.value !== require.main || ![".", descriptor.value.filename].includes(descriptor.value.id)) {
      contractFail("runtime_module_bootstrap_cache_invalid", phase,
        "bootstrap cache identity is not the executing main module", { filePath });
    }
    const loadedDescriptor = Object.getOwnPropertyDescriptor(descriptor.value, "loaded");
    if (!loadedDescriptor || !Object.prototype.hasOwnProperty.call(loadedDescriptor, "value")
        || Object.prototype.hasOwnProperty.call(loadedDescriptor, "get")
        || Object.prototype.hasOwnProperty.call(loadedDescriptor, "set")
        || typeof loadedDescriptor.value !== "boolean"
        || loadedDescriptor.writable !== true || loadedDescriptor.enumerable !== true
        || loadedDescriptor.configurable !== true) {
      contractFail("runtime_module_bootstrap_loaded_descriptor_invalid", phase,
        "bootstrap loaded must remain one standard own boolean data descriptor", { filePath });
    }
    const bootstrapLoaded = loadedDescriptor.value;
    if (phase === "module_journal_install" && bootstrapLoaded !== false) {
      contractFail("runtime_module_bootstrap_initial_loaded_invalid", phase,
        "bootstrap must install while the executing main Module is still loaded=false", { filePath });
    }
    if (state.bootstrapLoaded === true && bootstrapLoaded === false) {
      contractFail("runtime_module_bootstrap_loaded_regressed", phase,
        "bootstrap Module.loaded regressed from true to false", { filePath });
    }
    state.bootstrapLoaded = bootstrapLoaded;
  } else if (descriptor.value.id !== descriptor.value.filename
      || (descriptor.value.loaded !== true && !state.inFlightPaths.has(keyPath(filePath)))) {
    contractFail("runtime_module_cache_entry_invalid", phase,
      "non-bootstrap cache entry is not one loaded/in-flight exact Module", { filePath });
  }
  const bound = state.moduleIdentityByPath.get(keyPath(filePath));
  if (bound && bound !== descriptor.value) {
    contractFail("runtime_module_cache_identity_changed", phase,
      "require.cache Module object changed after identity binding", { filePath });
  }
  state.moduleIdentityByPath.set(keyPath(filePath), descriptor.value);
  return { key, module: descriptor.value };
}

function exactCacheSnapshot(state, phase) {
  assertModuleMachinery(state, phase);
  const keys = Reflect.ownKeys(require.cache);
  if (keys.some((key) => typeof key !== "string")) {
    contractFail("runtime_module_cache_symbol_forbidden", phase,
      "require.cache contains a symbol/non-string key");
  }
  const records = keys.map((filePath) => {
    const entry = state.manifestByPath.get(keyPath(filePath));
    if (!entry || !entry.loadable) {
      contractFail("runtime_module_cache_undeclared", phase,
        "require.cache contains a non-builtin file absent from the explicit manifest", { filePath });
    }
    exactCacheDescriptor(state, filePath, phase, false);
    return exactManifestFile(state.root, entry, phase);
  }).sort((left, right) => compareText(left.locator, right.locator));
  if (new Set(records.map((entry) => entry.locator)).size !== records.length) {
    contractFail("runtime_module_cache_duplicate", phase, "require.cache contains duplicate identities");
  }
  return records;
}

function assertHookIntegrity(state, phase) {
  if (Module._load !== state.hook || Module._resolveFilename !== state.originalResolve) {
    state.integrityFailure = "hook_replaced";
    contractFail("runtime_module_hook_replaced", phase,
      "Module._load or Module._resolveFilename changed during the journal lifecycle");
  }
  assertModuleMachinery(state, phase);
}

function exactSet(values) {
  return Array.from(new Set(values)).sort(compareText);
}

function setDigest(values) {
  return sha256Text(canonicalJson(exactSet(values)));
}

function assertExactCoverage(state, cache, phase) {
  const expected = state.manifest.entries.filter((entry) => entry.loadable)
    .map((entry) => entry.locator).sort(compareText);
  const loaded = exactSet(Array.from(state.loadedLocators));
  const cached = cache.map((entry) => entry.locator).sort(compareText);
  if (canonicalJson(loaded) !== canonicalJson(expected)
      || canonicalJson(cached) !== canonicalJson(expected)) {
    contractFail("runtime_module_manifest_coverage_mismatch", phase,
      "actual loaded/cache set does not exactly cover the explicit loadable manifest", {
        expected, loaded, cached,
      });
  }
  return { expected, loaded, cached };
}

function assertExactBuiltinCoverage(state, phase) {
  const expected = state.manifest.builtins.map((entry) => entry.name).sort(compareText);
  const actual = Array.from(state.actualBuiltins).sort(compareText);
  if (canonicalJson(actual) !== canonicalJson(expected)) {
    contractFail("runtime_module_builtin_coverage_mismatch", phase,
      "actual builtin set does not exactly cover the explicit manifest allowlist",
      { expected, actual });
  }
  return actual;
}

function installRuntimeModuleJournal(options) {
  if (activeState) {
    contractFail("runtime_module_journal_already_active", "module_journal",
      "only one runtime module journal may be active in a process");
  }
  const root = assertExactDirectory(path.resolve(options.root), "module_journal");
  const verifiedManifest = verifyExplicitModuleManifest({ root, manifest: options.manifest });
  const manifest = deepFreeze(JSON.parse(canonicalJson(verifiedManifest)));
  const bootstrap = manifest.entries.find((entry) => entry.role === "bootstrap");
  const bootstrapPath = pathForLocator(root, bootstrap.locator);
  if (!FIRST_PARENT_PATH || !samePath(FIRST_PARENT_PATH, bootstrapPath)) {
    contractFail("runtime_module_bootstrap_not_first", "module_journal",
      "runtime module journal must be first required by the declared bootstrap", {
        firstParentPath: FIRST_PARENT_PATH, bootstrapPath,
      });
  }
  const state = { root, manifest, manifestByPath: manifestIndex(root, manifest),
    originalLoad: Module._load, originalResolve: Module._resolveFilename,
    cacheObject: require.cache, extensionsObject: Module._extensions,
    extensionKeys: Reflect.ownKeys(Module._extensions),
    extensionHandlers: new Map(Reflect.ownKeys(Module._extensions)
      .map((key) => [key, Module._extensions[key]])),
    hook: null, installedAt: new Date().toISOString(),
    sealed: false, restored: false, sequence: 0, events: [], failures: [],
    postSealAttempts: [], checkpoints: [], checkpointPhases: new Set(),
    loadedLocators: new Set(), preexisting: null, sealRecord: null,
    integrityFailure: null, moduleIdentityByPath: new Map(), inFlightPaths: new Set(),
    bootstrapLoaded: null, bootstrapLoadedAtInstall: null,
    resolverMachinerySha256AtInstall: RESOLVER_MACHINERY_SHA256,
    builtinDeclarations: new Map(manifest.builtins.map((entry) => [entry.name, entry])),
    actualBuiltins: new Set(), attemptedLoads: 0, completedLoads: 0 };
  if (canonicalJson(state.extensionKeys) !== canonicalJson([".js", ".json", ".node"])) {
    contractFail("runtime_module_extensions_invalid", "module_journal_install",
      "Node module extension table is outside the fixed .js/.json/.node baseline");
  }
  const preexisting = exactCacheSnapshot(state, "module_journal_install");
  const expectedPreexisting = manifest.entries.filter((entry) => entry.preexisting)
    .map((entry) => entry.locator).sort(compareText);
  if (canonicalJson(preexisting.map((entry) => entry.locator))
      !== canonicalJson(expectedPreexisting)) {
    contractFail("runtime_module_preexisting_cache_mismatch", "module_journal_install",
      "bootstrap did not install before the exact declared preexisting cache set", {
        actual: preexisting.map((entry) => entry.locator), expected: expectedPreexisting,
      });
  }
  state.preexisting = preexisting;
  state.bootstrapLoadedAtInstall = state.bootstrapLoaded;
  if (state.bootstrapLoadedAtInstall !== false) {
    contractFail("runtime_module_bootstrap_initial_loaded_invalid", "module_journal_install",
      "bootstrap initial loaded state was not captured as false");
  }
  preexisting.forEach((entry) => state.loadedLocators.add(entry.locator));
  const bootstrapModule = exactCacheDescriptor(state, bootstrapPath,
    "module_journal_install", false).module;
  const journalEntry = manifest.entries.find((entry) => entry.role === "journal");
  const helperEntry = manifest.entries.find((entry) => entry.role === "journal_helper");
  const journalModule = exactCacheDescriptor(state, pathForLocator(root, journalEntry.locator),
    "module_journal_install", false).module;
  const helperModule = exactCacheDescriptor(state, pathForLocator(root, helperEntry.locator),
    "module_journal_install", false).module;
  if (journalModule.parent !== bootstrapModule || helperModule.parent !== journalModule
      || !bootstrapModule.children.includes(journalModule)
      || !journalModule.children.includes(helperModule)) {
    contractFail("runtime_module_preexisting_graph_invalid", "module_journal_install",
      "bootstrap -> journal -> helper cache graph is not exact");
  }
  const journaledModuleLoadCore = function journaledModuleLoadCore(request, parent, isMain) {
    const attemptedAt = new Date().toISOString();
    if (state.sealed) {
      state.postSealAttempts.push({ attemptedAt, request: String(request),
        parentPath: parent && parent.filename ? path.resolve(parent.filename) : null });
      contractFail("runtime_module_load_after_seal", "module_journal_sealed",
        "no module load is allowed after journal seal", { request: String(request) });
    }
    assertHookIntegrity(state, "module_journal_load");
    if (typeof request !== "string" || request.length < 1) {
      contractFail("runtime_module_request_invalid", "module_journal_load",
        "Module._load request must be one non-empty string");
    }
    const parentPath = parent && parent.filename ? path.resolve(parent.filename) : null;
    const parentEntry = parentPath ? state.manifestByPath.get(keyPath(parentPath)) : null;
    if (!parentEntry || !parentEntry.loadable) {
      contractFail("runtime_module_parent_undeclared", "module_journal_load",
        "module request parent is absent from the explicit manifest", { request, parentPath });
    }
    const boundParent = exactCacheDescriptor(state, parentPath,
      "module_journal_load", false).module;
    if (boundParent !== parent) {
      contractFail("runtime_module_parent_identity_invalid", "module_journal_load",
        "module request parent is not the cache-bound Module identity", { request, parentPath });
    }
    let resolved;
    try { resolved = state.originalResolve.call(Module, request, parent, isMain); }
    catch (error) {
      state.failures.push({ request, parent: parentEntry.locator,
        errorCode: error && error.code || "resolve_failed" });
      throw error;
    }
    const builtin = BUILTINS.has(request) || BUILTINS.has(resolved)
      || (typeof resolved === "string" && BUILTINS.has(resolved.replace(/^node:/, "")));
    const event = { sequence: ++state.sequence, attemptedAt, request,
      parent: parentEntry.locator, isMain: isMain === true,
      kind: builtin ? "builtin" : "file", resolved: builtin ? String(resolved) : null,
      beforeSha256: null, beforeBytes: null, afterSha256: null, afterBytes: null,
      result: "in_progress" };
    state.events.push(event);
    if (builtin) {
      const builtinName = canonicalBuiltin(request);
      if (!state.builtinDeclarations.has(builtinName)) {
        event.result = "failed";
        event.errorCode = "runtime_module_builtin_not_declared";
        state.failures.push({ sequence: event.sequence, request, errorCode: event.errorCode });
        contractFail(event.errorCode, "module_journal_load",
          "builtin module is absent from the exact manifest allowlist", { request, builtinName });
      }
      try {
        const result = state.originalLoad.call(Module, request, parent, isMain);
        assertHookIntegrity(state, "module_journal_load_after");
        event.result = "loaded";
        event.resolved = builtinName;
        state.actualBuiltins.add(builtinName);
        return result;
      } catch (error) {
        try { assertHookIntegrity(state, "module_journal_builtin_failed_after"); }
        catch (integrityError) {
          state.integrityFailure = integrityError.code || "builtin_failed_integrity";
        }
        event.result = "failed";
        event.errorCode = error && error.code || "builtin_load_failed";
        state.failures.push({ sequence: event.sequence, request, errorCode: event.errorCode });
        throw error;
      }
    }
    if (typeof resolved !== "string" || !path.isAbsolute(resolved)) {
      event.result = "failed";
      event.errorCode = "runtime_module_resolved_path_invalid";
      state.failures.push({ sequence: event.sequence, request, errorCode: event.errorCode });
      contractFail(event.errorCode, "module_journal_load",
        "non-builtin module did not resolve to one absolute entity path", { request, resolved });
    }
    const entry = state.manifestByPath.get(keyPath(resolved));
    if (!entry || !entry.loadable) {
      event.result = "failed";
      event.errorCode = "runtime_module_external_not_declared";
      state.failures.push({ sequence: event.sequence, request, resolved, errorCode: event.errorCode });
      contractFail(event.errorCode, "module_journal_load",
        "resolved non-builtin module lacks an explicit loadable artifact", { request, resolved });
    }
    event.resolved = entry.locator;
    const resolvedKey = keyPath(resolved);
    const cacheBefore = exactCacheDescriptor(state, resolved,
      "module_journal_load_before", true);
    if (state.loadedLocators.has(entry.locator)) {
      if (!cacheBefore || state.moduleIdentityByPath.get(resolvedKey) !== cacheBefore.module) {
        contractFail("runtime_module_cache_reload_forbidden", "module_journal_load",
          "a completed module was removed/replaced before a repeated load", { locator: entry.locator });
      }
      event.cacheBefore = "hit";
    } else if (state.inFlightPaths.has(resolvedKey)) {
      if (!cacheBefore) {
        contractFail("runtime_module_inflight_cache_missing", "module_journal_load",
          "circular in-flight module lacks its exact cache identity", { locator: entry.locator });
      }
      event.cacheBefore = "in_flight_hit";
    } else {
      if (cacheBefore) {
        contractFail("runtime_module_cache_injected", "module_journal_load",
          "first observed module load was satisfied by a pre-injected cache entry",
          { locator: entry.locator });
      }
      event.cacheBefore = "miss";
      state.inFlightPaths.add(resolvedKey);
    }
    const startedHere = event.cacheBefore === "miss";
    const before = exactManifestFile(state.root, entry, "module_journal_load_before");
    event.beforeSha256 = before.sha256;
    event.beforeBytes = before.bytes;
    try {
      const result = state.originalLoad.call(Module, request, parent, isMain);
      const after = exactManifestFile(state.root, entry, "module_journal_load_after");
      event.afterSha256 = after.sha256;
      event.afterBytes = after.bytes;
      if (after.sha256 !== before.sha256 || after.bytes !== before.bytes) {
        contractFail("runtime_module_changed_during_load", "module_journal_load",
          "module bytes changed between resolution and completed load", { locator: entry.locator });
      }
      assertHookIntegrity(state, "module_journal_load_after");
      const cacheAfter = exactCacheDescriptor(state, resolved,
        "module_journal_load_after", false);
      const bound = state.moduleIdentityByPath.get(resolvedKey);
      if (!cacheAfter || bound !== cacheAfter.module) {
        contractFail("runtime_module_cache_identity_changed", "module_journal_load_after",
          "loaded module did not bind one stable require.cache Module identity",
          { locator: entry.locator });
      }
      event.result = "loaded";
      if (startedHere) {
        state.loadedLocators.add(entry.locator);
        state.inFlightPaths.delete(resolvedKey);
      }
      return result;
    } catch (error) {
      try {
        exactManifestFile(state.root, entry, "module_journal_load_failed_after");
        assertHookIntegrity(state, "module_journal_load_failed_after");
      } catch (integrityError) {
        state.integrityFailure = integrityError.code || "load_failed_integrity";
      }
      if (startedHere) state.inFlightPaths.delete(resolvedKey);
      event.result = "failed";
      event.errorCode = error && error.code || "module_load_failed";
      state.failures.push({ sequence: event.sequence, request, resolved: entry.locator,
        errorCode: event.errorCode });
      throw error;
    }
  };
  state.hook = function journaledModuleLoad(request, parent, isMain) {
    const attempt = ++state.attemptedLoads;
    try {
      const result = journaledModuleLoadCore(request, parent, isMain);
      state.completedLoads += 1;
      return result;
    } catch (error) {
      if (!state.sealed) state.failures.push({ attempt, request: String(request),
        errorCode: error && error.code || "module_load_failed" });
      throw error;
    }
  };
  Module._load = state.hook;
  if (Module._load !== state.hook) {
    contractFail("runtime_module_hook_install_failed", "module_journal_install",
      "Module._load journal hook was not installed exactly");
  }
  activeState = state;

  function checkpoint(phaseValue) {
    const phase = assertPhase(phaseValue);
    if (state.sealed || state.checkpointPhases.has(phase)
        || !state.manifest.requiredPhases.includes(phase)) {
      contractFail("runtime_module_checkpoint_invalid", "module_journal_checkpoint",
        "checkpoint is sealed, duplicated, or outside the manifest phase set", { phase });
    }
    assertHookIntegrity(state, "module_journal_checkpoint");
    verifyExplicitModuleManifest({ root: state.root, manifest: state.manifest });
    const cache = exactCacheSnapshot(state, "module_journal_checkpoint");
    const record = { schema: CHECKPOINT_SCHEMA, apiVersion: API_VERSION, phase,
      capturedAt: new Date().toISOString(), eventCount: state.events.length,
      bootstrapLoaded: state.bootstrapLoaded,
      resolverMachinerySha256: RESOLVER_MACHINERY_SHA256,
      loadedSetSha256: setDigest(Array.from(state.loadedLocators)),
      cacheSetSha256: setDigest(cache.map((entry) => entry.locator)) };
    record.checkpointSha256 = sha256Text(canonicalJson(record));
    state.checkpointPhases.add(phase);
    state.checkpoints.push(record);
    return Object.freeze(Object.assign({}, record));
  }

  function seal(phaseValue) {
    const phase = assertPhase(phaseValue);
    if (state.sealed || state.checkpointPhases.has(phase)
        || !state.manifest.requiredPhases.includes(phase)) {
      contractFail("runtime_module_seal_invalid", "module_journal_seal",
        "seal phase is duplicated or outside the manifest phase set", { phase });
    }
    assertHookIntegrity(state, "module_journal_seal");
    verifyExplicitModuleManifest({ root: state.root, manifest: state.manifest });
    if (state.failures.length !== 0) {
      contractFail("runtime_module_load_failure_recorded", "module_journal_seal",
        "one or more module resolution/load attempts failed", { failures: state.failures });
    }
    const cache = exactCacheSnapshot(state, "module_journal_seal");
    const coverage = assertExactCoverage(state, cache, "module_journal_seal");
    assertExactBuiltinCoverage(state, "module_journal_seal");
    state.sealRecord = { schema: CHECKPOINT_SCHEMA, apiVersion: API_VERSION, phase,
      capturedAt: new Date().toISOString(), eventCount: state.events.length,
      bootstrapLoaded: state.bootstrapLoaded,
      resolverMachinerySha256: RESOLVER_MACHINERY_SHA256,
      loadedSetSha256: setDigest(coverage.loaded), cacheSetSha256: setDigest(coverage.cached) };
    state.sealRecord.checkpointSha256 = sha256Text(canonicalJson(state.sealRecord));
    state.checkpointPhases.add(phase);
    state.sealed = true;
    return Object.freeze(Object.assign({}, state.sealRecord));
  }

  function reverifyAndRestore() {
    if (!state.sealed || state.restored) {
      contractFail("runtime_module_restore_invalid", "module_journal_restore",
        "journal must be sealed exactly once before terminal restore");
    }
    assertHookIntegrity(state, "module_journal_restore");
    if (state.postSealAttempts.length !== 0 || state.failures.length !== 0) {
      contractFail("runtime_module_terminal_failure", "module_journal_restore",
        "failed or post-seal module loads prevent terminal journal restoration", {
          failures: state.failures, postSealAttempts: state.postSealAttempts,
        });
    }
    verifyExplicitModuleManifest({ root: state.root, manifest: state.manifest });
    const cache = exactCacheSnapshot(state, "module_journal_restore");
    const coverage = assertExactCoverage(state, cache, "module_journal_restore");
    const builtins = assertExactBuiltinCoverage(state, "module_journal_restore");
    const phases = state.checkpoints.map((entry) => entry.phase).concat([state.sealRecord.phase]);
    if (canonicalJson(phases) !== canonicalJson(state.manifest.requiredPhases)) {
      contractFail("runtime_module_phase_set_mismatch", "module_journal_restore",
        "journal checkpoints do not exactly match ordered manifest phases", {
          actual: phases, expected: state.manifest.requiredPhases,
        });
    }
    Module._load = state.originalLoad;
    if (Module._load !== state.originalLoad || Module._resolveFilename !== state.originalResolve) {
      contractFail("runtime_module_hook_restore_failed", "module_journal_restore",
        "Node module loader hook was not restored exactly");
    }
    state.restored = true;
    activeState = null;
    const artifact = { schema: JOURNAL_SCHEMA, apiVersion: API_VERSION,
      admissionStatus: ADMISSION_STATUS, installedAt: state.installedAt,
      sealedAt: state.sealRecord.capturedAt, restoredAt: new Date().toISOString(),
      root: state.root, manifestSha256: state.manifest.manifestSha256,
      preexisting: state.preexisting, events: state.events,
      checkpoints: state.checkpoints, seal: state.sealRecord,
      bootstrapLoadedAtInstall: state.bootstrapLoadedAtInstall,
      bootstrapLoadedAtRestore: state.bootstrapLoaded,
      resolverMachinerySha256AtInstall: state.resolverMachinerySha256AtInstall,
      resolverMachinerySha256AtRestore: RESOLVER_MACHINERY_SHA256,
      loadedFiles: coverage.loaded.map((locator) => {
        const entry = state.manifest.entries.find((candidate) => candidate.locator === locator);
        return { locator, sha256: entry.sha256, bytes: entry.bytes };
      }),
      builtins,
      cacheAtRestore: cache, hookInstalled: true, hookExactAtSeal: true,
      hookExactAtRestore: true, originalHookRestored: true,
      failureCount: 0, postSealAttemptCount: 0 };
    artifact.evidenceSha256 = sha256Text(canonicalJson(artifact));
    return deepFreeze(artifact);
  }

  return Object.freeze({ checkpoint, seal, reverifyAndRestore });
}

function verifyRuntimeModuleJournal(options) {
  if (activeState) {
    contractFail("runtime_module_verify_while_active", "module_journal_verify",
      "offline journal verification requires the runtime hook to be restored first");
  }
  const resolverMachinerySha256 = assertResolverMachinery(
    "module_journal_verify", RESOLVER_PATH_CACHE);
  const root = assertExactDirectory(path.resolve(options.root), "module_journal_verify");
  const manifest = verifyExplicitModuleManifest({ root, manifest: options.manifest });
  const artifact = options.artifact;
  if (!isPlainObject(artifact) || artifact.schema !== JOURNAL_SCHEMA
      || artifact.apiVersion !== API_VERSION || artifact.admissionStatus !== ADMISSION_STATUS
      || !samePath(artifact.root || "", root)
      || artifact.manifestSha256 !== manifest.manifestSha256
      || !Number.isFinite(Date.parse(artifact.installedAt))
      || !Number.isFinite(Date.parse(artifact.sealedAt))
      || !Number.isFinite(Date.parse(artifact.restoredAt))
      || artifact.hookInstalled !== true || artifact.hookExactAtSeal !== true
      || artifact.hookExactAtRestore !== true || artifact.originalHookRestored !== true
      || artifact.bootstrapLoadedAtInstall !== false
      || typeof artifact.bootstrapLoadedAtRestore !== "boolean"
      || artifact.resolverMachinerySha256AtInstall !== resolverMachinerySha256
      || artifact.resolverMachinerySha256AtRestore !== resolverMachinerySha256
      || artifact.failureCount !== 0 || artifact.postSealAttemptCount !== 0
      || !/^[a-f0-9]{64}$/.test(String(artifact.evidenceSha256 || ""))) {
    contractFail("runtime_module_journal_invalid", "module_journal_verify",
      "sealed runtime module journal envelope is malformed");
  }
  const payload = Object.assign({}, artifact);
  delete payload.evidenceSha256;
  if (sha256Text(canonicalJson(payload)) !== artifact.evidenceSha256
      || !Array.isArray(artifact.preexisting) || !Array.isArray(artifact.events)
      || !Array.isArray(artifact.checkpoints) || !Array.isArray(artifact.loadedFiles)
      || !Array.isArray(artifact.builtins)
      || !Array.isArray(artifact.cacheAtRestore) || !isPlainObject(artifact.seal)) {
    contractFail("runtime_module_journal_digest_mismatch", "module_journal_verify",
      "sealed runtime module journal digest or arrays are invalid");
  }
  if (artifact.sealedAt !== artifact.seal.capturedAt) {
    contractFail("runtime_module_timestamp_binding_invalid", "module_journal_verify",
      "artifact sealedAt must exactly repeat the seal checkpoint capturedAt label");
  }
  const expectedLoaded = manifest.entries.filter((entry) => entry.loadable)
    .map((entry) => ({ locator: entry.locator, sha256: entry.sha256, bytes: entry.bytes }));
  if (canonicalJson(artifact.loadedFiles) !== canonicalJson(expectedLoaded)
      || canonicalJson(artifact.builtins)
        !== canonicalJson(manifest.builtins.map((entry) => entry.name).sort(compareText))
      || canonicalJson(artifact.cacheAtRestore) !== canonicalJson(expectedLoaded)
      || canonicalJson(artifact.preexisting) !== canonicalJson(manifest.entries
        .filter((entry) => entry.preexisting)
        .map((entry) => ({ locator: entry.locator, sha256: entry.sha256, bytes: entry.bytes })))) {
    contractFail("runtime_module_journal_coverage_mismatch", "module_journal_verify",
      "journal preexisting/loaded/cache sets do not exactly cover the explicit manifest");
  }
  const byLocator = new Map(manifest.entries.map((entry) => [entry.locator, entry]));
  const builtinNames = new Set(manifest.builtins.map((entry) => entry.name));
  const observedBuiltins = new Set();
  const prefixLoaded = new Set(manifest.entries.filter((entry) => entry.preexisting)
    .map((entry) => entry.locator));
  artifact.events.forEach((event, index) => {
    if (!isPlainObject(event) || event.sequence !== index + 1
        || !["builtin", "file"].includes(event.kind) || event.result !== "loaded"
        || typeof event.request !== "string" || typeof event.parent !== "string"
        || event.isMain !== false || !byLocator.has(event.parent)
        || !byLocator.get(event.parent).loadable || !prefixLoaded.has(event.parent)
        || !Number.isFinite(Date.parse(event.attemptedAt))) {
      contractFail("runtime_module_event_invalid", "module_journal_verify",
        "runtime module load event is malformed or failed", { index });
    }
    if (event.kind === "file") {
      const entry = byLocator.get(event.resolved);
      if (!entry || !entry.loadable || event.beforeSha256 !== entry.sha256
          || event.afterSha256 !== entry.sha256 || event.beforeBytes !== entry.bytes
          || event.afterBytes !== entry.bytes
          || !["miss", "hit", "in_flight_hit"].includes(event.cacheBefore)
          || (!prefixLoaded.has(entry.locator) && event.cacheBefore !== "miss")
          || (prefixLoaded.has(entry.locator) && event.cacheBefore === "miss")) {
        contractFail("runtime_module_event_binding_invalid", "module_journal_verify",
          "runtime file load event is not bound to manifest bytes", { index });
      }
      const parentPath = pathForLocator(root, event.parent);
      const parentModule = new Module(parentPath);
      parentModule.filename = parentPath;
      parentModule.paths = REFLECT_APPLY(RESOLVER_FUNCTIONS.get("_nodeModulePaths"), Module,
        [REFLECT_APPLY(RESOLVER_PATH_DIRNAME, path, [parentPath])]);
      let recomputed;
      try {
        recomputed = withIsolatedResolverPathCache("module_journal_verify", () =>
          REFLECT_APPLY(RESOLVER_FUNCTIONS.get("_resolveFilename"), Module,
            [event.request, parentModule, false]));
      } catch (error) {
        contractFail("runtime_module_event_resolution_invalid", "module_journal_verify",
          "runtime file request no longer resolves from its recorded parent", {
            index, request: event.request, parent: event.parent,
            errorCode: error && error.code || "resolve_failed",
          });
      }
      if (typeof recomputed !== "string" || !path.isAbsolute(recomputed)
          || !samePath(recomputed, pathForLocator(root, entry.locator))) {
        contractFail("runtime_module_event_resolution_invalid", "module_journal_verify",
          "runtime file request and parent do not derive the recorded resolved file", {
            index, request: event.request, parent: event.parent, resolved: event.resolved,
          });
      }
      prefixLoaded.add(entry.locator);
    } else {
      const builtinName = canonicalBuiltin(event.request);
      if (event.resolved !== builtinName || !builtinNames.has(builtinName)
          || event.beforeSha256 !== null || event.beforeBytes !== null
          || event.afterSha256 !== null || event.afterBytes !== null
          || Object.prototype.hasOwnProperty.call(event, "cacheBefore")) {
        contractFail("runtime_module_builtin_event_invalid", "module_journal_verify",
          "runtime builtin load event is not bound to the exact builtin allowlist", { index });
      }
      observedBuiltins.add(builtinName);
    }
  });
  if (canonicalJson(Array.from(observedBuiltins).sort(compareText)) !== canonicalJson(artifact.builtins)
      || canonicalJson(Array.from(prefixLoaded).sort(compareText))
        !== canonicalJson(expectedLoaded.map((entry) => entry.locator).sort(compareText))) {
    contractFail("runtime_module_event_coverage_mismatch", "module_journal_verify",
      "runtime events do not derive the sealed builtin/file coverage");
  }
  const phases = artifact.checkpoints.map((entry) => entry.phase).concat([artifact.seal.phase]);
  if (canonicalJson(phases) !== canonicalJson(manifest.requiredPhases)) {
    contractFail("runtime_module_phase_set_mismatch", "module_journal_verify",
      "sealed journal phase set differs from explicit manifest");
  }
  let previousEventCount = 0;
  let bootstrapObservedTrue = false;
  let previousBootstrapLoaded = artifact.bootstrapLoadedAtInstall;
  artifact.checkpoints.concat([artifact.seal]).forEach((checkpoint, checkpointIndex, all) => {
    const digest = checkpoint.checkpointSha256;
    const checkpointPayload = Object.assign({}, checkpoint);
    delete checkpointPayload.checkpointSha256;
    if (!isPlainObject(checkpoint) || checkpoint.schema !== CHECKPOINT_SCHEMA
        || checkpoint.apiVersion !== API_VERSION || !Number.isFinite(Date.parse(checkpoint.capturedAt))
        || !Number.isInteger(checkpoint.eventCount) || checkpoint.eventCount < 0
        || typeof checkpoint.bootstrapLoaded !== "boolean"
        || checkpoint.resolverMachinerySha256 !== resolverMachinerySha256
        || checkpoint.eventCount < previousEventCount
        || checkpoint.eventCount > artifact.events.length
        || !/^[a-f0-9]{64}$/.test(String(checkpoint.loadedSetSha256 || ""))
        || !/^[a-f0-9]{64}$/.test(String(checkpoint.cacheSetSha256 || ""))
        || sha256Text(canonicalJson(checkpointPayload)) !== digest) {
      contractFail("runtime_module_checkpoint_invalid", "module_journal_verify",
        "runtime module checkpoint is malformed");
    }
    const loadedAtCheckpoint = new Set(manifest.entries.filter((entry) => entry.preexisting)
      .map((entry) => entry.locator));
    artifact.events.slice(0, checkpoint.eventCount).forEach((event) => {
      if (event.kind === "file") loadedAtCheckpoint.add(event.resolved);
    });
    const expectedSetDigest = setDigest(Array.from(loadedAtCheckpoint));
    if ((previousBootstrapLoaded === true && checkpoint.bootstrapLoaded === false)
        || (bootstrapObservedTrue && checkpoint.bootstrapLoaded === false)) {
      contractFail("runtime_module_bootstrap_loaded_semantics_invalid", "module_journal_verify",
        "bootstrap loaded evidence is not monotonic false→true");
    }
    bootstrapObservedTrue = bootstrapObservedTrue || checkpoint.bootstrapLoaded;
    previousBootstrapLoaded = checkpoint.bootstrapLoaded;
    if (checkpoint.loadedSetSha256 !== expectedSetDigest
        || checkpoint.cacheSetSha256 !== expectedSetDigest
        || (checkpointIndex === all.length - 1
          && checkpoint.eventCount !== artifact.events.length)) {
      contractFail("runtime_module_checkpoint_semantics_invalid", "module_journal_verify",
        "checkpoint digests/event prefix do not match the runtime events");
    }
    previousEventCount = checkpoint.eventCount;
  });
  if ((previousBootstrapLoaded === true && artifact.bootstrapLoadedAtRestore === false)
      || artifact.bootstrapLoadedAtRestore !== artifact.seal.bootstrapLoaded) {
    contractFail("runtime_module_bootstrap_loaded_semantics_invalid", "module_journal_verify",
      "terminal bootstrap loaded evidence regressed or changed after seal");
  }
  assertResolverMachinery("module_journal_verify", RESOLVER_PATH_CACHE);
  return artifact;
}

module.exports = {
  API_VERSION,
  ADMISSION_STATUS,
  CHECKPOINT_SCHEMA,
  JOURNAL_SCHEMA,
  MANIFEST_SCHEMA,
  buildExplicitModuleManifest,
  installRuntimeModuleJournal,
  verifyExplicitModuleManifest,
  verifyRuntimeModuleJournal,
};
