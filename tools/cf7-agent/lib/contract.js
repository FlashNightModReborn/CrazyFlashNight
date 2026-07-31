'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { TextDecoder, TextEncoder } = require('node:util');
const { parseStrictJson } = require('./strict-json');

const PROTOCOL_VERSION = '1.0';
const PROTOCOL_MAJOR = 1;
const MAX_JSON_FRAME_BYTES = 1_048_576;
const MAX_BINARY_FRAME_BYTES = 4_194_304;
const BINARY_METADATA_PREFIX_BYTES = 4;
const MAX_BINARY_METADATA_BYTES = 1_024;
const MAX_BINARY_READ_COUNT =
  MAX_BINARY_FRAME_BYTES - BINARY_METADATA_PREFIX_BYTES;
const MAX_BINARY_OBJECT_BYTES = 16_777_216;
const OPAQUE_ID = /^[A-Za-z0-9_-]{22,128}$/;
const PIPE_ID = /^[A-Za-z0-9_-]{22,86}$/;
const SHA256 = /^[A-Fa-f0-9]{64}$/;
const RPC_ID_CONTROL = /[\u0000-\u001f\u007f]/;
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });

const contractDirectory = path.resolve(
  __dirname,
  '../../../launcher/contracts/agent-runtime/v1',
);

function readArtifact(name) {
  return parseStrictJson(
    fs.readFileSync(path.join(contractDirectory, name), 'utf8'),
  );
}

const methodArtifact = readArtifact('method-registry.v1.json');
const parameterArtifact = readArtifact(
  'parameter-contracts.v1.json',
);
const methodParamsArtifact = readArtifact(
  'method-params.v1.schema.json',
);
const jsonRpcArtifact = readArtifact(
  'json-rpc.v1.schema.json',
);
const agentRuntimeArtifact = readArtifact(
  'agent-runtime.v1.schema.json',
);
const reasonArtifact = readArtifact('reason-codes.v1.json');
const methods = new Map(
  methodArtifact.methods.map((entry) => [entry.name, Object.freeze(entry)]),
);
const reasons = new Map(
  Object.entries(reasonArtifact.reasonCodes),
);
const parameterContracts = new Map(
  Object.entries(parameterArtifact.contracts),
);
const observationDataScopes = new Set(
  parameterArtifact.observationDataScopes,
);
const actionArgumentContracts =
  parameterArtifact.actionArguments;
const methodParameterDefinitions = methodParamsArtifact.$defs;
const jsonRpcDefinitions = jsonRpcArtifact.$defs;
const agentRuntimeDefinitions = agentRuntimeArtifact.$defs;
const traceExportConsentPurposes = new Set(
  methodParamsArtifact.$defs.traceExport
    .properties.consentPurpose.enum,
);
const parameterSchemaNames = Object.freeze({
  contentReadRequest: 'contentRead',
});
const actionArgumentSchemaNames = Object.freeze({
  'input.press_key': 'pressKeyArguments',
  'input.type_text': 'typeTextArguments',
  'input.scroll': 'scrollArguments',
  'semantic.set_value': 'setValueArguments',
  'input.drag': 'dragArguments',
  'semantic.secondary_action': 'secondaryArguments',
  'window.activate': 'empty',
  'session.shutdown': 'empty',
  'lifecycle.reveal': 'empty',
  'lifecycle.cancel': 'empty',
  'panel.open': 'panelArguments',
  'appearance.hair.change.v1.commit': 'hairCommitArguments',
  'appearance.hair.change.v1.restore': 'hairRestoreArguments',
});
const capabilities = new Set(
  [...methods.values()]
    .map((entry) => entry.requiredCapability)
    .filter((entry) => entry !== null),
);
const clientKinds = new Set([
  'jsonl_cli',
  'mcp_stdio',
  'wings_internal',
  'test_harness',
]);
const reconcileKinds = new Set([
  'none',
  'domain_authoritative',
  'visual_ambiguous',
  'manual_required',
]);
const runtimeModes = new Set([
  'formal_runtime',
  'isolated_candidate',
  'unqualified_dev',
]);
const runtimeQualificationStates = new Set([
  'verified',
  'unqualified',
]);

class ContractError extends Error {
  constructor(code, message, path = '$') {
    super(`${path}: ${message}`);
    this.name = 'ContractError';
    this.code = code;
    this.path = path;
  }
}

function fail(code, message, path) {
  throw new ContractError(code, message, path);
}

function isObject(value) {
  return value !== null
    && typeof value === 'object'
    && !Array.isArray(value);
}

function exactObject(value, keys, objectPath = '$') {
  if (!isObject(value)) {
    fail('object_required', 'Expected an object', objectPath);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length
    || actual.some((key, index) => key !== expected[index])
  ) {
    fail(
      'exact_properties_required',
      `Expected exactly: ${expected.join(', ')}`,
      objectPath,
    );
  }
  return value;
}

function exactObjectShape(
  value,
  required,
  optional,
  objectPath = '$',
) {
  if (!isObject(value)) {
    fail('object_required', 'Expected an object', objectPath);
  }
  const requiredSet = new Set(required);
  const allowed = new Set([...required, ...optional]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      fail(
        'unknown_property',
        `Property is not allowed: ${key}`,
        `${objectPath}.${key}`,
      );
    }
  }
  for (const key of requiredSet) {
    if (!Object.hasOwn(value, key)) {
      fail(
        'required',
        `Missing required parameter ${key}`,
        `${objectPath}.${key}`,
      );
    }
  }
  return value;
}

