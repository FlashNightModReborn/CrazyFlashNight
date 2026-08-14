"use strict";

const fs = require("fs");
const Module = require("module");
const path = require("path");
const Evidence = require("./evidence-artifact");

const DESCRIPTOR_SCHEMA =
  "workbench-live-e2e.playwright-websocket-toolchain.v1";
const RUNTIME_BINDING_SCHEMA =
  "workbench-live-e2e.playwright-websocket-runtime-binding.v1";
const FILES = Object.freeze([
  { role: "package_lock", relativePath: "launcher/perf/package-lock.json" },
  { role: "installed_package_manifest",
    relativePath: "launcher/perf/node_modules/playwright-core/package.json" },
  { role: "websocket_entry",
    relativePath: "launcher/perf/node_modules/playwright-core/lib/utilsBundle.js" },
  { role: "websocket_implementation",
    relativePath: "launcher/perf/node_modules/playwright-core/lib/utilsBundleImpl/index.js" },
]);
const OPTIONAL_NATIVE_MODULES = Object.freeze(["bufferutil", "utf-8-validate"]);
const BUILTIN_SET = new Set(Module.builtinModules.concat(
  Module.builtinModules.map((entry) => "node:" + entry)));
const ACTIVE_RUNTIME_BINDINGS = new Map();

