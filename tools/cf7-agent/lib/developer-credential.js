'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { TextDecoder } = require('node:util');
const {
  capabilities,
  observationDataScopes,
  opaqueId,
} = require('./contract');
const { projectRootHash } = require('./rendezvous');
const { parseStrictJson } = require('./strict-json');

const CREDENTIAL_SCHEMA =
  'cf7.agent_runtime.developer_credential.v1';
const MAXIMUM_CREDENTIAL_BYTES = 64 * 1024;
const MAXIMUM_CREDENTIAL_LIFETIME_MS = 8 * 60 * 60 * 1000;
const CREDENTIAL_PROPERTIES = Object.freeze([
  'schema',
  'clientInstanceId',
  'enrollmentReceipt',
  'credentialProof',
  'allowedCapabilities',
  'allowedTargets',
  'issuedUtc',
  'expiresUtc',
]);
const SECURITY_SCOPE_CAPABILITIES = new Set([
  ...[...observationDataScopes].map((scope) => `observe:${scope}`),
  'observation.persist',
  'observation.export',
]);
const strictUtf8 = new TextDecoder('utf-8', { fatal: true });
const ROUND_TRIP_UTC =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{7})(?:Z|\+00:00)$/u;

class DeveloperCredentialError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'DeveloperCredentialError';
    this.code = code;
  }
}

function developerCredentialPath(
  projectRoot,
  clientInstanceId,
  localAppData = process.env.LOCALAPPDATA,
) {
  validateOpaque(
    clientInstanceId,
    'client_instance_id_invalid',
    'Client instance ID must be an opaque protocol ID',
  );
  if (
    typeof localAppData !== 'string'
    || localAppData.trim() === ''
  ) {
    throw new DeveloperCredentialError(
      'local_app_data_required',
      'LOCALAPPDATA is unavailable',
    );
  }
  const clientHash = crypto
    .createHash('sha256')
    .update(clientInstanceId, 'utf8')
    .digest('hex');
  return path.join(
    path.resolve(localAppData),
    'CF7FlashNight',
    'agent-runtime',
    'v1',
    projectRootHash(projectRoot),
    'developer-credentials',
    `${clientHash}.json`,
  );
}

function loadDeveloperCredential(options) {
  const filePath = options.path ?? developerCredentialPath(
    options.projectRoot,
    options.clientInstanceId,
    options.localAppData,
  );
  let handle;
  try {
    const descriptor = fs.lstatSync(filePath);
    if (descriptor.isSymbolicLink() || !descriptor.isFile()) {
      fail(
        'credential_not_regular',
        'Developer credential must be a regular non-symlink file',
      );
    }
    if (
      descriptor.size <= 0
      || descriptor.size > MAXIMUM_CREDENTIAL_BYTES
    ) {
      fail(
        'credential_size_invalid',
        'Developer credential must be in (0, 64 KiB]',
      );
    }
    handle = fs.openSync(filePath, 'r');
    const opened = fs.fstatSync(handle);
    if (
      !opened.isFile()
      || opened.size <= 0
      || opened.size > MAXIMUM_CREDENTIAL_BYTES
      || opened.size !== descriptor.size
    ) {
      fail(
        'credential_changed',
        'Developer credential changed during validation',
      );
    }
    const bytes = fs.readFileSync(handle);
    let text;
    try {
      text = strictUtf8.decode(bytes);
    } catch {
      fail(
        'credential_utf8_invalid',
        'Developer credential is not strict UTF-8',
      );
    }
    const document = parseStrictJson(text, {
      maximumDepth: 8,
    });
    validateDeveloperCredentialDocument(
      document,
      options.clientInstanceId,
      options.now ?? Date.now(),
    );
    return Object.freeze({
      credentialProof: document.credentialProof,
      allowedCapabilities: Object.freeze([
        ...document.allowedCapabilities,
      ]),
      allowedTargets: Object.freeze([
        ...document.allowedTargets,
      ]),
      expiresUtc: document.expiresUtc,
      path: filePath,
    });
  } catch (error) {
    if (error instanceof DeveloperCredentialError) throw error;
    if (error && error.code === 'ENOENT') {
      throw new DeveloperCredentialError(
        'credential_not_found',
        'Developer credential file was not found',
      );
    }
    throw new DeveloperCredentialError(
      'credential_unreadable',
      'Developer credential could not be read or validated',
    );
  } finally {
    if (handle !== undefined) fs.closeSync(handle);
  }
}

