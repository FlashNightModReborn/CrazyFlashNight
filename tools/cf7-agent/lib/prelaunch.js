'use strict';

const childProcess = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const path = require('node:path');
const {
  AgentClient,
  randomOpaqueId,
} = require('./client');
const {
  opaqueId,
  validateAppLaunchResult,
} = require('./contract');
const {
  loadDeveloperCredential,
} = require('./developer-credential');
const {
  readRendezvous,
} = require('./rendezvous');

const FIXED_PROJECT_ROOT = path.resolve(
  __dirname,
  '..',
  '..',
  '..',
);
const FIXED_START_SCRIPT = path.join(
  FIXED_PROJECT_ROOT,
  'automation',
  'start.ps1',
);
const FIXED_POWERSHELL_EXE = resolveSystemPowerShell();
const FIXED_CAPABILITIES = Object.freeze(['app.launch']);
const FIXED_ENTRY_POINT = 'standard_entry';
const FIXED_RUNTIME_MODE = 'formal_runtime';
const DEFAULT_PRELAUNCH_TIMEOUT_MS = 180_000;
const DEFAULT_POLL_INTERVAL_MS = 100;
const RETRYABLE_AGENT_CODES = new Set([
  'ECONNREFUSED',
  'ENOENT',
  'EPIPE',
  'connection_timeout',
  'connection_closed',
  'request_timeout',
]);
const SPAWN_ALLOWED_RENDEZVOUS_CODES = new Set([
  'rendezvous_not_found',
  'process_stale',
]);
const WAIT_ONLY_RENDEZVOUS_CODES = new Set([
  'rendezvous_changed',
  'ticket_expired',
  'ticket_expiry_invalid',
]);

class PrelaunchError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'PrelaunchError';
    this.code = code;
  }
}

async function launchFormalRuntime(
  options,
  dependencyOverrides = {},
) {
  const clientInstanceId = requireClientInstanceId(
    options?.clientInstanceId,
  );
  const dependencies = createDependencies(
    dependencyOverrides,
  );
  assertFixedBootstrapPaths(dependencies.fileSystem);

  const credential = loadLaunchCredential(
    dependencies,
    clientInstanceId,
  );
  const deadline =
    dependencies.now() + dependencies.timeoutMs;
  let bootstrap = null;
  let bootstrapStarted = false;
  let spawnProhibited = false;
  let guardianConfirmed = false;
  let completed = false;

  try {
    while (dependencies.now() <= deadline) {
      const discovery = discoverFormalRuntime(
        dependencies,
      );
      if (discovery.kind === 'ready') {
        guardianConfirmed = true;
        try {
          const receipt = await callFixedLaunch(
            dependencies,
            credential,
            clientInstanceId,
            discovery.rendezvous,
            deadline,
          );
          completed = true;
          return receipt;
        } catch (error) {
          if (error instanceof PrelaunchError)
            throw error;
          if (!isRetryableAgentError(error)) {
            throw new PrelaunchError(
              'agent_authentication_failed',
              'The formal runtime rejected the authenticated launch handoff.',
            );
          }
        }
      } else {
        if (discovery.spawnProhibited)
          spawnProhibited = true;
        if (
          !bootstrapStarted
          && !spawnProhibited
          && discovery.spawnAllowed
        ) {
          bootstrap = startFixedBootstrap(
            dependencies,
          );
          bootstrapStarted = true;
        }
      }

      if (bootstrap?.spawnError) {
        throw new PrelaunchError(
          'human_intervention_required',
          'The fixed formal-runtime bootstrap could not be started.',
        );
      }
      await dependencies.sleep(
        dependencies.pollIntervalMs,
      );
    }

    throw new PrelaunchError(
      'human_intervention_required',
      guardianConfirmed
        ? 'The formal runtime did not complete the authenticated launch handoff before the fixed timeout.'
        : 'The fixed bootstrap did not publish an authenticated formal-runtime rendezvous before the fixed timeout.',
    );
  } finally {
    if (!completed && !guardianConfirmed)
      cleanupOwnedBootstrap(bootstrap);
  }
}

