'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  MAX_BINARY_FRAME_BYTES,
  MAX_BINARY_READ_COUNT,
  decodeBinaryPayload,
  encodeBinaryPayload,
  methodInputSchema,
  methods,
  parameterContracts,
  validateAppLaunchResult,
  validateRequest,
  validateResponse,
} = require('../lib/contract');
const { parseStrictJson } = require('../lib/strict-json');

const contractDirectory = path.resolve(
  __dirname,
  '../../../launcher/contracts/agent-runtime/v1',
);

function readContractArtifact(name) {
  return parseStrictJson(
    fs.readFileSync(path.join(contractDirectory, name), 'utf8'),
  );
}

const vectors = readContractArtifact('rpc-vectors.v1.json');
const agentRuntimeSchema = readContractArtifact(
  'agent-runtime.v1.schema.json',
);
const contractVectors = readContractArtifact(
  'contract-vectors.v1.json',
);

test('strict JSON parser rejects duplicate and trailing properties', () => {
  assert.throws(
    () => parseStrictJson('{"a":1,"a":2}'),
    /Duplicate object property/u,
  );
  assert.throws(
    () => parseStrictJson('{"a":1} false'),
    /Trailing content/u,
  );
});

test('closed registry and JSON-RPC vectors agree', () => {
  assert.equal(methods.size, 39);
  assert.equal(methods.has('action.execute'), false);
  for (const vector of vectors.validRequests) {
    assert.doesNotThrow(
      () => validateRequest(vector.value),
      vector.name,
    );
  }
  for (const vector of vectors.invalidRequests) {
    assert.throws(
      () => validateRequest(vector.value),
      undefined,
      vector.name,
    );
  }
  for (const vector of vectors.validResponses) {
    assert.doesNotThrow(
      () => validateResponse(vector.value),
      vector.name,
    );
  }
  for (const vector of vectors.invalidResponses) {
    assert.throws(
      () => validateResponse(vector.value),
      undefined,
      vector.name,
    );
  }
});

