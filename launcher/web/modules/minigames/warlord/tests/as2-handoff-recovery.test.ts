import assert from 'node:assert/strict';
import test from 'node:test';
import { recoverDefinitiveAs2BattleFailure } from '../src/app/as2-handoff-recovery.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { GameState, MoveOrAttackCommand } from '../src/core/types.js';
import { validateCommand } from '../src/core/validator.js';
import { clearAllPieces, makeState, setAction } from './helpers.js';

function playerBattleFixture(): { state: GameState; command: MoveOrAttackCommand } {
  const state = makeState('as2-failure-player');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'retry-red' });
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'retry-blue' });
  setAction(state, 'red', 4);
  state.activeTurnIndex = state.turnOrder.indexOf('red');
  return {
    state,
    command: {
      type: 'MOVE_OR_ATTACK',
      factionId: 'red',
      pieceIds: ['retry-red'],
      originNodeId: 'R-Supply',
      targetNodeId: 'North-Choke',
    },
  };
}

function aiBattleFixture(): { state: GameState; command: MoveOrAttackCommand } {
  const state = makeState('as2-failure-ai');
  clearAllPieces(state);
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'bounded-blue' });
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'bounded-red' });
  setAction(state, 'blue', 4);
  state.activeTurnIndex = state.turnOrder.indexOf('blue');
  return {
    state,
    command: {
      type: 'MOVE_OR_ATTACK',
      factionId: 'blue',
      pieceIds: ['bounded-blue'],
      originNodeId: 'North-Choke',
      targetNodeId: 'R-Supply',
    },
  };
}

test('AS2 明确拒绝玩家进攻时保持原战略态，重新选兵后仍可重试', () => {
  const { state, command } = playerBattleFixture();
  const before = structuredClone(state);
  const validation = validateCommand(state, command);
  assert.ok(validation.ok && validation.isBattle);

  const first = recoverDefinitiveAs2BattleFailure(state, command);
  const second = recoverDefinitiveAs2BattleFailure(first.state, command);

  assert.equal(first.outcome, 'player_retry');
  assert.equal(second.outcome, 'player_retry');
  assert.equal(first.state, state);
  assert.deepEqual(state, before);
  const retry = validateCommand(second.state, command);
  assert.ok(retry.ok && retry.isBattle);
});

test('AS2 明确拒绝 AI 进攻时只结束当前 AI 行动，不执行战斗也不重复该命令', () => {
  const { state, command } = aiBattleFixture();
  const before = structuredClone(state);
  const validation = validateCommand(state, command);
  assert.ok(validation.ok && validation.isBattle);

  const recovery = recoverDefinitiveAs2BattleFailure(state, command);

  assert.equal(recovery.outcome, 'ai_action_ended');
  assert.notEqual(recovery.state, state);
  assert.deepEqual(state, before);
  assert.equal(recovery.state.battles.length, 0);
  assert.equal(recovery.state.pieces['bounded-blue']?.nodeId, 'North-Choke');
  assert.equal(recovery.state.pieces['bounded-red']?.nodeId, 'R-Supply');
  assert.equal(recovery.state.commandSequence, before.commandSequence + 1);
  assert.equal(recovery.state.commandHistory.at(-1)?.command.type, 'END_ACTION');
  assert.equal(recovery.state.phase, 'SETTLEMENT_PLANNING');
  assert.equal(recovery.state.activeFactionId, null);
});

test('AS2 AI 失败恢复只接受仍处于当前行动位的发起方，否则保持原态并要求阻断', () => {
  const { state, command } = aiBattleFixture();
  setAction(state, 'red', 4);
  state.activeTurnIndex = state.turnOrder.indexOf('red');
  const before = structuredClone(state);

  const recovery = recoverDefinitiveAs2BattleFailure(state, command);

  assert.equal(recovery.outcome, 'blocked');
  assert.equal(recovery.state, state);
  assert.deepEqual(state, before);
});
