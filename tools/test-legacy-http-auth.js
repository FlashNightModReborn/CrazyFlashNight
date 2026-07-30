#!/usr/bin/env node
'use strict';

const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const Auth = require('./lib/legacy-http-auth');

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-legacy-http-auth-'));
const projectRoot = path.join(scratch, 'Project');
const localAppData = path.join(scratch, 'LocalAppData');
fs.mkdirSync(projectRoot, {recursive: true});
const credentialPath = Auth.expectedCredentialPath(projectRoot, {localAppData});
fs.mkdirSync(path.dirname(credentialPath), {recursive: true});

const token = crypto.randomBytes(32).toString('base64url');
const ports = {
  pid: 12345,
  httpPort: 1192,
  socketPort: 1193,
  legacyHttpAuthFile: credentialPath
};
const credential = {
  v: 1,
  kind: 'legacy_http_automation',
  pid: ports.pid,
  processStartUtcTicks: '638900000000000000',
  lifecycleId: crypto.randomBytes(16).toString('base64url'),
  header: Auth.HEADER_NAME,
  token,
  capabilities: ['legacy.task']
};
fs.writeFileSync(credentialPath, JSON.stringify(credential), 'utf8');
const authOptions = {
  localAppData,
  resolveProcessStartUtcTicks: () => credential.processStartUtcTicks
};

const loaded = Auth.readCredential(projectRoot, ports, authOptions);
assert.strictEqual(loaded.token, token);
assert.deepStrictEqual(
  Auth.authorizationHeaders(projectRoot, ports, authOptions),
  {[Auth.HEADER_NAME]: token});

assert.throws(
  () => Auth.readCredential(
    projectRoot,
    {...ports, legacyHttpAuthFile: path.join(scratch, 'attacker.json')},
    authOptions),
  /credential_path_mismatch/);

fs.writeFileSync(
  credentialPath,
  JSON.stringify({...credential, pid: ports.pid + 1}),
  'utf8');
assert.throws(
  () => Auth.readCredential(projectRoot, ports, authOptions),
  /credential_invalid/);

fs.writeFileSync(credentialPath, JSON.stringify(credential), 'utf8');
assert.throws(
  () => Auth.readCredential(
    projectRoot,
    ports,
    {
      localAppData,
      resolveProcessStartUtcTicks: () => '638900000000000001'
    }),
  /process_identity_mismatch/);

const actualProcessStart =
  Auth.resolveProcessStartUtcTicks(process.pid);
assert.match(actualProcessStart, /^[1-9][0-9]{15,18}$/);

fs.rmSync(scratch, {recursive: true, force: true});
console.log('legacy-http-auth tests: 6/6 passed');
