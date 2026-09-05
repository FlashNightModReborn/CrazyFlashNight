import assert from 'node:assert/strict';
import test from 'node:test';
import {
  StageOuterSessionAuthority,
  STAGE_MODE_SOURCE,
  STAGE_MODE_VERSION,
  STAGE_PLAYER_FACTION,
  type StageOuterSessionInit,
} from '../src/stage/session-authority.js';
import {
  STAGE_OUTER_BINDING_SCHEMA,
  type StageOuterBindingV1,
  type StageOuterTerminalV1,
} from '../src/stage/outer-authority.js';

const BINDING: StageOuterBindingV1 = {
  schema: STAGE_OUTER_BINDING_SCHEMA,
  runId: 'run.stage.001',
  subStageId: 'sub-stage.warlord.001',
  scenarioRef: 'scenario.warlord.tutorial.v1',
  callId: 'call.stage.001',
  revision: 4,
};

function stageInit(
  sent: StageOuterTerminalV1[],
  overrides: Partial<StageOuterSessionInit> = {},
): StageOuterSessionInit {
  return {
    source: STAGE_MODE_SOURCE,
    mode: STAGE_MODE_VERSION,
    stageOuterBinding: BINDING,
    stageTerminalSend: (terminal) => {
      sent.push(terminal);
      return true;
    },
    ...overrides,
  };
}

test('stage session mode activates only for exact source/mode and binds player to red', () => {
  assert.equal(STAGE_PLAYER_FACTION, 'red');
  const sent: StageOuterTerminalV1[] = [];
  const wrongSource = new StageOuterSessionAuthority(stageInit(sent, { source: 'runtime' }));
  assert.equal(wrongSource.status, 'inactive');
  assert.equal(wrongSource.emitGameOver('red'), 'inactive');

  const wrongMode = new StageOuterSessionAuthority(stageInit(sent, { mode: 'phase-b' }));
  assert.equal(wrongMode.status, 'inactive');
  assert.equal(wrongMode.prepareUserClose().handled, false);
  assert.equal(sent.length, 0);
});

test('stage session maps fixed red victory to complete and every other rule terminal to failure', () => {
  for (const [winner, expected] of [
    ['red', 'CompleteSubStage'],
    ['blue', 'FailStage'],
    ['draw', 'FailStage'],
  ] as const) {
    const sent: StageOuterTerminalV1[] = [];
    let closeRequests = 0;
    const authority = new StageOuterSessionAuthority(stageInit(sent, {
      stageAutomaticCloseRequest: () => { closeRequests += 1; },
    }));
    assert.equal(authority.emitGameOver(winner), 'sent');
    assert.equal(sent.length, 1);
    assert.equal(closeRequests, 1);
    assert.equal(sent[0]?.terminal, expected);
    assert.equal(sent[0]?.runId, BINDING.runId);
    assert.equal(sent[0]?.subStageId, BINDING.subStageId);
    assert.equal(sent[0]?.scenarioRef, BINDING.scenarioRef);
    assert.equal(sent[0]?.callId, BINDING.callId);
    assert.equal(sent[0]?.revision, BINDING.revision);
  }
});

test('stage session maps N-faction results by victory group instead of a red/blue identity alias', () => {
  for (const [winner, winningVictoryGroupId, playerVictoryGroupId, expected] of [
    ['player', 'victory-group.player', 'victory-group.player', 'CompleteSubStage'],
    ['allied-player-wing', 'victory-group.player', 'victory-group.player', 'CompleteSubStage'],
    ['boss-pact-a', 'victory-group.pact', 'victory-group.player', 'FailStage'],
    ['draw', null, 'victory-group.player', 'FailStage'],
  ] as const) {
    const sent: StageOuterTerminalV1[] = [];
    const authority = new StageOuterSessionAuthority(stageInit(sent));
    assert.equal(authority.emitGameOver(
      winner,
      'player',
      winningVictoryGroupId,
      playerVictoryGroupId,
    ), 'sent');
    assert.equal(sent[0]?.terminal, expected);
  }
});

test('stage session freezes the first terminal and re-acks its exact duplicate', () => {
  const sent: StageOuterTerminalV1[] = [];
  let closeRequests = 0;
  const authority = new StageOuterSessionAuthority(stageInit(sent, {
    stageAutomaticCloseRequest: () => { closeRequests += 1; },
  }));
  assert.equal(authority.emitGameOver('red'), 'sent');
  assert.equal(authority.emitGameOver('red'), 'duplicate');
  assert.equal(authority.emitGameOver('blue'), 'conflict');
  assert.deepEqual(authority.prepareUserClose(), { handled: true, ready: true });
  assert.equal(sent.length, 2);
  assert.equal(closeRequests, 1);
  assert.equal(sent[0]?.terminal, 'CompleteSubStage');
  assert.deepEqual(sent[1], sent[0]);
});

test('stage session preserves Unknown and never replaces it with failure or suspension', () => {
  const sent: StageOuterTerminalV1[] = [];
  const authority = new StageOuterSessionAuthority(stageInit(sent));
  assert.equal(authority.emitTechnicalUnknown(), 'sent');
  assert.equal(authority.emitGameOver('blue'), 'conflict');
  assert.deepEqual(authority.prepareUserClose(), { handled: true, ready: true });
  assert.equal(sent.length, 1);
  assert.equal(sent[0]?.terminal, 'Unknown');
  assert.equal(sent[0]?.reasonCode, 'warlord.stage.technical-unknown');
});

