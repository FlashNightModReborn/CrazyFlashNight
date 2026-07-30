'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnFileSync } = require('node:child_process');
const { TextDecoder } = require('node:util');
const {
  OPAQUE_ID,
  PROTOCOL_MAJOR,
  exactObject,
  opaqueId,
  pipeId,
  safeInteger,
} = require('./contract');
const { parseStrictJson } = require('./strict-json');

const MAXIMUM_RENDEZVOUS_BYTES = 64 * 1024;
const MAXIMUM_TICKET_TTL_MS = 30_000;
const DOTNET_UNIX_EPOCH_TICKS = 621355968000000000n;
const qualificationStates = new Set([
  'formal_runtime',
  'isolated_candidate',
  'unqualified_dev',
]);
const strictUtf8 = new TextDecoder('utf-8', { fatal: true });
const documentKeys = [
  'protocolMinMajor',
  'protocolMaxMajor',
  'pipeId',
  'launcherProcessId',
  'launcherStartTimeUtc',
  'lifecycleId',
  'runtimeQualificationState',
  'ticketExpiresUtc',
  'connectionTicket',
];

class RendezvousError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'RendezvousError';
    this.code = code;
  }
}

function projectRootHash(projectRoot) {
  if (typeof projectRoot !== 'string' || projectRoot.trim() === '') {
    throw new RendezvousError(
      'project_root_required',
      'A project root is required',
    );
  }
  const normalized = path.resolve(projectRoot)
    .replace(/[\\/]+$/u, '')
    .replaceAll('/', '\\')
    .toUpperCase();
  return crypto
    .createHash('sha256')
    .update(normalized, 'utf8')
    .digest('hex');
}

function rendezvousPath(projectRoot, localAppData = process.env.LOCALAPPDATA) {
  if (typeof localAppData !== 'string' || localAppData.trim() === '') {
    throw new RendezvousError(
      'local_app_data_required',
      'LOCALAPPDATA is unavailable',
    );
  }
  return path.join(
    path.resolve(localAppData),
    'CF7FlashNight',
    'agent-runtime',
    'v1',
    projectRootHash(projectRoot),
    'rendezvous.json',
  );
}

function parseUtc(value, valuePath) {
  if (
    typeof value !== 'string'
    || !/(?:Z|\+00:00)$/u.test(value)
  ) {
    throw new RendezvousError(
      'utc_timestamp_required',
      `${valuePath} must have an explicit zero UTC offset`,
    );
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw new RendezvousError(
      'utc_timestamp_invalid',
      `${valuePath} is not a valid timestamp`,
    );
  }
  return milliseconds;
}

function utcTimestampToDotNetTicks(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?(?:Z|\+00:00)$/u
    .exec(value);
  if (!match) {
    throw new RendezvousError(
      'utc_timestamp_invalid',
      'launcherStartTimeUtc is not a supported round-trip timestamp',
    );
  }
  const [
    ,
    year,
    month,
    day,
    hour,
    minute,
    second,
    fraction = '',
  ] = match;
  const wholeSecondMilliseconds = Date.UTC(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    Number(second),
  );
  if (!Number.isFinite(wholeSecondMilliseconds)) {
    throw new RendezvousError(
      'utc_timestamp_invalid',
      'launcherStartTimeUtc is outside the supported range',
    );
  }
  const roundTrip = new Date(wholeSecondMilliseconds);
  if (
    roundTrip.getUTCFullYear() !== Number(year)
    || roundTrip.getUTCMonth() + 1 !== Number(month)
    || roundTrip.getUTCDate() !== Number(day)
    || roundTrip.getUTCHours() !== Number(hour)
    || roundTrip.getUTCMinutes() !== Number(minute)
    || roundTrip.getUTCSeconds() !== Number(second)
  ) {
    throw new RendezvousError(
      'utc_timestamp_invalid',
      'launcherStartTimeUtc contains an invalid calendar value',
    );
  }
  const fractionalTicks = BigInt(
    (fraction + '0000000').slice(0, 7),
  );
  return (
    DOTNET_UNIX_EPOCH_TICKS
    + BigInt(wholeSecondMilliseconds) * 10_000n
    + fractionalTicks
  );
}

