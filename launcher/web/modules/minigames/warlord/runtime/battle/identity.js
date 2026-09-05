import { canonicalJson } from '../core/canonical.js';
function canonicalPieceIds(pieceIds) {
    return [...pieceIds].sort((left, right) => left.localeCompare(right));
}
export function createBattleIdentity(input) {
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
//# sourceMappingURL=identity.js.map