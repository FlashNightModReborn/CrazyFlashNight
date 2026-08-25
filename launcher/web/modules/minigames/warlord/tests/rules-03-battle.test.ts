import assert from 'node:assert/strict';
import test from 'node:test';
import { completePlayback, skipPlayback } from '../src/battle/playback.js';
import { resolveBattle } from '../src/battle/resolver.js';
import type { BattleResult, ResolveBattleInput } from '../src/battle/types.js';
import { applyCommand } from '../src/core/engine.js';
import { getRuntimeStats } from '../src/core/math.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import { getCardDefinition } from '../src/data/cards.js';
import { clearAllPieces, makeState, makeUnit, moveCommand, setAction } from './helpers.js';

function baseInput(seed: string): Omit<ResolveBattleInput, 'attackerUnits' | 'defenderUnits'> {
  return {
    battleId: `battle-${seed}`,
    seed,
    strategicRound: 1,
    commandSequence: 1,
    nodeId: 'Center-Command',
    nodeDefenseBonus: 0,
    attackerOriginNodeId: 'R-Supply',
  };
}

function firstActorAttack(result: BattleResult, pieceId: string) {
  return result.eventLog.find((event) => event.type === 'attack' && event.actorPieceId === pieceId && event.phase === 'normal');
}

test('AC-21 普通目标先看最小阵型档位，再看低 HP 比例，最后 pieceId', () => {
  const rankResult = resolveBattle({
    ...baseInput('ac-21-rank'), maxBattleRounds: 1,
    attackerUnits: [makeUnit('actor', 'red', 14, { attack: 1, speed: 100, hp: 1_000_000, maxHp: 1_000_000 })],
    defenderUnits: [
      makeUnit('heavy-high', 'blue', 15, { hp: 800, maxHp: 1000, attack: 1, speed: 1 }),
      makeUnit('heavy-low', 'blue', 15, { hp: 200, maxHp: 1000, attack: 1, speed: 1 }),
      makeUnit('assault-critical', 'blue', 14, { hp: 1, maxHp: 1000, attack: 1, speed: 1 }),
    ],
  });
  assert.equal(firstActorAttack(rankResult, 'actor')?.targetPieceId, 'heavy-low');

  const tieResult = resolveBattle({
    ...baseInput('ac-21-tie'), maxBattleRounds: 1,
    attackerUnits: [makeUnit('actor', 'red', 14, { attack: 1, speed: 100, hp: 1_000_000, maxHp: 1_000_000 })],
    defenderUnits: [
      makeUnit('heavy-b', 'blue', 15, { hp: 500, maxHp: 1000, attack: 1, speed: 1 }),
      makeUnit('heavy-a', 'blue', 15, { hp: 500, maxHp: 1000, attack: 1, speed: 1 }),
    ],
  });
  assert.equal(firstActorAttack(tieResult, 'actor')?.targetPieceId, 'heavy-a');
});

test('AC-22 每场新节点战斗都重新获得狙击先制齐射', () => {
  const attacker = makeUnit('sniper', 'red', 12, { hp: 1_000_000, maxHp: 1_000_000, attack: 1 });
  const defender = makeUnit('target', 'blue', 15, { hp: 1_000_000, maxHp: 1_000_000, attack: 1 });
  const first = resolveBattle({ ...baseInput('ac-22-a'), attackerUnits: [attacker], defenderUnits: [defender], maxBattleRounds: 1 });
  const second = resolveBattle({ ...baseInput('ac-22-b'), attackerUnits: [attacker], defenderUnits: [defender], maxBattleRounds: 1 });
  assert.equal(first.eventLog.filter((event) => event.type === 'sniper_volley').length, 1);
  assert.equal(second.eventLog.filter((event) => event.type === 'sniper_volley').length, 1);
  assert.equal(first.pieceResults.find((piece) => piece.pieceId === 'sniper')?.attacksMade, 1);
  assert.equal(second.pieceResults.find((piece) => piece.pieceId === 'sniper')?.attacksMade, 1);
});

test('AC-23 双方狙击先制按战斗回合开始快照同时结算', () => {
  let result: BattleResult | null = null;
  for (let index = 0; index < 256; index += 1) {
    const candidate = resolveBattle({
      ...baseInput(`ac-23-${index}`),
      attackerUnits: [makeUnit('red-sniper', 'red', 12, { hp: 1, maxHp: 1, attack: 100_000, speed: 30 })],
      defenderUnits: [makeUnit('blue-sniper', 'blue', 12, { hp: 1, maxHp: 1, attack: 100_000, speed: 30 })],
    });
    if (candidate.reason === 'mutual_wipe') {
      result = candidate;
      break;
    }
  }
  assert.ok(result);
  assert.equal(result.casualties.length, 2);
  assert.equal(result.eventLog.filter((event) => event.type === 'death' && event.phase === 'opening_volley').length, 2);
  assert.equal(result.pieceResults.find((piece) => piece.pieceId === 'red-sniper')?.attacksMade, 1);
  assert.equal(result.pieceResults.find((piece) => piece.pieceId === 'blue-sniper')?.attacksMade, 1);
});

