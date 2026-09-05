import { canonicalJson } from '../core/canonical.js';

export interface BattleIdentityInput {
  gameSeed: string;
  strategicRound: number;
  battleOrdinal: number;
  attackerIds: readonly string[];
  defenderIds: readonly string[];
}

export interface BattleIdentity {
  battleId: string;
  seed: string;
}

function canonicalPieceIds(pieceIds: readonly string[]): string[] {
  return [...pieceIds].sort((left, right) => left.localeCompare(right));
}

export function createBattleIdentity(input: BattleIdentityInput): BattleIdentity {
  const attackerIds = canonicalPieceIds(input.attackerIds);
  const defenderIds = canonicalPieceIds(input.defenderIds);
  return {
    battleId: `b-r${input.strategicRound}-o${input.battleOrdinal}`,
    seed: [
      input.gameSeed,
      input.strategicRound,
      input.battleOrdinal,
      canonicalJson(attackerIds),
      canonicalJson(defenderIds),
    ].join('|'),
  };
}
