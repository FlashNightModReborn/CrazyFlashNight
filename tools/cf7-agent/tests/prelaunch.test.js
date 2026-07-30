'use strict';

const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const path = require('node:path');
const test = require('node:test');
const {
  FIXED_POWERSHELL_EXE,
  FIXED_PROJECT_ROOT,
  FIXED_START_SCRIPT,
  launchFormalRuntime,
} = require('../lib/prelaunch');
const {
  parsePrelaunchArguments,
  runPrelaunchCli,
} = require('../prelaunch');

const CLIENT_ID = 'CCCCCCCCCCCCCCCCCCCCCC';
const CREDENTIAL_PROOF =
  'NEVER_PRINT_THIS_PRELAUNCH_SECRET_1234567890';
const REQUEST_ID = 'RRRRRRRRRRRRRRRRRRRRRR';

test('pre-launch spawn is the exact parameterized formal standard entry', async () => {
  const child = new FakeChild();
  const spawns = [];
  const calls = [];
  const connections = [];
  let reads = 0;
  const dependencies = fastDependencies({
    readRendezvous() {
      reads++;
      if (reads === 1) throw coded(
        'rendezvous_not_found',
      );
      return formalRendezvous();
    },
    spawnProcess(file, args, options) {
      spawns.push({ file, args, options });
      return child;
    },
    async connectClient(options) {
      connections.push(options);
      return fakeClient(calls);
    },
  });

  const receipt = await launchFormalRuntime(
    { clientInstanceId: CLIENT_ID },
    dependencies,
  );

  assert.deepEqual(receipt, launchReceipt(REQUEST_ID));
  assert.equal(
    FIXED_PROJECT_ROOT,
    path.resolve(__dirname, '..', '..', '..'),
  );
  assert.equal(
    FIXED_START_SCRIPT,
    path.join(
      FIXED_PROJECT_ROOT,
      'automation',
      'start.ps1',
    ),
  );
  assert.deepEqual(spawns, [{
    file: FIXED_POWERSHELL_EXE,
    args: [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      FIXED_START_SCRIPT,
    ],
    options: {
      cwd: FIXED_PROJECT_ROOT,
      windowsHide: true,
      stdio: 'ignore',
      shell: false,
    },
  }]);
  assert.equal(path.win32.isAbsolute(spawns[0].file), true);
  assert.equal(
    spawns[0].file.toLowerCase().endsWith(
      '\\system32\\windowspowershell\\v1.0\\powershell.exe',
    ),
    true,
  );
  assert.equal(
    JSON.stringify(spawns).includes(CLIENT_ID),
    false,
  );
  assert.equal(
    JSON.stringify(spawns).includes(CREDENTIAL_PROOF),
    false,
  );
  assert.equal(
    spawns[0].args.includes('-CandidateRoot'),
    false,
  );
  assert.equal(
    spawns[0].args.includes(
      '-EnableLegacyHttpAutomation',
    ),
    false,
  );
  assert.equal(child.unrefCount, 1);
  assert.equal(child.killCount, 0);
  assert.equal(connections.length, 1);
  assert.equal(
    connections[0].projectRoot,
    FIXED_PROJECT_ROOT,
  );
  assert.deepEqual(
    connections[0].requestedCapabilities,
    ['app.launch'],
  );
  assert.equal(
    connections[0].credentialProof,
    CREDENTIAL_PROOF,
  );
  assert.deepEqual(calls, [{
    method: 'app.launch',
    params: {
      launchRequestId: REQUEST_ID,
      entryPoint: 'standard_entry',
      runtimeMode: 'formal_runtime',
    },
  }]);
});

test('developer credential without app.launch fails before discovery or spawn', async () => {
  let reads = 0;
  let spawns = 0;
  let connections = 0;
  const dependencies = fastDependencies({
    loadCredential() {
      return {
        credentialProof: CREDENTIAL_PROOF,
        allowedCapabilities: ['session.status'],
      };
    },
    readRendezvous() {
      reads++;
      return formalRendezvous();
    },
    spawnProcess() {
      spawns++;
      return new FakeChild();
    },
    async connectClient() {
      connections++;
      return fakeClient([]);
    },
  });

  await assert.rejects(
    launchFormalRuntime(
      { clientInstanceId: CLIENT_ID },
      dependencies,
    ),
    (error) => error.code === 'capability_denied',
  );
  assert.equal(reads, 0);
  assert.equal(spawns, 0);
  assert.equal(connections, 0);
});

test('already-running formal runtime authenticates without starting bootstrap', async () => {
  const calls = [];
  let spawns = 0;
  let closeCount = 0;
  const dependencies = fastDependencies({
    readRendezvous: () => formalRendezvous(),
    spawnProcess() {
      spawns++;
      return new FakeChild();
    },
    async connectClient() {
      const client = fakeClient(calls);
      client.close = () => {
        closeCount++;
      };
      return client;
    },
  });

  const receipt = await launchFormalRuntime(
    { clientInstanceId: CLIENT_ID },
    dependencies,
  );

  assert.deepEqual(receipt, launchReceipt(REQUEST_ID));
  assert.equal(spawns, 0);
  assert.equal(closeCount, 1);
  assert.equal(calls.length, 1);
});