function createDependencies(overrides) {
  const timeoutMs = overrides.timeoutMs
    ?? DEFAULT_PRELAUNCH_TIMEOUT_MS;
  const pollIntervalMs = overrides.pollIntervalMs
    ?? DEFAULT_POLL_INTERVAL_MS;
  if (
    !Number.isSafeInteger(timeoutMs)
    || timeoutMs < 1
    || timeoutMs > DEFAULT_PRELAUNCH_TIMEOUT_MS
    || !Number.isSafeInteger(pollIntervalMs)
    || pollIntervalMs < 1
    || pollIntervalMs > timeoutMs
  ) {
    throw new PrelaunchError(
      'prelaunch_configuration_invalid',
      'The internal pre-launch timeout configuration is invalid.',
    );
  }
  return {
    fileSystem: overrides.fileSystem ?? fs,
    loadCredential:
      overrides.loadCredential
        ?? loadDeveloperCredential,
    readRendezvous:
      overrides.readRendezvous
        ?? readRendezvous,
    connectClient:
      overrides.connectClient
        ?? AgentClient.connect,
    spawnProcess:
      overrides.spawnProcess
        ?? childProcess.spawn,
    createRequestId:
      overrides.createRequestId
        ?? randomOpaqueId,
    now: overrides.now ?? Date.now,
    sleep: overrides.sleep ?? sleep,
    localAppData:
      overrides.localAppData
        ?? process.env.LOCALAPPDATA,
    processProbe: overrides.processProbe,
    connectionFactory:
      overrides.connectionFactory,
    timeoutMs,
    pollIntervalMs,
  };
}

function requireClientInstanceId(value) {
  try {
    opaqueId(value, '$.clientInstanceId');
    return value;
  } catch {
    throw new PrelaunchError(
      'client_instance_id_required',
      'An explicit opaque clientInstanceId is required.',
    );
  }
}

function assertFixedBootstrapPaths(fileSystem) {
  assertFixedRegularFile(
    fileSystem,
    FIXED_START_SCRIPT,
    'The repository-owned formal-runtime bootstrap is unavailable.',
  );
  assertFixedRegularFile(
    fileSystem,
    FIXED_POWERSHELL_EXE,
    'The system Windows PowerShell bootstrap host is unavailable.',
  );
}

function assertFixedStartScript(fileSystem) {
  assertFixedBootstrapPaths(fileSystem);
}

function assertFixedRegularFile(
  fileSystem,
  fixedPath,
  message,
) {
  try {
    if (typeof fixedPath !== 'string' || fixedPath === '')
      throw new Error('fixed path unavailable');
    const descriptor = fileSystem.lstatSync(
      fixedPath,
    );
    if (
      !descriptor.isFile()
      || descriptor.isSymbolicLink()
    ) {
      throw new Error('not a regular file');
    }
    const realPath = (
      fileSystem.realpathSync.native
        ?? fileSystem.realpathSync
    )(fixedPath);
    if (!sameWindowsPath(realPath, fixedPath)) {
      throw new Error('path resolves elsewhere');
    }
  } catch {
    throw new PrelaunchError(
      'bootstrap_path_invalid',
      message,
    );
  }
}

function loadLaunchCredential(
  dependencies,
  clientInstanceId,
) {
  let credential;
  try {
    credential = dependencies.loadCredential({
      projectRoot: FIXED_PROJECT_ROOT,
      clientInstanceId,
      localAppData: dependencies.localAppData,
      now: dependencies.now(),
    });
  } catch {
    throw new PrelaunchError(
      'developer_credential_invalid',
      'A valid protected developer credential is required.',
    );
  }
  if (
    !Array.isArray(credential.allowedCapabilities)
    || !credential.allowedCapabilities.includes('app.launch')
  ) {
    throw new PrelaunchError(
      'capability_denied',
      'The developer credential does not allow app.launch.',
    );
  }
  return credential;
}

function discoverFormalRuntime(dependencies) {
  try {
    const rendezvous = dependencies.readRendezvous({
      projectRoot: FIXED_PROJECT_ROOT,
      localAppData: dependencies.localAppData,
      processProbe: dependencies.processProbe,
      now: dependencies.now(),
    });
    if (
      rendezvous.runtimeQualificationState
      !== FIXED_RUNTIME_MODE
    ) {
      throw new PrelaunchError(
        'runtime_mode_conflict',
        'A non-formal runtime is already active.',
      );
    }
    return {
      kind: 'ready',
      rendezvous,
      spawnAllowed: false,
      spawnProhibited: true,
    };
  } catch (error) {
    if (error instanceof PrelaunchError) throw error;
    if (SPAWN_ALLOWED_RENDEZVOUS_CODES.has(error?.code)) {
      return {
        kind: 'unavailable',
        spawnAllowed: true,
        spawnProhibited: false,
      };
    }
    if (WAIT_ONLY_RENDEZVOUS_CODES.has(error?.code)) {
      return {
        kind: 'unavailable',
        spawnAllowed: false,
        spawnProhibited: true,
      };
    }
    throw new PrelaunchError(
      'rendezvous_invalid',
      'The protected Agent Runtime rendezvous is invalid.',
    );
  }
}