test('every MCP tool publishes its exact frozen input schema', () => {
  for (const definition of methods.values()) {
    if (definition.preAuthentication) continue;
    const schema = methodInputSchema(definition.name);
    assert.equal(schema.type, 'object', definition.name);
    assert.equal(
      schema.additionalProperties,
      false,
      definition.name,
    );
    assert.equal(
      JSON.stringify(schema).includes(
        'agent-runtime.v1.schema.json',
      ),
      false,
      `${definition.name} has an external ref`,
    );
  }

  const windowList = methodInputSchema('window.list');
  assert.deepEqual(
    windowList.required,
    ['sessionId', 'observationGrantId', 'dataScope'],
  );
  assert.equal(
    windowList.properties.dataScope.const,
    'window_metadata',
  );
  const windowState = methodInputSchema('window.state');
  assert.deepEqual(
    windowState.properties.dataScope.enum,
    ['window_metadata', 'pixels'],
  );
  for (const dataScope of ['window_metadata', 'pixels']) {
    assert.doesNotThrow(() => validateRequest({
      jsonrpc: '2.0',
      id: `window-state-${dataScope}`,
      method: 'window.state',
      params: {
        sessionId: 'S'.repeat(22),
        observationGrantId: 'G'.repeat(22),
        dataScope,
        targetId: 'T'.repeat(22),
      },
    }));
  }
  assert.throws(
    () => validateRequest({
      jsonrpc: '2.0',
      id: 'window-state-accessibility',
      method: 'window.state',
      params: {
        sessionId: 'S'.repeat(22),
        observationGrantId: 'G'.repeat(22),
        dataScope: 'accessibility',
        targetId: 'T'.repeat(22),
      },
    }),
    (error) => error.code === 'enum',
  );

  const grantIssue = methodInputSchema(
    'observation.grant.issue',
  );
  assert.equal(
    grantIssue.required.includes('lifecycleRef'),
    true,
  );
  assert.equal(
    Object.hasOwn(grantIssue.properties, 'sessionId'),
    false,
  );
  assert.equal(grantIssue.required.includes('targetIds'), false);
  assert.equal(grantIssue.required.includes('targetKinds'), false);
  assert.equal(grantIssue.oneOf.length, 2);
  assert.equal(grantIssue.properties.targetIds.maxItems, 32);
  assert.equal(
    grantIssue.properties.targetKinds.items.$ref,
    '#/$defs/surfaceKind',
  );
  assert.deepEqual(
    grantIssue.$defs.surfaceKind.enum,
    [
      'launcher',
      'flash',
      'web_overlay',
      'native_hud',
      'wings_shell',
      'business_modal',
    ],
  );

  const click = methodInputSchema('input.click');
  assert.equal(click.properties.operation.const, 'input.click');
  assert.equal(click.properties.arguments.oneOf.length, 2);
  assert.equal(
    click.$defs.clickCoordinateArguments
      .additionalProperties,
    false,
  );

  const leaseAcquire = methodInputSchema('lease.acquire');
  assert.deepEqual(
    leaseAcquire.properties.kind.enum,
    [
      'gui_input',
      'domain_transaction',
      'structured_action',
      'shutdown',
    ],
  );
  assert.equal(
    leaseAcquire.properties.argumentBoundsHash.$ref,
    '#/$defs/sha256',
  );
  const structuredActionAcquireCondition =
    leaseAcquire.allOf.find(
      (entry) => entry.if?.properties?.kind?.const
        === 'structured_action',
    );
  assert.ok(structuredActionAcquireCondition);
  assert.equal(
    structuredActionAcquireCondition.then.properties
      .capabilities.items.const,
    'panel.open',
  );
  assert.equal(
    structuredActionAcquireCondition.then.properties
      .targetScope.maxItems,
    1,
  );
  assert.equal(
    structuredActionAcquireCondition.then.properties
      .requestedTtlMs.maximum,
    30_000,
  );
  assert.equal(
    structuredActionAcquireCondition.then.properties
      .requestedActionLimit.const,
    1,
  );
  assert.equal(
    structuredActionAcquireCondition.else.properties
      .capabilities.not.contains.const,
    'panel.open',
  );
  assert.doesNotThrow(() => validateRequest({
    jsonrpc: '2.0',
    id: 'bounded-lease',
    method: 'lease.acquire',
    params: {
      sessionId: 'S'.repeat(22),
      kind: 'gui_input',
      capabilities: ['input.click'],
      targetScope: ['T'.repeat(22)],
      requestedTtlMs: 1000,
      requestedActionLimit: 1,
      argumentBoundsHash: 'A'.repeat(64),
    },
  }));
  const shutdownLease = {
    jsonrpc: '2.0',
    id: 'shutdown-lease',
    method: 'lease.acquire',
    params: {
      sessionId: 'S'.repeat(22),
      kind: 'shutdown',
      capabilities: ['session.shutdown'],
      targetScope: ['T'.repeat(22)],
      requestedTtlMs: 30_000,
      requestedActionLimit: 1,
    },
  };
  assert.doesNotThrow(
    () => validateRequest(shutdownLease),
  );
  for (const [name, params] of [
    [
      'gui-kind-with-shutdown-authority',
      {
        ...shutdownLease.params,
        kind: 'gui_input',
      },
    ],
    [
      'shutdown-kind-with-input-authority',
      {
        ...shutdownLease.params,
        capabilities: ['input.click'],
      },
    ],
    [
      'shutdown-kind-with-multiple-targets',
      {
        ...shutdownLease.params,
        targetScope: [
          'T'.repeat(22),
          'U'.repeat(22),
        ],
      },
    ],
    [
      'shutdown-kind-with-widened-ttl',
      {
        ...shutdownLease.params,
        requestedTtlMs: 30_001,
      },
    ],
    [
      'shutdown-kind-with-multiple-actions',
      {
        ...shutdownLease.params,
        requestedActionLimit: 2,
      },
    ],
    [
      'shutdown-kind-with-client-operation',
      {
        ...shutdownLease.params,
        operation:
          'appearance.hair.change.v1.commit',
      },
    ],
  ]) {
    assert.throws(
      () => validateRequest({
        ...shutdownLease,
        id: name,
        params,
      }),
      undefined,
      name,
    );
  }
  const structuredActionLease = {
    jsonrpc: '2.0',
    id: 'structured-action-lease',
    method: 'lease.acquire',
    params: {
      sessionId: 'S'.repeat(22),
      kind: 'structured_action',
      capabilities: ['panel.open'],
      targetScope: ['T'.repeat(22)],
      requestedTtlMs: 30_000,
      requestedActionLimit: 1,
    },
  };
  assert.doesNotThrow(
    () => validateRequest(structuredActionLease),
  );
  const structuredActionBinding =
    parameterContracts.get('leaseAcquire')
      .kindBindings.structured_action;
  assert.deepEqual(
    structuredActionBinding.capabilitiesExact,
    ['panel.open'],
  );
  assert.equal(structuredActionBinding.minimumTargets, 1);
  assert.equal(structuredActionBinding.maximumTargets, 1);
  assert.equal(
    structuredActionBinding.requiredTargetKind,
    'launcher',
  );
  assert.deepEqual(
    structuredActionBinding.allowedSessionModes,
    ['developer_interactive', 'unattended_test'],
  );
  assert.equal(structuredActionBinding.maximumTtlMs, 30_000);
  assert.equal(structuredActionBinding.maximumActions, 1);
  assert.equal(
    structuredActionBinding.operationDerivedByServer,
    'panel.open',
  );
  assert.equal(
    structuredActionBinding.renewAfterAllowed,
    false,
  );
  assert.equal(
    structuredActionBinding.renewalOperationResult,
    'operation_invalid',
  );
  const leaseDescriptor =
    agentRuntimeSchema.$defs.leaseDescriptor;
  assert.equal(
    leaseDescriptor.properties.purpose.enum.includes(
      'structured_action',
    ),
    true,
  );
  const structuredActionDescriptorCondition =
    leaseDescriptor.allOf.find(
      (entry) => entry.if?.properties?.purpose?.const
        === 'structured_action',
    );
  assert.ok(structuredActionDescriptorCondition);
  assert.deepEqual(
    structuredActionDescriptorCondition.then.properties
      .sessionMode.enum,
    ['developer_interactive', 'unattended_test'],
  );
  assert.equal(
    structuredActionDescriptorCondition.then.not.required[0],
    'renewAfter',
  );
  assert.equal(
    structuredActionDescriptorCondition.then.properties
      .capabilities.items.const,
    'panel.open',
  );
  assert.equal(
    structuredActionDescriptorCondition.then.properties
      .scope.properties.operationScope.items.const,
    'panel.open',
  );
  assert.equal(
    structuredActionDescriptorCondition.then.properties
      .scope.properties.maximumActions.const,
    1,
  );
  assert.equal(
    structuredActionDescriptorCondition.else.properties
      .capabilities.not.contains.const,
    'panel.open',
  );
  const structuredActionDescriptor =
    contractVectors.valid.structuredActionLease;
  assert.equal(
    structuredActionDescriptor.purpose,
    'structured_action',
  );
  assert.equal(
    structuredActionDescriptor.sessionMode,
    'unattended_test',
  );
  assert.deepEqual(
    structuredActionDescriptor.capabilities,
    ['panel.open'],
  );
  assert.deepEqual(
    structuredActionDescriptor.scope.operationScope,
    ['panel.open'],
  );
  assert.equal(
    structuredActionDescriptor.scope.targetScope.length,
    1,
  );
  assert.equal(
    structuredActionDescriptor.expiresMonotonic
      - structuredActionDescriptor.issuedMonotonic,
    30_000,
  );
  assert.equal(
    Object.hasOwn(structuredActionDescriptor, 'renewAfter'),
    false,
  );
  for (const [name, params] of [
    [
      'gui-kind-with-panel-open-authority',
      {
        ...structuredActionLease.params,
        kind: 'gui_input',
      },
    ],
    [
      'structured-action-kind-with-input-authority',
      {
        ...structuredActionLease.params,
        capabilities: ['input.click'],
      },
    ],
    [
      'structured-action-kind-with-mixed-authority',
      {
        ...structuredActionLease.params,
        capabilities: ['panel.open', 'input.click'],
      },
    ],
    [
      'structured-action-kind-with-multiple-targets',
      {
        ...structuredActionLease.params,
        targetScope: [
          'T'.repeat(22),
          'U'.repeat(22),
        ],
      },
    ],
    [
      'structured-action-kind-with-widened-ttl',
      {
        ...structuredActionLease.params,
        requestedTtlMs: 30_001,
      },
    ],
    [
      'structured-action-kind-with-multiple-actions',
      {
        ...structuredActionLease.params,
        requestedActionLimit: 2,
      },
    ],
    [
      'structured-action-kind-with-client-operation',
      {
        ...structuredActionLease.params,
        operation:
          'appearance.hair.change.v1.commit',
      },
    ],
  ]) {
    assert.throws(
      () => validateRequest({
        ...structuredActionLease,
        id: name,
        params,
      }),
      undefined,
      name,
    );
  }
  assert.throws(
    () => validateRequest({
      jsonrpc: '2.0',
      id: 'malformed-bounds',
      method: 'lease.acquire',
      params: {
        sessionId: 'S'.repeat(22),
        kind: 'gui_input',
        capabilities: ['input.click'],
        targetScope: ['T'.repeat(22)],
        requestedTtlMs: 1000,
        requestedActionLimit: 1,
        argumentBoundsHash: 'self-attested',
      },
    }),
    (error) => error.code === 'sha256',
  );

  const hairConsent = methodInputSchema(
    'appearance.hair.change.v1.consent',
  );
  assert.deepEqual(hairConsent.required, [
    'observationGrantId',
    'targetId',
    'sessionId',
    'lifecycleGeneration',
    'transactionId',
    'previewHash',
  ]);
  assert.equal(hairConsent.additionalProperties, false);
  assert.equal(
    Object.hasOwn(
      hairConsent.properties,
      'securityPrincipalId',
    ),
    false,
  );

  const capture = methodInputSchema('observation.capture');
  assert.equal(capture.properties.dataScope.const, 'pixels');
  assert.throws(
    () => validateRequest({
      jsonrpc: '2.0',
      id: 'capture-non-pixels',
      method: 'observation.capture',
      params: {
        observationGrantId: 'G'.repeat(22),
        sessionId: 'S'.repeat(22),
        targetId: 'T'.repeat(22),
        dataScope: 'accessibility',
        allowValidatedFlashKeyframeFallback: false,
      },
    }),
    (error) => error.code === 'pixels_scope_required',
  );

  const traceExport = methodInputSchema('trace.export');
  assert.equal(
    traceExport.required.includes('observationGrantId'),
    true,
  );
  assert.equal(
    traceExport.required.includes('consentPurpose'),
    true,
  );
  const base = {
    jsonrpc: '2.0',
    id: 'trace-1',
    method: 'trace.export',
    params: {
      sessionId: 'S'.repeat(22),
      observationGrantId: 'G'.repeat(22),
      consentPurpose: 'input.click',
      fromServerSequence: 0,
      maximumRecords: 100,
      format: 'jsonl',
    },
  };
  assert.doesNotThrow(() => validateRequest(base));
  for (const consentPurpose of [
    'trace.export',
    'data.export',
    'observe:pixels',
    'observation.grant.manage',
  ]) {
    assert.throws(
      () => validateRequest({
        ...base,
        params: {
          ...base.params,
          consentPurpose,
        },
      }),
      (error) => error.code === 'enum',
    );
  }
});

