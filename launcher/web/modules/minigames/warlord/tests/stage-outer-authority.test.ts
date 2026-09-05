import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyStageOuterEvent,
  createStageOuterAuthorityState,
  parseStageOuterAttempt,
  parseStageOuterBinding,
  parseStageOuterTerminal,
  STAGE_OUTER_ATTEMPT_SCHEMA,
  STAGE_OUTER_BINDING_SCHEMA,
  STAGE_OUTER_TERMINAL_SCHEMA,
  type StageOuterAuthorityState,
  type StageOuterBindingV1,
  type StageOuterTerminalKind,
} from '../src/stage/outer-authority.js';

const BINDING: StageOuterBindingV1 = {
  schema: STAGE_OUTER_BINDING_SCHEMA,
  runId: 'run.007',
  subStageId: 'sub-stage.007',
  scenarioRef: 'scenario.tutorial.v1',
  callId: 'call.007',
  revision: 3,
};

function authorityState(binding: unknown = BINDING): StageOuterAuthorityState {
  const result = createStageOuterAuthorityState(binding);
  if (!result.ok) throw new Error(JSON.stringify(result.issues));
  return result.value;
}

function terminal(
  terminalKind: StageOuterTerminalKind,
  reasonCode = 'stage.complete',
): Record<string, unknown> {
  return {
    schema: STAGE_OUTER_TERMINAL_SCHEMA,
    runId: BINDING.runId,
    subStageId: BINDING.subStageId,
    scenarioRef: BINDING.scenarioRef,
    callId: BINDING.callId,
    revision: BINDING.revision,
    terminal: terminalKind,
    reasonCode,
  };
}

function notStarted(): Record<string, unknown> {
  return {
    schema: STAGE_OUTER_ATTEMPT_SCHEMA,
    runId: BINDING.runId,
    subStageId: BINDING.subStageId,
    scenarioRef: BINDING.scenarioRef,
    callId: BINDING.callId,
    revision: BINDING.revision,
    result: 'not_started',
    reasonCode: 'stage.not-started',
  };
}

test('outer authority validates exact keys, opaque identity and revision', () => {
  const parsed = parseStageOuterBinding(BINDING);
  assert(parsed.ok, JSON.stringify(parsed.issues));
  assert.equal(parsed.value.runId, 'run.007');
  assert.equal(parsed.value.revision, 3);
  assert.equal(Object.isFrozen(parsed.value), true);

  const extra = parseStageOuterBinding({ ...BINDING, stageName: 'tutorial' });
  assert.equal(extra.ok, false);
  if (extra.ok) throw new Error('Expected exact-key rejection.');
  assert.equal(extra.issues.some((issue) => issue.reasonCode === 'unexpected_key'), true);

  const missing = parseStageOuterBinding({
    schema: STAGE_OUTER_BINDING_SCHEMA,
    runId: BINDING.runId,
    subStageId: BINDING.subStageId,
    scenarioRef: BINDING.scenarioRef,
    callId: BINDING.callId,
  });
  assert.equal(missing.ok, false);
  if (missing.ok) throw new Error('Expected missing-key rejection.');
  assert.equal(missing.issues.some((issue) => issue.reasonCode === 'missing_key'), true);
  assert.equal(missing.issues.some((issue) => issue.reasonCode === 'invalid_revision'), true);

  assert.equal(parseStageOuterBinding({ ...BINDING, callId: 'bad id' }).ok, false);
  assert.equal(parseStageOuterBinding({ ...BINDING, revision: 1.5 }).ok, false);
});

test('outer authority terminal contract is a closed four-value set', () => {
  const terminalKinds: readonly StageOuterTerminalKind[] = [
    'CompleteSubStage', 'FailStage', 'Suspended', 'Unknown',
  ];
  for (const terminalKind of terminalKinds) {
    const parsed = parseStageOuterTerminal(terminal(terminalKind));
    assert(parsed.ok, JSON.stringify(parsed.issues));
    assert.equal(parsed.value.terminal, terminalKind);
  }

  const notATerminal = parseStageOuterTerminal(terminal('CompleteSubStage', 'stage.not-started'));
  assert(notATerminal.ok);
  const invalid = parseStageOuterTerminal({
    ...terminal('CompleteSubStage'),
    terminal: 'not_started',
  });
  assert.equal(invalid.ok, false);
  if (invalid.ok) throw new Error('Expected closed terminal rejection.');
  assert.equal(invalid.issues.some((issue) => issue.reasonCode === 'invalid_terminal'), true);

  const extra = parseStageOuterTerminal({ ...terminal('Unknown'), payload: {} });
  assert.equal(extra.ok, false);
  if (extra.ok) throw new Error('Expected exact-key rejection.');
  assert.equal(extra.issues.some((issue) => issue.reasonCode === 'unexpected_key'), true);
});

