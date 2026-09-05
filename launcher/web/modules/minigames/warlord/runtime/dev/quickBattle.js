import { resolveBattle } from '../battle/resolver.js';
import { getCardDefinition } from '../data/cards.js';
import { requireNode } from '../core/access.js';
import { areHostile, requireFaction } from '../core/factions.js';
import { getRuntimeStats } from '../core/math.js';
import { adjacentNodeIds, piecesAtNode } from '../core/selectors.js';
function snapshot(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        throw new Error(`Missing piece ${pieceId}`);
    const card = requireFaction(state, piece.factionId).cards[piece.cardId];
    if (!card)
        throw new Error(`Missing card state ${piece.factionId}/${piece.cardId}`);
    const definition = getCardDefinition(piece.cardId);
    const stats = getRuntimeStats(piece.cardId, card);
    return {
        pieceId,
        factionId: piece.factionId,
        cardId: piece.cardId,
        displayName: definition.displayName,
        behaviorId: definition.behaviorId,
        tags: [...definition.tags],
        formationRank: definition.formationRank,
        hp: piece.hp,
        maxHp: piece.maxHp,
        attack: stats.attack,
        defense: stats.defense,
        speed: stats.speed,
        frozenCardLevel: card.level,
    };
}
function findMatchup(state, selectedNodeId) {
    const selected = piecesAtNode(state, selectedNodeId);
    if (selected[0]) {
        for (const adjacent of adjacentNodeIds(state, selectedNodeId)) {
            const defenders = piecesAtNode(state, adjacent);
            const defender = defenders.find((piece) => areHostile(state, selected[0].factionId, piece.factionId));
            if (defender) {
                return {
                    attackerNode: selectedNodeId,
                    defenderNode: adjacent,
                    attackerFaction: selected[0].factionId,
                    defenderFaction: defender.factionId,
                };
            }
        }
    }
    const factionOrder = [
        state.playerFactionId,
        ...state.turnOrder.filter((factionId) => factionId !== state.playerFactionId),
    ];
    const nodeIds = Object.keys(state.map.nodes).sort();
    for (const attackerFaction of factionOrder) {
        for (const attackerNode of nodeIds) {
            if (piecesAtNode(state, attackerNode, attackerFaction).length === 0)
                continue;
            for (const defenderNode of adjacentNodeIds(state, attackerNode)) {
                const defender = piecesAtNode(state, defenderNode)
                    .find((piece) => areHostile(state, attackerFaction, piece.factionId));
                if (defender) {
                    return {
                        attackerNode,
                        defenderNode,
                        attackerFaction,
                        defenderFaction: defender.factionId,
                    };
                }
            }
        }
    }
    return null;
}
export function runQuickBattle(state, selectedNodeId, runs = 100) {
    const matchup = findMatchup(state, selectedNodeId);
    if (!matchup)
        throw new Error('当前棋盘缺少可用于快测的双方编队。');
    const attackerUnits = piecesAtNode(state, matchup.attackerNode, matchup.attackerFaction)
        .slice(0, requireNode(state, matchup.defenderNode).attackWidth)
        .map((piece) => snapshot(state, piece.pieceId));
    const defenderUnits = piecesAtNode(state, matchup.defenderNode, matchup.defenderFaction)
        .map((piece) => snapshot(state, piece.pieceId));
    if (attackerUnits.length === 0 || defenderUnits.length === 0)
        throw new Error('快测编队为空。');
    let attackerWins = 0;
    let defenderWins = 0;
    let battleRounds = 0;
    let attackerHp = 0;
    let defenderHp = 0;
    for (let i = 0; i < runs; i += 1) {
        const result = resolveBattle({
            battleId: `quick-${i}`,
            seed: `${state.gameSeed}|quick|${selectedNodeId}|${i}`,
            strategicRound: state.strategicRound,
            commandSequence: state.commandSequence,
            nodeId: matchup.defenderNode,
            nodeDefenseBonus: requireNode(state, matchup.defenderNode).defenseBonus,
            attackerOriginNodeId: matchup.attackerNode,
            attackerUnits,
            defenderUnits,
        });
        if (result.winner === 'attacker')
            attackerWins += 1;
        else
            defenderWins += 1;
        battleRounds += result.battleRounds;
        attackerHp += result.pieceResults.filter((piece) => piece.factionId === matchup.attackerFaction).reduce((sum, piece) => sum + piece.hpAfter, 0);
        defenderHp += result.pieceResults.filter((piece) => piece.factionId === matchup.defenderFaction).reduce((sum, piece) => sum + piece.hpAfter, 0);
    }
    return {
        source: `${requireNode(state, matchup.attackerNode).displayName} → ${requireNode(state, matchup.defenderNode).displayName}`,
        runs,
        attackerWins,
        defenderWins,
        attackerWinRate: attackerWins / runs,
        averageBattleRounds: battleRounds / runs,
        averageAttackerRemainingHp: attackerHp / runs,
        averageDefenderRemainingHp: defenderHp / runs,
    };
}
//# sourceMappingURL=quickBattle.js.map