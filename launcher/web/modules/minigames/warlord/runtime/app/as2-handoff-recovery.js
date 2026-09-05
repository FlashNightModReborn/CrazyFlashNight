import { applyCommand } from '../core/engine.js';
/**
 * Recover only from a definitive "battle did not start" result.
 * Unknown outcomes must remain fail-closed in the session authority path.
 */
export function recoverDefinitiveAs2BattleFailure(state, command) {
    const faction = state.factions[command.factionId];
    if (!faction)
        return { outcome: 'blocked', state };
    if (faction.controller === 'player') {
        return { outcome: 'player_retry', state };
    }
    const actionPhase = state.phase === 'FIRST_FACTION_ACTION'
        || state.phase === 'SECOND_FACTION_ACTION';
    if (!actionPhase || state.activeFactionId !== command.factionId) {
        return { outcome: 'blocked', state };
    }
    const ended = applyCommand(state, {
        type: 'END_ACTION',
        factionId: command.factionId,
    });
    return ended.ok
        ? { outcome: 'ai_action_ended', state: ended.state }
        : { outcome: 'blocked', state };
}
//# sourceMappingURL=as2-handoff-recovery.js.map