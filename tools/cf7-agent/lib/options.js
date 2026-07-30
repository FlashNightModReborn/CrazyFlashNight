'use strict';

const path = require('node:path');
const {
  loadDeveloperCredential,
  validateProof,
} = require('./developer-credential');
const { opaqueId } = require('./contract');

function parseAdapterOptions(argv, environment = process.env) {
  const values = {
    projectRoot: environment.CF7_AGENT_PROJECT_ROOT,
    clientInstanceId:
      environment.CF7_AGENT_CLIENT_INSTANCE_ID,
    credentialProof: environment.CF7_AGENT_CREDENTIAL_PROOF,
    expectedLifecycleId:
      environment.CF7_AGENT_LIFECYCLE_ID,
    requestedCapabilities: splitCapabilities(
      environment.CF7_AGENT_CAPABILITIES,
    ),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === '--project-root') {
      values.projectRoot = requiredArgument(argv, ++index, option);
    } else if (option === '--client-instance-id') {
      values.clientInstanceId = requiredArgument(
        argv,
        ++index,
        option,
      );
    } else if (option === '--credential-proof') {
      values.credentialProof = requiredArgument(
        argv,
        ++index,
        option,
      );
    } else if (option === '--expected-lifecycle-id') {
      values.expectedLifecycleId = requiredArgument(
        argv,
        ++index,
        option,
      );
    } else if (option === '--capability') {
      values.requestedCapabilities.push(
        requiredArgument(argv, ++index, option),
      );
    } else if (option === '--capabilities') {
      values.requestedCapabilities.push(
        ...splitCapabilities(
          requiredArgument(argv, ++index, option),
        ),
      );
    } else if (option === '--request-timeout-ms') {
      const raw = requiredArgument(argv, ++index, option);
      const timeout = Number(raw);
      if (
        !Number.isSafeInteger(timeout)
        || timeout < 1
        || timeout > 300_000
      ) {
        throw new Error(
          '--request-timeout-ms must be an integer in [1, 300000]',
        );
      }
      values.requestTimeoutMs = timeout;
    } else {
      throw new Error(`Unknown option: ${option}`);
    }
  }
  values.projectRoot = path.resolve(
    values.projectRoot ?? process.cwd(),
  );
  values.requestedCapabilities = [
    ...new Set(values.requestedCapabilities),
  ];
  if (typeof values.clientInstanceId !== 'string') {
    throw new Error(
      'An explicit --client-instance-id is required',
    );
  }
  try {
    opaqueId(values.clientInstanceId, '$.clientInstanceId');
  } catch {
    throw new Error(
      '--client-instance-id must be an opaque protocol ID',
    );
  }
  if (values.credentialProof === undefined) {
    const credential = loadDeveloperCredential({
      projectRoot: values.projectRoot,
      clientInstanceId: values.clientInstanceId,
      localAppData: environment.LOCALAPPDATA,
    });
    values.credentialProof = credential.credentialProof;
  } else {
    validateProof(values.credentialProof);
  }
  if (values.requestedCapabilities.length === 0) {
    throw new Error(
      'At least one explicit --capability is required',
    );
  }
  return values;
}

function requiredArgument(argv, index, option) {
  const value = argv[index];
  if (typeof value !== 'string' || value === '') {
    throw new Error(`${option} requires a value`);
  }
  return value;
}

function splitCapabilities(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    return [];
  }
  return value.split(',').map((item) => item.trim()).filter(Boolean);
}

module.exports = {
  parseAdapterOptions,
  splitCapabilities,
};
