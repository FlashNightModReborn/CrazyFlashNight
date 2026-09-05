import assert from 'node:assert/strict';
import test from 'node:test';
import { requireNode } from '../src/core/access.js';
import { generateAiPlanningCommands, generateNextAiAction, runAiActionPhase } from '../src/ai/heuristic.js';
import { applyCommand } from '../src/core/engine.js';
import { bounty, getRuntimeStats, needXp } from '../src/core/math.js';
import { runSettlementAutoInPlace } from '../src/core/lifecycle.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import { piecesAtNode } from '../src/core/selectors.js';
import { createGame } from '../src/core/state.js';
import type { GameState } from '../src/core/types.js';
import { validateCommand } from '../src/core/validator.js';
import { PROMOTIONS } from '../src/data/config.js';
import { exportReplay, importAndReplay } from '../src/replay/replay.js';
import { applyOk, clearAllPieces, faction, makeState, moveCommand, setAction, setPlanning } from './helpers.js';

function stateWithOneCasualty(seed: string): GameState {
  for (let index = 0; index < 128; index += 1) {
    const state = makeState(`${seed}-${index}`);
    clearAllPieces(state);
    faction(state, 'red').cards[15].level = 50;
    createPieceInPlace(state, 'red', 15, 'R-Supply', 1, { pieceId: 'xp-killer' });
    const victim = createPieceInPlace(state, 'blue', 14, 'North-Choke', 1, { pieceId: 'xp-victim' });
    victim.hp = 1;
    setAction(state, 'red', 4);
    const result = applyCommand(state, moveCommand(state, ['xp-killer'], 'R-Supply', 'North-Choke'));
    if (result.ok && result.state.casualtyLedger.length === 1) return result.state;
  }
  throw new Error('Could not find deterministic casualty seed.');
}

test('AC-27 每个伤亡只结算一次击杀方 1 倍、损失方 3 倍经验', () => {
  const state = stateWithOneCasualty('ac-27');
  const entry = state.casualtyLedger[0];
  assert.ok(entry);
  const expected = bounty(entry.cardId, entry.frozenCardLevel);
  assert.equal(entry.killerXp, expected);
  assert.equal(entry.loserXp, expected * 3);
  assert.equal(faction(state, 'red').xpPool, 0);
  assert.equal(faction(state, 'blue').xpPool, 0);

  runSettlementAutoInPlace(state);
  assert.equal(faction(state, 'red').xpPool, expected);
  assert.equal(faction(state, 'blue').xpPool, expected * 3);
  const afterFirst = { red: faction(state, 'red').xpPool, blue: faction(state, 'blue').xpPool };
  runSettlementAutoInPlace(state);
  assert.deepEqual({ red: faction(state, 'red').xpPool, blue: faction(state, 'blue').xpPool }, afterFirst);
});

test('AC-28 经验溢出保留；升级同步现存棋子并保持生命比例', () => {
  let state = makeState('ac-28');
  const piece = piecesAtNode(state, 'R-HQ', 'red').find((candidate) => candidate.cardId === 14);
  assert.ok(piece);
  const oldMax = piece.maxHp;
  piece.hp = Math.round(oldMax * 0.5);
  const oldHp = piece.hp;
  const amount = needXp(14, 1) + needXp(14, 2) + 10;
  setPlanning(state);
  faction(state, 'red').xpPool = amount;
  state = applyOk(state, { type: 'ALLOCATE_XP', factionId: 'red', cardId: 14, amount });
  assert.equal(faction(state, 'red').cards[14].level, 3);
  assert.equal(faction(state, 'red').cards[14].xpIntoLevel, 10);
  const beforeSync = state.pieces[piece.pieceId];
  assert.equal(beforeSync?.maxHp, oldMax);
  state = applyOk(state, { type: 'COMMIT_PLANNING', factionId: 'red' });
  state = applyOk(state, { type: 'COMMIT_PLANNING', factionId: 'blue' });
  const synced = state.pieces[piece.pieceId];
  assert.ok(synced);
  const newStats = getRuntimeStats(14, faction(state, 'red').cards[14]);
  assert.equal(synced.maxHp, newStats.maxHp);
  assert.equal(synced.hp, Math.round(newStats.maxHp * oldHp / oldMax));
});