function methodInputSchema(method) {
  const definition = methods.get(method);
  if (!definition || definition.preAuthentication) {
    fail(
      'rpc_method_not_found',
      'Method does not expose an MCP input schema',
      '$.method',
    );
  }
  let root;
  if (definition.parameterContract === 'actionEnvelope') {
    root = actionInputSchema(method);
  } else {
    const schemaName = parameterSchemaNames[
      definition.parameterContract
    ] ?? definition.parameterContract;
    const source = schemaName === 'contentRead'
      ? jsonRpcDefinitions.contentReadRequest
      : methodParameterDefinitions[schemaName];
    if (!source) {
      fail(
        'parameter_schema_missing',
        'Method parameter JSON Schema is not frozen',
        '$.method',
      );
    }
    root = cloneJson(source);
  }
  return bundleLocalDefinitions(root);
}

function actionInputSchema(method) {
  const root = cloneJson(agentRuntimeDefinitions.actionEnvelope);
  root.properties.operation = { const: method };
  if (method === 'input.click') {
    root.properties.arguments = {
      oneOf: [
        { $ref: '#/$defs/clickCoordinateArguments' },
        { $ref: '#/$defs/clickSemanticArguments' },
      ],
    };
  } else {
    const argumentSchemaName = actionArgumentSchemaNames[method];
    if (!argumentSchemaName) {
      fail(
        'action_arguments_contract_missing',
        'Action method has no exact JSON Schema',
        '$.method',
      );
    }
    root.properties.arguments = {
      $ref: `#/$defs/${argumentSchemaName}`,
    };
  }
  return root;
}

