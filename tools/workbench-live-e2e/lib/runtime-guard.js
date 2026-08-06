"use strict";

const childProcess = require("child_process");
const net = require("net");
const path = require("path");
const RuntimeIdentity = require("../../lib/runtime-process-identity");
const {
  canonicalJson,
  contractFail,
  isPlainObject,
  samePath,
  sha256Text,
} = require("./evidence-artifact");

const API_VERSION = "FROZEN-v1";

function parseWindowsCommandLine(commandLine) {
  const source = String(commandLine || "");
  if (!source || /[\0\r\n]/.test(source)) {
    contractFail("windows_command_line_invalid", "runtime",
      "observed process command line is empty or contains a forbidden character");
  }
  const args = [];
  let index = 0;
  while (index < source.length) {
    while (index < source.length && /[ \t]/.test(source[index])) index += 1;
    if (index >= source.length) break;
    let value = "";
    let quoted = false;
    let consumed = false;
    while (index < source.length) {
      if (!quoted && /[ \t]/.test(source[index])) break;
      let slashes = 0;
      while (source[index] === "\\") { slashes += 1; index += 1; }
      if (source[index] === '"') {
        value += "\\".repeat(Math.floor(slashes / 2));
        if (slashes % 2 === 1) {
          value += '"';
          index += 1;
        } else {
          index += 1;
          if (quoted && source[index] === '"') {
            value += '"';
            index += 1;
          } else {
            quoted = !quoted;
          }
        }
        consumed = true;
        continue;
      }
      value += "\\".repeat(slashes);
      if (index >= source.length || (!quoted && /[ \t]/.test(source[index]))) break;
      value += source[index];
      index += 1;
      consumed = true;
    }
    if (quoted || !consumed) {
      contractFail("windows_command_line_invalid", "runtime",
        "observed process command line cannot be parsed exactly");
    }
    args.push(value);
  }
  if (args.length < 1) {
    contractFail("windows_command_line_invalid", "runtime",
      "observed process command line has no arguments");
  }
  return args;
}

function allocateLoopbackCdpPort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.once("error", reject);
    server.listen({ host: "127.0.0.1", port: 0, exclusive: true }, () => {
      const address = server.address();
      const port = address && Number(address.port);
      server.close((error) => {
        if (error) return reject(error);
        if (!Number.isInteger(port) || port < 1024 || port > 65535) {
          return reject(new Error("operating system returned an invalid CDP port"));
        }
        return resolve({ port, allocatedAt: new Date().toISOString(), exclusiveBeforeLaunch: true });
      });
    });
  });
}

function withScopedEnvironment(overrides, callback, options) {
  if (!isPlainObject(overrides) || typeof callback !== "function") {
    contractFail("scoped_environment_invalid", "launcher", "environment scope arguments are invalid");
  }
  const settings = options || {};
  const forbiddenNonEmpty = new Set(settings.forbiddenNonEmpty || []);
  const previous = {};
  Object.keys(overrides).forEach((name) => {
    previous[name] = process.env[name];
    if (forbiddenNonEmpty.has(name) && previous[name] && previous[name].trim()) {
      contractFail("environment_preexisting", "launcher",
        "refusing to replace a pre-existing launch environment value", { name });
    }
    const value = overrides[name];
    if (value == null) delete process.env[name];
    else process.env[name] = String(value);
  });
  try { return callback(); }
  finally {
    Object.keys(overrides).forEach((name) => {
      if (previous[name] === undefined) delete process.env[name];
      else process.env[name] = previous[name];
    });
  }
}

function withWebViewDebugEnvironment(cdpPort, callback) {
  if (!Number.isInteger(cdpPort) || cdpPort < 1024 || cdpPort > 65535) {
    contractFail("cdp_port_invalid", "launcher", "runner-owned CDP port is invalid", { cdpPort });
  }
  return withScopedEnvironment({
    CF7_WEBVIEW2_ARGS: "--remote-debugging-port=" + cdpPort,
    CF7_WEBVIEW2_DEV_MODE: "1",
  }, callback, { forbiddenNonEmpty: ["CF7_WEBVIEW2_ARGS"] });
}