function fail(code, message, details) {
  const error = new Error(message || code);
  error.code = code;
  error.phase = "playwright_websocket_toolchain";
  error.details = details || null;
  throw error;
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function directDirectoryChain(rootValue, targetValue) {
  const root = path.resolve(rootValue);
  const target = path.resolve(targetValue);
  if (!Evidence.pathInside(root, target)) {
    fail("playwright_toolchain_path_escape", "toolchain path escaped the canonical root", {
      root, target,
    });
  }
  const relative = path.relative(root, target);
  const segments = relative ? relative.split(path.sep) : [];
  let cursor = root;
  [""].concat(segments.slice(0, -1)).forEach((segment, index) => {
    if (index > 0) cursor = path.join(cursor, segment);
    let stat;
    let real;
    try {
      stat = fs.lstatSync(cursor);
      real = fs.realpathSync.native(cursor);
    } catch (error) {
      fail("playwright_toolchain_directory_unavailable", error.message, { directory: cursor });
    }
    if (!stat.isDirectory() || stat.isSymbolicLink() || !samePath(real, cursor)) {
      fail("playwright_toolchain_directory_reparse", "toolchain ancestor is not a direct directory", {
        directory: cursor, real,
      });
    }
  });
  return target;
}

function exactFile(root, descriptor) {
  const absolutePath = directDirectoryChain(root,
    path.join(root, descriptor.relativePath.replace(/\//g, path.sep)));
  const file = Evidence.readExactRegularFile(absolutePath, {
    phase: "playwright_websocket_toolchain", maximumBytes: 32 * 1024 * 1024,
  });
  return { record: { role: descriptor.role, relativePath: descriptor.relativePath,
    absolutePath: file.path, bytes: file.length, sha256: file.sha256 },
  content: file.bytes };
}

function parseJson(file, label) {
  try { return JSON.parse(file.content.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { fail("playwright_toolchain_json_invalid", label + ": " + error.message); }
}

function packageProjection(files) {
  const byRole = new Map(files.map((entry) => [entry.record.role, entry]));
  const lock = parseJson(byRole.get("package_lock"), "package_lock");
  const installed = parseJson(byRole.get("installed_package_manifest"), "package_manifest");
  const lockRoot = lock && lock.packages && lock.packages[""];
  const lockedPlaywright = lock && lock.packages
    && lock.packages["node_modules/playwright"];
  const lockedCore = lock && lock.packages
    && lock.packages["node_modules/playwright-core"];
  if (!lockRoot || lock.lockfileVersion !== 3
      || !lockedPlaywright || !lockedCore
      || installed.name !== "playwright-core"
      || typeof installed.version !== "string" || !/^\d+\.\d+\.\d+$/.test(installed.version)
      || lockedCore.version !== installed.version
      || !lockedPlaywright.dependencies
      || lockedPlaywright.dependencies["playwright-core"] !== installed.version
      || typeof lockedCore.resolved !== "string" || typeof lockedCore.integrity !== "string"
      || typeof lockedPlaywright.resolved !== "string"
      || typeof lockedPlaywright.integrity !== "string"
      || !lockRoot.dependencies || typeof lockRoot.dependencies.playwright !== "string") {
    fail("playwright_toolchain_lock_mismatch",
      "installed playwright-core is detached from the exact package lock");
  }
  return { lockfileVersion: lock.lockfileVersion,
    declaredPlaywright: lockRoot.dependencies.playwright,
    playwrightVersion: lockedPlaywright.version,
    playwrightResolved: lockedPlaywright.resolved,
    playwrightIntegrity: lockedPlaywright.integrity,
    playwrightCoreVersion: installed.version,
    playwrightCoreResolved: lockedCore.resolved,
    playwrightCoreIntegrity: lockedCore.integrity };
}

function unsignedDescriptor(value) {
  const copy = Object.assign({}, value);
  delete copy.descriptorSha256;
  return copy;
}

function captureDescriptorBundle(rootValue) {
  const root = path.resolve(rootValue);
  directDirectoryChain(root, path.join(root, "__root_probe__"));
  const captures = FILES.map((entry) => exactFile(root, entry));
  const files = captures.map((entry) => entry.record);
  const value = { schema: DESCRIPTOR_SCHEMA, canonicalRoot: root,
    nodeVersion: process.version, package: packageProjection(captures), files };
  value.descriptorSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(unsignedDescriptor(value)));
  return { descriptor: value, captures };
}

function captureDescriptor(rootValue) {
  return captureDescriptorBundle(rootValue).descriptor;
}

function validateDescriptor(value, rootValue, options) {
  const settings = options || {};
  const root = path.resolve(rootValue);
  const exactKeys = ["schema", "canonicalRoot", "nodeVersion", "package", "files",
    "descriptorSha256"].sort();
  if (!value || typeof value !== "object"
      || Evidence.canonicalJson(Object.keys(value).sort()) !== Evidence.canonicalJson(exactKeys)
      || value.schema !== DESCRIPTOR_SCHEMA || !samePath(value.canonicalRoot, root)
      || value.nodeVersion !== process.version || !Array.isArray(value.files)
      || value.files.length !== FILES.length
      || value.descriptorSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(unsignedDescriptor(value)))) {
    fail("playwright_toolchain_descriptor_invalid",
      "Playwright WebSocket descriptor is malformed or detached");
  }
  const current = captureDescriptor(root);
  if (Evidence.canonicalJson(current) !== Evidence.canonicalJson(value)) {
    fail("playwright_toolchain_descriptor_drift",
      "canonical Playwright WebSocket runtime changed after capture");
  }
  if (settings.expectedPackageLock) {
    const lock = value.files.find((entry) => entry.role === "package_lock");
    if (!lock || lock.sha256 !== settings.expectedPackageLock.sha256
        || lock.bytes !== settings.expectedPackageLock.bytes) {
      fail("playwright_toolchain_package_lock_unbound",
        "external toolchain package lock differs from the protected scope");
    }
  }
  return value;
}

function byRole(descriptor, role) {
  const matches = descriptor.files.filter((entry) => entry.role === role);
  if (matches.length !== 1) fail("playwright_toolchain_descriptor_invalid",
    "toolchain file role is not unique", { role });
  return matches[0];
}

function assertOptionalNativeFallback(entryPath) {
  const resolver = Module.createRequire(entryPath);
  OPTIONAL_NATIVE_MODULES.forEach((request) => {
    let resolved = null;
    try { resolved = resolver.resolve(request); }
    catch (error) {
      if (!error || error.code !== "MODULE_NOT_FOUND") throw error;
    }
    if (resolved !== null) {
      fail("playwright_toolchain_optional_native_present",
        "optional WebSocket native acceleration must remain unavailable", {
          request, resolved,
        });
    }
  });
}

function runtimeProjection(descriptor, builtinRequests) {
  const entry = byRole(descriptor, "websocket_entry");
  const implementation = byRole(descriptor, "websocket_implementation");
  const cache = [entry, implementation].map((file) => ({ relativePath: file.relativePath,
    absolutePath: file.absolutePath, bytes: file.bytes, sha256: file.sha256 }));
  return { schema: RUNTIME_BINDING_SCHEMA,
    descriptorSha256: descriptor.descriptorSha256,
    entryPath: entry.absolutePath, implementationPath: implementation.absolutePath,
    moduleCache: cache, builtinRequests: Array.from(new Set(builtinRequests)).sort(),
    optionalNativeModules: OPTIONAL_NATIVE_MODULES.map((request) => ({ request,
      resolution: "MODULE_NOT_FOUND", fallbackForced: true })),
    environment: { WS_NO_BUFFER_UTIL: "1", WS_NO_UTF_8_VALIDATE: "1" },
    websocketSurface: { exportName: "ws", type: "function", openState: 1 } };
}

function createRuntimeBinding(descriptor, builtinRequests) {
  const value = runtimeProjection(descriptor, builtinRequests);
  value.bindingSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function validateRuntimeBinding(value, descriptor) {
  validateDescriptor(descriptor, descriptor.canonicalRoot);
  const exactKeys = ["schema", "descriptorSha256", "entryPath", "implementationPath",
    "moduleCache", "builtinRequests", "optionalNativeModules", "environment",
    "websocketSurface", "bindingSha256"].sort();
  if (!value || typeof value !== "object"
      || Evidence.canonicalJson(Object.keys(value).sort()) !== Evidence.canonicalJson(exactKeys)
      || value.schema !== RUNTIME_BINDING_SCHEMA
      || !Array.isArray(value.builtinRequests)
      || value.builtinRequests.some((entry, index) => !BUILTIN_SET.has(entry)
        || index > 0 && value.builtinRequests[index - 1].localeCompare(entry) >= 0)
      || value.bindingSha256 !== Evidence.sha256Text(Evidence.canonicalJson(
        Object.fromEntries(Object.entries(value).filter(([key]) => key !== "bindingSha256"))))
      || Evidence.canonicalJson(value)
        !== Evidence.canonicalJson(createRuntimeBinding(descriptor, value.builtinRequests))) {
    fail("playwright_toolchain_runtime_binding_invalid",
      "Playwright WebSocket runtime binding is malformed or detached");
  }
  return value;
}

function compileCapturedModule(filePath, content, parent) {
  const loadedModule = new Module(filePath, parent || module);
  loadedModule.filename = filePath;
  loadedModule.paths = Module._nodeModulePaths(path.dirname(filePath));
  require.cache[filePath] = loadedModule;
  try {
    loadedModule._compile(content.toString("utf8").replace(/^\uFEFF/, ""), filePath);
    loadedModule.loaded = true;
    return loadedModule.exports;
  } catch (error) {
    delete require.cache[filePath];
    throw error;
  }
}

function guardedLoad(descriptorValue) {
  const descriptor = validateDescriptor(descriptorValue, descriptorValue.canonicalRoot);
  const captured = captureDescriptorBundle(descriptor.canonicalRoot);
  if (Evidence.canonicalJson(captured.descriptor) !== Evidence.canonicalJson(descriptor)) {
    fail("playwright_toolchain_descriptor_drift",
      "canonical Playwright WebSocket runtime changed before captured-byte execution");
  }
  const entry = byRole(descriptor, "websocket_entry");
  const implementation = byRole(descriptor, "websocket_implementation");
  const sourceByPath = new Map(captured.captures.map((item) => [
    path.resolve(item.record.absolutePath).toLowerCase(), item,
  ]));
  const resolver = Module.createRequire(entry.absolutePath);
  if (!samePath(resolver.resolve(entry.absolutePath), entry.absolutePath)
      || !samePath(resolver.resolve("./utilsBundleImpl"), implementation.absolutePath)) {
    fail("playwright_toolchain_resolution_drift",
      "Playwright WebSocket entry or implementation resolved outside the descriptor");
  }
  assertOptionalNativeFallback(entry.absolutePath);
  const expected = [entry.absolutePath, implementation.absolutePath];
  if (expected.some((filePath) => Object.prototype.hasOwnProperty.call(require.cache, filePath))) {
    fail("playwright_toolchain_cache_preseeded",
      "Playwright WebSocket runtime was present in require.cache before guarded load");
  }
  const previousEnvironment = OPTIONAL_NATIVE_MODULES.map((request) => {
    const name = request === "bufferutil" ? "WS_NO_BUFFER_UTIL" : "WS_NO_UTF_8_VALIDATE";
    return { name, present: Object.prototype.hasOwnProperty.call(process.env, name),
      value: process.env[name] };
  });
  process.env.WS_NO_BUFFER_UTIL = "1";
  process.env.WS_NO_UTF_8_VALIDATE = "1";
  const before = new Set(Object.keys(require.cache).map((entryPath) => path.resolve(entryPath)));
  const builtinRequests = [];
  const originalLoad = Module._load;
  Module._load = function guardedModuleLoad(request, parent, isMain) {
    let resolved;
    if (BUILTIN_SET.has(request)) {
      builtinRequests.push(request);
    } else {
      resolved = Module._resolveFilename(request, parent, isMain);
      if (!expected.some((allowed) => samePath(allowed, resolved))) {
        fail("playwright_toolchain_transitive_module_forbidden",
          "Playwright WebSocket load reached an undeclared external module", {
            request, resolved,
          });
      }
      const source = sourceByPath.get(path.resolve(resolved).toLowerCase());
      if (!source) {
        fail("playwright_toolchain_transitive_module_forbidden",
          "allowed Playwright module has no fd-verified source capture", { request, resolved });
      }
      if (require.cache[source.record.absolutePath]) {
        return require.cache[source.record.absolutePath].exports;
      }
      return compileCapturedModule(source.record.absolutePath, source.content, parent);
    }
    return originalLoad.apply(this, arguments);
  };
  let loaded;
  let loadError = null;
  try {
    const entrySource = sourceByPath.get(path.resolve(entry.absolutePath).toLowerCase());
    loaded = compileCapturedModule(entry.absolutePath, entrySource.content, module);
  }
  catch (error) { loadError = error; }
  finally {
    Module._load = originalLoad;
    previousEnvironment.forEach((item) => {
      if (item.present) process.env[item.name] = item.value;
      else delete process.env[item.name];
    });
  }
  if (loadError) {
    expected.forEach((filePath) => { delete require.cache[filePath]; });
    throw loadError;
  }
  const added = Object.keys(require.cache).map((entryPath) => path.resolve(entryPath))
    .filter((entryPath) => !before.has(entryPath)).sort((left, right) => left.localeCompare(right));
  const expectedSorted = expected.slice().map((entryPath) => path.resolve(entryPath))
    .sort((left, right) => left.localeCompare(right));
  validateDescriptor(descriptor, descriptor.canonicalRoot);
  assertOptionalNativeFallback(entry.absolutePath);
  if (Evidence.canonicalJson(added) !== Evidence.canonicalJson(expectedSorted)
      || expected.some((filePath) => !require.cache[filePath]
        || !samePath(require.cache[filePath].filename, filePath))
      || !loaded || typeof loaded.ws !== "function" || loaded.ws.OPEN !== 1) {
    fail("playwright_toolchain_runtime_load_invalid",
      "guarded Playwright WebSocket load did not produce the exact two-file runtime");
  }
  const binding = createRuntimeBinding(descriptor, builtinRequests);
  ACTIVE_RUNTIME_BINDINGS.set(binding.bindingSha256, {
    entryModule: require.cache[entry.absolutePath],
    implementationModule: require.cache[implementation.absolutePath],
    entryExports: loaded,
    implementationExports: require.cache[implementation.absolutePath].exports,
    WebSocket: loaded.ws,
  });
  return { WebSocket: loaded.ws, binding };
}

function reverifyLoaded(descriptorValue, bindingValue) {
  const descriptor = validateDescriptor(descriptorValue, descriptorValue.canonicalRoot);
  const binding = validateRuntimeBinding(bindingValue, descriptor);
  const entry = byRole(descriptor, "websocket_entry");
  const implementation = byRole(descriptor, "websocket_implementation");
  assertOptionalNativeFallback(entry.absolutePath);
  const entryCache = require.cache[entry.absolutePath];
  const implementationCache = require.cache[implementation.absolutePath];
  const active = ACTIVE_RUNTIME_BINDINGS.get(binding.bindingSha256);
  if (!active || !entryCache || !implementationCache
      || entryCache !== active.entryModule
      || implementationCache !== active.implementationModule
      || !samePath(entryCache.filename, entry.absolutePath)
      || !samePath(implementationCache.filename, implementation.absolutePath)
      || entryCache.exports !== active.entryExports
      || implementationCache.exports !== active.implementationExports
      || entryCache.exports.ws !== active.WebSocket
      || typeof active.WebSocket !== "function" || active.WebSocket.OPEN !== 1) {
    fail("playwright_toolchain_runtime_cache_drift",
      "loaded Playwright WebSocket cache no longer matches its runtime binding");
  }
  return { WebSocket: entryCache.exports.ws, binding };
}

function replayRuntimeBinding(descriptorValue, bindingValue) {
  const descriptor = validateDescriptor(descriptorValue, descriptorValue.canonicalRoot);
  validateRuntimeBinding(bindingValue, descriptor);
  const entry = byRole(descriptor, "websocket_entry");
  const implementation = byRole(descriptor, "websocket_implementation");
  const present = [entry.absolutePath, implementation.absolutePath]
    .map((filePath) => Object.prototype.hasOwnProperty.call(require.cache, filePath));
  if (present[0] !== present[1]) {
    fail("playwright_toolchain_runtime_cache_drift",
      "Playwright WebSocket cache contains a split entry/implementation state");
  }
  const replay = present[0] ? reverifyLoaded(descriptor, bindingValue)
    : guardedLoad(descriptor);
  if (Evidence.canonicalJson(replay.binding) !== Evidence.canonicalJson(bindingValue)) {
    fail("playwright_toolchain_runtime_replay_drift",
      "fresh guarded Playwright load differs from the recorded runtime binding");
  }
  return replay;
}

module.exports = {
  DESCRIPTOR_SCHEMA,
  FILES,
  OPTIONAL_NATIVE_MODULES,
  RUNTIME_BINDING_SCHEMA,
  captureDescriptor,
  guardedLoad,
  replayRuntimeBinding,
  reverifyLoaded,
  validateDescriptor,
  validateRuntimeBinding,
};