test('stage session malformed binding fails closed instead of becoming ordinary exercise', () => {
  const sent: StageOuterTerminalV1[] = [];
  const authority = new StageOuterSessionAuthority(stageInit(sent, {
    stageOuterBinding: { ...BINDING, callId: 'bad id' },
  }));
  assert.equal(authority.isStageMode, true);
  assert.equal(authority.status, 'blocked');
  assert.equal(authority.blocksGameplay, true);
  assert.equal(authority.emitGameOver('red'), 'blocked');
  assert.deepEqual(authority.prepareUserClose(), { handled: true, ready: false });
  assert.equal(sent.length, 0);
});

test('stage session retries the exact frozen terminal after an initial transport failure', () => {
  const sent: StageOuterTerminalV1[] = [];
  let attempts = 0;
  const authority = new StageOuterSessionAuthority(stageInit(sent, {
    stageTerminalSend: (terminal) => {
      attempts += 1;
      if (attempts === 1) return false;
      sent.push(terminal);
      return true;
    },
  }));
  assert.equal(authority.emitGameOver('red'), 'blocked');
  assert.equal(authority.status, 'terminal_failed');
  assert.equal(authority.emitGameOver('red'), 'duplicate');
  assert.equal(authority.status, 'terminal_sent');
  assert.equal(attempts, 2);
  assert.equal(sent.length, 1);
  assert.equal(sent[0]?.terminal, 'CompleteSubStage');
});

test('stage session repeated transport rejection or throw keeps the terminal failed and close blocked', () => {
  for (const stageTerminalSend of [
    () => false,
    () => { throw new Error('transport unavailable'); },
  ]) {
    let closeRequests = 0;
    const authority = new StageOuterSessionAuthority(stageInit([], {
      stageTerminalSend,
      stageAutomaticCloseRequest: () => { closeRequests += 1; },
    }));
    assert.equal(authority.emitGameOver('red'), 'blocked');
    assert.equal(authority.status, 'terminal_failed');
    assert.deepEqual(authority.prepareUserClose(), { handled: true, ready: false });
    assert.equal(closeRequests, 0);
  }
});

test('stage session manual close sends Suspended before caller performs exact close', () => {
  const sent: StageOuterTerminalV1[] = [];
  let automaticCloseRequests = 0;
  let exactCloseRequests = 0;
  const authority = new StageOuterSessionAuthority(stageInit(sent, {
    stageAutomaticCloseRequest: () => { automaticCloseRequests += 1; },
  }));

  const prepared = authority.prepareUserClose();
  if (prepared.ready) exactCloseRequests += 1;

  assert.deepEqual(prepared, { handled: true, ready: true });
  assert.equal(sent.length, 1);
  assert.equal(sent[0]?.terminal, 'Suspended');
  assert.equal(automaticCloseRequests, 0);
  assert.equal(exactCloseRequests, 1);
});

test('missing Action result closes as return-only Unknown instead of a reopenable suspension', () => {
  const sent: StageOuterTerminalV1[] = [];
  const authority = new StageOuterSessionAuthority(stageInit(sent));

  assert.deepEqual(
    authority.prepareActionResultUnknownClose(),
    { handled: true, ready: true },
  );
  assert.equal(sent.length, 1);
  assert.equal(sent[0]?.terminal, 'Unknown');
  assert.equal(sent[0]?.reasonCode, 'warlord.stage.action-result-unknown');
  assert.deepEqual(
    authority.prepareActionResultUnknownClose(),
    { handled: true, ready: true },
  );
  assert.equal(sent.length, 2);
  assert.deepEqual(sent[1], sent[0]);
});

test('stage session same-binding rebind preserves terminal while new binding and dispose fence old state', () => {
  const sent: StageOuterTerminalV1[] = [];
  const authority = new StageOuterSessionAuthority(stageInit(sent));
  assert.equal(authority.emitGameOver('red'), 'sent');

  const reboundSent: StageOuterTerminalV1[] = [];
  const same = authority.rebind(stageInit(reboundSent));
  assert.equal(same.contextChanged, false);
  assert.deepEqual(authority.prepareUserClose(), { handled: true, ready: true });
  assert.equal(reboundSent.length, 0);

  const nextBinding = { ...BINDING, callId: 'call.stage.002', revision: 5 };
  const changed = authority.rebind(stageInit(reboundSent, { stageOuterBinding: nextBinding }));
  assert.equal(changed.contextChanged, true);
  assert.equal(authority.status, 'awaiting_terminal');
  assert.equal(authority.emitGameOver('blue'), 'sent');
  assert.equal(reboundSent.length, 1);
  assert.equal(reboundSent[0]?.callId, 'call.stage.002');

  authority.dispose();
  assert.equal(authority.status, 'disposed');
  assert.equal(authority.emitTechnicalUnknown(), 'stale');
  assert.equal(reboundSent.length, 1);
});