function validateRendezvousDocument(
  document,
  options = {},
) {
  try {
    exactObject(document, documentKeys);
    if (
      document.protocolMinMajor !== PROTOCOL_MAJOR
      || document.protocolMaxMajor !== PROTOCOL_MAJOR
    ) {
      throw new RendezvousError(
        'protocol_range_unsupported',
        'Rendezvous protocol range must be exactly v1',
      );
    }
    pipeId(document.pipeId);
    safeInteger(
      document.launcherProcessId,
      1,
      2147483647,
      '$.launcherProcessId',
    );
    parseUtc(
      document.launcherStartTimeUtc,
      '$.launcherStartTimeUtc',
    );
    opaqueId(document.lifecycleId, '$.lifecycleId');
    if (
      typeof document.runtimeQualificationState !== 'string'
      || !qualificationStates.has(
        document.runtimeQualificationState,
      )
    ) {
      throw new RendezvousError(
        'qualification_state_invalid',
        'Rendezvous qualification state is unknown',
      );
    }
    const expiry = parseUtc(
      document.ticketExpiresUtc,
      '$.ticketExpiresUtc',
    );
    opaqueId(document.connectionTicket, '$.connectionTicket');
    const now = options.now ?? Date.now();
    if (expiry <= now) {
      throw new RendezvousError(
        'ticket_expired',
        'Connection ticket has expired',
      );
    }
    if (expiry - now > MAXIMUM_TICKET_TTL_MS) {
      throw new RendezvousError(
        'ticket_expiry_invalid',
        'Connection ticket exceeds the 30 second TTL',
      );
    }
    if (
      options.expectedLifecycleId !== undefined
      && options.expectedLifecycleId !== null
      && document.lifecycleId !== options.expectedLifecycleId
    ) {
      throw new RendezvousError(
        'lifecycle_stale',
        'Rendezvous lifecycle does not match the expected lifecycle',
      );
    }
    return document;
  } catch (error) {
    if (error instanceof RendezvousError) throw error;
    throw new RendezvousError(
      error.code ?? 'rendezvous_malformed',
      error.message,
    );
  }
}

function systemProcessProbe(processId) {
  const script =
    `$process = Get-Process -Id ${processId} -ErrorAction Stop; `
    + '[Console]::Out.Write('
    + '$process.StartTime.ToUniversalTime().Ticks.ToString('
    + '[Globalization.CultureInfo]::InvariantCulture))';
  const result = spawnFileSync(
    'powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', script],
    {
      encoding: 'utf8',
      windowsHide: true,
      timeout: 5_000,
      maxBuffer: 8_192,
    },
  );
  if (result.status !== 0 || !/^\d+$/u.test(result.stdout.trim())) {
    return null;
  }
  return BigInt(result.stdout.trim());
}

function readRendezvous(options) {
  const filePath = options.path ?? rendezvousPath(
    options.projectRoot,
    options.localAppData,
  );
  let descriptor;
  let handle;
  try {
    descriptor = fs.lstatSync(filePath);
    if (descriptor.isSymbolicLink() || !descriptor.isFile()) {
      throw new RendezvousError(
        'rendezvous_not_regular',
        'Rendezvous must be a regular non-symlink file',
      );
    }
    if (descriptor.size > MAXIMUM_RENDEZVOUS_BYTES) {
      throw new RendezvousError(
        'rendezvous_oversized',
        'Rendezvous exceeds 64 KiB',
      );
    }
    handle = fs.openSync(filePath, 'r');
    const opened = fs.fstatSync(handle);
    if (!opened.isFile() || opened.size > MAXIMUM_RENDEZVOUS_BYTES) {
      throw new RendezvousError(
        'rendezvous_changed',
        'Rendezvous changed during validation',
      );
    }
    const bytes = fs.readFileSync(handle);
    let text;
    try {
      text = strictUtf8.decode(bytes);
    } catch {
      throw new RendezvousError(
        'rendezvous_malformed',
        'Rendezvous is not strict UTF-8',
      );
    }
    const document = parseStrictJson(text, {
      maximumDepth: 8,
    });
    validateRendezvousDocument(document, options);
    const probe = options.processProbe ?? systemProcessProbe;
    const actualTicks = probe(document.launcherProcessId);
    const expectedTicks = utcTimestampToDotNetTicks(
      document.launcherStartTimeUtc,
    );
    if (
      actualTicks === null
      || BigInt(actualTicks) !== expectedTicks
    ) {
      throw new RendezvousError(
        'process_stale',
        'Rendezvous PID/start-time identity is stale',
      );
    }
    return Object.freeze({
      ...document,
      path: filePath,
    });
  } catch (error) {
    if (error instanceof RendezvousError) throw error;
    if (error && error.code === 'ENOENT') {
      throw new RendezvousError(
        'rendezvous_not_found',
        'Rendezvous file was not found',
      );
    }
    throw new RendezvousError(
      'rendezvous_unreadable',
      `Rendezvous could not be read: ${error.message}`,
    );
  } finally {
    if (handle !== undefined) fs.closeSync(handle);
  }
}

module.exports = {
  MAXIMUM_RENDEZVOUS_BYTES,
  MAXIMUM_TICKET_TTL_MS,
  RendezvousError,
  projectRootHash,
  readRendezvous,
  rendezvousPath,
  systemProcessProbe,
  utcTimestampToDotNetTicks,
  validateRendezvousDocument,
};
