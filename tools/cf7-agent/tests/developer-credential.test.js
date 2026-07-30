'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');
const {
  CREDENTIAL_SCHEMA,
  MAXIMUM_CREDENTIAL_BYTES,
  developerCredentialPath,
  loadDeveloperCredential,
} = require('../lib/developer-credential');
const { parseAdapterOptions } = require('../lib/options');

const CLIENT_ID = 'CCCCCCCCCCCCCCCCCCCCCC';
const OTHER_CLIENT_ID = 'DDDDDDDDDDDDDDDDDDDDDD';
const PROOF = 'PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP';
const PROJECT_ROOT = path.resolve(__dirname, '../../..');
const FIXED_NOW = Date.now();

test('shared adapter options load the exact developer credential', (t) => {
  const fixture = createFixture(t);
  writeCredential(fixture, validCredential());
  const options = parseAdapterOptions([
    '--project-root',
    PROJECT_ROOT,
    '--client-instance-id',
    CLIENT_ID,
    '--capability',
    'session.status',
  ], {
    LOCALAPPDATA: fixture.localAppData,
  });
  assert.equal(options.clientInstanceId, CLIENT_ID);
  assert.equal(options.credentialProof, PROOF);
  assert.deepEqual(options.requestedCapabilities, [
    'session.status',
  ]);
});

test('environment client ID uses the same shared credential loader', (t) => {
  const fixture = createFixture(t);
  writeCredential(fixture, validCredential());
  const options = parseAdapterOptions([
    '--project-root',
    PROJECT_ROOT,
    '--capability',
    'session.status',
  ], {
    LOCALAPPDATA: fixture.localAppData,
    CF7_AGENT_CLIENT_INSTANCE_ID: CLIENT_ID,
  });
  assert.equal(options.clientInstanceId, CLIENT_ID);
  assert.equal(options.credentialProof, PROOF);
});

test('explicit proof takes priority and never requires a credential file', () => {
  const options = parseAdapterOptions([
    '--project-root',
    PROJECT_ROOT,
    '--client-instance-id',
    CLIENT_ID,
    '--credential-proof',
    'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
    '--capability',
    'session.status',
  ], {});
  assert.equal(
    options.credentialProof,
    'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
  );
});

test('adapter options reject a missing explicit client ID', () => {
  assert.throws(
    () => parseAdapterOptions([
      '--credential-proof',
      'XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
      '--capability',
      'session.status',
    ], {}),
    /explicit --client-instance-id/u,
  );
});

test('credential loader rejects expired enrollment', (t) => {
  const fixture = createFixture(t);
  writeCredential(fixture, validCredential({
    issuedUtc: roundTripUtc(FIXED_NOW - 7_200_000),
    expiresUtc: roundTripUtc(FIXED_NOW - 1),
  }));
  assert.throws(
    () => loadDeveloperCredential({
      projectRoot: PROJECT_ROOT,
      clientInstanceId: CLIENT_ID,
      localAppData: fixture.localAppData,
      now: FIXED_NOW,
    }),
    (error) => error.code === 'credential_expired',
  );
});

test('credential loader rejects a mismatched client', (t) => {
  const fixture = createFixture(t);
  writeCredential(fixture, validCredential({
    clientInstanceId: OTHER_CLIENT_ID,
  }));
  assert.throws(
    () => loadFixture(fixture),
    (error) => error.code === 'credential_client_mismatch',
  );
});

test('credential loader rejects extra fields and wrong schema', (t) => {
  const fixture = createFixture(t);
  writeCredential(fixture, {
    ...validCredential(),
    extra: true,
  });
  assert.throws(
    () => loadFixture(fixture),
    (error) => error.code === 'credential_properties_invalid',
  );
  writeCredential(fixture, validCredential({
    schema: 'cf7.agent_runtime.developer_credential.v2',
  }));
  assert.throws(
    () => loadFixture(fixture),
    (error) => error.code === 'credential_schema_invalid',
  );
});

test('credential loader rejects oversized files', (t) => {
  const fixture = createFixture(t);
  const filePath = credentialPath(fixture);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(
    filePath,
    Buffer.alloc(MAXIMUM_CREDENTIAL_BYTES + 1, 0x41),
  );
  assert.throws(
    () => loadFixture(fixture),
    (error) => error.code === 'credential_size_invalid',
  );
});

test('credential loader rejects invalid capability and target shapes', (t) => {
  const fixture = createFixture(t);
  writeCredential(fixture, validCredential({
    allowedCapabilities: ['not.registered'],
  }));
  assert.throws(
    () => loadFixture(fixture),
    (error) => error.code === 'credential_capabilities_invalid',
  );
  writeCredential(fixture, validCredential({
    allowedTargets: ['*'],
  }));
  assert.throws(
    () => loadFixture(fixture),
    (error) => error.code === 'credential_targets_invalid',
  );
});

test('configuration diagnostics never disclose stored proof', (t) => {
  const fixture = createFixture(t);
  const secret =
    'NEVER_PRINT_THIS_DEVELOPER_PROOF_1234567890';
  writeCredential(fixture, {
    ...validCredential({ credentialProof: secret }),
    unexpected: 'reject document',
  });
  const environment = {
    ...process.env,
    LOCALAPPDATA: fixture.localAppData,
  };
  delete environment.CF7_AGENT_CREDENTIAL_PROOF;
  delete environment.CF7_AGENT_CLIENT_INSTANCE_ID;
  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../cli.js'),
      '--project-root',
      PROJECT_ROOT,
      '--client-instance-id',
      CLIENT_ID,
      '--capability',
      'session.status',
    ],
    {
      encoding: 'utf8',
      env: environment,
      timeout: 10_000,
      windowsHide: true,
    },
  );
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr.includes(secret), false);
  assert.match(result.stderr, /^cf7-agent-cli:/u);
});

function createFixture(t) {
  const localAppData = fs.mkdtempSync(
    path.join(os.tmpdir(), 'cf7-agent-credential-'),
  );
  t.after(() => {
    fs.rmSync(localAppData, { recursive: true, force: true });
  });
  return { localAppData };
}

function credentialPath(fixture) {
  return developerCredentialPath(
    PROJECT_ROOT,
    CLIENT_ID,
    fixture.localAppData,
  );
}

function writeCredential(fixture, document) {
  const filePath = credentialPath(fixture);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(document), 'utf8');
}

function loadFixture(fixture) {
  return loadDeveloperCredential({
    projectRoot: PROJECT_ROOT,
    clientInstanceId: CLIENT_ID,
    localAppData: fixture.localAppData,
    now: FIXED_NOW,
  });
}

function validCredential(overrides = {}) {
  return {
    schema: CREDENTIAL_SCHEMA,
    clientInstanceId: CLIENT_ID,
    enrollmentReceipt: 'RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR',
    credentialProof: PROOF,
    allowedCapabilities: ['session.status'],
    allowedTargets: ['TTTTTTTTTTTTTTTTTTTTTT'],
    issuedUtc: roundTripUtc(FIXED_NOW - 60_000),
    expiresUtc: roundTripUtc(FIXED_NOW + 3_600_000),
    ...overrides,
  };
}

function roundTripUtc(milliseconds) {
  return new Date(milliseconds)
    .toISOString()
    .replace(/\.(\d{3})Z$/u, '.$10000+00:00');
}
