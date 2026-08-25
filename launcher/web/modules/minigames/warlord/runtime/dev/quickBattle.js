import { resolveBattle } from '../battle/resolver.js';
import { getCardDefinition } from '../data/cards.js';
import { adjacentNodeIds } from '../data/map.js';
import { getRuntimeStats } from '../core/math.js';
import { piecesAtNode } from '../core/selectors.js';
function snapshot(state, pieceId) {
    const piece = state.pieces[pieceId];
    if (!piece)
        throw new Error(`Missing piece ${pieceId}`);
    const card = state.factions[piece.factionId].cards[piece.cardId];
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
        for (const adjacent of adjacentNodeIds(selectedNodeId)) {
            const defenders = piecesAtNode(state, adjacent);
            if (defenders[0] && defenders[0].factionId !== selected[0].factionId) {
                return {
                    attackerNode: selectedNodeId,
                    defenderNode: adjacent,
                    attackerFaction: selected[0].factionId,
                    defenderFaction: defenders[0].factionId,
                };
            }
        }
    }
    const redNode = Object.keys(state.map.nodes).find((nodeId) => piecesAtNode(state, nodeId, 'red').length > 0);
    const blueNode = Object.keys(state.map.nodes).find((nodeId) => piecesAtNode(state, nodeId, 'blue').length > 0);
    if (!redNode || !blueNode)
        return null;
    return { attackerNode: redNode, defenderNode: blueNode, attackerFaction: 'red', defenderFaction: 'blue' };
}
export function runQuickBattle(state, selectedNodeId, runs = 100) {
    const matchup = findMatchup(state, selectedNodeId);
    if (!matchup)
        throw new Error('当前棋盘缺少可用于快测的双方编队。');
    const attackerUnits = piecesAtNode(state, matchup.attackerNode, matchup.attackerFaction)
        .slice(0, state.map.nodes[matchup.defenderNode].attackWidth)
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
            nodeDefenseBonus: state.map.nodes[matchup.defenderNode].defenseBonus,
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
        source: `${state.map.nodes[matchup.attackerNode].displayName} → ${state.map.nodes[matchup.defenderNode].displayName}`,
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