import {
  DAMAGE_RANDOM_MAX,
  DAMAGE_RANDOM_MIN,
  DAMAGE_SCALE,
  HIT_MAX,
  HIT_MIN,
  MAX_BATTLE_ROUNDS,
} from '../data/config.js';
import { clamp } from '../core/math.js';
import { DeterministicRng, deterministicTie } from '../core/rng.js';
import type { BehaviorId, FactionId } from '../core/types.js';
import type {
  BattleCasualty,
  BattleEvent,
  BattlePieceResult,
  BattleResult,
  BattleSide,
  BattleUnitSnapshot,
  ResolveBattleInput,
} from './types.js';

interface Combatant extends BattleUnitSnapshot {
  side: BattleSide;
  nextAttackRound: number;
  suppressionPending: boolean;
  damageDealt: number;
  attacksMade: number;
  suppressionsApplied: number;
  dead: boolean;
  killerFactionId?: FactionId;
}

interface PendingVolleyDamage {
  shooter: Combatant;
  target: Combatant;
  damage: number;
  hitChance: number;
  roll: number;
  tagMultiplier: number;
}

function initialNextAttackRound(behaviorId: BehaviorId): number {
  switch (behaviorId) {
    case 'ammo': return 2;
    case 'sniper': return 1;
    case 'assault':
    case 'heavy':
      return 1;
  }
}

function nextInterval(behaviorId: BehaviorId): number {
  switch (behaviorId) {
    case 'sniper':
    case 'ammo':
      return 2;
    case 'assault':
    case 'heavy':
      return 1;
  }
}

function createCombatant(unit: BattleUnitSnapshot, side: BattleSide): Combatant {
  return {
    ...unit,
    tags: [...unit.tags],
    side,
    nextAttackRound: initialNextAttackRound(unit.behaviorId),
    suppressionPending: false,
    damageDealt: 0,
    attacksMade: 0,
    suppressionsApplied: 0,
    dead: unit.hp <= 0,
  };
}

function alive(units: Combatant[]): Combatant[] {
  return units.filter((unit) => !unit.dead && unit.hp > 0);
}

function hpRatio(unit: Combatant): number {
  return unit.maxHp > 0 ? unit.hp / unit.maxHp : 0;
}

function displayOrder(units: Combatant[]): Combatant[] {
  return [...units].sort((a, b) => (
    a.formationRank - b.formationRank
    || hpRatio(b) - hpRatio(a)
    || a.pieceId.localeCompare(b.pieceId)
  ));
}

function normalTargets(enemies: Combatant[], count: number): Combatant[] {
  const candidates = alive(enemies);
  const picked: Combatant[] = [];
  while (picked.length < count && candidates.length > 0) {
    candidates.sort((a, b) => (
      a.formationRank - b.formationRank
      || hpRatio(a) - hpRatio(b)
      || a.pieceId.localeCompare(b.pieceId)
    ));
    const next = candidates.shift();
    if (!next) break;
    picked.push(next);
  }
  return picked;
}

function sniperTargets(enemies: Combatant[], count: number): Combatant[] {
  const candidates = alive(enemies);
  if (candidates.length === 0 || count <= 0) return [];
  const primary = [...candidates].sort((a, b) => {
    const group = (unit: Combatant): number => {
      if (unit.tags.includes('boss')) return 0;
      if (unit.tags.includes('elite')) return 1;
      return 2;
    };
    return group(a) - group(b) || hpRatio(a) - hpRatio(b) || a.pieceId.localeCompare(b.pieceId);
  })[0];
  if (!primary || count === 1) return primary ? [primary] : [];

  const formation = displayOrder(candidates);
  const index = formation.findIndex((unit) => unit.pieceId === primary.pieceId);
  const adjacent = index > 0 ? formation[index - 1] : formation[index + 1];
  return adjacent && adjacent.pieceId !== primary.pieceId ? [primary, adjacent] : [primary];
}

function targetCount(behaviorId: BehaviorId): number {
  return behaviorId === 'sniper' || behaviorId === 'ammo' ? 2 : 1;
}

function selectTargets(actor: Combatant, enemies: Combatant[]): Combatant[] {
  if (actor.behaviorId === 'sniper') return sniperTargets(enemies, targetCount(actor.behaviorId));
  return normalTargets(enemies, targetCount(actor.behaviorId));
}

