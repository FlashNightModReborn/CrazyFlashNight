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
  validateAppLaunchResult,
  validateRequest,
  validateResponse,
} = require('../lib/contract');
const { parseStrictJson } = require('../lib/strict-json');

const vectorPath = path.resolve(
  __dirname,
  '../../../launcher/contracts/agent-runtime/v1/rpc-vectors.v1.json',
);
const vectors = parseStrictJson(
  fs.readFileSync(vectorPath, 'utf8'),
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
    ['gui_input', 'domain_transaction', 'shutdown'],
  );
  assert.equal(
    leaseAcquire.properties.argumentBoundsHash.$ref,
    '#/$defs/sha256',
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
