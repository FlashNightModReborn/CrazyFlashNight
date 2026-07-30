'use strict';

const crypto = require('crypto');
const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');

const HEADER_NAME = 'X-CF7-Automation-Token';
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function projectRootHash(projectRoot) {
  if (typeof projectRoot !== 'string' || !projectRoot.trim()) {
    throw new Error('legacy_http_project_root_required');
  }
  const canonical = path.resolve(projectRoot)
    .replace(/[\\/]+$/, '')
    .toUpperCase();
  return crypto.createHash('sha256')
    .update(canonical, 'utf8')
    .digest('hex')
    .slice(0, 32);
}

function expectedCredentialPath(projectRoot, options = {}) {
  const localAppData = options.localAppData || process.env.LOCALAPPDATA;
  if (typeof localAppData !== 'string' || !localAppData.trim()) {
    throw new Error('legacy_http_localappdata_unavailable');
  }
  return path.join(
    path.resolve(localAppData),
    'CF7FlashNight',
    'agent-runtime',
    'v1',
    projectRootHash(projectRoot),
    'legacy-http-credential.json');
}

function readCredential(projectRoot, ports, options = {}) {
  if (!ports || !Number.isInteger(ports.pid) || ports.pid <= 0) {
    throw new Error('legacy_http_ports_pid_invalid');
  }
  const expectedPath = expectedCredentialPath(projectRoot, options);
  const advertised = ports.legacyHttpAuthFile;
  if (typeof advertised !== 'string'
      || path.resolve(advertised).toUpperCase() !== expectedPath.toUpperCase()) {
    throw new Error('legacy_http_credential_path_mismatch');
  }
  const stat = fs.lstatSync(expectedPath);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error('legacy_http_credential_not_regular_file');
  }
  const parsed = JSON.parse(fs.readFileSync(expectedPath, 'utf8'));
  if (parsed.v !== 1
      || parsed.kind !== 'legacy_http_automation'
      || parsed.pid !== ports.pid
      || parsed.header !== HEADER_NAME
      || typeof parsed.lifecycleId !== 'string'
      || !parsed.lifecycleId
      || typeof parsed.processStartUtcTicks !== 'string'
      || !/^[1-9][0-9]{15,18}$/.test(parsed.processStartUtcTicks)
      || typeof parsed.token !== 'string'
      || !TOKEN_PATTERN.test(parsed.token)
      || !Array.isArray(parsed.capabilities)) {
    throw new Error('legacy_http_credential_invalid');
  }
  const actualStartTicks = resolveProcessStartUtcTicks(
    parsed.pid,
    options);
  if (actualStartTicks !== parsed.processStartUtcTicks) {
    throw new Error(
      'legacy_http_credential_process_identity_mismatch');
  }
  return Object.freeze({
    path: expectedPath,
    header: HEADER_NAME,
    token: parsed.token,
    pid: parsed.pid,
    processStartUtcTicks: parsed.processStartUtcTicks,
    lifecycleId: parsed.lifecycleId,
    capabilities: Object.freeze(parsed.capabilities.slice())
  });
}

function resolveProcessStartUtcTicks(pid, options = {}) {
  if (typeof options.resolveProcessStartUtcTicks === 'function') {
    const resolved = String(options.resolveProcessStartUtcTicks(pid));
    if (!/^[1-9][0-9]{15,18}$/.test(resolved)) {
      throw new Error(
        'legacy_http_credential_process_identity_unavailable');
    }
    return resolved;
  }
  if (process.platform !== 'win32') {
    throw new Error(
      'legacy_http_credential_process_identity_unavailable');
  }

  const systemRoot = process.env.SystemRoot || 'C:\\Windows';
  const powershell = path.join(
    systemRoot,
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe');
  const script =
    '$ErrorActionPreference = "Stop"; '
    + `$processRecord = Get-Process -Id ${pid}; `
    + '[Console]::Out.Write('
    + '$processRecord.StartTime.ToUniversalTime().Ticks.ToString('
    + '[Globalization.CultureInfo]::InvariantCulture))';
  try {
    const output = childProcess.execFileSync(
      powershell,
      ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
      {
        encoding: 'utf8',
        windowsHide: true,
        timeout: 5000,
        stdio: ['ignore', 'pipe', 'ignore']
      }).trim();
    if (!/^[1-9][0-9]{15,18}$/.test(output)) {
      throw new Error('invalid_process_start_ticks');
    }
    return output;
  } catch (_error) {
    throw new Error(
      'legacy_http_credential_process_identity_unavailable');
  }
}

function authorizationHeaders(projectRoot, ports, options = {}) {
  const credential = readCredential(projectRoot, ports, options);
  return Object.freeze({[credential.header]: credential.token});
}

module.exports = {
  HEADER_NAME,
  authorizationHeaders,
  expectedCredentialPath,
  projectRootHash,
  readCredential,
  resolveProcessStartUtcTicks
};