function bundleLocalDefinitions(root) {
  const bundled = Object.create(null);

  function includeReferences(value) {
    if (Array.isArray(value)) {
      for (const item of value) includeReferences(item);
      return;
    }
    if (!isObject(value)) return;
    if (
      typeof value.$ref === 'string'
      && (
        value.$ref.startsWith('#/$defs/')
        || value.$ref.startsWith(
          'agent-runtime.v1.schema.json#/$defs/',
        )
        || value.$ref.startsWith(
          'json-rpc.v1.schema.json#/$defs/',
        )
      )
    ) {
      const name = value.$ref.slice(
        value.$ref.lastIndexOf('/') + 1,
      );
      value.$ref = `#/$defs/${name}`;
      if (!Object.hasOwn(bundled, name)) {
        const source = agentRuntimeDefinitions[name]
          ?? jsonRpcDefinitions[name]
          ?? methodParameterDefinitions[name];
        if (!source) {
          fail(
            'parameter_schema_reference_missing',
            `JSON Schema definition is missing: ${name}`,
            '$.method',
          );
        }
        bundled[name] = cloneJson(source);
        includeReferences(bundled[name]);
      }
    }
    for (const child of Object.values(value)) {
      includeReferences(child);
    }
  }

  includeReferences(root);
  const schema = {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    ...root,
  };
  if (Object.keys(bundled).length !== 0) {
    schema.$defs = bundled;
  }
  return schema;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function rpcId(value, valuePath = '$.id') {
  if (
    typeof value !== 'string'
    || value.length < 1
    || value.length > 128
    || RPC_ID_CONTROL.test(value)
  ) {
    fail(
      'rpc_string_id_required',
      'ID must be a 1-128 character non-control string',
      valuePath,
    );
  }
  return value;
}

function opaqueId(value, valuePath) {
  if (typeof value !== 'string' || !OPAQUE_ID.test(value)) {
    fail(
      'opaque_id',
      'Expected a 22-128 character base64url-compatible opaque ID',
      valuePath,
    );
  }
  return value;
}

function pipeId(value, valuePath = '$.pipeId') {
  if (typeof value !== 'string' || !PIPE_ID.test(value)) {
    fail(
      'opaque_pipe_id',
      'Expected a 22-86 character opaque pipe ID',
      valuePath,
    );
  }
  return value;
}

function safeInteger(value, minimum, maximum, valuePath) {
  if (
    !Number.isSafeInteger(value)
    || value < minimum
    || value > maximum
  ) {
    fail(
      'integer_range',
      `Expected an integer in [${minimum}, ${maximum}]`,
      valuePath,
    );
  }
  return value;
}

function validateHello(params) {
  exactObject(params, [
    'protocolVersion',
    'clientInstanceId',
    'clientKind',
    'requestedCapabilities',
    'nonce',
    'connectionToken',
    'credentialProof',
  ], '$.params');
  if (params.protocolVersion !== PROTOCOL_VERSION) {
    fail(
      'protocol_version_mismatch',
      'protocolVersion must equal 1.0',
      '$.params.protocolVersion',
    );
  }
  opaqueId(params.clientInstanceId, '$.params.clientInstanceId');
  opaqueId(params.nonce, '$.params.nonce');
  opaqueId(params.connectionToken, '$.params.connectionToken');
  if (!clientKinds.has(params.clientKind)) {
    fail('unknown_client_kind', 'Unknown client kind', '$.params.clientKind');
  }
  if (
    typeof params.credentialProof !== 'string'
    || params.credentialProof.length < 32
    || params.credentialProof.length > 4096
  ) {
    fail(
      'credential_proof_invalid',
      'Credential proof must contain 32-4096 characters',
      '$.params.credentialProof',
    );
  }
  if (
    !Array.isArray(params.requestedCapabilities)
    || params.requestedCapabilities.length < 1
    || params.requestedCapabilities.length > capabilities.size
  ) {
    fail(
      'capabilities_invalid',
      'At least one bounded capability is required',
      '$.params.requestedCapabilities',
    );
  }
  const seen = new Set();
  params.requestedCapabilities.forEach((capability, index) => {
    if (typeof capability !== 'string' || !capabilities.has(capability)) {
      fail(
        'unknown_capability',
        'Capability is not in the closed registry',
        `$.params.requestedCapabilities[${index}]`,
      );
    }
    if (seen.has(capability)) {
      fail(
        'duplicate_capability',
        'Requested capabilities must be unique',
        `$.params.requestedCapabilities[${index}]`,
      );
    }
    seen.add(capability);
  });
}

function validateContentRead(params) {
  exactObject(params, ['handle', 'offset', 'count'], '$.params');
  opaqueId(params.handle, '$.params.handle');
  safeInteger(
    params.offset,
    0,
    Number.MAX_SAFE_INTEGER,
    '$.params.offset',
  );
  safeInteger(
    params.count,
    1,
    MAX_BINARY_READ_COUNT,
    '$.params.count',
  );
}

function validateMethodParams(method, params) {
  const definition = methods.get(method);
  if (!definition) {
    fail(
      'rpc_method_not_found',
      'Method is not in the closed v1 registry',
      '$.method',
    );
  }
  if (definition.preAuthentication) {
    validateHello(params);
    return;
  }
  const contract = parameterContracts.get(
    definition.parameterContract,
  );
  if (!contract) {
    fail(
      'parameter_contract_missing',
      'Method parameter contract is not frozen',
      '$.params',
    );
  }
  exactObjectShape(
    params,
    contract.required,
    contract.optional,
    '$.params',
  );

  switch (definition.parameterContract) {
    case 'empty':
      break;
    case 'windowList':
      validateWindowParams(params, false);
      break;
    case 'windowTarget':
      validateWindowParams(params, true);
      break;
    case 'windowState':
      validateWindowStateParams(params);
      break;
    case 'appLaunch':
      opaqueId(params.launchRequestId, '$.params.launchRequestId');
      if (
        params.entryPoint !== 'standard_entry'
        || ![
          'formal_runtime',
          'isolated_candidate',
          'unqualified_dev',
        ].includes(params.runtimeMode)
      ) {
        fail(
          'app_launch_contract',
          'app.launch entryPoint or runtimeMode is invalid',
          '$.params',
        );
      }
      if (
        params.runtimeMode === 'isolated_candidate'
        && (
          typeof params.expectedBuildIdentity !== 'string'
          || !SHA256.test(params.expectedPayloadClosure)
        )
      ) {
        fail(
          'candidate_identity_required',
          'Candidate launch requires identity and payload closure',
          '$.params',
        );
      }
      break;
    case 'sessionBinding':
      opaqueId(params.sessionId, '$.params.sessionId');
      safeInteger(
        params.lifecycleGeneration,
        1,
        Number.MAX_SAFE_INTEGER,
        '$.params.lifecycleGeneration',
      );
      break;
    case 'actionEnvelope':
      validateActionParams(method, params);
      break;
    case 'leaseAcquire':
      validateLeaseAcquireParams(params);
      break;
    case 'leaseRenew':
      opaqueId(params.leaseId, '$.params.leaseId');
      safeInteger(
        params.requestedTtlMs,
        1,
        1_800_000,
        '$.params.requestedTtlMs',
      );
      break;
    case 'leaseRelease':
      opaqueId(params.leaseId, '$.params.leaseId');
      break;
    case 'traceExport':
      opaqueId(params.sessionId, '$.params.sessionId');
      opaqueId(
        params.observationGrantId,
        '$.params.observationGrantId',
      );
      boundedString(
        params.consentPurpose,
        1,
        128,
        '$.params.consentPurpose',
      );
      if (!traceExportConsentPurposes.has(params.consentPurpose)) {
        fail(
          'enum',
          'Consent purpose is not exportable',
          '$.params.consentPurpose',
        );
      }
      safeInteger(
        params.fromServerSequence,
        0,
        Number.MAX_SAFE_INTEGER,
        '$.params.fromServerSequence',
      );
      safeInteger(
        params.maximumRecords,
        1,
        10_000,
        '$.params.maximumRecords',
      );
      if (params.format !== 'jsonl') {
        fail(
          'constant',
          'Trace format must equal jsonl',
          '$.params.format',
        );
      }
      break;
    case 'observationGrantIssue':
      validateGrantIssueParams(params);
      break;
    case 'observationGrantRevoke':
      opaqueId(
        params.observationGrantId,
        '$.params.observationGrantId',
      );
      break;
    case 'observationCapture':
      validateObservationCaptureParams(params);
      break;
    case 'observationReference':
      opaqueId(
        params.observationGrantId,
        '$.params.observationGrantId',
      );
      opaqueId(params.sessionId, '$.params.sessionId');
      opaqueId(params.observationId, '$.params.observationId');
      break;
    case 'contentReadRequest':
      validateContentRead(params);
      break;
    case 'actionGet':
      opaqueId(params.sessionId, '$.params.sessionId');
      opaqueId(params.actionId, '$.params.actionId');
      break;
    case 'hairInspect':
      validateHairReadParams(params, false);
      break;
    case 'hairPreview':
      validateHairReadParams(params, true);
      break;
    case 'hairConsent':
      validateHairConsentParams(params);
      break;
    case 'hairReconcile':
      opaqueId(
        params.observationGrantId,
        '$.params.observationGrantId',
      );
      opaqueId(params.targetId, '$.params.targetId');
      opaqueId(params.transactionId, '$.params.transactionId');
      break;
    default:
      fail(
        'parameter_contract_missing',
        'No parameter validator is compiled for the contract',
        '$.params',
      );
  }
}

function validateWindowParams(params, targetRequired) {
  opaqueId(params.sessionId, '$.params.sessionId');
  opaqueId(
    params.observationGrantId,
    '$.params.observationGrantId',
  );
  if (params.dataScope !== 'window_metadata') {
    fail(
      'constant',
      'Window reads require window_metadata scope',
      '$.params.dataScope',
    );
  }
  if (targetRequired) {
    opaqueId(params.targetId, '$.params.targetId');
  }
}

function validateWindowStateParams(params) {
  opaqueId(params.sessionId, '$.params.sessionId');
  opaqueId(
    params.observationGrantId,
    '$.params.observationGrantId',
  );
  if (
    params.dataScope !== 'window_metadata'
    && params.dataScope !== 'pixels'
  ) {
    fail(
      'enum',
      'window.state accepts window_metadata or pixels',
      '$.params.dataScope',
    );
  }
  opaqueId(params.targetId, '$.params.targetId');
}

function validateActionParams(method, params) {
  for (const name of [
    'actionId',
    'idempotencyKey',
    'sessionId',
    'observationGrantId',
    'leaseId',
    'observationId',
    'targetId',
  ]) {
    opaqueId(params[name], `$.params.${name}`);
  }
  for (const name of [
    'expectedLifecycleGeneration',
    'expectedSurfaceEpoch',
    'expectedCoordinateSpaceVersion',
    'expectedFocusEpoch',
    'expectedModalEpoch',
  ]) {
    safeInteger(
      params[name],
      1,
      Number.MAX_SAFE_INTEGER,
      `$.params.${name}`,
    );
  }
  safeInteger(
    params.deadlineMs,
    1,
    30_000,
    '$.params.deadlineMs',
  );
  if (params.operation !== method) {
    fail(
      'operation_method_mismatch',
      'Action operation must equal the wire method',
      '$.params.operation',
    );
  }
  if (
    typeof params.reason !== 'string'
    || params.reason.length < 1
    || params.reason.length > 512
    || !isObject(params.arguments)
  ) {
    fail(
      'action_envelope_invalid',
      'Action reason or arguments are invalid',
      '$.params',
    );
  }
  for (const name of [
    'expectedAttemptId',
    'expectedPanelInstanceId',
    'frameId',
    'semanticSnapshotId',
    'nodeId',
  ]) {
    if (Object.hasOwn(params, name)) {
      opaqueId(params[name], `$.params.${name}`);
    }
  }
  for (const name of [
    'expectedAttemptGeneration',
    'expectedSemanticGeneration',
    'expectedDocumentGeneration',
  ]) {
    if (Object.hasOwn(params, name)) {
      safeInteger(
        params[name],
        1,
        Number.MAX_SAFE_INTEGER,
        `$.params.${name}`,
      );
    }
  }
  if (
    Object.hasOwn(params, 'expectedAttemptId')
    !== Object.hasOwn(params, 'expectedAttemptGeneration')
  ) {
    fail(
      'pair_required',
      'Attempt ID and generation must appear together',
      '$.params',
    );
  }
  validateActionArguments(method, params);
}

function validateActionArguments(method, params) {
  const specification = actionArgumentContracts[method];
  if (!specification) {
    fail(
      'action_arguments_contract_missing',
      'Action arguments contract is missing',
      '$.params.arguments',
    );
  }
  let required = specification.required;
  if (method === 'input.click') {
    const semantic = Object.hasOwn(params, 'nodeId');
    required = semantic
      ? specification.semanticRequired
      : specification.coordinateRequired;
    if (semantic) {
      for (const name of [
        'nodeId',
        'semanticSnapshotId',
        'expectedSemanticGeneration',
      ]) {
        if (!Object.hasOwn(params, name)) {
          fail(
            'semantic_binding_required',
            'Semantic click binding is incomplete',
            '$.params',
          );
        }
      }
      if (Object.hasOwn(params, 'frameId')) {
        fail(
          'semantic_frame_conflict',
          'Semantic click cannot include frameId',
          '$.params.frameId',
        );
      }
    } else if (!Object.hasOwn(params, 'frameId')) {
      fail(
        'frame_required',
        'Coordinate click requires frameId',
        '$.params.frameId',
      );
    }
  }
  exactObject(params.arguments, required, '$.params.arguments');
  if (
    ['input.scroll', 'input.drag'].includes(method)
    && !Object.hasOwn(params, 'frameId')
  ) {
    fail(
      'frame_required',
      'Coordinate action requires frameId',
      '$.params.frameId',
    );
  }
  if (
    ['semantic.set_value', 'semantic.secondary_action'].includes(method)
  ) {
    for (const name of [
      'nodeId',
      'semanticSnapshotId',
      'expectedSemanticGeneration',
    ]) {
      if (!Object.hasOwn(params, name)) {
        fail(
          'semantic_binding_required',
          'Semantic action binding is incomplete',
          '$.params',
        );
      }
    }
  }
  if (
    Object.hasOwn(params.arguments, 'coordinateSpace')
    && params.arguments.coordinateSpace !== 'observation_px'
  ) {
    fail(
      'coordinate_space',
      'Coordinate space must equal observation_px',
      '$.params.arguments.coordinateSpace',
    );
  }
  if (method === 'input.type_text') {
    boundedString(params.arguments.text, 1, 32_768, '$.params.arguments.text');
  } else if (method === 'semantic.set_value') {
    boundedString(params.arguments.value, 0, 32_768, '$.params.arguments.value');
  } else if (method === 'panel.open') {
    protocolName(params.arguments.panel, '$.params.arguments.panel');
  } else if (method === 'semantic.secondary_action') {
    protocolName(params.arguments.action, '$.params.arguments.action');
  } else if (method === 'appearance.hair.change.v1.commit') {
    opaqueId(
      params.arguments.transactionId,
      '$.params.arguments.transactionId',
    );
    if (!SHA256.test(params.arguments.previewHash)) {
      fail(
        'sha256',
        'previewHash must be SHA-256',
        '$.params.arguments.previewHash',
      );
    }
    boundedString(
      params.arguments.consentToken,
      1,
      256,
      '$.params.arguments.consentToken',
    );
  } else if (method === 'appearance.hair.change.v1.restore') {
    opaqueId(
      params.arguments.transactionId,
      '$.params.arguments.transactionId',
    );
    boundedString(
      params.arguments.restoreToken,
      1,
      256,
      '$.params.arguments.restoreToken',
    );
  }
}

function validateLeaseAcquireParams(params) {
  opaqueId(params.sessionId, '$.params.sessionId');
  if (![
    'gui_input',
    'domain_transaction',
    'structured_action',
    'shutdown',
  ].includes(params.kind)) {
    fail('enum', 'Lease kind is invalid', '$.params.kind');
  }
  stringArray(
    params.capabilities,
    capabilities,
    1,
    capabilities.size,
    '$.params.capabilities',
  );
  stringArray(
    params.targetScope,
    null,
    1,
    32,
    '$.params.targetScope',
    true,
  );
  safeInteger(
    params.requestedTtlMs,
    1,
    1_800_000,
    '$.params.requestedTtlMs',
  );
  safeInteger(
    params.requestedActionLimit,
    1,
    10_000,
    '$.params.requestedActionLimit',
  );
  if (
    Object.hasOwn(params, 'argumentBoundsHash')
    && !SHA256.test(params.argumentBoundsHash)
  ) {
    fail(
      'sha256',
      'argumentBoundsHash must be SHA-256',
      '$.params.argumentBoundsHash',
    );
  }
  const requestsShutdown =
    params.capabilities.includes('session.shutdown');
  const requestsStructuredAction =
    params.capabilities.includes('panel.open');
  if (params.kind === 'domain_transaction') {
    if (requestsShutdown) {
      fail(
        'lease_kind_mismatch',
        'Shutdown requires the dedicated shutdown lease kind',
        '$.params.capabilities',
      );
    }
    if (![
      'appearance.hair.change.v1.commit',
      'appearance.hair.change.v1.restore',
    ].includes(params.operation)) {
      fail(
        'domain_operation_required',
        'Domain lease must bind a frozen hair write method',
        '$.params.operation',
      );
    }
    if (requestsStructuredAction) {
      fail(
        'lease_kind_mismatch',
        'panel.open requires the dedicated structured-action lease kind',
        '$.params.capabilities',
      );
    }
  } else if (params.kind === 'shutdown') {
    if (
      params.capabilities.length !== 1
      || params.capabilities[0] !== 'session.shutdown'
    ) {
      fail(
        'capability_scope_required',
        'Shutdown lease requires exactly session.shutdown',
        '$.params.capabilities',
      );
    }
    if (params.targetScope.length !== 1) {
      fail(
        'exactly_one',
        'Shutdown lease requires exactly one target',
        '$.params.targetScope',
      );
    }
    if (params.requestedTtlMs > 30_000) {
      fail(
        'maximum',
        'Shutdown lease expires within 30 seconds',
        '$.params.requestedTtlMs',
      );
    }
    if (params.requestedActionLimit !== 1) {
      fail(
        'constant',
        'Shutdown lease is one-shot',
        '$.params.requestedActionLimit',
      );
    }
    if (
      Object.hasOwn(params, 'operation')
      || Object.hasOwn(params, 'previewHash')
      || Object.hasOwn(params, 'expectedRevision')
    ) {
      fail(
        'shutdown_lease_fields',
        'Shutdown operation binding is derived by the server',
        '$.params',
      );
    }
    if (requestsStructuredAction) {
      fail(
        'lease_kind_mismatch',
        'panel.open requires the dedicated structured-action lease kind',
        '$.params.capabilities',
      );
    }
  } else if (params.kind === 'structured_action') {
    if (requestsShutdown) {
      fail(
        'lease_kind_mismatch',
        'session.shutdown requires the dedicated shutdown lease kind',
        '$.params.capabilities',
      );
    }
    if (
      params.capabilities.length !== 1
      || params.capabilities[0] !== 'panel.open'
    ) {
      fail(
        'capability_scope_required',
        'Structured-action lease requires exactly panel.open',
        '$.params.capabilities',
      );
    }
    if (params.targetScope.length !== 1) {
      fail(
        'exactly_one',
        'Structured-action lease requires exactly one target',
        '$.params.targetScope',
      );
    }
    if (params.requestedTtlMs > 30_000) {
      fail(
        'maximum',
        'Structured-action lease expires within 30 seconds',
        '$.params.requestedTtlMs',
      );
    }
    if (params.requestedActionLimit !== 1) {
      fail(
        'constant',
        'Structured-action lease is one-shot',
        '$.params.requestedActionLimit',
      );
    }
    if (
      Object.hasOwn(params, 'operation')
      || Object.hasOwn(params, 'previewHash')
      || Object.hasOwn(params, 'expectedRevision')
    ) {
      fail(
        'structured_action_lease_fields',
        'Structured-action operation binding is derived by the server',
        '$.params',
      );
    }
  } else {
    if (
      Object.hasOwn(params, 'operation')
      || Object.hasOwn(params, 'previewHash')
      || Object.hasOwn(params, 'expectedRevision')
    ) {
      fail(
        'gui_lease_domain_fields',
        'GUI lease cannot carry domain fields',
        '$.params',
      );
    }
    if (requestsShutdown) {
      fail(
        'lease_kind_mismatch',
        'Shutdown requires the dedicated shutdown lease kind',
        '$.params.capabilities',
      );
    }
    if (requestsStructuredAction) {
      fail(
        'lease_kind_mismatch',
        'panel.open requires the dedicated structured-action lease kind',
        '$.params.capabilities',
      );
    }
  }
}

function validateGrantIssueParams(params) {
  opaqueId(params.lifecycleRef, '$.params.lifecycleRef');
  const hasTargetIds = Object.hasOwn(params, 'targetIds');
  const hasTargetKinds = Object.hasOwn(params, 'targetKinds');
  if (hasTargetIds === hasTargetKinds) {
    fail(
      'target_selector_exclusive',
      'Exactly one of targetIds or targetKinds is required',
      '$.params',
    );
  }
  if (hasTargetIds) {
    stringArray(
      params.targetIds,
      null,
      1,
      32,
      '$.params.targetIds',
      true,
    );
  } else {
    stringArray(
      params.targetKinds,
      new Set([
        'launcher',
        'flash',
        'web_overlay',
        'native_hud',
        'wings_shell',
        'business_modal',
      ]),
      1,
      6,
      '$.params.targetKinds',
    );
  }
  const scopes = stringArray(
    params.dataScopes,
    observationDataScopes,
    1,
    observationDataScopes.size,
    '$.params.dataScopes',
  );
  safeInteger(
    params.requestedTtlMs,
    1,
    900_000,
    '$.params.requestedTtlMs',
  );
  for (const name of [
    'allowEphemeralKeyframes',
    'allowPersistence',
    'allowExport',
  ]) {
    if (typeof params[name] !== 'boolean') {
      fail(
        'boolean_required',
        `${name} must be boolean`,
        `$.params.${name}`,
      );
    }
  }
  if (
    params.allowEphemeralKeyframes
    && !scopes.includes('pixels')
  ) {
    fail(
      'pixels_scope_required',
      'Keyframe fallback requires pixels scope',
      '$.params.allowEphemeralKeyframes',
    );
  }
  for (const [flag, scope] of [
    ['allowPersistence', 'retention.persist'],
    ['allowExport', 'data.export'],
  ]) {
    if (params[flag] !== scopes.includes(scope)) {
      fail(
        'scope_flag_mismatch',
        `${flag} must exactly match ${scope}`,
        `$.params.${flag}`,
      );
    }
    if (
      params[flag]
      && (
        typeof params.consentReceipt !== 'string'
        || params.consentReceipt.length < 1
      )
    ) {
      fail(
        'consent_required',
        'Persistence/export requires consentReceipt',
        '$.params.consentReceipt',
      );
    }
  }
}

function validateObservationCaptureParams(params) {
  opaqueId(
    params.observationGrantId,
    '$.params.observationGrantId',
  );
  opaqueId(params.sessionId, '$.params.sessionId');
  opaqueId(params.targetId, '$.params.targetId');
  if (params.dataScope !== 'pixels') {
    fail(
      'pixels_scope_required',
      'observation.capture only accepts pixels',
      '$.params.dataScope',
    );
  }
  if (
    typeof params.allowValidatedFlashKeyframeFallback !== 'boolean'
  ) {
    fail(
      'boolean_required',
      'Fallback flag must be boolean',
      '$.params.allowValidatedFlashKeyframeFallback',
    );
  }
  if (
    params.allowValidatedFlashKeyframeFallback
    && params.dataScope !== 'pixels'
  ) {
    fail(
      'pixels_scope_required',
      'Flash keyframe fallback requires pixels',
      '$.params.allowValidatedFlashKeyframeFallback',
    );
  }
}

function validateHairReadParams(params, preview) {
  opaqueId(
    params.observationGrantId,
    '$.params.observationGrantId',
  );
  opaqueId(params.targetId, '$.params.targetId');
  exactObject(params.binding, [
    'sessionId',
    'lifecycleGeneration',
    'attemptId',
    'attemptGeneration',
    'slotId',
    'saveSignature',
  ], '$.params.binding');
  opaqueId(params.binding.sessionId, '$.params.binding.sessionId');
  opaqueId(params.binding.attemptId, '$.params.binding.attemptId');
  safeInteger(
    params.binding.lifecycleGeneration,
    1,
    Number.MAX_SAFE_INTEGER,
    '$.params.binding.lifecycleGeneration',
  );
  safeInteger(
    params.binding.attemptGeneration,
    1,
    Number.MAX_SAFE_INTEGER,
    '$.params.binding.attemptGeneration',
  );
  boundedString(params.binding.slotId, 1, 128, '$.params.binding.slotId');
  if (!SHA256.test(params.binding.saveSignature)) {
    fail('sha256', 'saveSignature must be SHA-256', '$.params.binding.saveSignature');
  }
  if (preview) {
    boundedString(params.hairIdentifier, 1, 160, '$.params.hairIdentifier');
    boundedString(
      params.expectedCurrentHair,
      1,
      160,
      '$.params.expectedCurrentHair',
    );
    safeInteger(
      params.expectedRevision,
      0,
      Number.MAX_SAFE_INTEGER,
      '$.params.expectedRevision',
    );
    safeInteger(
      params.expectedGeneration,
      0,
      Number.MAX_SAFE_INTEGER,
      '$.params.expectedGeneration',
    );
    if (!SHA256.test(params.expectedSnapshotHash)) {
      fail(
        'sha256',
        'expectedSnapshotHash must be SHA-256',
        '$.params.expectedSnapshotHash',
      );
    }
  }
}

function validateHairConsentParams(params) {
  opaqueId(
    params.observationGrantId,
    '$.params.observationGrantId',
  );
  opaqueId(params.targetId, '$.params.targetId');
  opaqueId(params.sessionId, '$.params.sessionId');
  safeInteger(
    params.lifecycleGeneration,
    1,
    Number.MAX_SAFE_INTEGER,
    '$.params.lifecycleGeneration',
  );
  opaqueId(params.transactionId, '$.params.transactionId');
  if (!SHA256.test(params.previewHash)) {
    fail(
      'sha256',
      'previewHash must be SHA-256',
      '$.params.previewHash',
    );
  }
}

function boundedString(value, minimum, maximum, valuePath) {
  if (
    typeof value !== 'string'
    || value.length < minimum
    || value.length > maximum
    || RPC_ID_CONTROL.test(value)
  ) {
    fail('string_range', 'String is outside its frozen range', valuePath);
  }
}

function protocolName(value, valuePath) {
  if (
    typeof value !== 'string'
    || !/^[a-z][a-z0-9_.-]{0,127}$/u.test(value)
  ) {
    fail('protocol_name', 'Invalid protocol name', valuePath);
  }
}

function stringArray(
  value,
  allowed,
  minimum,
  maximum,
  valuePath,
  opaqueItems = false,
) {
  if (
    !Array.isArray(value)
    || value.length < minimum
    || value.length > maximum
  ) {
    fail('array_range', 'Array is outside its frozen range', valuePath);
  }
  const seen = new Set();
  value.forEach((item, index) => {
    if (
      typeof item !== 'string'
      || seen.has(item)
      || (allowed && !allowed.has(item))
      || (opaqueItems && !OPAQUE_ID.test(item))
    ) {
      fail(
        'array_item_invalid',
        'Array item is unknown, duplicate, or malformed',
        `${valuePath}[${index}]`,
      );
    }
    seen.add(item);
  });
  return value;
}

function validateRequest(value) {
  exactObject(value, ['jsonrpc', 'id', 'method', 'params']);
  if (value.jsonrpc !== '2.0') {
    fail('jsonrpc_version', 'jsonrpc must equal 2.0', '$.jsonrpc');
  }
  rpcId(value.id);
  if (typeof value.method !== 'string' || !methods.has(value.method)) {
    fail(
      'rpc_method_not_found',
      'Method is not in the closed v1 registry',
      '$.method',
    );
  }
  if (!isObject(value.params)) {
    fail(
      'rpc_params_object_required',
      'Named object params are required',
      '$.params',
    );
  }
  validateMethodParams(value.method, value.params);
  return value;
}

function validateError(error) {
  exactObject(error, ['code', 'message', 'data'], '$.error');
  safeInteger(error.code, -2147483648, 2147483647, '$.error.code');
  if (
    typeof error.message !== 'string'
    || error.message.length < 1
    || error.message.length > 512
  ) {
    fail('rpc_error_message', 'Invalid error message', '$.error.message');
  }
  exactObject(
    error.data,
    ['reasonCode', 'retryable', 'reconcileKind', 'serverSequence'],
    '$.error.data',
  );
  if (
    typeof error.data.reasonCode !== 'string'
    || !reasons.has(error.data.reasonCode)
  ) {
    fail(
      'unknown_reason_code',
      'Reason code is not registered',
      '$.error.data.reasonCode',
    );
  }
  const reason = reasons.get(error.data.reasonCode);
  if (error.data.retryable !== reason.retryable) {
    fail(
      'reason_metadata_mismatch',
      'retryable does not match the reason registry',
      '$.error.data.retryable',
    );
  }
  if (
    typeof error.data.reconcileKind !== 'string'
    || !reconcileKinds.has(error.data.reconcileKind)
    || !reason.reconcileKinds.includes(error.data.reconcileKind)
  ) {
    fail(
      'reason_metadata_mismatch',
      'reconcileKind does not match the reason registry',
      '$.error.data.reconcileKind',
    );
  }
  safeInteger(
    error.data.serverSequence,
    1,
    Number.MAX_SAFE_INTEGER,
    '$.error.data.serverSequence',
  );
}

function validateResponse(value) {
  if (!isObject(value)) {
    fail('rpc_response_object_required', 'Response must be one object');
  }
  const hasResult = Object.hasOwn(value, 'result');
  const hasError = Object.hasOwn(value, 'error');
  if (hasResult === hasError) {
    fail(
      'rpc_result_error_exclusive',
      'Exactly one of result or error is required',
    );
  }
  exactObject(
    value,
    hasResult
      ? ['jsonrpc', 'id', 'result']
      : ['jsonrpc', 'id', 'error'],
  );
  if (value.jsonrpc !== '2.0') {
    fail('jsonrpc_version', 'jsonrpc must equal 2.0', '$.jsonrpc');
  }
  rpcId(value.id);
  if (hasError) validateError(value.error);
  return value;
}

function validateMinimalSessionReference(
  value,
  objectPath = '$.result.minimalSessionRef',
) {
  exactObjectShape(
    value,
    ['projectRunning', 'qualificationState'],
    ['lifecycleRef'],
    objectPath,
  );
  if (typeof value.projectRunning !== 'boolean') {
    fail(
      'boolean_required',
      'projectRunning must be boolean',
      `${objectPath}.projectRunning`,
    );
  }
  if (!runtimeQualificationStates.has(value.qualificationState)) {
    fail(
      'runtime_qualification_state',
      'qualificationState is invalid',
      `${objectPath}.qualificationState`,
    );
  }
  if (value.projectRunning) {
    opaqueId(value.lifecycleRef, `${objectPath}.lifecycleRef`);
  } else if (Object.hasOwn(value, 'lifecycleRef')) {
    fail(
      'lifecycle_ref_not_applicable',
      'A stopped project cannot expose lifecycleRef',
      `${objectPath}.lifecycleRef`,
    );
  }
}

function validateAppLaunchResult(value) {
  exactObject(
    value,
    [
      'launchRequestId',
      'entryPoint',
      'started',
      'alreadyRunning',
      'runtimeMode',
      'minimalSessionRef',
    ],
    '$.result',
  );
  opaqueId(value.launchRequestId, '$.result.launchRequestId');
  if (
    value.entryPoint !== 'standard_entry'
    || value.started !== false
    || value.alreadyRunning !== true
  ) {
    fail(
      'app_launch_result_contract',
      'app.launch result lifecycle status is invalid',
      '$.result',
    );
  }
  if (!runtimeModes.has(value.runtimeMode)) {
    fail(
      'runtime_mode',
      'runtimeMode is invalid',
      '$.result.runtimeMode',
    );
  }
  validateMinimalSessionReference(value.minimalSessionRef);
  return value;
}

function validateMethodResult(method, value) {
  if (method === 'app.launch') {
    validateAppLaunchResult(value);
  }
  return value;
}

function validateBinaryMetadata(metadata, contentLength) {
  exactObject(
    metadata,
    ['handle', 'offset', 'totalLength', 'final', 'contentHash'],
    '$.binaryMetadata',
  );
  opaqueId(metadata.handle, '$.binaryMetadata.handle');
  safeInteger(
    metadata.offset,
    0,
    MAX_BINARY_OBJECT_BYTES,
    '$.binaryMetadata.offset',
  );
  safeInteger(
    metadata.totalLength,
    0,
    MAX_BINARY_OBJECT_BYTES,
    '$.binaryMetadata.totalLength',
  );
  if (
    !Number.isSafeInteger(contentLength)
    || contentLength < 0
    || metadata.offset > metadata.totalLength
    || metadata.offset + contentLength > metadata.totalLength
  ) {
    fail('binary_range', 'Binary chunk range is invalid', '$.binaryMetadata');
  }
  if (typeof metadata.final !== 'boolean') {
    fail('binary_final', 'final must be boolean', '$.binaryMetadata.final');
  }
  const actuallyFinal =
    metadata.offset + contentLength === metadata.totalLength;
  if (
    metadata.final !== actuallyFinal
    || (!metadata.final && contentLength === 0)
  ) {
    fail(
      'binary_final',
      'final does not match the terminal range',
      '$.binaryMetadata.final',
    );
  }
  if (
    typeof metadata.contentHash !== 'string'
    || !SHA256.test(metadata.contentHash)
  ) {
    fail(
      'content_hash_invalid',
      'contentHash must be a SHA-256 hex string',
      '$.binaryMetadata.contentHash',
    );
  }
  return metadata;
}

function decodeBinaryPayload(payload) {
  if (
    !Buffer.isBuffer(payload)
    || payload.length < BINARY_METADATA_PREFIX_BYTES
    || payload.length > MAX_BINARY_FRAME_BYTES
  ) {
    fail('binary_payload_size', 'Binary payload size is invalid');
  }
  const metadataLength = payload.readUInt32LE(0);
  if (
    metadataLength < 1
    || metadataLength > MAX_BINARY_METADATA_BYTES
    || metadataLength > payload.length - BINARY_METADATA_PREFIX_BYTES
  ) {
    fail(
      'binary_metadata_size',
      'Binary metadata length is invalid',
    );
  }
  const headerEnd = BINARY_METADATA_PREFIX_BYTES + metadataLength;
  let metadataText;
  try {
    metadataText = decoder.decode(
      payload.subarray(BINARY_METADATA_PREFIX_BYTES, headerEnd),
    );
  } catch {
    fail('binary_metadata_utf8', 'Binary metadata is not strict UTF-8');
  }
  const metadata = parseStrictJson(metadataText, { maximumDepth: 8 });
  const content = Buffer.from(payload.subarray(headerEnd));
  validateBinaryMetadata(metadata, content.length);
  return { metadata, content };
}

function encodeBinaryPayload(metadata, content) {
  const data = Buffer.from(content);
  validateBinaryMetadata(metadata, data.length);
  const header = Buffer.from(
    encoder.encode(JSON.stringify(metadata)),
  );
  if (
    header.length < 1
    || header.length > MAX_BINARY_METADATA_BYTES
    || (
      BINARY_METADATA_PREFIX_BYTES
      + header.length
      + data.length
    ) > MAX_BINARY_FRAME_BYTES
  ) {
    fail('binary_payload_size', 'Binary payload exceeds the 4 MiB cap');
  }
  const payload = Buffer.allocUnsafe(
    BINARY_METADATA_PREFIX_BYTES + header.length + data.length,
  );
  payload.writeUInt32LE(header.length, 0);
  header.copy(payload, BINARY_METADATA_PREFIX_BYTES);
  data.copy(payload, BINARY_METADATA_PREFIX_BYTES + header.length);
  return payload;
}

module.exports = {
  BINARY_METADATA_PREFIX_BYTES,
  ContractError,
  MAX_BINARY_FRAME_BYTES,
  MAX_BINARY_METADATA_BYTES,
  MAX_BINARY_OBJECT_BYTES,
  MAX_BINARY_READ_COUNT,
  MAX_JSON_FRAME_BYTES,
  OPAQUE_ID,
  PIPE_ID,
  PROTOCOL_MAJOR,
  PROTOCOL_VERSION,
  capabilities,
  decodeBinaryPayload,
  encodeBinaryPayload,
  exactObject,
  exactObjectShape,
  isObject,
  methodInputSchema,
  methods,
  observationDataScopes,
  parameterContracts,
  opaqueId,
  pipeId,
  rpcId,
  safeInteger,
  validateBinaryMetadata,
  validateContentRead,
  validateHello,
  validateMethodParams,
  validateMethodResult,
  validateAppLaunchResult,
  validateRequest,
  validateResponse,
};
