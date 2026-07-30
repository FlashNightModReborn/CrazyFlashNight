'use strict';

const fs = require('fs');
const path = require('path');
const Auth = require('./legacy-http-auth');

const PRIVILEGED_PATHS = new Set([
  '/console',
  '/status',
  '/task',
  '/shutdown',
  '/save-push',
  '/logs',
  '/diagnostic'
]);

function fail(code) {
  throw new Error(code);
}

function isPlainObject(value) {
  return value !== null
    && typeof value === 'object'
    && !Array.isArray(value);
}

function isTcpPort(value) {
  return Number.isInteger(value) && value >= 1 && value <= 65535;
}

function isPrivilegedPath(pathname) {
  if (typeof pathname !== 'string') return false;
  return PRIVILEGED_PATHS.has(pathname.split('?', 1)[0]);
}

function assertRegularFile(filePath, code) {
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch (_error) {
    fail(code);
  }
  if (!stat.isFile() || stat.isSymbolicLink()) fail(code);
}

function readExactLauncherPorts(projectRoot, options = {}) {
  if (typeof projectRoot !== 'string' || !projectRoot.trim()) {
    fail('legacy_http_project_root_required');
  }
  const root = path.resolve(projectRoot);
  const portsFile = path.join(root, 'launcher_ports.json');
  assertRegularFile(portsFile, 'legacy_http_ports_file_invalid');

  let ports;
  try {
    ports = JSON.parse(fs.readFileSync(portsFile, 'utf8'));
  } catch (_error) {
    fail('legacy_http_ports_json_invalid');
  }
  if (!isPlainObject(ports)
      || !Number.isInteger(ports.pid) || ports.pid <= 0
      || !isTcpPort(ports.httpPort)
      || !isTcpPort(ports.socketPort)
      || ports.httpPort === ports.socketPort) {
    fail('legacy_http_ports_shape_invalid');
  }
  if (options.skipProcessCheck !== true) {
    try {
      process.kill(ports.pid, 0);
    } catch (_error) {
      fail('legacy_http_ports_pid_not_running');
    }
  }
  return Object.freeze({
    projectRoot: root,
    portsFile,
    pid: ports.pid,
    httpPort: ports.httpPort,
    socketPort: ports.socketPort,
    legacyHttpAuthFile:
      typeof ports.legacyHttpAuthFile === 'string'
        ? ports.legacyHttpAuthFile
        : null
  });
}

function readExactLauncherHttpContext(projectRoot, options = {}) {
  const ports = readExactLauncherPorts(projectRoot, options);
  const credential = Auth.readCredential(ports.projectRoot, ports, options);
  return Object.freeze({
    ...ports,
    credential,
    authorizationHeaders: Object.freeze({
      [credential.header]: credential.token
    })
  });
}

function authorizationHeadersFor(context, pathname) {
  if (!isPrivilegedPath(pathname)) return Object.freeze({});
  if (!context
      || !isTcpPort(context.httpPort)
      || !context.authorizationHeaders
      || typeof context.authorizationHeaders[Auth.HEADER_NAME] !== 'string') {
    fail('legacy_http_authorization_context_required');
  }
  return context.authorizationHeaders;
}

module.exports = {
  PRIVILEGED_PATHS,
  authorizationHeadersFor,
  isPrivilegedPath,
  readExactLauncherHttpContext,
  readExactLauncherPorts
};