test('AC-24 弹药兵第 1 战斗回合装填，只在偶数战斗回合攻击', () => {
  const result = resolveBattle({
    ...baseInput('ac-24'), maxBattleRounds: 4,
    attackerUnits: [makeUnit('ammo', 'red', 13, { hp: 1_000_000, maxHp: 1_000_000, attack: 1, speed: 50 })],
    defenderUnits: [makeUnit('tank', 'blue', 14, { hp: 1_000_000, maxHp: 1_000_000, attack: 1, speed: 1 })],
  });
  assert.equal(result.eventLog.filter((event) => event.type === 'reload' && event.actorPieceId === 'ammo' && event.battleRound === 1).length, 1);
  const attackRounds = result.eventLog
    .filter((event) => event.type === 'attack' && event.actorPieceId === 'ammo')
    .map((event) => event.battleRound);
  assert.deepEqual(attackRounds, [2, 4]);
});

test('AC-25 压制在目标完成下一次攻击前不可叠加或刷新', () => {
  let result: BattleResult | null = null;
  for (let index = 0; index < 256; index += 1) {
    const candidate = resolveBattle({
      ...baseInput(`ac-25-${index}`), maxBattleRounds: 2,
      attackerUnits: [
        makeUnit('heavy-a', 'red', 15, { hp: 1_000_000, maxHp: 1_000_000, attack: 1, speed: 100 }),
        makeUnit('heavy-b', 'red', 15, { hp: 1_000_000, maxHp: 1_000_000, attack: 1, speed: 99 }),
      ],
      defenderUnits: [makeUnit('suppressed', 'blue', 14, { hp: 1_000_000, maxHp: 1_000_000, attack: 1, speed: 1 })],
    });
    const roundOneHits = candidate.eventLog.filter((event) => (
      (event.type === 'damage' || event.type === 'special')
      && event.battleRound === 1
      && (event.actorPieceId === 'heavy-a' || event.actorPieceId === 'heavy-b')
    )).length;
    if (roundOneHits === 2) {
      result = candidate;
      break;
    }
  }
  assert.ok(result);
  const suppressionsBeforeConsumption = result.eventLog.filter((event) => event.type === 'suppression' && event.targetPieceId === 'suppressed');
  assert.equal(suppressionsBeforeConsumption.length, 1);
  assert.equal(suppressionsBeforeConsumption[0]?.battleRound, 1);
  assert.ok(result.eventLog.some((event) => event.type === 'attack' && event.actorPieceId === 'suppressed' && event.battleRound === 2));
});

test('AC-26 只改变 auditOnlyStats 不会改变同种子战果', () => {
  const definition = getCardDefinition(14);
  const audit = definition.auditOnlyStats;
  const backup = structuredClone(audit);
  const makeResult = (): BattleResult => {
    const stats = getRuntimeStats(14, { level: 20, purchasedPromotions: [] });
    return resolveBattle({
      ...baseInput('ac-26'),
      attackerUnits: [makeUnit('assault', 'red', 14, { ...stats, hp: stats.maxHp, maxHp: stats.maxHp })],
      defenderUnits: [makeUnit('heavy', 'blue', 15)],
    });
  };
  const before = makeResult();
  try {
    audit.dodgeRate = { min: -9999, max: 9999 };
    audit.toughness = 9999;
    audit.magicResistance = { arbitrary: 9999 };
    audit.equipmentDefense = 9999;
    audit.weight = 9999;
    const after = makeResult();
    assert.deepEqual(after, before);
  } finally {
    audit.dodgeRate = backup.dodgeRate;
    audit.toughness = backup.toughness;
    audit.magicResistance = backup.magicResistance;
    audit.equipmentDefense = backup.equipmentDefense;
    audit.weight = backup.weight;
  }
});

test('AC-33 双方狙击先制互灭时节点保持原所有者且为空，不产生失败重入锁', () => {
  let finalState = null as ReturnType<typeof makeState> | null;
  for (let index = 0; index < 256; index += 1) {
    const state = makeState(`ac-33-${index}`);
    clearAllPieces(state);
    const red = createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'mutual-red' });
    const blue = createPieceInPlace(state, 'blue', 12, 'North-Choke', 1, { pieceId: 'mutual-blue' });
    red.hp = red.maxHp = 1;
    blue.hp = blue.maxHp = 1;
    setAction(state, 'red', 2);
    const result = applyCommand(state, moveCommand(state, [red.pieceId], 'R-Supply', 'North-Choke'));
    if (result.ok && result.state.battles[0]?.result.reason === 'mutual_wipe') {
      finalState = result.state;
      break;
    }
  }
  assert.ok(finalState);
  assert.equal(finalState.map.nodes['North-Choke'].ownerFactionId, null);
  assert.equal(finalState.map.nodes['North-Choke'].pieceIds.length, 0);
  assert.equal(Object.values(finalState.pieces).filter((piece) => piece.failedAssaultLocks.length > 0).length, 0);
});

test('AC-36 立即结算与完整观看投影使用同一解析结果', () => {
  const result = resolveBattle({
    ...baseInput('ac-36'),
    attackerUnits: [makeUnit('a', 'red', 14)],
    defenderUnits: [makeUnit('d', 'blue', 13)],
  });
  const watched = completePlayback(result);
  const skipped = skipPlayback(result);
  assert.equal(watched.winner, skipped.winner);
  assert.equal(watched.reason, skipped.reason);
  assert.deepEqual(watched.pieceResults, skipped.pieceResults);
  assert.equal(watched.finalRngState, skipped.finalRngState);
  assert.equal(watched.mode, 'watched');
  assert.equal(skipped.mode, 'skipped');
});