function validateDeveloperCredentialDocument(
  document,
  expectedClientInstanceId,
  now = Date.now(),
) {
  if (
    document === null
    || typeof document !== 'object'
    || Array.isArray(document)
  ) {
    fail(
      'credential_document_invalid',
      'Developer credential document must be an object',
    );
  }
  const actualProperties = Object.keys(document).sort();
  const expectedProperties = [...CREDENTIAL_PROPERTIES].sort();
  if (
    actualProperties.length !== expectedProperties.length
    || actualProperties.some(
      (property, index) => property !== expectedProperties[index],
    )
  ) {
    fail(
      'credential_properties_invalid',
      'Developer credential has unknown or missing properties',
    );
  }
  if (document.schema !== CREDENTIAL_SCHEMA) {
    fail(
      'credential_schema_invalid',
      'Developer credential schema is unsupported',
    );
  }
  validateOpaque(
    document.clientInstanceId,
    'credential_client_invalid',
    'Developer credential client ID is invalid',
  );
  if (document.clientInstanceId !== expectedClientInstanceId) {
    fail(
      'credential_client_mismatch',
      'Developer credential belongs to a different client',
    );
  }
  validateOpaque(
    document.enrollmentReceipt,
    'credential_receipt_invalid',
    'Developer enrollment receipt is invalid',
  );
  validateProof(document.credentialProof);
  validateCapabilities(document.allowedCapabilities);
  validateTargets(document.allowedTargets);
  const issued = parseRoundTripUtc(document.issuedUtc, 'issuedUtc');
  const expires = parseRoundTripUtc(document.expiresUtc, 'expiresUtc');
  if (
    expires <= issued
    || expires - issued > MAXIMUM_CREDENTIAL_LIFETIME_MS
  ) {
    fail(
      'credential_lifetime_invalid',
      'Developer credential lifetime is invalid',
    );
  }
  if (!Number.isFinite(now) || expires <= now) {
    fail(
      'credential_expired',
      'Developer credential is expired',
    );
  }
  return document;
}

function validateProof(value) {
  if (
    typeof value !== 'string'
    || value.length < 32
    || value.length > 4096
    || !/^[A-Za-z0-9_-]+$/u.test(value)
  ) {
    fail(
      'credential_proof_invalid',
      'Developer credential proof is invalid',
    );
  }
}

function validateCapabilities(values) {
  validateStringArray(
    values,
    'credential_capabilities_invalid',
    (value) => (
      capabilities.has(value)
      || SECURITY_SCOPE_CAPABILITIES.has(value)
    ),
    'Developer credential capabilities are invalid',
  );
}

function validateTargets(values) {
  validateStringArray(
    values,
    'credential_targets_invalid',
    (value) => (
      value !== '*'
      && isOpaque(value)
    ),
    'Developer credential targets are invalid',
  );
}

function validateStringArray(
  values,
  code,
  predicate,
  message,
) {
  if (
    !Array.isArray(values)
    || values.length === 0
    || values.some((value) => (
      typeof value !== 'string'
      || !predicate(value)
    ))
    || new Set(values).size !== values.length
  ) {
    fail(code, message);
  }
}

function parseRoundTripUtc(value, field) {
  if (typeof value !== 'string') {
    fail(
      'credential_timestamp_invalid',
      `Developer credential ${field} is not explicit UTC`,
    );
  }
  const match = ROUND_TRIP_UTC.exec(value);
  if (!match) {
    fail(
      'credential_timestamp_invalid',
      `Developer credential ${field} is not explicit UTC`,
    );
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    fail(
      'credential_timestamp_invalid',
      `Developer credential ${field} is invalid`,
    );
  }
  const roundTrip = new Date(milliseconds);
  if (
    roundTrip.getUTCFullYear() !== Number(match[1])
    || roundTrip.getUTCMonth() + 1 !== Number(match[2])
    || roundTrip.getUTCDate() !== Number(match[3])
    || roundTrip.getUTCHours() !== Number(match[4])
    || roundTrip.getUTCMinutes() !== Number(match[5])
    || roundTrip.getUTCSeconds() !== Number(match[6])
  ) {
    fail(
      'credential_timestamp_invalid',
      `Developer credential ${field} is invalid`,
    );
  }
  return milliseconds;
}

function validateOpaque(value, code, message) {
  try {
    opaqueId(value, '$.opaqueId');
  } catch {
    fail(code, message);
  }
}

function isOpaque(value) {
  try {
    opaqueId(value, '$.opaqueId');
    return true;
  } catch {
    return false;
  }
}

function fail(code, message) {
  throw new DeveloperCredentialError(code, message);
}

module.exports = {
  CREDENTIAL_PROPERTIES,
  CREDENTIAL_SCHEMA,
  DeveloperCredentialError,
  MAXIMUM_CREDENTIAL_BYTES,
  MAXIMUM_CREDENTIAL_LIFETIME_MS,
  developerCredentialPath,
  loadDeveloperCredential,
  validateDeveloperCredentialDocument,
  validateProof,
};
