'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  candidateRoot,
  parseUnattendedArguments,
} = require('../unattended');

const SLOT = 'cf7_agent_equipment_tuning';
const A5_SLOT = 'cf7_agent_a5_material_shop_run';
const CANDIDATE_ID =
  'c-32ed30866355-5d18a14d6c-20260730t154609961z-39b299d9';

test('entry parser exposes only adapter, exact slot, and safe candidate ID', () => {
  assert.deepEqual(
    parseUnattendedArguments([
      '--adapter',
      'jsonl',
      '--slot',
      SLOT,
    ]),
    {
      adapter: 'jsonl',
      slot: SLOT,
      candidateId: undefined,
    },
  );
  const rejected = [
    ['--client-instance-id', 'client_AAAAAAAAAAAAAAAA'],
    ['--credential-proof', 'secret_AAAAAAAAAAAAAAAAA'],
    ['--credential-path', 'C:\\secret.json'],
    ['--capability', 'app.launch'],
    ['--project-root', 'C:\\arbitrary'],
    ['--candidate-root', 'C:\\arbitrary'],
    ['--credential-timeout-ms', '600000'],
    ['--legacy-http'],
    ['--developer'],
  ];
  for (const extra of rejected) {
    assert.throws(
      () => parseUnattendedArguments([
        '--adapter',
        'mcp',
        '--slot',
        SLOT,
        ...extra,
      ]),
      (error) => error.code === 'argument_invalid',
    );
  }
  for (const invalidSlot of [
    'cf7_agent_profile_test',
    '../cf7_agent_equipment_tuning',
    'CF7_AGENT_EQUIPMENT_TUNING',
  ]) {
    assert.throws(
      () => parseUnattendedArguments([
        '--adapter',
        'jsonl',
        '--slot',
        invalidSlot,
      ]),
      (error) => error.code === 'slot_invalid',
    );
  }
  for (const invalidCandidate of [
    '..',
    'c-BBBBBBBBBBBBBBBB',
    'c-32ed30866355-5d18a14d6c-../../formal',
  ]) {
    assert.throws(
      () => parseUnattendedArguments([
        '--adapter',
        'mcp',
        '--slot',
        SLOT,
        '--candidate-id',
        invalidCandidate,
      ]),
      (error) => error.code === 'candidate_invalid',
    );
  }
});

test('A5 slot allows formal runtime or the exact materialized a5 candidate leaf', () => {
  assert.deepEqual(
    parseUnattendedArguments([
      '--adapter',
      'jsonl',
      '--slot',
      A5_SLOT,
    ]),
    {
      adapter: 'jsonl',
      slot: A5_SLOT,
      candidateId: undefined,
    },
  );
  assert.deepEqual(
    parseUnattendedArguments([
      '--adapter',
      'mcp',
      '--slot',
      A5_SLOT,
      '--candidate-id',
      'a5',
    ]),
    {
      adapter: 'mcp',
      slot: A5_SLOT,
      candidateId: 'a5',
    },
  );

  for (const invalidCandidate of [
    CANDIDATE_ID,
    'a4',
    'A5',
    '../a5',
  ]) {
    const args = [
      '--adapter',
      'mcp',
      '--slot',
      A5_SLOT,
    ];
    args.push('--candidate-id', invalidCandidate);
    assert.throws(
      () => parseUnattendedArguments(args),
      (error) => error.code === 'candidate_invalid',
    );
  }

  assert.throws(
    () => parseUnattendedArguments([
      '--adapter',
      'mcp',
      '--slot',
      SLOT,
      '--candidate-id',
      'a5',
    ]),
    (error) => error.code === 'candidate_invalid',
  );

  const resourcesRoot = path.resolve(
    'tmp',
    'workbench-live-e2e',
    'material-shop',
    'materialized',
    'run-id',
    'resources',
  );
  assert.equal(
    candidateRoot(resourcesRoot, 'a5'),
    path.join(
      resourcesRoot,
      'tmp',
      'runtime-candidates',
      'v2',
      'a5',
    ),
  );
});

test('compiled Host policy authenticates the selected Core instead of the Node wrapper', () => {
  const entryPath = path.resolve(
    __dirname,
    '..',
    'unattended.js',
  );
  const hostSource = fs.readFileSync(
    path.resolve(
      __dirname,
      '..',
      '..',
      '..',
      'launcher',
      'src',
      'AgentRuntime',
      'Integration',
      'LauncherUnattendedCredentialBootstrap.cs',
    ),
    'utf8',
  );
  const entrySource = fs.readFileSync(entryPath, 'utf8');

  assert.doesNotMatch(hostSource, /RunnerEntrySha256/u);
  assert.match(
    hostSource,
    /TrustedUnattendedRuntimeBundle\s*\.\s*VerifySelectedProcess/u,
  );
  assert.match(
    hostSource,
    /document\.RunnerExecutableSha256/u,
  );
  assert.match(
    entrySource,
    /automation[\s\S]*start\.ps1/u,
  );
  assert.doesNotMatch(
    entrySource,
    /unattended-bootstrap-request/u,
  );
  assert.doesNotMatch(
    entrySource,
    /connectUnattendedAdapter|credentialProof|NamedPipe/u,
  );
  assert.doesNotMatch(
    entrySource,
    /require\(['"]\.\/lib\/unattended/u,
  );
});