function tagMultiplier(actor: Combatant, target: Combatant): number {
  if (actor.behaviorId === 'assault' && target.tags.includes('human')) return 1.5;
  if (actor.behaviorId === 'sniper' && target.tags.includes('elite')) return 1.5;
  return 1;
}

function rollDamage(
  actor: Combatant,
  target: Combatant,
  rng: DeterministicRng,
  nodeDefenseBonus: number,
): { hit: boolean; hitChance: number; roll: number; damage: number; multiplier: number } {
  const hitChance = clamp(0.9 + (actor.speed - target.speed) / 200, HIT_MIN, HIT_MAX);
  const roll = rng.next();
  const multiplier = tagMultiplier(actor, target);
  if (roll > hitChance) return { hit: false, hitChance, roll, damage: 0, multiplier };
  const defenseBonus = target.side === 'defender' ? nodeDefenseBonus : 0;
  const effectiveDefense = target.defense * (1 + defenseBonus);
  const damage = Math.max(1, Math.floor(
    actor.attack
      * DAMAGE_SCALE
      * (300 / (300 + effectiveDefense))
      * multiplier
      * rng.range(DAMAGE_RANDOM_MIN, DAMAGE_RANDOM_MAX),
  ));
  return { hit: true, hitChance, roll, damage, multiplier };
}

function allDead(units: Combatant[]): boolean {
  return alive(units).length === 0;
}

function immutableEvents(events: BattleEvent[]): readonly BattleEvent[] {
  return Object.freeze(events.map((event) => Object.freeze({ ...event })));
}

