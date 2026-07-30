#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function includesAll(file, markers) {
  const source = read(file);
  for (const marker of markers) {
    assert.ok(source.includes(marker), `${file} is missing ${marker}`);
  }
  assert.ok(!source.includes('PORT_CANDIDATES'), `${file} retains candidate scanning`);
}

includesAll('tools/arena-calibration/run-unattended.js', [
  'LegacyHttpClient.authorizationHeadersFor',
  'LegacyHttpClient.readExactLauncherHttpContext',
  'enableLegacyHttpAutomation: true'
]);
includesAll('tools/equipment-tuning/run-unattended.js', [
  'LegacyHttpClient.authorizationHeadersFor',
  'LegacyHttpClient.readExactLauncherHttpContext',
  'enableLegacyHttpAutomation: true'
]);
includesAll('tools/prepare-loot-target-full-save.js', [
  'LegacyHttpClient.authorizationHeadersFor',
  'LegacyHttpClient.readExactLauncherHttpContext'
]);

for (const file of [
  'scripts/gobang_trainer_cycle.ps1',
  'scripts/protocol_latency_cycle.ps1'
]) {
  const source = read(file);
  assert.ok(source.includes('tools\\lib\\LegacyHttpAuth.ps1'));
  assert.ok(source.includes('-Headers $context.Headers'));
  assert.ok(!source.includes('$BusPorts'));
}

const powerShellCli = read('tools/cfn-cli.ps1');
assert.ok(powerShellCli.includes('Get-Cf7LegacyHttpContext'));
assert.ok(powerShellCli.includes('-Headers $context.Headers'));
assert.ok(powerShellCli.includes('/logBatch'));
assert.ok(!powerShellCli.includes('candidate port'));

const bashCli = read('tools/cfn-cli.sh');
assert.ok(bashCli.includes('read_legacy_auth_context'));
assert.ok(bashCli.includes('-H "$AUTH_HEADER: $AUTH_TOKEN"'));
assert.ok(bashCli.includes('refusing process-name fallback'));
assert.ok(!bashCli.includes('PORTS=('));

const runtimeIdentity = read('tools/lib/runtime-process-identity.js');
assert.ok(runtimeIdentity.includes('"-EnableLegacyHttpAutomation"'));
assert.ok(runtimeIdentity.includes('enableLegacyHttpAutomation === true'));

console.log('legacy HTTP client migration checks: passed');
