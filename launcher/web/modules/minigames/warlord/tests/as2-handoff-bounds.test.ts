import assert from 'node:assert/strict';
import test from 'node:test';
import type { BattleRecord } from '../src/battle/types.js';
import {
  AS2_BATTLE_HANDOFF_EVENT_LOG_LIMIT,
  AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES,
  buildAs2BattleEnvelope,
  type As2BattleEnvelope,
  type As2BattleClientContext,
} from '../src/battle/as2-authority.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { GameState, MoveOrAttackCommand } from '../src/core/types.js';
import { makeReplay } from '../src/replay/replay.js';
import { clearAllPieces, makeState, setAction } from './helpers.js';

function battleFixture(seed: string): { state: GameState; command: MoveOrAttackCommand } {
  const state = makeState(seed);
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'handoff-red' });
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'handoff-blue' });
  setAction(state, 'red', 4);
  return {
    state,
    command: {
      type: 'MOVE_OR_ATTACK',
      factionId: 'red',
      pieceIds: ['handoff-red'],
      originNodeId: 'R-Supply',
      targetNodeId: 'North-Choke',
    },
  };
}

function clientContext(): As2BattleClientContext {
  return {
    seed: 'handoff-bounds',
    preset: 'standard',
    difficulty: 'normal',
    mapTheme: 'desert',
    forceWebglFailure: false,
    aiSeenTransitions: [],
  };
}

function historicalBattle(serial: number): BattleRecord {
  const token = String(serial).padStart(3, '0');
  return {
    battleId: `historical-battle-${token}`,
    seed: `历史战斗-${token}`,
    strategicRound: 1,
    commandSequence: serial,
    nodeId: 'North-Choke',
    attackerOriginNodeId: 'R-Supply',
    attackerPieceIds: [],
    defenderPieceIds: [],
    attackerSnapshots: [],
    defenderSnapshots: [],
    result: {
      winner: 'attacker',
      reason: 'wiped',
      battleRounds: 1,
      pieceResults: [],
      casualties: [],
      eventLog: [],
      finalRngState: serial,
    },
  };
}

function appendSettledHistory(state: GameState, serial: number): void {
  const token = String(serial).padStart(3, '0');
  state.commandSequence = serial;
  state.battleOrdinal = serial;
  state.nextEventOrdinal = 1000 + serial;
  state.battles.push(historicalBattle(serial));
  state.commandHistory.push({
    sequence: serial,
    command: { type: 'END_ACTION', factionId: 'red' },
  });
  state.eventLog.push({
    eventId: `historical-event-${token}`,
    strategicRound: 1,
    commandSequence: serial,
    type: 'move',
    factionId: 'red',
    message: `连续交战记录-${token}`,
  });
  state.casualtyLedger.push({
    casualtyId: `settled-casualty-${token}`,
    strategicRound: 1,
    battleId: `historical-battle-${token}`,
    deadPieceId: `historical-piece-${token}`,
    deadFactionId: 'blue',
    killerFactionId: 'red',
    cardId: 15,
    frozenCardLevel: 1,
    bounty: 100,
    killerXp: 50,
    loserXp: 25,
    settled: true,
  });
}

test('96 次连续 AS2 handoff 只传有界投影且不会改写原战略态', async () => {
  const { state, command } = battleFixture('连续交战-平台化');
  state.casualtyLedger.push({
    casualtyId: 'unsettled-casualty',
    strategicRound: 1,
    battleId: 'pending-battle',
    deadPieceId: 'pending-piece',
    deadFactionId: 'blue',
    killerFactionId: 'red',
    cardId: 15,
    frozenCardLevel: 1,
    bounty: 100,
    killerXp: 50,
    loserXp: 25,
    settled: false,
  });

  const requestBytes: number[] = [];
  let lastEnvelope: As2BattleEnvelope | null = null;
  for (let serial = 1; serial <= 96; serial += 1) {
    appendSettledHistory(state, serial);
    const before = structuredClone(state);
    const token = String(serial).padStart(3, '0');
    const envelope = await buildAs2BattleEnvelope({
      panelInstanceId: 'warlord.panel.handoff-bounds',
      callId: `warlord.call.handoff-${token}`,
      sessionId: 'warlord.session.handoff-bounds',
      requestId: `warlord.request.handoff-${token}`,
      state,
      command,
      clientContext: clientContext(),
    });

    assert.deepEqual(state, before);
    assert.equal(envelope.request.state.commandSequence, state.commandSequence);
    assert.equal(envelope.request.state.battleOrdinal, state.battleOrdinal);
    assert.equal(envelope.request.state.nextEventOrdinal, state.nextEventOrdinal);
    assert.deepEqual(envelope.request.state.battles, []);
    assert.deepEqual(envelope.request.state.commandHistory, []);
    assert.deepEqual(
      envelope.request.state.eventLog,
      state.eventLog.slice(-AS2_BATTLE_HANDOFF_EVENT_LOG_LIMIT),
    );
    assert.deepEqual(
      envelope.request.state.casualtyLedger.map((entry) => entry.casualtyId),
      ['unsettled-casualty'],
    );
    requestBytes.push(new TextEncoder().encode(JSON.stringify(envelope.request)).byteLength);
    lastEnvelope = envelope;
  }

  assert.ok(lastEnvelope);
  assert.equal(state.battles.length, 96);
  assert.equal(state.commandHistory.length, 96);
  assert.equal(makeReplay(state).commands.length, 96);
  assert.throws(() => makeReplay(lastEnvelope.request.state), /完整命令历史/);
  const plateau = requestBytes.slice(AS2_BATTLE_HANDOFF_EVENT_LOG_LIMIT);
  assert.ok(Math.max(...plateau) - Math.min(...plateau) <= 8);
  assert.ok(Math.max(...requestBytes) < AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES);
  assert.equal(lastEnvelope.request.state.eventLog.at(-1)?.message, '连续交战记录-096');
});

test('AS2 handoff 软门按真实 UTF-8 字节而不是 JavaScript 字符数判定', async () => {
  const { state, command } = battleFixture('utf8-soft-limit');
  const chinesePayload = '战'.repeat(AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES / 2);
  assert.ok(chinesePayload.length < AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES);
  assert.ok(new TextEncoder().encode(chinesePayload).byteLength > AS2_BATTLE_REQUEST_SOFT_LIMIT_BYTES);
  state.gameSeed = chinesePayload;

  let rejection: unknown = null;
  try {
    await buildAs2BattleEnvelope({
      panelInstanceId: 'warlord.panel.utf8-limit',
      callId: 'warlord.call.utf8-limit',
      sessionId: 'warlord.session.utf8-limit',
      requestId: 'warlord.request.utf8-limit',
      state,
      command,
      clientContext: clientContext(),
    });
  } catch (error) {
    rejection = error;
  }
  assert.ok(rejection instanceof Error);
  assert.match(rejection.message, /超过 Web 侧 393216 字节软上限/);
});

test('录像导出对等长但不连续的命令历史同样 fail closed', () => {
  const state = makeState('replay-gap-fails-closed');
  state.commandSequence = 2;
  state.commandHistory = [
    { sequence: 1, command: { type: 'END_ACTION', factionId: 'red' } },
    { sequence: 3, command: { type: 'END_ACTION', factionId: 'blue' } },
  ];

  assert.throws(() => makeReplay(state), /完整命令历史/);
});