function resolveBeforeMutation(options) {
  if (!options || typeof options.assertNoRuntime !== "function"
      || typeof options.resolveIdentity !== "function"
      || typeof options.prepareMutation !== "function") {
    contractFail("candidate_prepare_contract_invalid", "preparation",
      "candidate-before-mutation callbacks are incomplete");
  }
  options.assertNoRuntime();
  const expectedIdentity = options.resolveIdentity();
  if (!isPlainObject(expectedIdentity)) {
    contractFail("candidate_identity_invalid", "preparation",
      "candidate identity must resolve before any clone mutation");
  }
  const preparation = options.prepareMutation(expectedIdentity);
  return { expectedIdentity, preparation };
}

function validateCandidateIdentity(identity, candidateRoot) {
  const root = path.resolve(candidateRoot || "");
  const expectedProcess = path.join(root, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe");
  if (!isPlainObject(identity) || identity.runtimeMode !== "isolated_candidate"
      || !samePath(identity.installRoot || root, root)
      || !samePath(identity.processPath || "", expectedProcess)
      || !/^[A-Fa-f0-9]{64}$/.test(String(identity.coreSha256 || ""))
      || !/^[A-Fa-f0-9]{64}$/.test(String(identity.buildIdentity || ""))
      || !/^[A-Fa-f0-9]{64}$/.test(String(identity.payloadClosure || ""))) {
    contractFail("candidate_identity_invalid", "candidate_identity",
      "candidate identity is not one exact isolated installation", { candidateRoot: root });
  }
  return identity;
}

function publicCandidateIdentity(identity) {
  return {
    runtimeMode: identity.runtimeMode,
    processPath: path.resolve(identity.processPath),
    coreSha256: String(identity.coreSha256).toUpperCase(),
    buildIdentity: String(identity.buildIdentity).toUpperCase(),
    payloadClosure: String(identity.payloadClosure).toUpperCase(),
    installRoot: path.resolve(identity.installRoot),
  };
}

function resolveCandidateIdentityBeforeMutation(options) {
  if (!options || typeof options.assertNoRuntime !== "function"
      || typeof options.prepareClone !== "function" || !options.root || !options.candidateRoot) {
    contractFail("candidate_prepare_contract_invalid", "candidate_identity",
      "candidate-before-clone contract is incomplete");
  }
  options.assertNoRuntime();
  const resolved = RuntimeIdentity.resolveExpectedRuntimeIdentity(options.root, options.candidateRoot);
  validateCandidateIdentity(resolved, options.candidateRoot);
  const identity = publicCandidateIdentity(resolved);
  const identitySha256 = sha256Text(canonicalJson(identity));
  const resolvedAt = new Date().toISOString();
  const preparation = options.prepareClone(Object.freeze(Object.assign({}, identity)), {
    schema: "workbench-live-e2e.candidate-before-clone.v1",
    apiVersion: API_VERSION,
    resolvedAt,
    identitySha256,
  });
  return { schema: "workbench-live-e2e.candidate-before-clone.v1",
    apiVersion: API_VERSION, resolvedAt, identity, identitySha256, preparation };
}

function assertByteInvariant(before, after, options) {
  const settings = options || {};
  const shaField = settings.shaField || "sha256";
  const bytesField = settings.bytesField || "bytes";
  if (!isPlainObject(before) || !isPlainObject(after)
      || before[shaField] !== after[shaField] || before[bytesField] !== after[bytesField]) {
    contractFail(settings.code || "byte_invariant_changed", settings.phase || "invariant",
      settings.message || "read-only source bytes changed", { before, after });
  }
  return { sha256: after[shaField], bytes: after[bytesField] };
}

function assertRuntimeCdpBinding(binding, identity, trustedExpectations) {
  const trusted = trustedExpectations;
  const allowedTrustedKeys = new Set(["expectedPageUrl", "expectedPageOrigin",
    "expectedUserDataRoot", "expectedListenerExecutableName",
    "expectedListenerExecutablePath", "expectedPageContentSha256", "expectedPageContentBytes"]);
  let expectedOrigin = null;
  try { expectedOrigin = new URL(String(trusted && trusted.expectedPageUrl || "")).origin; }
  catch (_error) { expectedOrigin = null; }
  const hasKnownContentSha = isPlainObject(trusted)
    && Object.prototype.hasOwnProperty.call(trusted, "expectedPageContentSha256");
  const hasKnownContentBytes = isPlainObject(trusted)
    && Object.prototype.hasOwnProperty.call(trusted, "expectedPageContentBytes");
  if (!isPlainObject(binding) || !isPlainObject(identity) || !isPlainObject(trusted)
      || Object.keys(trusted).some((key) => !allowedTrustedKeys.has(key))
      || typeof trusted.expectedPageUrl !== "string" || !trusted.expectedPageUrl
      || typeof trusted.expectedPageOrigin !== "string"
      || trusted.expectedPageOrigin !== expectedOrigin
      || typeof trusted.expectedUserDataRoot !== "string"
      || !path.isAbsolute(trusted.expectedUserDataRoot)
      || !/^[A-Za-z0-9._-]+\.exe$/i.test(String(trusted.expectedListenerExecutableName || ""))
      || (trusted.expectedListenerExecutablePath != null
        && (typeof trusted.expectedListenerExecutablePath !== "string"
          || !path.isAbsolute(trusted.expectedListenerExecutablePath)))
      || hasKnownContentSha !== hasKnownContentBytes
      || (hasKnownContentSha
        && (!/^[a-f0-9]{64}$/.test(String(trusted.expectedPageContentSha256 || ""))
          || !Number.isInteger(trusted.expectedPageContentBytes)
          || trusted.expectedPageContentBytes < 1))
      || !Number.isInteger(binding.port) || binding.port < 1024 || binding.port > 65535
      || !Number.isInteger(identity.pid) || binding.runtimePid !== identity.pid
      || binding.exclusiveBeforeLaunch !== true
      || binding.configurationSource !== "CF7_WEBVIEW2_ARGS"
      || binding.developerMode !== true || !isPlainObject(binding.attestation)
      || binding.attestation.port !== binding.port
      || binding.attestation.runtimePid !== identity.pid
      || !Number.isInteger(binding.attestation.listenerPid)
      || !Array.isArray(binding.attestation.ancestorPids)
      || !binding.attestation.ancestorPids.includes(identity.pid)
      || binding.attestation.exactPortArgument !== true
      || binding.attestation.exactUserDataRoot !== true
      || typeof binding.attestation.userDataRoot !== "string"
      || !samePath(binding.attestation.userDataRoot, trusted.expectedUserDataRoot)
      || typeof binding.attestation.listenerExecutablePath !== "string"
      || !path.isAbsolute(binding.attestation.listenerExecutablePath)
      || path.basename(binding.attestation.listenerExecutablePath).toLowerCase()
        !== trusted.expectedListenerExecutableName.toLowerCase()
      || String(binding.attestation.listenerExecutable || "").toLowerCase()
        !== trusted.expectedListenerExecutableName.toLowerCase()
      || (trusted.expectedListenerExecutablePath != null
        && !samePath(binding.attestation.listenerExecutablePath,
          trusted.expectedListenerExecutablePath))
      || !/^[a-f0-9]{64}$/.test(String(binding.attestation.commandLineSha256 || ""))
      || !/^[a-f0-9]{64}$/.test(String(binding.attestation.argvSha256 || ""))
      || !Number.isFinite(Date.parse(binding.allocatedAt))
      || !Number.isFinite(Date.parse(binding.attestation.observedAt))
      || Date.parse(binding.attestation.observedAt) < Date.parse(binding.allocatedAt)
      || Date.parse(binding.attestation.observedAt) - Date.parse(binding.allocatedAt) > 10 * 60 * 1000
      || !isPlainObject(binding.pageIdentity)
      || !expectedOrigin || binding.expectedPageUrl !== trusted.expectedPageUrl
      || binding.pageIdentity.url !== trusted.expectedPageUrl
      || binding.pageIdentity.origin !== trusted.expectedPageOrigin
      || !Number.isFinite(binding.pageIdentity.timeOrigin)
      || !["interactive", "complete"].includes(binding.pageIdentity.readyState)
      || typeof binding.pageIdentity.userAgent !== "string" || !binding.pageIdentity.userAgent
      || sha256Text(canonicalJson(binding.pageIdentity)) !== binding.pageIdentitySha256
      || !/^[a-f0-9]{64}$/.test(String(binding.pageContentSha256 || ""))
      || !Number.isInteger(binding.pageContentBytes) || binding.pageContentBytes < 1
      || (hasKnownContentSha
        && (binding.pageContentSha256 !== trusted.expectedPageContentSha256
          || binding.pageContentBytes !== trusted.expectedPageContentBytes))
      || !Number.isFinite(Date.parse(binding.pageContentCapturedAt))
      || Date.parse(binding.pageContentCapturedAt) < Date.parse(binding.attestation.observedAt)
      || Date.parse(binding.pageContentCapturedAt) - Date.parse(binding.attestation.observedAt) > 60000) {
    contractFail("cdp_runtime_binding_invalid", "runtime",
      "CDP endpoint is not causally bound to the authenticated runtime PID");
  }
  return binding;
}

function assertFreshRestartIdentity(options) {
  const first = options && options.first;
  const restart = options && options.restart;
  const stableFields = ["runtimeMode", "coreSha256", "buildIdentity", "payloadClosure"];
  if (!isPlainObject(first) || !isPlainObject(restart)
      || !Number.isInteger(first.pid) || !Number.isInteger(restart.pid)
      || first.pid === restart.pid || !samePath(first.processPath || "", restart.processPath || "")
      || stableFields.some((field) => first[field] !== restart[field])
      || typeof options.firstAttemptId !== "string" || !options.firstAttemptId
      || typeof options.restartAttemptId !== "string" || !options.restartAttemptId
      || options.firstAttemptId === options.restartAttemptId) {
    contractFail("restart_identity_not_fresh", "restart",
      "restart must use a fresh PID/attempt with the same candidate identity");
  }
  return { firstPid: first.pid, restartPid: restart.pid,
    firstAttemptId: options.firstAttemptId, restartAttemptId: options.restartAttemptId,
    buildIdentity: first.buildIdentity, payloadClosure: first.payloadClosure };
}

function runPowerShellJson(script, phase) {
  const result = childProcess.spawnSync("powershell.exe", [
    "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script,
  ], { encoding: "utf8", windowsHide: true, timeout: 30000 });
  if (result.status !== 0) {
    contractFail("windows_observation_failed", phase || "runtime",
      "read-only Windows process observation failed", {
        status: result.status,
        stderr: String(result.stderr || "").slice(-2000),
      });
  }
  const text = String(result.stdout || "").trim();
  if (!text) return [];
  try {
    const value = JSON.parse(text);
    return Array.isArray(value) ? value : [value];
  } catch (error) {
    contractFail("windows_observation_invalid", phase || "runtime", error.message);
  }
}

function attestLoopbackCdpEndpoint(options) {
  const port = Number(options.port);
  const runtimePid = Number(options.runtimePid);
  if (!Number.isInteger(port) || port < 1024 || port > 65535
      || !Number.isInteger(runtimePid) || runtimePid < 1) {
    contractFail("cdp_attestation_input_invalid", "runtime", "CDP attestation input is invalid");
  }
  const listeners = runPowerShellJson(
    "$ErrorActionPreference='Stop'; @(Get-NetTCPConnection -State Listen -LocalPort " + port
      + " | Where-Object { $_.LocalAddress -in @('127.0.0.1','::1') }"
      + " | Select-Object LocalAddress,LocalPort,OwningProcess) | ConvertTo-Json -Compress",
    "runtime");
  const ipv4Listeners = listeners.filter((entry) => entry.LocalAddress === "127.0.0.1");
  const listenerPids = Array.from(new Set(ipv4Listeners.map((entry) => Number(entry.OwningProcess))
    .filter((value) => Number.isInteger(value) && value > 0)));
  if (listenerPids.length !== 1) {
    contractFail("cdp_listener_not_exact", "runtime",
      "runner-owned CDP port does not have one exact IPv4 loopback listener", {
        port, listenerPids,
      });
  }
  const processes = runPowerShellJson(
    "$ErrorActionPreference='Stop'; @(Get-CimInstance Win32_Process"
      + " | Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine)"
      + " | ConvertTo-Json -Compress -Depth 3",
    "runtime");
  const byPid = new Map(processes.map((entry) => [Number(entry.ProcessId), entry]));
  const listenerPid = listenerPids[0];
  const listener = byPid.get(listenerPid);
  if (!listener) {
    contractFail("cdp_listener_process_missing", "runtime", "CDP listener process is absent");
  }
  const ancestorPids = [];
  const visited = new Set();
  let current = listener;
  for (let depth = 0; current && depth < 32; depth += 1) {
    const pid = Number(current.ProcessId);
    if (!Number.isInteger(pid) || visited.has(pid)) break;
    visited.add(pid);
    ancestorPids.push(pid);
    if (pid === runtimePid) break;
    current = byPid.get(Number(current.ParentProcessId));
  }
  const commandLine = String(listener.CommandLine || "");
  const executablePath = String(listener.ExecutablePath || "");
  const expectedPortArg = "--remote-debugging-port=" + port;
  const expectedUserDataRoot = options.expectedUserDataRoot
    ? path.resolve(options.expectedUserDataRoot) : null;
  const argv = parseWindowsCommandLine(commandLine);
  const portArguments = argv.filter((entry) => entry.toLowerCase()
    .startsWith("--remote-debugging-port="));
  const exactPortArguments = portArguments.filter((entry) => entry === expectedPortArg);
  const userDataArguments = argv.filter((entry) => entry.toLowerCase().startsWith("--user-data-dir="));
  const exactUserDataArguments = expectedUserDataRoot ? userDataArguments.filter((entry) =>
    samePath(entry.slice("--user-data-dir=".length), expectedUserDataRoot)) : [];
  if (!ancestorPids.includes(runtimePid) || !samePath(argv[0] || "", executablePath)
      || portArguments.length !== 1 || exactPortArguments.length !== 1
      || (expectedUserDataRoot
        && (userDataArguments.length !== 1 || exactUserDataArguments.length !== 1))
      || (options.expectedExecutableName
        && path.basename(executablePath).toLowerCase() !== String(options.expectedExecutableName).toLowerCase())) {
    contractFail("cdp_listener_process_mismatch", "runtime",
      "CDP listener is not an authenticated runtime descendant with the exact launch arguments", {
        listenerPid,
        runtimePid,
        ancestorPids,
      });
  }
  return {
    schema: "workbench-live-e2e.cdp-endpoint-attestation.v1",
    observedAt: new Date().toISOString(),
    port,
    runtimePid,
    listenerPid,
    listenerLocalAddress: "127.0.0.1",
    ancestorPids,
    listenerExecutablePath: path.resolve(executablePath),
    listenerExecutable: path.basename(executablePath),
    commandLineSha256: sha256Text(commandLine),
    argvSha256: sha256Text(canonicalJson(argv)),
    exactPortArgument: true,
    exactUserDataRoot: expectedUserDataRoot ? true : null,
    userDataRoot: expectedUserDataRoot,
  };
}

module.exports = {
  API_VERSION,
  allocateLoopbackCdpPort,
  assertByteInvariant,
  assertFreshRestartIdentity,
  assertRuntimeCdpBinding,
  attestLoopbackCdpEndpoint,
  parseWindowsCommandLine,
  publicCandidateIdentity,
  resolveCandidateIdentityBeforeMutation,
  resolveBeforeMutation,
  validateCandidateIdentity,
  withScopedEnvironment,
  withWebViewDebugEnvironment,
};