test('AC-29 普通卡必须按基础训练→强化药剂→超级血清顺序购买', () => {
  let state = makeState('ac-29');
  setPlanning(state);
  faction(state, 'red').cards[14].level = 50;
  faction(state, 'red').gold = 1000;
  const skipBase = validateCommand(state, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 14, promotionId: '强化药剂' });
  assert.ok(!skipBase.ok);
  assert.match(skipBase.error ?? '', /必须按序购买 基础训练/);
  state = applyOk(state, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 14, promotionId: '基础训练' });
  assert.deepEqual(faction(state, 'red').cards[14].purchasedPromotions, ['基础训练']);
  faction(state, 'red').cards[14].promotedThisSettlement = false;
  const skipStrong = validateCommand(state, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 14, promotionId: '超级血清' });
  assert.ok(!skipStrong.ok);
  assert.match(skipStrong.error ?? '', /必须按序购买 强化药剂/);
});

test('AC-30 精锐卡从源序列首项起步，不白送被省略阶段属性', () => {
  let elite = makeState('ac-30-elite');
  setPlanning(elite);
  faction(elite, 'red').cards[82].level = 50;
  faction(elite, 'red').gold = 1000;
  const beforeElite = getRuntimeStats(82, faction(elite, 'red').cards[82]);
  elite = applyOk(elite, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 82, promotionId: '强化药剂' });
  const afterElite = getRuntimeStats(82, faction(elite, 'red').cards[82]);
  assert.equal(afterElite.maxHp - beforeElite.maxHp, PROMOTIONS.强化药剂.hp);
  assert.equal(afterElite.attack - beforeElite.attack, PROMOTIONS.强化药剂.attack);
  assert.deepEqual(faction(elite, 'red').cards[82].purchasedPromotions, ['强化药剂']);

  let boss = makeState('ac-30-boss');
  setPlanning(boss);
  faction(boss, 'red').cards[85].level = 50;
  faction(boss, 'red').gold = 1000;
  const beforeBoss = getRuntimeStats(85, faction(boss, 'red').cards[85]);
  boss = applyOk(boss, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 85, promotionId: '超级血清' });
  const afterBoss = getRuntimeStats(85, faction(boss, 'red').cards[85]);
  assert.equal(afterBoss.maxHp - beforeBoss.maxHp, PROMOTIONS.超级血清.hp);
  assert.deepEqual(faction(boss, 'red').cards[85].purchasedPromotions, ['超级血清']);
});

test('AC-31 每张卡每个战略结算最多完成一次升阶', () => {
  let state = makeState('ac-31');
  setPlanning(state);
  faction(state, 'red').cards[14].level = 50;
  faction(state, 'red').gold = 1000;
  state = applyOk(state, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 14, promotionId: '基础训练' });
  const sameSettlement = validateCommand(state, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 14, promotionId: '强化药剂' });
  assert.ok(!sameSettlement.ok);
  assert.match(sameSettlement.error ?? '', /最多升阶一次/);
  faction(state, 'red').cards[14].promotedThisSettlement = false;
  const nextSettlement = validateCommand(state, { type: 'PURCHASE_PROMOTION', factionId: 'red', cardId: 14, promotionId: '强化药剂' });
  assert.ok(nextSettlement.ok);
});

test('AC-35 难度只改变 AI 聚合后向下取整的金币，不改变属性、AP、经验或决策算法', () => {
  const easy = createGame({ seed: 'ac-35', difficulty: 'easy' });
  const normal = createGame({ seed: 'ac-35', difficulty: 'normal' });
  const hard = createGame({ seed: 'ac-35', difficulty: 'hard' });
  const extreme = createGame({ seed: 'ac-35', difficulty: 'extreme' });
  assert.deepEqual([
    faction(easy, 'blue').gold,
    faction(normal, 'blue').gold,
    faction(hard, 'blue').gold,
    faction(extreme, 'blue').gold,
  ], [16, 20, 25, 30]);
  const normalBlue = piecesAtNode(normal, 'B-HQ', 'blue')[0];
  const hardBlue = piecesAtNode(hard, 'B-HQ', 'blue')[0];
  assert.ok(normalBlue && hardBlue);
  assert.deepEqual(
    { hp: normalBlue.maxHp, ap: faction(normal, 'blue').actionPoints, card: faction(normal, 'blue').cards[normalBlue.cardId] },
    { hp: hardBlue.maxHp, ap: faction(hard, 'blue').actionPoints, card: faction(hard, 'blue').cards[hardBlue.cardId] },
  );
  assert.equal(bounty(14, 1), 260);

  // 5 + 8 + 6 = 19; easy must floor once: floor(19 * .8) = 15, not per-node 4+6+4 = 14.
  for (const node of Object.values(easy.map.nodes)) {
    if (!['B-HQ', 'B-Economy', 'South-Depot'].includes(node.nodeId)) {
      if (node.ownerFactionId === 'blue') node.ownerFactionId = null;
    }
  }
  requireNode(easy, 'South-Depot').ownerFactionId = 'blue';
  requireNode(easy, 'South-Depot').activeFromRound = 1;
  const beforeIncome = faction(easy, 'blue').gold;
  runSettlementAutoInPlace(easy);
  assert.equal(faction(easy, 'blue').gold - beforeIncome, 15);

  faction(hard, 'blue').gold = faction(normal, 'blue').gold;
  normal.activeFactionId = 'blue';
  hard.activeFactionId = 'blue';
  normal.phase = 'FIRST_FACTION_ACTION';
  hard.phase = 'FIRST_FACTION_ACTION';
  const normalDecision = generateNextAiAction(normal, 'blue');
  const hardDecision = generateNextAiAction(hard, 'blue');
  assert.ok(normalDecision);
  assert.deepEqual(hardDecision, normalDecision);
});