test('app.launch result is minimal, opaque, and exact', () => {
  const result = {
    launchRequestId: 'L'.repeat(22),
    entryPoint: 'standard_entry',
    started: false,
    alreadyRunning: true,
    runtimeMode: 'formal_runtime',
    minimalSessionRef: {
      projectRunning: true,
      qualificationState: 'verified',
      lifecycleRef: 'R'.repeat(22),
    },
  };
  assert.doesNotThrow(() => validateAppLaunchResult(result));
  assert.throws(
    () => validateAppLaunchResult({
      ...result,
      session: {
        sessionId: 'S'.repeat(22),
        launcherPid: 123,
        slot: 'developer_slot',
      },
    }),
    (error) => error.code === 'exact_properties_required',
  );
  assert.throws(
    () => validateAppLaunchResult({
      ...result,
      entryPoint: 'standard',
    }),
    (error) => error.code === 'app_launch_result_contract',
  );
});

test('binary vectors round-trip under the outer payload cap', () => {
  for (const vector of vectors.validBinaryChunks) {
    const content = Buffer.from(vector.contentBase64, 'base64');
    const payload = encodeBinaryPayload(vector.metadata, content);
    assert.ok(payload.length <= MAX_BINARY_FRAME_BYTES);
    const decoded = decodeBinaryPayload(payload);
    assert.deepEqual(decoded.metadata, vector.metadata);
    assert.deepEqual(decoded.content, content);
  }
  for (const vector of vectors.invalidBinaryChunks) {
    assert.throws(
      () => encodeBinaryPayload(
        vector.metadata,
        Buffer.from(vector.contentBase64, 'base64'),
      ),
      undefined,
      vector.name,
    );
  }
  assert.equal(MAX_BINARY_READ_COUNT, 4_194_300);
});

test('binary header duplicates fail before deserialization', () => {
  const header = Buffer.from(
    '{"handle":"EEEEEEEEEEEEEEEEEEEEEE",'
    + '"offset":0,"offset":0,"totalLength":0,'
    + '"final":true,'
    + '"contentHash":"e3b0c44298fc1c149afbf4c8996fb924'
    + '27ae41e4649b934ca495991b7852b855"}',
    'utf8',
  );
  const payload = Buffer.alloc(4 + header.length);
  payload.writeUInt32LE(header.length, 0);
  header.copy(payload, 4);
  assert.throws(
    () => decodeBinaryPayload(payload),
    /Duplicate object property/u,
  );
});
