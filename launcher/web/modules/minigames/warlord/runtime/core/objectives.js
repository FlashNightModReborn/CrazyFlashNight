import { addGameEvent } from './events.js';
import { activeFactionIds, defeatFactionInPlace, requireFaction } from './factions.js';
function commanderSnapshot(state) {
    return Object.fromEntries(Object.values(state.commanders)
        .sort((left, right) => left.commanderId.localeCompare(right.commanderId))
        .map((commander) => [commander.commanderId, commander.status]));
}
function activeVictoryGroupIds(state) {
    const alive = new Set(activeFactionIds(state));
    return Object.values(state.victoryGroups)
        .filter((group) => group.factionIds.some((factionId) => alive.has(factionId)))
        .map((group) => group.victoryGroupId)
        .sort();
}
function representativeFaction(state, victoryGroupId) {
    const group = state.victoryGroups[victoryGroupId];
    if (!group)
        return 'draw';
    return group.factionIds.find((factionId) => requireFaction(state, factionId).defeatedAtRound === null)
        ?? group.factionIds[0]
        ?? 'draw';
}
export function applyGameResultInPlace(state, result) {
    if (state.result)
        return;
    state.result = result;
    state.phase = 'GAME_OVER';
    state.activeFactionId = null;
    addGameEvent(state, {
        type: 'game_over',
        factionId: result.winner === 'draw' ? undefined : result.winner,
        message: result.winner === 'draw'
            ? `战略回合 ${result.decidedAtRound} 结束，未形成胜利方。`
            : `${state.victoryGroups[result.winningVictoryGroupId ?? '']?.displayName ?? requireFaction(state, result.winner).displayName}达成战略胜利。`,
        data: { reasonCode: result.reasonCode, winningVictoryGroupId: result.winningVictoryGroupId },
    });
}
export function evaluateVictoryGroupsInPlace(state, reasonCode = 'AllHostileVictoryGroupsEliminated', reason = 'elimination') {
    const activeGroups = activeVictoryGroupIds(state);
    if (activeGroups.length > 1)
        return false;
    const winningVictoryGroupId = activeGroups[0] ?? null;
    applyGameResultInPlace(state, {
        winner: winningVictoryGroupId ? representativeFaction(state, winningVictoryGroupId) : 'draw',
        winningVictoryGroupId,
        reason,
        reasonCode,
        decidedAtRound: state.strategicRound,
        survivingFactionIds: activeFactionIds(state),
        capturedCommandPostNodeIds: [...state.capturedCommandPostNodeIds],
        commanderStates: commanderSnapshot(state),
    });
    return true;
}
export function captureCommandPostInPlace(state, capturingFactionId, nodeId) {
    const defeated = Object.values(state.factions).find((faction) => (faction.commandPostNodeId === nodeId
        && faction.factionId !== capturingFactionId
        && faction.defeatedAtRound === null));
    if (!defeated)
        return false;
    state.capturedCommandPostNodeIds.push(nodeId);
    defeatFactionInPlace(state, defeated.factionId, 'command_post_captured');
    const playerDefeated = defeated.factionId === state.playerFactionId;
    if (playerDefeated) {
        const winnerGroupId = requireFaction(state, capturingFactionId).victoryGroupId;
        applyGameResultInPlace(state, {
            winner: capturingFactionId,
            winningVictoryGroupId: winnerGroupId,
            reason: 'command_post_captured',
            reasonCode: 'CommandPostCaptured',
            decidedAtRound: state.strategicRound,
            survivingFactionIds: activeFactionIds(state),
            capturedCommandPostNodeIds: [...state.capturedCommandPostNodeIds],
            commanderStates: commanderSnapshot(state),
        });
        return true;
    }
    return evaluateVictoryGroupsInPlace(state, 'CommandPostCaptured', 'command_post_captured');
}
export function makeRoundLimitResult(state, score) {
    const groupScores = Object.values(state.victoryGroups).map((group) => ({
        group,
        score: group.factionIds.reduce((sum, factionId) => {
            const value = score[factionId] ?? [0, 0, 0, 0];
            return [sum[0] + value[0], sum[1] + value[1], sum[2] + value[2], sum[3] + value[3]];
        }, [0, 0, 0, 0]),
    })).sort((left, right) => {
        for (let index = 0; index < 4; index += 1) {
            const delta = (right.score[index] ?? 0) - (left.score[index] ?? 0);
            if (delta !== 0)
                return delta;
        }
        return left.group.victoryGroupId.localeCompare(right.group.victoryGroupId);
    });
    const best = groupScores[0];
    const second = groupScores[1];
    const tied = best && second && best.score.every((value, index) => value === second.score[index]);
    const winningVictoryGroupId = best && !tied ? best.group.victoryGroupId : null;
    return {
        winner: winningVictoryGroupId ? representativeFaction(state, winningVictoryGroupId) : 'draw',
        winningVictoryGroupId,
        reason: 'round_limit',
        reasonCode: 'RoundLimitScore',
        decidedAtRound: state.strategicRound,
        score,
        survivingFactionIds: activeFactionIds(state),
        capturedCommandPostNodeIds: [...state.capturedCommandPostNodeIds],
        commanderStates: commanderSnapshot(state),
    };
}
//# sourceMappingURL=objectives.js.map