test('outer authority accepts all terminal kinds without mapping Unknown to FailStage', () => {
  for (const terminalKind of [
    'CompleteSubStage', 'FailStage', 'Suspended', 'Unknown',
  ] as const) {
    const result = applyStageOuterEvent(authorityState(), terminal(terminalKind));
    assert(result.ok, result.ok ? undefined : result.reasonCode);
    assert.equal(result.disposition, 'accepted');
    assert.equal(result.state.phase, 'terminal');
    if (result.state.phase !== 'terminal') throw new Error('Expected terminal state.');
    assert.equal(result.state.terminal.terminal, terminalKind);
  }
});

test('outer authority treats only an identical terminal replay as duplicate', () => {
  const accepted = applyStageOuterEvent(authorityState(), terminal('CompleteSubStage'));
  assert(accepted.ok);
  assert.equal(accepted.disposition, 'accepted');

  const duplicate = applyStageOuterEvent(accepted.state, structuredClone(terminal('CompleteSubStage')));
  assert(duplicate.ok);
  assert.equal(duplicate.disposition, 'duplicate');
  assert.equal(duplicate.state, accepted.state);

  const changedTerminal = applyStageOuterEvent(accepted.state, terminal('FailStage', 'stage.failed'));
  assert.equal(changedTerminal.ok, false);
  if (changedTerminal.ok) throw new Error('Expected terminal conflict.');
  assert.equal(changedTerminal.reasonCode, 'terminal_conflict');
  assert.equal(changedTerminal.state, accepted.state);

  const changedReason = applyStageOuterEvent(
    accepted.state,
    terminal('CompleteSubStage', 'stage.complete-different'),
  );
  assert.equal(changedReason.ok, false);
  if (changedReason.ok) throw new Error('Expected terminal conflict.');
  assert.equal(changedReason.reasonCode, 'terminal_conflict');
  assert.equal(changedReason.state, accepted.state);
});

test('outer authority absorbs not_started as a non-recoverable startup failure', () => {
  const parsed = parseStageOuterAttempt(notStarted());
  assert(parsed.ok, JSON.stringify(parsed.issues));
  assert.equal(parsed.value.schema, 'warlord.stage-outer-attempt.v1');
  assert.equal(parsed.value.result, 'not_started');

  const initial = authorityState();
  const failedStart = applyStageOuterEvent(initial, notStarted());
  assert(failedStart.ok);
  assert.equal(failedStart.disposition, 'not_started');
  assert.equal(failedStart.state.phase, 'not_started');
  assert.equal(failedStart.state.binding, initial.binding);

  const lateTerminal = applyStageOuterEvent(failedStart.state, terminal('CompleteSubStage'));
  assert.equal(lateTerminal.ok, false);
  if (lateTerminal.ok) throw new Error('Expected late terminal rejection.');
  assert.equal(lateTerminal.reasonCode, 'late_event');
  assert.equal(lateTerminal.state, failedStart.state);

  const lateAttempt = applyStageOuterEvent(failedStart.state, notStarted());
  assert.equal(lateAttempt.ok, false);
  if (lateAttempt.ok) throw new Error('Expected late attempt rejection.');
  assert.equal(lateAttempt.reasonCode, 'late_event');
  assert.equal(lateAttempt.state, failedStart.state);
});

test('outer authority rejects identity drift and stale revisions without state mutation', () => {
  const initial = authorityState();
  const identityDrift = applyStageOuterEvent(initial, {
    ...terminal('CompleteSubStage'),
    scenarioRef: 'scenario.other.v1',
  });
  assert.equal(identityDrift.ok, false);
  if (identityDrift.ok) throw new Error('Expected identity drift rejection.');
  assert.equal(identityDrift.reasonCode, 'identity_drift');
  assert.equal(identityDrift.state, initial);

  const futureRevision = applyStageOuterEvent(initial, {
    ...terminal('CompleteSubStage'),
    revision: BINDING.revision + 1,
  });
  assert.equal(futureRevision.ok, false);
  if (futureRevision.ok) throw new Error('Expected revision drift rejection.');
  assert.equal(futureRevision.reasonCode, 'identity_drift');
  assert.equal(futureRevision.state, initial);

  const staleRevision = applyStageOuterEvent(initial, {
    ...terminal('CompleteSubStage'),
    revision: BINDING.revision - 1,
  });
  assert.equal(staleRevision.ok, false);
  if (staleRevision.ok) throw new Error('Expected stale event rejection.');
  assert.equal(staleRevision.reasonCode, 'late_event');
  assert.equal(staleRevision.state, initial);
});

test('outer authority rejects malformed event contracts fail closed', () => {
  const initial = authorityState();
  const malformed = applyStageOuterEvent(initial, {
    ...terminal('CompleteSubStage'),
    revision: '3',
  });
  assert.equal(malformed.ok, false);
  if (malformed.ok) throw new Error('Expected malformed contract rejection.');
  assert.equal(malformed.reasonCode, 'invalid_contract');
  assert.equal(malformed.state, initial);
  assert.equal(malformed.issues.some((issue) => issue.reasonCode === 'invalid_revision'), true);
});
