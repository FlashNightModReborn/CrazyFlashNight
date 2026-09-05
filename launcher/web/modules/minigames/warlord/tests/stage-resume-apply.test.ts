import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildResumeAppliedReceipt,
  canEmitStageGameOver,
} from '../src/stage/resume-apply.js';
import { STAGE_OUTER_BINDING_SCHEMA } from '../src/stage/outer-authority.js';

const BINDING = {
  schema: STAGE_OUTER_BINDING_SCHEMA,
  runId: 'run.resume.1',
  subStageId: 'sub.resume.1',
  scenarioRef: 'warlord_tutorial_v1',
  callId: 'call.resume.1',
  revision: 2,
} as const;

const RESUME = {
  inputDigest: `sha256:${'A'.repeat(64)}`,
  request: {
    sessionId: 'session.resume.1',
    requestId: 'request.resume.1',
  },
};

test('stage resume apply receipt binds exact battle and outer-stage identities', () => {
  const applied = buildResumeAppliedReceipt(RESUME, BINDING, 'applied');
  assert.deepEqual(applied, {
    schema: 'warlord.as2-resume-apply.v1',
    status: 'applied',
    inputDigest: RESUME.inputDigest,
    sessionId: 'session.resume.1',
    requestId: 'request.resume.1',
    stageOuterBinding: BINDING,
  });
  assert.notEqual(applied?.stageOuterBinding, BINDING);

  assert.equal(buildResumeAppliedReceipt(
    { ...RESUME, inputDigest: 'sha256:bad' },
    BINDING,
    'applied',
  ), null);
  assert.equal(buildResumeAppliedReceipt(
    { ...RESUME, request: { ...RESUME.request, requestId: 'bad id' } },
    BINDING,
    'applied',
  ), null);
  assert.equal(buildResumeAppliedReceipt(
    RESUME,
    { ...BINDING, callId: 'bad id' },
    'applied',
  ), null);
});

test('a frozen battle result never auto-promotes to an outer stage terminal', () => {
  assert.equal(canEmitStageGameOver(true, 'GAME_OVER', true), false);
  assert.equal(canEmitStageGameOver(true, 'FIRST_FACTION_ACTION', false), false);
  assert.equal(canEmitStageGameOver(false, 'FIRST_FACTION_ACTION', true), false);
  assert.equal(canEmitStageGameOver(false, 'GAME_OVER', true), true);
});