export function resolveBattle(input: ResolveBattleInput): BattleResult {
  const rng = new DeterministicRng(input.seed);
  const attackers = input.attackerUnits.map((unit) => createCombatant(unit, 'attacker'));
  const defenders = input.defenderUnits.map((unit) => createCombatant(unit, 'defender'));
  const allUnits = [...attackers, ...defenders];
  const maxRounds = input.maxBattleRounds ?? MAX_BATTLE_ROUNDS;
  const events: BattleEvent[] = [];
  let eventOrdinal = 0;
  let completedRound = 0;

  const push = (event: Omit<BattleEvent, 'eventId' | 'battleId'>): void => {
    eventOrdinal += 1;
    events.push({ ...event, eventId: `${input.battleId}:e${eventOrdinal}`, battleId: input.battleId });
  };

  const sideUnits = (side: BattleSide): Combatant[] => side === 'attacker' ? attackers : defenders;
  const enemyUnits = (side: BattleSide): Combatant[] => side === 'attacker' ? defenders : attackers;

  const finish = (winner: BattleSide, reason: BattleResult['reason'], battleRounds: number): BattleResult => {
    push({
      battleRound: battleRounds,
      phase: 'system',
      type: 'battle_end',
      message: reason === 'battle_round_limit'
        ? `达到 ${battleRounds} 个战斗回合上限，守方守住。`
        : reason === 'mutual_wipe'
          ? '双方在狙击先制批次中互相全灭，节点保持原所有者。'
          : `${winner === 'attacker' ? '进攻方' : '守方'}歼灭对手。`,
    });

    const casualties: BattleCasualty[] = allUnits
      .filter((unit) => unit.dead)
      .map((unit) => ({
        pieceId: unit.pieceId,
        factionId: unit.factionId,
        killerFactionId: unit.killerFactionId ?? (unit.side === 'attacker' ? defenders[0]?.factionId : attackers[0]?.factionId) ?? unit.factionId,
        cardId: unit.cardId,
        frozenCardLevel: unit.frozenCardLevel,
      }))
      .sort((a, b) => a.pieceId.localeCompare(b.pieceId));

    const pieceResults: BattlePieceResult[] = allUnits
      .map((unit) => ({
        pieceId: unit.pieceId,
        factionId: unit.factionId,
        cardId: unit.cardId,
        hpAfter: Math.max(0, unit.hp),
        dead: unit.dead,
        damageDealt: unit.damageDealt,
        attacksMade: unit.attacksMade,
        suppressionsApplied: unit.suppressionsApplied,
        frozenCardLevel: unit.frozenCardLevel,
      }))
      .sort((a, b) => a.pieceId.localeCompare(b.pieceId));

    return {
      winner,
      reason,
      battleRounds,
      pieceResults,
      casualties,
      eventLog: immutableEvents(events),
      finalRngState: rng.getState(),
    };
  };

  for (let battleRound = 1; battleRound <= maxRounds; battleRound += 1) {
    completedRound = battleRound;
    push({ battleRound, phase: 'system', type: 'round_start', message: `战斗回合 ${battleRound} 开始。` });

    if (battleRound === 1) {
      const volleyShooters = allUnits
        .filter((unit) => !unit.dead && unit.behaviorId === 'sniper')
        .sort((a, b) => a.pieceId.localeCompare(b.pieceId));
      if (volleyShooters.length > 0) {
        push({ battleRound, phase: 'opening_volley', type: 'sniper_volley', message: '双方狙击兵同时执行入场先制齐射。' });
      }
      const pending: PendingVolleyDamage[] = [];
      for (const shooter of volleyShooters) {
        const targets = sniperTargets(enemyUnits(shooter.side), 2);
        shooter.attacksMade += 1;
        for (const target of targets) {
          const roll = rollDamage(shooter, target, rng, input.nodeDefenseBonus);
          push({
            battleRound,
            phase: 'opening_volley',
            type: 'attack',
            actorPieceId: shooter.pieceId,
            actorFactionId: shooter.factionId,
            targetPieceId: target.pieceId,
            targetFactionId: target.factionId,
            hitChance: roll.hitChance,
            roll: roll.roll,
            tagMultiplier: roll.multiplier,
            message: `${shooter.displayName}先制瞄准 ${target.displayName}。`,
          });
          if (!roll.hit) {
            push({
              battleRound,
              phase: 'opening_volley',
              type: 'miss',
              actorPieceId: shooter.pieceId,
              actorFactionId: shooter.factionId,
              targetPieceId: target.pieceId,
              targetFactionId: target.factionId,
              hitChance: roll.hitChance,
              roll: roll.roll,
              message: `${shooter.displayName}先制射击未命中。`,
            });
          } else {
            pending.push({ shooter, target, damage: roll.damage, hitChance: roll.hitChance, roll: roll.roll, tagMultiplier: roll.multiplier });
            push({
              battleRound,
              phase: 'opening_volley',
              type: roll.multiplier > 1 ? 'special' : 'damage',
              actorPieceId: shooter.pieceId,
              actorFactionId: shooter.factionId,
              targetPieceId: target.pieceId,
              targetFactionId: target.factionId,
              damage: roll.damage,
              tagMultiplier: roll.multiplier,
              message: `${shooter.displayName}造成 ${roll.damage} 伤害${roll.multiplier > 1 ? '（精英特攻）' : ''}。`,
            });
          }
        }
        shooter.nextAttackRound = 3;
      }

      const damageByTarget = new Map<string, { target: Combatant; total: number; killerFactionId: FactionId }>();
      for (const item of pending) {
        item.shooter.damageDealt += item.damage;
        const current = damageByTarget.get(item.target.pieceId);
        damageByTarget.set(item.target.pieceId, {
          target: item.target,
          total: (current?.total ?? 0) + item.damage,
          killerFactionId: item.shooter.factionId,
        });
      }
      for (const { target, total, killerFactionId } of [...damageByTarget.values()].sort((a, b) => a.target.pieceId.localeCompare(b.target.pieceId))) {
        target.hp = Math.max(0, target.hp - total);
        if (target.hp <= 0) {
          target.dead = true;
          target.killerFactionId = killerFactionId;
          push({
            battleRound,
            phase: 'opening_volley',
            type: 'death',
            targetPieceId: target.pieceId,
            targetFactionId: target.factionId,
            hpAfter: 0,
            message: `${target.displayName}在先制齐射中阵亡。`,
          });
        }
      }

      if (allDead(attackers) && allDead(defenders)) return finish('defender', 'mutual_wipe', battleRound);
      if (allDead(defenders)) return finish('attacker', 'wiped', battleRound);
      if (allDead(attackers)) return finish('defender', 'wiped', battleRound);

      for (const unit of allUnits.filter((candidate) => !candidate.dead && candidate.behaviorId === 'ammo')) {
        push({
          battleRound,
          phase: 'normal',
          type: 'reload',
          actorPieceId: unit.pieceId,
          actorFactionId: unit.factionId,
          message: `${unit.displayName}完成第 1 战斗回合装填，不攻击。`,
        });
      }
    }

    const actionOrder = alive(allUnits).sort((a, b) => (
      b.speed - a.speed
      || deterministicTie(input.seed, battleRound, a.pieceId) - deterministicTie(input.seed, battleRound, b.pieceId)
      || a.pieceId.localeCompare(b.pieceId)
    ));

    for (const actor of actionOrder) {
      if (actor.dead || actor.hp <= 0) continue;
      if (actor.nextAttackRound > battleRound) continue;
      if (battleRound === 1 && actor.behaviorId === 'sniper') continue;

      const targets = selectTargets(actor, enemyUnits(actor.side));
      if (targets.length === 0) break;
      const consumedSuppression = actor.suppressionPending;
      actor.attacksMade += 1;

      for (const target of targets) {
        if (target.dead) continue;
        const roll = rollDamage(actor, target, rng, input.nodeDefenseBonus);
        push({
          battleRound,
          phase: 'normal',
          type: 'attack',
          actorPieceId: actor.pieceId,
          actorFactionId: actor.factionId,
          targetPieceId: target.pieceId,
          targetFactionId: target.factionId,
          hitChance: roll.hitChance,
          roll: roll.roll,
          tagMultiplier: roll.multiplier,
          message: `${actor.displayName}攻击 ${target.displayName}。`,
        });
        if (!roll.hit) {
          push({
            battleRound,
            phase: 'normal',
            type: 'miss',
            actorPieceId: actor.pieceId,
            actorFactionId: actor.factionId,
            targetPieceId: target.pieceId,
            targetFactionId: target.factionId,
            hitChance: roll.hitChance,
            roll: roll.roll,
            message: `${actor.displayName}未命中 ${target.displayName}。`,
          });
          continue;
        }

        const applied = Math.min(target.hp, roll.damage);
        target.hp = Math.max(0, target.hp - roll.damage);
        actor.damageDealt += applied;
        push({
          battleRound,
          phase: 'normal',
          type: roll.multiplier > 1 ? 'special' : 'damage',
          actorPieceId: actor.pieceId,
          actorFactionId: actor.factionId,
          targetPieceId: target.pieceId,
          targetFactionId: target.factionId,
          damage: roll.damage,
          hpAfter: target.hp,
          tagMultiplier: roll.multiplier,
          message: `${actor.displayName}造成 ${roll.damage} 伤害${roll.multiplier > 1 ? `（特攻 ×${roll.multiplier.toFixed(1)}）` : ''}。`,
        });

        if (target.hp <= 0) {
          target.dead = true;
          target.killerFactionId = actor.factionId;
          push({
            battleRound,
            phase: 'normal',
            type: 'death',
            actorPieceId: actor.pieceId,
            actorFactionId: actor.factionId,
            targetPieceId: target.pieceId,
            targetFactionId: target.factionId,
            hpAfter: 0,
            message: `${target.displayName}阵亡。`,
          });
        } else if ((actor.behaviorId === 'ammo' || actor.behaviorId === 'heavy') && !target.suppressionPending) {
          target.nextAttackRound += 1;
          target.suppressionPending = true;
          actor.suppressionsApplied += 1;
          push({
            battleRound,
            phase: 'normal',
            type: 'suppression',
            actorPieceId: actor.pieceId,
            actorFactionId: actor.factionId,
            targetPieceId: target.pieceId,
            targetFactionId: target.factionId,
            message: `${target.displayName}受到压制，下一次攻击推迟 1 个战斗回合。`,
          });
        }
      }

      actor.nextAttackRound = battleRound + nextInterval(actor.behaviorId);
      if (consumedSuppression) actor.suppressionPending = false;

      if (allDead(defenders)) return finish('attacker', 'wiped', battleRound);
      if (allDead(attackers)) return finish('defender', 'wiped', battleRound);
    }

    push({ battleRound, phase: 'system', type: 'round_end', message: `战斗回合 ${battleRound} 结束。` });
  }

  return finish('defender', 'battle_round_limit', completedRound);
}