function startFixedBootstrap(dependencies) {
  const argumentsList = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    FIXED_START_SCRIPT,
  ];
  let child;
  try {
    child = dependencies.spawnProcess(
      FIXED_POWERSHELL_EXE,
      argumentsList,
      {
        cwd: FIXED_PROJECT_ROOT,
        windowsHide: true,
        stdio: 'ignore',
        shell: false,
      },
    );
  } catch {
    throw new PrelaunchError(
      'human_intervention_required',
      'The fixed formal-runtime bootstrap could not be started.',
    );
  }
  if (
    child === null
    || typeof child !== 'object'
    || typeof child.kill !== 'function'
  ) {
    throw new PrelaunchError(
      'human_intervention_required',
      'The fixed formal-runtime bootstrap could not be started.',
    );
  }
  const state = {
    child,
    exited:
      child.exitCode !== null
      && child.exitCode !== undefined,
    spawnError: false,
  };
  child.once?.('error', () => {
    state.spawnError = true;
  });
  child.once?.('exit', () => {
    state.exited = true;
  });
  child.unref?.();
  return state;
}

async function callFixedLaunch(
  dependencies,
  credential,
  clientInstanceId,
  rendezvous,
  deadline,
) {
  const launchRequestId =
    dependencies.createRequestId();
  try {
    opaqueId(
      launchRequestId,
      '$.launchRequestId',
    );
  } catch {
    throw new PrelaunchError(
      'request_identity_invalid',
      'The pre-launch request identity could not be created.',
    );
  }
  const requestTimeoutMs = Math.max(
    1,
    Math.min(30_000, deadline - dependencies.now()),
  );
  let client;
  try {
    client = await dependencies.connectClient({
      projectRoot: FIXED_PROJECT_ROOT,
      rendezvous,
      requestedCapabilities: FIXED_CAPABILITIES,
      clientKind: 'jsonl_cli',
      clientInstanceId,
      credentialProof: credential.credentialProof,
      requestTimeoutMs,
      connectionFactory:
        dependencies.connectionFactory
        ?? createNamedPipeConnectionFactory(
          requestTimeoutMs,
        ),
    });
    const receipt = await client.call(
      'app.launch',
      {
        launchRequestId,
        entryPoint: FIXED_ENTRY_POINT,
        runtimeMode: FIXED_RUNTIME_MODE,
      },
    );
    validateAppLaunchResult(receipt);
    if (
      receipt.launchRequestId !== launchRequestId
      || receipt.entryPoint !== FIXED_ENTRY_POINT
      || receipt.runtimeMode !== FIXED_RUNTIME_MODE
      || receipt.started !== false
      || receipt.alreadyRunning !== true
    ) {
      throw new PrelaunchError(
        'launch_receipt_invalid',
        'The formal runtime returned an invalid launch receipt.',
      );
    }
    return receipt;
  } finally {
    client?.close();
  }
}

function isRetryableAgentError(error) {
  return RETRYABLE_AGENT_CODES.has(error?.code)
    || error?.errorPayload?.data?.reasonCode
      === 'connection_ticket_expired';
}

function createNamedPipeConnectionFactory(timeoutMs) {
  return (pipePath) => new Promise((resolve, reject) => {
    const stream = net.createConnection(pipePath);
    let settled = false;
    let timer;
    const finish = (callback, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      stream.removeListener('error', fail);
      callback(value);
    };
    const fail = (error) => {
      stream.destroy();
      finish(reject, error);
    };
    timer = setTimeout(() => {
      const error = new Error(
        'Timed out connecting to the Agent Runtime pipe.',
      );
      error.code = 'connection_timeout';
      fail(error);
    }, timeoutMs);
    stream.once('error', fail);
    stream.once('connect', () => {
      finish(resolve, stream);
    });
  });
}

function cleanupOwnedBootstrap(state) {
  if (
    !state
    || state.exited
    || state.child.exitCode !== null
    && state.child.exitCode !== undefined
    || state.child.signalCode !== null
    && state.child.signalCode !== undefined
  ) {
    return;
  }
  try {
    state.child.kill();
  } catch {
  }
}

function sameWindowsPath(left, right) {
  return path.resolve(left)
    .replaceAll('/', '\\')
    .toUpperCase()
    === path.resolve(right)
      .replaceAll('/', '\\')
      .toUpperCase();
}

function resolveSystemPowerShell() {
  const systemRoot =
    process.env.SystemRoot ?? process.env.WINDIR;
  if (
    typeof systemRoot !== 'string'
    || !path.win32.isAbsolute(systemRoot)
  ) {
    return null;
  }
  return path.win32.join(
    systemRoot,
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe',
  );
}

function sleep(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

module.exports = {
  DEFAULT_PRELAUNCH_TIMEOUT_MS,
  FIXED_CAPABILITIES,
  FIXED_ENTRY_POINT,
  FIXED_POWERSHELL_EXE,
  FIXED_PROJECT_ROOT,
  FIXED_RUNTIME_MODE,
  FIXED_START_SCRIPT,
  PrelaunchError,
  assertFixedBootstrapPaths,
  assertFixedStartScript,
  createNamedPipeConnectionFactory,
  launchFormalRuntime,
};