test('AI-VALIDATOR AI 行动与规划命令均由玩家同款 validator 接受', () => {
  const initial = makeState('ai-validator');
  const activeFactionId = initial.activeFactionId;
  assert.ok(activeFactionId);
  const run = runAiActionPhase(initial, activeFactionId);
  assert.equal(run.invalidGenerated, 0);
  assert.ok(run.commands.length > 0);

  let shadow = initial;
  for (const command of run.commands) {
    const validation = validateCommand(shadow, command);
    assert.ok(validation.ok, `${command.type}: ${validation.error ?? 'unknown validator rejection'}`);
    shadow = applyOk(shadow, command);
  }
  assert.deepEqual(shadow, run.state);

  const planning = makeState('ai-validator-planning');
  setPlanning(planning);
  faction(planning, 'red').gold = 200;
  faction(planning, 'red').xpPool = 10_000;
  const planningCommands = generateAiPlanningCommands(planning, 'red');
  assert.ok(planningCommands.some((command) => command.type === 'COMMIT_PLANNING'));
  let planningShadow = planning;
  for (const command of planningCommands) {
    const validation = validateCommand(planningShadow, command);
    assert.ok(validation.ok, `${command.type}: ${validation.error ?? 'unknown validator rejection'}`);
    planningShadow = applyOk(planningShadow, command);
  }
});

test('AI-TIER-UPGRADE 核心职能齐全后为已解锁 T2 留预算，并在可支付时生产重装', () => {
  const saving = makeState('ai-tier-saving');
  setPlanning(saving);
  faction(saving, 'red').cards[15].level = 10;
  faction(saving, 'red').cards[15].purchasedPromotions = ['基础训练'];
  faction(saving, 'red').gold = 59;
  const savingCommands = generateAiPlanningCommands(saving, 'red');
  assert.equal(savingCommands.filter((command) => command.type === 'ENQUEUE_PRODUCTION').length, 0);

  const buying = makeState('ai-tier-buying');
  setPlanning(buying);
  faction(buying, 'red').cards[15].level = 10;
  faction(buying, 'red').cards[15].purchasedPromotions = ['基础训练'];
  faction(buying, 'red').gold = 60;
  const buyingCommands = generateAiPlanningCommands(buying, 'red');
  const firstOrder = buyingCommands.find((command) => command.type === 'ENQUEUE_PRODUCTION');
  assert.ok(firstOrder && firstOrder.type === 'ENQUEUE_PRODUCTION');
  assert.equal(firstOrder.cardId, 15);
});

test('AC-37 导出录像后重新导入可逐字段重现同一状态', () => {
  let state = createGame({ seed: 'ac-37', preset: 'all-units', difficulty: 'hard' });
  const attackers = piecesAtNode(state, 'R-Supply', 'red').slice(0, 2).map((piece) => piece.pieceId);
  state = applyOk(state, moveCommand(state, attackers, 'R-Supply', 'North-Choke'));
  state = applyOk(state, { type: 'END_ACTION', factionId: 'red' });
  const json = exportReplay(state);
  const replayed = importAndReplay(json);
  assert.deepEqual(replayed, state);
});
