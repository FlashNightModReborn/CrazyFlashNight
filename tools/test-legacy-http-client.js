#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const Auth = require('./lib/legacy-http-auth');
const Client = require('./lib/legacy-http-client');

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-legacy-http-client-'));
try {
  const projectRoot = path.join(scratch, 'Project');
  const localAppData = path.join(scratch, 'LocalAppData');
  fs.mkdirSync(projectRoot, {recursive: true});
  const credentialPath = Auth.expectedCredentialPath(projectRoot, {localAppData});
  fs.mkdirSync(path.dirname(credentialPath), {recursive: true});

  const ports = {
    pid: 12345,
    httpPort: 1192,
    socketPort: 1193,
    legacyHttpAuthFile: credentialPath
  };
  const token = crypto.randomBytes(32).toString('base64url');
  fs.writeFileSync(
    path.join(projectRoot, 'launcher_ports.json'),
    JSON.stringify(ports),
    'utf8');
  fs.writeFileSync(credentialPath, JSON.stringify({
    v: 1,
    kind: 'legacy_http_automation',
    pid: ports.pid,
    processStartUtcTicks: '638900000000000000',
    lifecycleId: crypto.randomBytes(16).toString('base64url'),
    header: Auth.HEADER_NAME,
    token,
    capabilities: ['legacy.task']
  }), 'utf8');

  const context = Client.readExactLauncherHttpContext(
    projectRoot,
    {
      localAppData,
      skipProcessCheck: true,
      resolveProcessStartUtcTicks:
        () => '638900000000000000'
    });
  assert.strictEqual(context.httpPort, ports.httpPort);
  assert.deepStrictEqual(
    Client.authorizationHeadersFor(context, '/task?x=1'),
    {[Auth.HEADER_NAME]: token});
  assert.deepStrictEqual(
    Client.authorizationHeadersFor(context, '/testConnection'),
    {});
  assert.throws(
    () => Client.authorizationHeadersFor(null, '/shutdown'),
    /authorization_context_required/);

  fs.writeFileSync(
    path.join(projectRoot, 'launcher_ports.json'),
    JSON.stringify({...ports, httpPort: '1192'}),
    'utf8');
  assert.throws(
    () => Client.readExactLauncherPorts(
      projectRoot,
      {skipProcessCheck: true}),
    /ports_shape_invalid/);

  fs.writeFileSync(
    path.join(projectRoot, 'launcher_ports.json'),
    JSON.stringify({...ports, legacyHttpAuthFile: path.join(scratch, 'wrong.json')}),
    'utf8');
  assert.throws(
    () => Client.readExactLauncherHttpContext(
      projectRoot,
      {
        localAppData,
        skipProcessCheck: true,
        resolveProcessStartUtcTicks:
          () => '638900000000000000'
      }),
    /credential_path_mismatch/);

  console.log('legacy-http-client tests: 6/6 passed');
} finally {
  fs.rmSync(scratch, {recursive: true, force: true});
}