test('missing rendezvous starts once and hands off only after formal rendezvous', async () => {
  const child = new FakeChild();
  let reads = 0;
  let spawns = 0;
  let connections = 0;
  const dependencies = fastDependencies({
    readRendezvous() {
      reads++;
      if (reads < 3)
        throw coded('rendezvous_not_found');
      return formalRendezvous();
    },
    spawnProcess() {
      spawns++;
      return child;
    },
    async connectClient() {
      connections++;
      return fakeClient([]);
    },
  });

  await launchFormalRuntime(
    { clientInstanceId: CLIENT_ID },
    dependencies,
  );

  assert.equal(reads, 3);
  assert.equal(spawns, 1);
  assert.equal(connections, 1);
  assert.equal(child.killCount, 0);
});

test('timeout kills only the owned unfinished bootstrap and keeps secrets out of errors', async () => {
  const child = new FakeChild();
  const dependencies = fastDependencies({
    timeoutMs: 20,
    pollIntervalMs: 10,
    readRendezvous() {
      throw coded('rendezvous_not_found');
    },
    spawnProcess() {
      return child;
    },
  });

  let observed;
  try {
    await launchFormalRuntime(
      { clientInstanceId: CLIENT_ID },
      dependencies,
    );
  } catch (error) {
    observed = error;
  }

  assert.equal(
    observed?.code,
    'human_intervention_required',
  );
  assert.equal(
    String(observed?.message).includes(CREDENTIAL_PROOF),
    false,
  );
  assert.equal(child.killCount, 1);
});

test('non-formal rendezvous and caller-selected launch controls fail closed', async () => {
  let spawns = 0;
  await assert.rejects(
    launchFormalRuntime(
      { clientInstanceId: CLIENT_ID },
      fastDependencies({
        readRendezvous() {
          return {
            ...formalRendezvous(),
            runtimeQualificationState:
              'isolated_candidate',
          };
        },
        spawnProcess() {
          spawns++;
          return new FakeChild();
        },
      }),
    ),
    (error) => error.code === 'runtime_mode_conflict',
  );
  assert.equal(spawns, 0);
  for (const argv of [
    ['--project-root', FIXED_PROJECT_ROOT],
    ['--credential-proof', CREDENTIAL_PROOF],
    ['--runtime-mode', 'isolated_candidate'],
    ['--candidate-root', 'C:\\candidate'],
    ['--legacy'],
  ]) {
    assert.throws(
      () => parsePrelaunchArguments(argv),
      (error) => error.code === 'argument_invalid',
    );
  }
});

test('CLI writes one minimal receipt line and redacts arbitrary failures', async () => {
  const output = collector();
  const diagnostic = collector();
  const receipt = launchReceipt(REQUEST_ID);
  const success = await runPrelaunchCli({
    argv: ['--client-instance-id', CLIENT_ID],
    output,
    diagnostic,
    async launchAuthority() {
      return receipt;
    },
  });
  assert.equal(success, 0);
  assert.equal(
    output.text(),
    `${JSON.stringify(receipt)}\n`,
  );
  assert.equal(
    output.text().trim().split('\n').length,
    1,
  );
  assert.equal(diagnostic.text(), '');

  const failedOutput = collector();
  const failedDiagnostic = collector();
  const failure = await runPrelaunchCli({
    argv: ['--client-instance-id', CLIENT_ID],
    output: failedOutput,
    diagnostic: failedDiagnostic,
    async launchAuthority() {
      throw new Error(CREDENTIAL_PROOF);
    },
  });
  assert.equal(failure, 1);
  assert.equal(failedOutput.text(), '');
  assert.equal(
    failedDiagnostic.text().includes(CREDENTIAL_PROOF),
    false,
  );
  assert.equal(
    failedDiagnostic.text().trim().split('\n').length,
    1,
  );
});

function fastDependencies(overrides = {}) {
  let now = 0;
  return {
    timeoutMs: 100,
    pollIntervalMs: 10,
    loadCredential() {
      return {
        credentialProof: CREDENTIAL_PROOF,
        allowedCapabilities: ['app.launch'],
      };
    },
    readRendezvous: () => formalRendezvous(),
    spawnProcess: () => new FakeChild(),
    async connectClient() {
      return fakeClient([]);
    },
    createRequestId: () => REQUEST_ID,
    now: () => now,
    async sleep(milliseconds) {
      now += milliseconds;
    },
    ...overrides,
  };
}

function fakeClient(calls) {
  return {
    async call(method, params) {
      calls.push({ method, params });
      return launchReceipt(params.launchRequestId);
    },
    close() {
    },
  };
}

function formalRendezvous() {
  return {
    runtimeQualificationState: 'formal_runtime',
  };
}

function launchReceipt(launchRequestId) {
  return {
    launchRequestId,
    entryPoint: 'standard_entry',
    started: false,
    alreadyRunning: true,
    runtimeMode: 'formal_runtime',
    minimalSessionRef: {
      projectRunning: true,
      qualificationState: 'verified',
      lifecycleRef: 'LLLLLLLLLLLLLLLLLLLLLL',
    },
  };
}

function coded(code) {
  return Object.assign(new Error(code), { code });
}

class FakeChild extends EventEmitter {
  constructor() {
    super();
    this.exitCode = null;
    this.signalCode = null;
    this.killCount = 0;
    this.unrefCount = 0;
  }

  kill() {
    this.killCount++;
    this.signalCode = 'SIGTERM';
    return true;
  }

  unref() {
    this.unrefCount++;
  }
}

function collector() {
  let value = '';
  return {
    write(chunk) {
      value += String(chunk);
    },
    text() {
      return value;
    },
  };
}
